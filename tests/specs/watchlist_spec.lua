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
    "UI/Kit/Tooltip.lua", "UI/Kit/Button.lua", "UI/Kit/IconButton.lua", "UI/Kit/Window.lua", "Features/PriceChart.lua",
    "Features/ChartPanel.lua", "Features/Watchlist.lua", "Features/Workspace.lua",
}

--- Item 7 rose over two days, 8 fell, 9 has no readings. 7 and 8 are tracked, and so is 9.
local function setup()
    Fake.install()
    local S = load_addon(unpack(FILES))
    S.settings = {}
    S.Clock.now = function() return NOON end
    S.db = { scan = {} }
    S.store = S.ReadingStore.New(S.db)
    for h = 0, 47 do
        S.store:Add({ item = 7, ts = NOON - h * HOUR, price = 2000 - h * 10, qty = 40 })
        S.store:Add({ item = 8, ts = NOON - h * HOUR, price = 500 + h * 5, qty = 40 })
    end
    S.tracked = S.Tracked.New({})
    S.tracked:Add(8); S.tracked:Add(7); S.tracked:Add(9)
    S.RichestItem = function() return 7 end
    S.Print = function() end
    return S
end

local function names(rows)
    local out = {}
    for i, r in ipairs(rows) do out[i] = r.id end
    return out
end

-- Pure rows -----------------------------------------------------------------------------------------

