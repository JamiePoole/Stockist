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
    "UI/Kit/Tooltip.lua", "UI/Kit/Button.lua", "UI/Kit/IconButton.lua", "UI/Kit/Guide.lua", "UI/Kit/Window.lua", "Features/PopOut.lua",
    "Features/PriceChart.lua", "Features/ItemPicker.lua", "Features/ChartPanel.lua", "Features/Watchlist.lua",
    "Features/Ticker.lua", "Features/Movers.lua", "Features/Workspace.lua",
}

local NAMES = { [1] = "Aloe", [2] = "Bark", [3] = "Cinder", [4] = "Dust", [5] = "Ember", [6] = "Frost" }
-- the price 47 hours ago and now, so the 24h move is known: 1 and 2 rose, 3 and 4 fell, 5 is flat
local PRICES = { [1] = { 1000, 1300 }, [2] = { 1000, 1050 }, [3] = { 1000, 700 }, [4] = { 1000, 980 }, [5] = { 1000, 1000 } }

--- Items 1-5 have two days of hourly scans along a straight line between their two prices; 6 has one scan.
local function setup()
    Fake.install()
    local S = load_addon(unpack(FILES))
    S.settings = {}
    S.Clock.now = function() return NOON end
    S.db = { scan = {} }
    S.store = S.ReadingStore.New(S.db)
    for id, p in pairs(PRICES) do
        for h = 47, 0, -1 do
            local price = p[1] + (p[2] - p[1]) * (47 - h) / 47
            S.store:Add({ item = id, ts = NOON - h * HOUR, price = price, qty = 5 })
        end
    end
    S.store:Add({ item = 6, ts = NOON, price = 500, qty = 1 })
    S.tracked = S.Tracked.New({})
    S.tracked:Add(2); S.tracked:Add(3)
    S.ItemInfo.Name = function(id) return NAMES[id] end
    S.Print = function() end
    return S
end

local function ids(rows)
    local out = {}
    for i, r in ipairs(rows) do out[i] = r.id end
    return table.concat(out, ",")
end

-- Pure part -----------------------------------------------------------------------------------------

test("risers and fallers are listed biggest first, from every item given", function()
    local S = setup()
    local d = S.Movers.Compute(S.store, S.store:Items(), NOON, function(id) return NAMES[id] end, 10)
    eq(ids(d.risers), "1,2", "+30% then +5%")
    eq(ids(d.fallers), "3,4", "-30% then -2%")
    eq(d.risers[1].move > d.risers[2].move, true)
    eq(d.fallers[1].move < d.fallers[2].move, true)
    eq(d.risers[1].price, 1300, "with its latest price")
    Fake.uninstall()
end)

