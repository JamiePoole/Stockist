load_support("fake_wow")

local DAY, HOUR = 86400, 3600
local NOON = 40 * DAY + 12 * HOUR

local FILES = {
    "Core/Clock.lua", "Core/EventBus.lua", "Core/Registry.lua", "Core/Panels.lua", "Core/Link.lua",
    "Core/Format.lua", "Core/Calendar.lua", "Core/ItemInfo.lua", "Core/Help.lua", "Core/HelpTopics.lua",
    "Core/Commands.lua", "Data/Rollup.lua", "Data/Indicators.lua", "Data/ReadingStore.lua", "Data/Tracked.lua",
    "UI/Charts/Charts.lua", "UI/Charts/Util.lua", "UI/Charts/Scale.lua", "UI/Charts/Formatters.lua",
    "UI/Charts/Theme.lua", "UI/Charts/Series/Line.lua", "UI/Charts/Series/Candle.lua", "UI/Charts/Series/Bar.lua",
    "UI/Charts/Overlays/Overlays.lua", "UI/Charts/Core.lua", "UI/Charts/FrameCanvas.lua", "UI/Charts/ChartFrame.lua",
    "UI/Kit/Tooltip.lua", "UI/Kit/Button.lua", "UI/Kit/IconButton.lua", "UI/Kit/Window.lua", "Features/PopOut.lua",
    "Features/PriceChart.lua", "Features/ItemPicker.lua", "Features/ChartPanel.lua", "Features/Watchlist.lua",
    "Features/Ticker.lua", "Features/Workspace.lua",
}

local NAMES = { [7] = "Linen Cloth", [8] = "Mageweave Cloth", [9] = "Heart of Fire" }

--- Items 7 and 8 have two days of hourly prices and are tracked; 9 is tracked with no prices.
local function setup()
    Fake.install()
    local S = load_addon(unpack(FILES))
    S.settings = {}
    S.Clock.now = function() return NOON end
    S.db = { scan = {} }
    S.store = S.ReadingStore.New(S.db)
    for h = 47, 0, -1 do
        S.store:Add({ item = 7, ts = NOON - h * HOUR, price = 1000 + (47 - h) * 10, qty = 10 })
        S.store:Add({ item = 8, ts = NOON - h * HOUR, price = 900 - (47 - h) * 5, qty = 10 })
    end
    S.tracked = S.Tracked.New({})
    S.tracked:Add(7); S.tracked:Add(8); S.tracked:Add(9)
    S.ItemInfo.Name = function(id) return NAMES[id] end
    S.Print = function() end
    return S
end

--- A ticker whose window is `width` wide, so the test decides whether it has to scroll.
local function tickerOf(S, width, opts)
    local t = S.Ticker.Create(UIParent, opts or { link = "A" })
    t.view:SetSize(width, 30)
    t:Refresh()
    return t
end

