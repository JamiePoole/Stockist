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
    "UI/Kit/Tooltip.lua", "UI/Kit/Button.lua", "UI/Kit/IconButton.lua", "UI/Kit/Window.lua", "Features/PopOut.lua", "Features/PriceChart.lua",
    "Features/ItemPicker.lua", "Features/ChartPanel.lua", "Features/Watchlist.lua", "Features/Ticker.lua", "Features/Workspace.lua",
}

--- Item 7 rose over two days, 8 fell, 9 has no readings. 7 and 8 are tracked, and so is 9.
local function setup()
    Fake.install()
    local S = load_addon(unpack(FILES))
    S.settings = {}
    S.Clock.now = function() return NOON end
    S.db = { scan = {} }
    S.store = S.ReadingStore.New(S.db)
    for h = 47, 0, -1 do -- oldest first: scans arrive in time order
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

test("a row only reacts to the left button, so a stray right click cannot untrack anything", function()
    local S = setup()
    local panel = panelFor(S)
    local row = shownRows(panel)[1]
    eq(#row.clickButtons, 1); eq(row.clickButtons[1], "LeftButtonUp")
    Fake.fire(row, "OnClick", "RightButton") -- even if the client delivered one
    eq(S.tracked:Has(7), true, "still tracked")
    eq(#shownRows(panel), 3)
    Fake.uninstall()
end)

test("untracking is a deliberate two-step: select the row, press the button", function()
    local S = setup()
    local panel = panelFor(S)
    local events = {}
    S.Events:On("TRACKED_CHANGED", function(id, on) events[#events + 1] = { id, on } end)
    Fake.fire(shownRows(panel)[1], "OnClick", "LeftButton")
    Fake.fire(panel.trackButton, "OnClick")
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

-- Recent and scoped change ------------------------------------------------------------------------------

test("the recent move compares the latest scan with the average of the last two hours of scans", function()
    local S = setup()
    local pct, used = S.store:SmoothedChange(7, 2 * HOUR)
    eq(used, 2, "the scans at 1h and 2h before")
    near(pct, (2000 - 1985) / 1985 * 100, 1e-9)
    eq(S.store:SmoothedChange(8, 2 * HOUR) < 0, true, "item 8 fell")
    eq(S.store:SmoothedChange(9, 2 * HOUR), nil, "no readings")
    S.store:Add({ item = 10, ts = NOON - 900, price = 100, qty = 1 })
    S.store:Add({ item = 10, ts = NOON, price = 130, qty = 1 })
    eq(S.store:SmoothedChange(10, 2 * HOUR), nil, "needs at least two earlier scans to average")
    S.store:Add({ item = 11, ts = NOON - 7 * HOUR, price = 5000, qty = 1 })
    S.store:Add({ item = 11, ts = NOON - 6 * HOUR, price = 5000, qty = 1 })
    S.store:Add({ item = 11, ts = NOON, price = 100, qty = 1 })
    eq(S.store:SmoothedChange(11, 2 * HOUR), nil, "scans older than the window are not averaged in")
    Fake.uninstall()
end)

test("a single odd scan does not make the recent move jump like a two-scan comparison would", function()
    local S = setup()
    for i = 1, 6 do S.store:Add({ item = 12, ts = NOON - (7 - i) * 900, price = 1000, qty = 1 }) end
    S.store:Add({ item = 12, ts = NOON, price = 1100, qty = 1 })
    local pct = S.store:SmoothedChange(12, 2 * HOUR)
    near(pct, 10, 1e-9)
    -- and when one earlier scan was the odd one, it is averaged away
    S.store:Add({ item = 13, ts = NOON - 3600, price = 2000, qty = 1 })
    for i = 1, 4 do S.store:Add({ item = 13, ts = NOON - 3600 + i * 600, price = 1000, qty = 1 }) end
    S.store:Add({ item = 13, ts = NOON, price = 1000, qty = 1 })
    eq(math.abs(S.store:SmoothedChange(13, 2 * HOUR)) < 25, true, "damped by the other scans")
    Fake.uninstall()
end)

test("the change over a scope uses the price that long ago, or the oldest we hold if it covers half of it", function()
    local S = setup()
    local pct, covered = S.store:ChangeOver(7, DAY, NOON)
    eq(pct > 0, true); eq(covered, DAY, "a full day of history")
    eq(S.store:ChangeOver(7, 7 * DAY, NOON), nil, "47h is less than half of a week")
    for h = 95, 0, -1 do S.store:Add({ item = 20, ts = NOON - h * HOUR, price = 1000 + (95 - h) * 10, qty = 1 }) end
    pct, covered = S.store:ChangeOver(20, 7 * DAY, NOON)
    eq(pct > 0, true, "four days is more than half of a week")
    eq(covered >= 3.5 * DAY and covered < 7 * DAY, true, "and it says how much it covered")
    eq(S.store:ChangeOver(9, DAY, NOON), nil, "no readings")
    Fake.uninstall()
end)

test("Format.Span gives one short unit", function()
    local S = setup()
    eq(S.Format.Span(30), "1m"); eq(S.Format.Span(45 * 60), "45m"); eq(S.Format.Span(3 * 3600), "3h")
    eq(S.Format.Span(47 * 3600), "47h"); eq(S.Format.Span(3 * 86400), "3d")
    Fake.uninstall()
end)

test("the header figure follows the chart scope and says how long it really covers", function()
    local S = setup()
    for h = 95, 0, -1 do S.store:Add({ item = 20, ts = NOON - h * HOUR, price = 1000 + (95 - h) * 10, qty = 1 }) end
    local day = S.PriceChart.HeaderParts(S.store, 20, NOON, "1D")
    eq(day.changeLabel, "24h"); eq(day.change > 0, true)
    local week = S.PriceChart.HeaderParts(S.store, 20, NOON, "1W")
    eq(week.changeLabel, "3d", "just under four days exist (rounded down), so it does not claim 7d")
    eq(week.change > day.change, true, "a longer span moved more on a steady climb")
    local month = S.PriceChart.HeaderParts(S.store, 20, NOON, "1M")
    eq(month.change, nil, "4 days is less than half of 30")
    eq(S.PriceChart.HeaderParts(S.store, 20, NOON).changeLabel, "24h", "24h by default")
    Fake.uninstall()
end)

test("Format.Change is coloured by direction and empty for nothing", function()
    local S = setup()
    eq(S.Format.Change(nil), "")
    eq(S.Format.Change(1.5):find("\226\150\178" .. "1.50%", 1, true) ~= nil, true, "an up triangle and the size, no plus sign")
    eq(S.Format.Change(-1.5):find("\226\150\188" .. "1.50%", 1, true) ~= nil, true, "a down triangle and the size, no minus sign")
    eq(S.Format.Change(0.001):find("0.00%", 1, true) ~= nil, true, "a move that rounds to nothing")
    eq(S.Format.Change(0.001):find("\226\150", 1, true), nil, "has no triangle")
    eq(S.Format.Change(-0.002):find("\226\150", 1, true), nil, "neither does a tiny fall")
    eq(S.Format.Change(1.5):find("|cff33c773", 1, true) ~= nil, true, "green")
    eq(S.Format.Change(-1.5):find("|cffeb4d4d", 1, true) ~= nil, true, "red")
    eq(S.Format.Change(0):find("|cff999999", 1, true) ~= nil, true, "grey")
    Fake.uninstall()
end)

test("each watchlist row shows the recent move beside the price and the 24h move after it", function()
    local S = setup()
    local panel = panelFor(S)
    local row = shownRows(panel)[1] -- item 7
    eq(row.recent.text:find("0.76%", 1, true) ~= nil, true, row.recent.text)
    eq(row.recent.text:find("\226\150\178", 1, true) ~= nil, true, "up triangle")
    eq(row.change.text:find("24h", 1, true) ~= nil, true, row.change.text)
    eq(row.change.text:find("\226\150\178", 1, true) ~= nil, true, "item 7 rose")
    eq(row.recent.points[#row.recent.points][2], row.price, "the recent move right after the price")
    eq(row.change.points[#row.change.points][2], row.recent, "and the 24h move after that")
    local empty = shownRows(panel)[3]
    eq(empty.recent.text, ""); eq(empty.change.text, "", "no data: no moves shown")
    Fake.uninstall()
end)

test("the price line in a row is static: no cursor, crosshair or tooltip", function()
    local S = setup()
    local panel = panelFor(S)
    local spark = shownRows(panel)[1].spark
    eq(spark.config.static, true)
    local hovered = 0
    local real = S.Charts.Hover
    S.Charts.Hover = function(...) hovered = hovered + 1 end
    spark.CursorPosition = function() return 5, 5 end -- as if the mouse were over it
    Fake.fire(spark.frame, "OnUpdate")
    eq(hovered, 0, "static charts never draw a hover")
    -- the same cursor on a normal chart does
    local normal = S.Charts.Create(UIParent, { series = { { type = "line", points = { { x = 1, y = 1 }, { x = 2, y = 2 } } } } })
    normal.frame:SetSize(100, 50)
    normal.CursorPosition = function() return 5, 5 end
    Fake.fire(normal.frame, "OnUpdate")
    eq(hovered > 0, true, "a normal chart does")
    S.Charts.Hover = real
    Fake.uninstall()
end)

test("dropping an item on the watchlist tracks it and selects it for the group", function()
    local S = setup()
    local carrying = 99
    GetCursorInfo = function() return "item", carrying end
    ClearCursor = function() end
    local panel = panelFor(S)
    local events = {}
    S.Events:On("TRACKED_CHANGED", function(id, on) events[#events + 1] = { id, on } end)
    Fake.fire(panel.list, "OnReceiveDrag")
    eq(S.tracked:Has(99), true, "now tracked")
    eq(S.Link.Get("A"), 99, "and shown in the chart")
    eq(events[1][1], 99); eq(events[1][2], true)
    eq(#shownRows(panel), 4, "it appears in the list")

    carrying = 8 -- an item that is already tracked: just selected, no second event
    Fake.fire(shownRows(panel)[2], "OnReceiveDrag")
    eq(S.Link.Get("A"), 8)
    carrying = 7
    Fake.fire(panel.frame, "OnReceiveDrag")
    eq(S.Link.Get("A"), 7)
    eq(#events, 1, "tracking was announced once")
    GetCursorInfo, ClearCursor = nil, nil
    Fake.uninstall()
end)

test("dropping something that is not an item is ignored by the watchlist", function()
    local S = setup()
    S.ItemInfo.Exists = function(id) return id ~= 555 end
    GetCursorInfo = function() return "item", 555 end
    ClearCursor = function() end
    local panel = panelFor(S)
    Fake.fire(panel.list, "OnReceiveDrag")
    eq(S.tracked:Has(555), false, "an ID the game says does not exist is not tracked")
    eq(S.Link.Get("A"), nil)
    GetCursorInfo, ClearCursor = nil, nil
    Fake.uninstall()
end)

test("the watchlist shows its own drop cue while an item is carried", function()
    local S = setup()
    local panel = panelFor(S)
    local cue
    for _, o in ipairs(Fake.objects) do if o.kind == "FontString" and o.text == "Drop to track this item" then cue = o end end
    eq(cue ~= nil, true, "worded for tracking, not charting")
    GetCursorInfo = function() return "item", 5 end
    local watcher
    for _, o in ipairs(Fake.objects) do if o.events and o.events["CURSOR_CHANGED"] then watcher = o end end
    Fake.fire(watcher, "OnEvent", "CURSOR_CHANGED")
    eq(cue.parent.shown, true)
    GetCursorInfo = function() return nil end
    Fake.fire(watcher, "OnEvent", "CURSOR_CHANGED")
    eq(cue.parent.shown, false)
    GetCursorInfo = nil
    Fake.uninstall()
end)

test("with too little history the scope move is a dim dash, not a gap, and says how much is needed", function()
    local S = setup()
    local parts = S.PriceChart.HeaderParts(S.store, 7, NOON, "1W")
    eq(parts.change, nil)
    local text = S.PriceChart.ChangeText(parts)
    eq(text:find("- 7d", 1, true) ~= nil, true, text)
    eq(text:find("|cff33c773", 1, true), nil); eq(text:find("|cffeb4d4d", 1, true), nil)
    eq(parts.needSpan, 3.5 * DAY)
    eq(parts.history, 47 * HOUR, "how much history exists")
    eq(S.store:HistorySpan(9, NOON), 0, "none for an item with no readings")
    local full = S.PriceChart.HeaderParts(S.store, 7, NOON, "1D")
    eq(S.PriceChart.ChangeText(full):find("%", 1, true) ~= nil, true, "a real move still shows as before")
    Fake.uninstall()
end)