test("flat items, items with one scan and unknown items are not listed", function()
    local S = setup()
    local d = S.Movers.Compute(S.store, { 5, 6, 999 }, NOON, function(id) return NAMES[id] or "x" end, 10)
    eq(#d.risers, 0); eq(#d.fallers, 0)
    Fake.uninstall()
end)

test("each list is cut to the limit", function()
    local S = setup()
    local d = S.Movers.Compute(S.store, S.store:Items(), NOON, function(id) return NAMES[id] end, 1)
    eq(ids(d.risers), "1"); eq(ids(d.fallers), "3")
    Fake.uninstall()
end)

test("an item's move carries the label saying how far back it reaches", function()
    local S = setup()
    for h = 15, 0, -1 do S.store:Add({ item = 9, ts = NOON - h * HOUR, price = 100 + (15 - h) * 10, qty = 1 }) end
    local d = S.Movers.Compute(S.store, { 1, 9 }, NOON, function() return "n" end, 5)
    local plain, short
    for _, r in ipairs(d.risers) do if r.id == 1 then plain = r elseif r.id == 9 then short = r end end
    eq(plain.label, nil, "a full 24 hours has no label")
    eq(short.label, "15h", "15 hours of history says so")
    Fake.uninstall()
end)

test("ties are broken by item ID so the order is stable", function()
    local S = setup()
    for id = 20, 22 do
        for h = 47, 0, -1 do S.store:Add({ item = id, ts = NOON - h * HOUR, price = 1000 + (47 - h) * 2, qty = 1 }) end
    end
    local d = S.Movers.Compute(S.store, { 22, 20, 21 }, NOON, function() return "n" end, 5)
    eq(ids(d.risers), "20,21,22")
    Fake.uninstall()
end)

test("the number of rows per list follows the panel's height, between one and ten", function()
    local S = setup()
    local C = S.Movers.Capacity
    eq(C(100), 1, "a squat panel still gets one row each")
    eq(C(400), 8, "(400 - header - two headings - gap) / 2 / 20, rounded down")
    eq(C(190), 3)
    eq(C(2000), 10, "never more than ten")
    Fake.uninstall()
end)

-- The panel -----------------------------------------------------------------------------------------

local function panelOf(S, opts)
    local p = S.Movers.Create(UIParent, opts or { link = "A" })
    p.frame:SetSize(280, 400)
    p:Refresh()
    return p
end

local function shown(widgets)
    local out = {}
    for _, w in ipairs(widgets) do if w.shown ~= false and w.itemID then out[#out + 1] = w.itemID end end
    return table.concat(out, ",")
end

test("the panel shows rising and falling items in two lists with price and move", function()
    local S = setup()
    local p = panelOf(S)
    eq(shown(p.rise), "1,2"); eq(shown(p.fall), "3,4")
    local top = p.rise[1]
    eq(top.nameText.text, "Aloe")
    eq(top.moveText.text:find("ArrowUp", 1, true) ~= nil, true, "an up arrow for a riser")
    eq(p.fall[1].moveText.text:find("ArrowDown", 1, true) ~= nil, true, "a down arrow for a faller")
    eq(top.priceText.text ~= "", true)
    eq(p.empty.shown, false)
    eq(p.riseHead.shown, true); eq(p.fallHead.shown, true)
    Fake.uninstall()
end)

test("the watchlist switch narrows the lists to tracked items and back", function()
    local S = setup()
    local p = panelOf(S)
    Fake.fire(p.trackedButton, "OnClick")
    eq(p.onlyTracked, true)
    eq(shown(p.rise), "2"); eq(shown(p.fall), "3", "only the tracked items")
    eq(S.UI.Button.IsActive(p.trackedButton), true, "the switch lights up")
    Fake.fire(p.trackedButton, "OnClick")
    eq(shown(p.rise), "1,2")
    eq(S.UI.Button.IsActive(p.trackedButton), false)
    Fake.uninstall()
end)

test("with nothing to show it says why, differently for the two modes", function()
    local S = setup()
    S.store = S.ReadingStore.New({})
    local p = panelOf(S)
    eq(p.empty.shown, true)
    eq(p.empty.text:find("scans", 1, true) ~= nil, true, p.empty.text)
    eq(p.riseHead.shown, false)
    Fake.fire(p.trackedButton, "OnClick")
    eq(p.empty.text:find("watchlist", 1, true) ~= nil, true, p.empty.text)
    Fake.uninstall()
end)

test("clicking an item selects it in the link group, and opens the workspace if it is closed", function()
    local S = setup()
    local chart = S.ChartPanel.Create(UIParent, { link = "A" })
    local p = panelOf(S)
    eq(S.Workspace.IsShown(), false)
    Fake.fire(p.rise[2], "OnClick", "LeftButton")
    eq(S.Link.Get("A"), 2)
    eq(chart:GetItem(), 2, "a chart in the group follows")
    eq(S.Workspace.IsShown(), true, "and the workspace opened")
    local unlinked = panelOf(S, {})
    Fake.fire(unlinked.rise[1], "OnClick", "LeftButton")
    eq(S.Link.Get("A"), 2, "a panel with no group changes nothing")
    Fake.uninstall()
end)

test("it refreshes after a scan or a tracking change, and catches up if hidden at the time", function()
    local S = setup()
    local p = panelOf(S)
    for h = 47, 0, -1 do S.store:Add({ item = 7, ts = NOON - h * HOUR, price = 1000 + (47 - h) * 20, qty = 1 }) end
    S.Events:Fire("SCAN_COMPLETE")
    eq(shown(p.rise):find("7", 1, true) ~= nil, true, "a new riser appeared")
    p.frame.shown = false
    S.tracked:Add(7)
    S.Events:Fire("TRACKED_CHANGED", 7, true)
    Fake.fire(p.trackedButton, "OnClick") -- state change while hidden is also fine
    p.frame.shown = true
    Fake.fire(p.frame, "OnShow")
    eq(S.UI.Button.IsActive(p.trackedButton), true)
    Fake.uninstall()
end)

test("the lists grow and shrink with the panel's height", function()
    local S = setup()
    for id = 30, 40 do
        for h = 47, 0, -1 do S.store:Add({ item = id, ts = NOON - h * HOUR, price = 1000 + (47 - h) * (id - 28), qty = 1 }) end
    end
    local p = S.Movers.Create(UIParent, { link = "A" })
    p.frame:SetSize(280, 190); p:Refresh()
    local small = #(shown(p.rise):gsub("[^,]", ""))
    p.frame:SetSize(280, 700); p:Refresh()
    local big = #(shown(p.rise):gsub("[^,]", ""))
    eq(big > small, true, "taller shows more rows")
    eq(big + 1 <= 10, true, "capped at ten")
    Fake.uninstall()
end)

test("the movers panel can pop out, keeping its group and its switch, and has a window title", function()
    local S = setup()
    local p = S.Movers.Create(UIParent, { link = "A", popOut = true })
    p.frame:SetSize(280, 400)
    Fake.fire(p.trackedButton, "OnClick")
    Fake.fire(p.popOutButton, "OnClick")
    local slot = S.PopOut.Slot("movers")
    eq(slot ~= nil and slot.win.frame.shown, true)
    eq(slot.panel.link, "A"); eq(slot.panel.onlyTracked, true, "starts with the same filter")
    eq(slot.panel.popOutButton, nil, "no pop-out button inside the pop-out")
    eq(slot.win.title.text, "Stockist - Movers")
    Fake.uninstall()
end)

test("the workspace has the movers panel under the watchlist, in the main group", function()
    local S = setup()
    S.Workspace.Show()
    local cell
    for _, c in ipairs(S.Workspace.LAYOUTS.trader.cells) do if c.panel == "movers" then cell = c end end
    eq(cell ~= nil and cell.link == "A", true)
    eq(cell.x, 0); eq(cell.w, 0.27, "the same column as the watchlist")
    local placeholder
    for _, o in ipairs(Fake.objects) do
        if o.kind == "FontString" and o.text and o.text:find("Coming soon", 1, true) then placeholder = o end
    end
    eq(placeholder, nil, "every panel type in the layout is built")
    Fake.uninstall()
end)

test("every help key the movers panel uses has a topic", function()
    local S = setup()
    for _, key in ipairs(S.Movers.HELP_KEYS) do eq(S.Help.topics:Get(key) ~= nil, true, key) end
    Fake.uninstall()
end)
