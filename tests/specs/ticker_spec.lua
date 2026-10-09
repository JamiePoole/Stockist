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
    eq(segs[1].price ~= nil, true)
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
    eq(seven.move.text:find("%", 1, true) ~= nil, true, "and the move, in its own font string")
    eq(seven.move.text:find("|cff33c773", 1, true) ~= nil, true, "item 7 rose: green")
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

-- ids of the items the player tracks (everything before the "Market movers" heading)
local function mine(t)
    local out = {}
    for _, seg in ipairs(t.items) do
        if seg.heading then break end
        out[#out + 1] = seg.id
    end
    return out
end

test("with nothing tracked it shows the biggest movers on the market, under a heading", function()
    local S = setup()
    S.tracked = S.Tracked.New({})
    local t = tickerOf(S, 2000)
    eq(t.empty.shown, false)
    eq(t.items[1].heading, "Market movers")
    local ids = {}
    for _, b in ipairs(t.copies) do if b.shown and b.itemID then ids[#ids + 1] = b.itemID end end
    table.sort(ids)
    eq(ids[1], 7); eq(ids[2], 8, "both items with a price and a move")
    eq(t.copies[1].itemID, nil, "the heading is not clickable")
    Fake.fire(t.copies[1], "OnClick", "LeftButton")
    eq(S.Link.Get("A"), nil, "clicking the heading selects nothing")
    Fake.uninstall()
end)

test("with no prices at all it says how to get some, and does not scroll", function()
    local S = setup()
    S.tracked = S.Tracked.New({})
    S.store = S.ReadingStore.New({})
    local t = tickerOf(S, 120)
    eq(t.empty.shown, true)
    eq(t.scrolling, false)
    eq(#visibleItems(t), 0)
    Fake.uninstall()
end)

test("your own items come first, then market movers top the strip up while there are few of them", function()
    local S = setup()
    S.tracked = S.Tracked.New({})
    local t = tickerOf(S, 2000)
    eq(t.items[1].heading, "Market movers")
    S.tracked:Add(7)
    S.Events:Fire("TRACKED_CHANGED", 7, true)
    eq(t.items[1].id, 7, "yours first")
    eq(t.items[2].heading, "Market movers")
    eq(t.items[3].id, 8, "then the movers")
    for _, seg in ipairs(t.items) do
        if seg.id == 7 then eq(seg == t.items[1], true, "an item you track is not repeated among the movers") end
    end
    Fake.uninstall()
end)

test("with enough items of your own there are no market movers", function()
    local S = setup()
    S.tracked = S.Tracked.New({})
    for id = 40, 46 do
        for h = 47, 0, -1 do S.store:Add({ item = id, ts = NOON - h * HOUR, price = 100 + id + (47 - h), qty = 1 }) end
        S.tracked:Add(id)
    end
    local t = tickerOf(S, 2000)
    eq(#t.items, 7)
    for _, seg in ipairs(t.items) do eq(seg.heading, nil) end
    Fake.uninstall()
end)

test("the strip is topped up so there is always something to scroll", function()
    local S = setup()
    S.tracked = S.Tracked.New({})
    S.tracked:Add(7)
    for id = 50, 62 do
        for h = 47, 0, -1 do S.store:Add({ item = id, ts = NOON - h * HOUR, price = 100 + (47 - h) * id, qty = 1 }) end
    end
    local t = tickerOf(S, 700)
    eq(t.scrolling, true, "one tracked item alone would stand still; with movers it scrolls")
    Fake.uninstall()
end)

test("movers: the largest moves up or down, up to the limit, zero and unmeasurable ones left out", function()
    local S = setup()
    local rows = {
        { id = 1, name = "a", price = 10, change = 5 },
        { id = 2, name = "b", price = 10, change = -12 },
        { id = 3, name = "c", price = 10, change = 0.5 },
        { id = 4, name = "d", price = 10, change = 0 },
        { id = 5, name = "e", price = 10 },                    -- nothing to measure
        { id = 6, name = "f", price = 10, recent = -7 },        -- only a recent move: still counts
        { id = 7, name = "g", change = 50 },                    -- no price
    }
    local segs = S.Ticker.MoverSegments(rows, 3)
    local ids = {}
    for _, g in ipairs(segs) do ids[#ids + 1] = g.id end
    eq(table.concat(ids, ","), "1,2,6", "the three biggest, shown in name order")
    eq(#S.Ticker.MoverSegments(rows, 10), 4, "unmoved, unmeasured and priceless ones never appear")
    eq(#S.Ticker.MoverSegments({}, 5), 0)
    Fake.uninstall()
end)

test("an item's move is its 24h change, a labelled shorter one when history is short, else the recent move", function()
    local S = setup()
    local pct, label = S.Ticker.Move(S.store, 7, NOON)
    eq(pct > 0, true); eq(label, nil, "a plain 24h move has no label")

    for h = 15, 0, -1 do S.store:Add({ item = 30, ts = NOON - h * HOUR, price = 1000 + (15 - h) * 10, qty = 1 }) end
    pct, label = S.Ticker.Move(S.store, 30, NOON)
    eq(pct > 0, true); eq(label, "15h", "only 15 hours of history: it says so")

    for i = 1, 5 do S.store:Add({ item = 31, ts = NOON - (6 - i) * 900, price = 1000, qty = 1 }) end
    S.store:Add({ item = 31, ts = NOON, price = 1100, qty = 1 })
    pct, label = S.Ticker.Move(S.store, 31, NOON)
    near(pct, 10, 1e-6); eq(label, "recent", "under half a day: the recent move")

    S.store:Add({ item = 32, ts = NOON, price = 100, qty = 1 })
    eq(S.Ticker.Move(S.store, 32, NOON), nil, "one reading: nothing to measure")
    eq(S.Ticker.Move(S.store, 999, NOON), nil, "no readings")
    Fake.uninstall()
end)

test("the tape shows the move even when the history is short", function()
    local S = setup()
    S.tracked = S.Tracked.New({})
    for h = 15, 0, -1 do S.store:Add({ item = 30, ts = NOON - h * HOUR, price = 1000 + (15 - h) * 10, qty = 1 }) end
    S.tracked:Add(30)
    local t = tickerOf(S, 2000)
    local text = visibleItems(t)[1].move.text
    eq(text:find("%", 1, true) ~= nil, true, text)
    eq(text:find("15h", 1, true) ~= nil, true, "labelled with what it covers: " .. text)
    Fake.uninstall()
end)

test("choosing an item from a popped-out ticker or watchlist opens the workspace if it is closed", function()
    local S = setup()
    local t = tickerOf(S, 2000)
    eq(S.Workspace.IsShown(), false)
    Fake.fire(visibleItems(t)[1], "OnClick", "LeftButton")
    eq(S.Workspace.IsShown(), true, "the ticker opened it")
    eq(S.Link.Get("A") ~= nil, true)

    StockistWorkspace:Hide()
    local list = S.Watchlist.Create(UIParent, { link = "A" })
    list.list:SetSize(220, 300); list:Refresh()
    local row
    for _, r in ipairs(list.rowFrames) do if r.itemID == 8 then row = r end end
    Fake.fire(row, "OnClick", "LeftButton")
    eq(S.Workspace.IsShown(), true, "and so did the watchlist")
    eq(S.Link.Get("A"), 8)
    Fake.uninstall()
end)

test("choosing an item while the workspace is already open does not touch it", function()
    local S = setup()
    S.Workspace.Show(7)
    local shows = 0
    local real = S.Workspace.Show
    S.Workspace.Show = function(...) shows = shows + 1; return real(...) end
    local t = tickerOf(S, 2000)
    Fake.fire(visibleItems(t)[1], "OnClick", "LeftButton")
    eq(shows, 0)
    Fake.uninstall()
end)

test("it follows tracking changes, and drops items that are no longer tracked", function()
    local S = setup()
    local t = tickerOf(S, 2000)
    S.tracked:Remove(8)
    S.Events:Fire("TRACKED_CHANGED", 8, false)
    eq(table.concat(mine(t), ","), "7")
    for h = 47, 0, -1 do S.store:Add({ item = 20, ts = NOON - h * HOUR, price = 500, qty = 1 }) end
    S.tracked:Add(20)
    S.Events:Fire("TRACKED_CHANGED", 20, true)
    eq(table.concat(mine(t), ","), "20,7", "name order")
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
    eq(table.concat(mine(t), ","), "7,8", "not redrawn while hidden")
    t.frame.shown = true
    Fake.fire(t.frame, "OnShow")
    eq(table.concat(mine(t), ","), "7")
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

test("the move is drawn in the chat font, because the panels' usual font has no triangles", function()
    local S = setup()
    local calls = {}
    local fs = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 13, "OUTLINE" end,
        SetFont = function(_, face, size, flags) calls[#calls + 1] = { face, size, flags } end }
    S.Format.UseMoveFont(fs)
    eq(calls[1][1], "Fonts\\ARIALN.TTF", "the narrow Latin font when there is no chat font object")
    eq(calls[1][2], 13, "same size"); eq(calls[1][3], "OUTLINE", "same flags")

    ChatFontNormal = { GetFont = function() return "Interface\\Custom\\Chat.ttf", 14, "" end }
    S.Format.UseMoveFont(fs)
    eq(calls[2][1], "Interface\\Custom\\Chat.ttf", "the player's own chat font when there is one")
    ChatFontNormal = nil

    local bare = { GetFont = function() end, SetFont = function(_, _, size) calls[3] = size end }
    S.Format.UseMoveFont(bare)
    eq(calls[3], 12, "a font string with no size reported still gets one")
    Fake.uninstall()
end)

test("every move text in the ticker, watchlist and chart header gets that font", function()
    local S = setup()
    local used = {}
    local real = S.Format.UseMoveFont
    S.Format.UseMoveFont = function(fs) used[fs] = true; return real(fs) end
    local t = tickerOf(S, 2000)
    local list = S.Watchlist.Create(UIParent, { link = "A" })
    list.list:SetSize(220, 300); list:Refresh()
    local chart = S.ChartPanel.Create(UIParent)
    for _, b in ipairs(t.copies) do eq(used[b.move], true, "ticker item") end
    for _, row in ipairs(list.rowFrames) do eq(used[row.recent] and used[row.change], true, "watchlist row") end
    eq(used[chart.changeText] and used[chart.recentText], true, "chart header")
    Fake.uninstall()
end)