local function visibleItems(t)
    local out = {}
    for _, b in ipairs(t.copies) do if b.shown and b.itemID then out[#out + 1] = b end end
    return out
end

-- Pure part -----------------------------------------------------------------------------------------

test("segments are the tracked items that have a price, in the order given", function()
    local S = setup()
    local rows = S.Watchlist.Rows(S.store, S.tracked:List(), NOON, function(id) return NAMES[id] end)
    local segs = S.Ticker.Segments(rows)
    eq(#segs, 2, "item 9 has no price, so it is left out")
    eq(segs[1].name < segs[2].name or segs[1].name == segs[2].name, true, "sorted by name")
    eq(segs[1].price ~= nil and segs[1].change ~= nil, true)
    Fake.uninstall()
end)

test("the tape scrolls only when its items are wider than the room", function()
    local S = setup()
    eq(S.Ticker.NeedsScroll(500, 400), true)
    eq(S.Ticker.NeedsScroll(400, 400), false, "exactly fitting stands still")
    eq(S.Ticker.NeedsScroll(100, 400), false)
    Fake.uninstall()
end)

test("advancing moves the tape left at the given speed and wraps seamlessly after one copy", function()
    local S = setup()
    local A = S.Ticker.Advance
    near(A(0, 1, 40, 500), -40, 1e-9)
    near(A(-40, 0.5, 40, 500), -60, 1e-9)
    near(A(-490, 1, 40, 500), -30, 1e-9, "past the end of the first copy: back by exactly one copy")
    near(A(-499.9, 0.01, 40, 500), -0.3, 1e-6, "just past the end: wraps by one copy")
    eq(A(0, 1, 40, 0), 0, "nothing to scroll")
    eq(A(-10, 1000, 40, 500) <= 0 and A(-10, 1000, 40, 500) > -500, true, "a long pause still lands inside the loop")
    Fake.uninstall()
end)

-- The panel -----------------------------------------------------------------------------------------

test("each tracked item with a price becomes one item on the tape: name, price, 24h move", function()
    local S = setup()
    local t = tickerOf(S, 2000)
    local items = visibleItems(t)
    eq(#items, 2)
    local ids = { items[1].itemID, items[2].itemID }
    table.sort(ids)
    eq(ids[1], 7); eq(ids[2], 8)
    local seven
    for _, b in ipairs(items) do if b.itemID == 7 then seven = b end end
    eq(seven.label.text:find("Linen Cloth", 1, true) ~= nil, true, "the name")
    eq(seven.label.text:find("%", 1, true) ~= nil, true, "and the move")
    eq(seven.label.text:find("|cff33c773", 1, true) ~= nil, true, "item 7 rose: green")
    eq(t.empty.shown, false)
    Fake.uninstall()
end)

test("when everything fits the tape stands still, with no repeat copies", function()
    local S = setup()
    local t = tickerOf(S, 2000)
    eq(t.scrolling, false)
    eq(#visibleItems(t), 2, "just one copy")
    t.offset = -50
    Fake.fire(t.frame, "OnUpdate", 1)
    eq(t.offset, -50, "nothing moves")
    t:Refresh()
    eq(t.offset, 0, "and it sits at the left edge")
    Fake.uninstall()
end)

test("when it does not fit, a second copy follows the first and the tape scrolls", function()
    local S = setup()
    local t = tickerOf(S, 120)
    eq(t.scrolling, true)
    eq(#visibleItems(t), 4, "two copies of two items")
    local first, repeated
    for _, b in ipairs(t.copies) do
        if b.itemID == 7 then if not first then first = b else repeated = b end end
    end
    local function x(b) return b.points[#b.points][4] end
    eq(x(repeated) - x(first), t.loop, "the second copy starts exactly one loop after the first")
    eq(t.tape.size[1], t.loop * 2)

    local before = t.offset
    Fake.fire(t.frame, "OnUpdate", 1)
    eq(t.offset < before, true, "it moves left")
    Fake.uninstall()
end)

test("it wraps when the first copy has gone past", function()
    local S = setup()
    local t = tickerOf(S, 120)
    t.offset = -(t.loop - 1)
    Fake.fire(t.frame, "OnUpdate", 1)
    eq(t.offset > -t.loop and t.offset <= 0, true, "back inside the loop")
    Fake.uninstall()
end)

test("hovering the strip pauses it", function()
    local S = setup()
    local t = tickerOf(S, 120)
    t.frame.IsMouseOver = function() return true end
    local before = t.offset
    Fake.fire(t.frame, "OnUpdate", 1)
    eq(t.offset, before, "paused under the mouse")
    t.frame.IsMouseOver = function() return false end
    Fake.fire(t.frame, "OnUpdate", 1)
    eq(t.offset < before, true, "and goes on when the mouse leaves")
    Fake.uninstall()
end)

test("a refresh keeps the scroll position, so a new price does not restart the tape", function()
    local S = setup()
    local t = tickerOf(S, 120)
    t.offset = -77
    S.Events:Fire("SCAN_COMPLETE")
    eq(t.offset, -77)
    Fake.uninstall()
end)

test("clicking an item selects it in the panel's link group", function()
    local S = setup()
    local t = tickerOf(S, 2000)
    local chart = S.ChartPanel.Create(UIParent, { link = "A" })
    local seven
    for _, b in ipairs(visibleItems(t)) do if b.itemID == 7 then seven = b end end
    Fake.fire(seven, "OnClick", "LeftButton")
    eq(S.Link.Get("A"), 7)
    eq(chart:GetItem(), 7, "a chart in the group follows")
    local unlinked = tickerOf(S, 2000, {})
    Fake.fire(visibleItems(unlinked)[1], "OnClick", "LeftButton")
    eq(S.Link.Get("A"), 7, "a ticker with no group changes nothing")
    Fake.uninstall()
end)

test("with nothing tracked it says how to fill it, and does not scroll", function()
    local S = setup()
    S.tracked = S.Tracked.New({})
    local t = tickerOf(S, 120)
    eq(t.empty.shown, true)
    eq(t.scrolling, false)
    eq(#visibleItems(t), 0)
    Fake.uninstall()
end)

test("it follows tracking changes, and drops items that are no longer tracked", function()
    local S = setup()
    local t = tickerOf(S, 2000)
    S.tracked:Remove(8)
    S.Events:Fire("TRACKED_CHANGED", 8, false)
    eq(#visibleItems(t), 1)
    for h = 47, 0, -1 do S.store:Add({ item = 20, ts = NOON - h * HOUR, price = 500, qty = 1 }) end
    S.tracked:Add(20)
    S.Events:Fire("TRACKED_CHANGED", 20, true)
    eq(#visibleItems(t), 2)
    Fake.uninstall()
end)

test("the repeat copies are hidden again when the tape stops needing them", function()
    local S = setup()
    local t = tickerOf(S, 120)
    eq(#visibleItems(t), 4)
    t.view:SetSize(5000, 30)
    t:Refresh()
    eq(#visibleItems(t), 2)
    eq(t.scrolling, false)
    Fake.uninstall()
end)

test("a hidden ticker catches up when shown", function()
    local S = setup()
    local t = tickerOf(S, 2000)
    t.frame.shown = false
    S.tracked:Remove(8)
    S.Events:Fire("TRACKED_CHANGED", 8, false)
    eq(#visibleItems(t), 2, "not redrawn while hidden")
    t.frame.shown = true
    Fake.fire(t.frame, "OnShow")
    eq(#visibleItems(t), 1)
    Fake.uninstall()
end)

test("dropping an item on the ticker tracks it and shows it in the chart", function()
    local S = setup()
    GetCursorInfo = function() return "item", 99 end
    ClearCursor = function() end
    local t = tickerOf(S, 2000)
    Fake.fire(t.frame, "OnReceiveDrag")
    eq(S.tracked:Has(99), true)
    eq(S.Link.Get("A"), 99)
    GetCursorInfo, ClearCursor = nil, nil
    Fake.uninstall()
end)

test("the ticker can pop out, keeping its link group, and has its own window title", function()
    local S = setup()
    local t = tickerOf(S, 2000, { link = "A", popOut = true })
    eq(t.popOutButton ~= nil, true)
    Fake.fire(t.popOutButton, "OnClick")
    local slot = S.PopOut.Slot("ticker")
    eq(slot ~= nil and slot.win.frame.shown, true)
    eq(slot.panel.link, "A")
    eq(slot.panel.popOutButton, nil, "no pop-out button inside the pop-out")
    eq(slot.win.title.text, "Stockist - Ticker")
    Fake.uninstall()
end)

test("the workspace layout has the ticker as a strip across the top, in the main link group", function()
    local S = setup()
    S.Workspace.Show()
    local cell
    for _, c in ipairs(S.Workspace.LAYOUTS.trader.cells) do if c.panel == "ticker" then cell = c end end
    eq(cell.y, 0); eq(cell.w, 1); eq(cell.link, "A")
    eq(cell.h < 0.1, true, "a thin strip")
    local placeholder
    for _, o in ipairs(Fake.objects) do
        if o.kind == "FontString" and o.text and o.text:find("Coming soon", 1, true) then placeholder = o end
    end
    eq(placeholder, nil, "all three panel types are built")
    Fake.uninstall()
end)

test("every help key the ticker uses has a topic", function()
    local S = setup()
    for _, key in ipairs(S.Ticker.HELP_KEYS) do eq(S.Help.topics:Get(key) ~= nil, true, key) end
    Fake.uninstall()
end)