test("rows carry price, change, age and a price line, sorted by name", function()
    local S = setup()
    local nameOf = function(id) return ({ [7] = "Zeal", [8] = "apple", [9] = "Mist" })[id] end
    local rows = S.Watchlist.Rows(S.store, S.tracked:List(), NOON, nameOf)
    eq(table.concat(names(rows), ","), "8,9,7", "case-insensitive by name: apple, Mist, Zeal")
    eq(rows[3].price, 2000, "newest reading")
    eq(rows[3].change > 0, true, "item 7 rose over 24h")
    eq(rows[1].change < 0, true, "item 8 fell")
    eq(rows[3].age, 0)
    eq(#rows[3].spark >= 2, true, "enough points for a line")
    eq(rows[2].price, nil, "no readings: no price")
    eq(rows[2].change, nil); eq(rows[2].age, nil)
    eq(#rows[2].spark, 0)
    Fake.uninstall()
end)

test("equal names fall back to the item id so the order is stable", function()
    local S = setup()
    local rows = S.Watchlist.Rows(S.store, { 9, 7, 8 }, NOON, function() return "Same" end)
    eq(table.concat(names(rows), ","), "7,8,9")
    Fake.uninstall()
end)

test("the price line is green when it ends higher, red when lower, grey when flat or too short", function()
    local S = setup()
    local W = S.Watchlist
    local up = W.SparkConfig({ { x = 1, y = 5 }, { x = 2, y = 9 } }).series[1].color
    local down = W.SparkConfig({ { x = 1, y = 9 }, { x = 2, y = 5 } }).series[1].color
    local flat = W.SparkConfig({ { x = 1, y = 5 }, { x = 2, y = 5 } }).series[1].color
    eq(up[2] > up[1], true, "green"); eq(down[1] > down[2], true, "red")
    eq(flat[1] == flat[2] and flat[2] == flat[3], true, "grey")
    local one = W.SparkConfig({ { x = 1, y = 5 } })
    eq(#one.series[1].points, 0, "a single point draws nothing")
    eq(one.minimal, true, "no axes")
    Fake.uninstall()
end)

test("how many rows fit and how far the list can scroll", function()
    local S = setup()
    local fit, max = S.Watchlist.Capacity(110, 10)
    eq(fit, 3); eq(max, 7)
    fit, max = S.Watchlist.Capacity(10, 2)
    eq(fit, 1, "at least one row"); eq(max, 1)
    fit, max = S.Watchlist.Capacity(400, 2)
    eq(fit, 11); eq(max, 0)
    Fake.uninstall()
end)

test("every help key the watchlist uses has a topic", function()
    local S = setup()
    for _, key in ipairs(S.Watchlist.HELP_KEYS) do eq(S.Help.topics:Get(key) ~= nil, true, key) end
    Fake.uninstall()
end)

-- The panel ---------------------------------------------------------------------------------------

local function panelFor(S)
    local panel = S.Watchlist.Create(UIParent, { link = "A" })
    panel.list:SetSize(220, 300) -- room for eight rows
    panel:Refresh()
    return panel
end

local function shownRows(panel)
    local out = {}
    for _, row in ipairs(panel.rowFrames) do
        if row.shown ~= false and row.itemID then out[#out + 1] = row end
    end
    return out
end

test("the panel lists every tracked item with its price and change", function()
    local S = setup()
    local panel = panelFor(S)
    local rows = shownRows(panel)
    eq(#rows, 3)
    eq(rows[1].itemID, 7, "item:7 sorts before item:8 and item:9 when no names are cached")
    eq(rows[1].price.text:find("20", 1, true) ~= nil, true, "price shown")
    eq(rows[3].price.text, "no data yet", "an item without readings says so")
    eq(rows[3].change.text, "")
    eq(panel.empty.shown, false, "no empty message while there are rows")
    eq(panel.title.text, "Watchlist (3)")
    Fake.uninstall()
end)

test("an empty watchlist explains how to add something", function()
    local S = setup()
    S.tracked = S.Tracked.New({})
    local panel = panelFor(S)
    eq(#shownRows(panel), 0)
    eq(panel.empty.shown, true)
    eq(panel.empty.text:find("Track", 1, true) ~= nil, true)
    eq(panel.title.text, "Watchlist")
    Fake.uninstall()
end)

test("clicking a row selects the item in the link group and highlights it", function()
    local S = setup()
    local panel = panelFor(S)
    local seen = {}
    S.Events:On("LINK_SELECTED", function(group, id) seen[#seen + 1] = group .. id end)
    local row = shownRows(panel)[2]
    Fake.fire(row, "OnClick", "LeftButton")
    eq(S.Link.Get("A"), row.itemID)
    eq(seen[1], "A" .. row.itemID)
    eq(row.selectedBg.shown, true, "the chosen row is highlighted")
    eq(shownRows(panel)[1].selectedBg.shown, false)
    Fake.uninstall()
end)

test("right-clicking a row stops tracking that item", function()
    local S = setup()
    local panel = panelFor(S)
    local events = {}
    S.Events:On("TRACKED_CHANGED", function(id, on) events[#events + 1] = { id, on } end)
    Fake.fire(shownRows(panel)[1], "OnClick", "RightButton")
    eq(S.tracked:Has(7), false)
    eq(events[1][1], 7); eq(events[1][2], false)
    eq(#shownRows(panel), 2, "the list redraws without it")
    Fake.uninstall()
end)

test("the track button adds or removes the item selected in the group", function()
    local S = setup()
    local panel = panelFor(S)
    S.Link.Select("A", 99)
    eq(panel.trackButton.text, "Track this item")
    Fake.fire(panel.trackButton, "OnClick")
    eq(S.tracked:Has(99), true)
    eq(panel.trackButton.text, "Stop tracking this item")
    eq(#shownRows(panel), 4, "and it appears in the list")
    Fake.fire(panel.trackButton, "OnClick")
    eq(S.tracked:Has(99), false)
    Fake.uninstall()
end)

test("the track button is unavailable until something is selected", function()
    local S = setup()
    local panel = panelFor(S)
    eq(S.UI.Tooltip.IsAvailable(panel.trackButton), false)
    Fake.fire(panel.trackButton, "OnClick")
    eq(S.tracked:Count(), 3, "clicking with no selection changes nothing")
    S.Link.Select("A", 7)
    eq(S.UI.Tooltip.IsAvailable(panel.trackButton), true)
    eq(panel.trackButton.text, "Stop tracking this item", "7 is already tracked")
    Fake.uninstall()
end)

test("a long list scrolls with the mouse wheel and stays inside its bounds", function()
    local S = setup()
    for id = 20, 29 do S.tracked:Add(id) end -- 13 items
    local panel = S.Watchlist.Create(UIParent, { link = "A" })
    panel.list:SetSize(220, 108) -- three rows
    panel:Refresh()
    eq(#shownRows(panel), 3)
    local first = shownRows(panel)[1].itemID
    Fake.fire(panel.list, "OnMouseWheel", -1)
    eq(panel.offset, 1)
    eq(shownRows(panel)[1].itemID ~= first, true)
    Fake.fire(panel.list, "OnMouseWheel", 1); Fake.fire(panel.list, "OnMouseWheel", 1)
    eq(panel.offset, 0, "cannot scroll above the top")
    for _ = 1, 40 do Fake.fire(panel.list, "OnMouseWheel", -1) end
    eq(panel.offset, 10, "cannot scroll past the last row")
    Fake.uninstall()
end)

test("the panel follows scans and tracking changes made elsewhere", function()
    local S = setup()
    local panel = panelFor(S)
    S.tracked:Add(50)
    S.Events:Fire("TRACKED_CHANGED", 50, true)
    eq(#shownRows(panel), 4)
    S.tracked:Remove(50)
    S.Events:Fire("TRACKED_CHANGED", 50, false)
    eq(#shownRows(panel), 3)
    Fake.uninstall()
end)

test("the workspace now builds a real watchlist in its first cell", function()
    local S = setup()
    S.Workspace.Show(7)
    local placeholder
    for _, o in ipairs(Fake.objects) do
        if o.kind == "FontString" and o.text and o.text:find("Coming soon", 1, true) then placeholder = o end
    end
    eq(placeholder, nil, "no placeholder: both panel types exist")
    eq(S.Link.Get("A"), 7)
    Fake.uninstall()
end)
