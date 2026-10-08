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
    "Features/Workspace.lua",
}

local NAMES = { [7] = "Linen Cloth", [8] = "Mageweave Cloth", [9] = "Heart of Fire" }

local function setup()
    Fake.install()
    local S = load_addon(unpack(FILES))
    S.settings = {}
    S.Clock.now = function() return NOON end
    S.db = { scan = {} }
    S.store = S.ReadingStore.New(S.db)
    for id = 7, 9 do
        for h = 47, 0, -1 do S.store:Add({ item = id, ts = NOON - h * HOUR, price = 100 * id + h, qty = 10 }) end
    end
    S.tracked = S.Tracked.New({})
    S.tracked:Add(7); S.tracked:Add(8)
    S.ItemInfo.Name = function(id) return NAMES[id] end
    S.Print = function() end
    return S
end

test("each pop-out is its own window with its own panel", function()
    local S = setup()
    local a = S.PopOut.Open("chart", { itemID = 7 })
    local b = S.PopOut.Open("chart", { itemID = 8 })
    local c = S.PopOut.Open("watchlist")
    eq(a.win ~= b.win, true, "two chart windows")
    eq(a.panel ~= b.panel, true)
    eq(a.panel:GetItem(), 7); eq(b.panel:GetItem(), 8)
    eq(a.win.frame.shown, true); eq(b.win.frame.shown, true); eq(c.win.frame.shown, true)
    eq(S.PopOut.OpenCount("chart"), 2)
    eq(S.PopOut.OpenCount("watchlist"), 1)
    Fake.uninstall()
end)

test("the first chart window keeps its old name so its saved position survives; the others are numbered", function()
    local S = setup()
    local a = S.PopOut.Open("chart", { itemID = 7 })
    local b = S.PopOut.Open("chart", { itemID = 8 })
    local c = S.PopOut.Open("watchlist")
    eq(StockistChartWindow, a.win.frame)
    eq(StockistPopout_chart_2, b.win.frame)
    eq(StockistPopout_watchlist_1, c.win.frame)
    Fake.uninstall()
end)

test("a closed pop-out is reused by the next one, with the new options", function()
    local S = setup()
    local a = S.PopOut.Open("chart", { itemID = 7 })
    local b = S.PopOut.Open("chart", { itemID = 8 })
    a.win.frame:Hide()
    local c = S.PopOut.Open("chart", { itemID = 9 })
    eq(c, a, "the closed window came back")
    eq(c.panel:GetItem(), 9)
    eq(c.win.frame.shown, true)
    eq(S.PopOut.OpenCount("chart"), 2)
    Fake.uninstall()
end)

test("when every slot is open the last one is reused instead of making more", function()
    local S = setup()
    local last
    for i = 1, 14 do last = S.PopOut.Open("chart", { itemID = 7 + (i % 3) }) end
    eq(#S.PopOut.slots.chart, 12)
    eq(last, S.PopOut.slots.chart[12])
    Fake.uninstall()
end)

test("new windows are staggered, but one with a saved position stays put", function()
    local S = setup()
    S.PopOut.Open("chart", { itemID = 7 })
    local b = S.PopOut.Open("chart", { itemID = 8 })
    local last = b.win.frame.points[#b.win.frame.points]
    eq(last[1], "CENTER")
    eq(last[4], 28, "down and right of the first")
    eq(last[5], -28)
    Fake.uninstall()

    S = setup()
    S.settings.windows = { StockistPopout_chart_2 = { point = "TOP", relPoint = "TOP", x = 5, y = -5, w = 600, h = 400 } }
    S.PopOut.Open("chart", { itemID = 7 })
    local d = S.PopOut.Open("chart", { itemID = 8 })
    local p = d.win.frame.points[#d.win.frame.points]
    eq(p[1], "TOP"); eq(p[4], 5, "the remembered position wins")
    Fake.uninstall()
end)

test("pop-outs of the same item are independent: choosing an item in one leaves the other alone", function()
    local S = setup()
    local a = S.PopOut.Open("chart", { itemID = 7 })
    local b = S.PopOut.Open("chart", { itemID = 7 })
    a.panel:Pick(9)
    eq(a.panel:GetItem(), 9); eq(b.panel:GetItem(), 7)
    eq(S.Link.Get("A"), nil, "and no link group was touched")
    Fake.uninstall()
end)

test("the chart pop-out carries the scope and indicators of the panel it came from", function()
    local S = setup()
    local panel = S.ChartPanel.Create(UIParent, { link = "A", timeframe = "1M", indicators = { sma = false, bollinger = true } })
    panel:SetItem(7)
    panel:PopOut()
    local slot = S.PopOut.Slot("chart", 1)
    eq(slot.panel.state.timeframe, "1M")
    eq(slot.panel.state.indicators.bollinger, true); eq(slot.panel.state.indicators.sma, false)
    slot.panel.state.indicators.sma = true
    eq(panel.state.indicators.sma, false, "separate tables: they do not share state")
    eq(slot.panel.link, nil, "the pop-out is not linked")
    Fake.uninstall()
end)

test("every panel that can pop out has a button for it, and a popped-out panel has none", function()
    local S = setup()
    local watch = S.Watchlist.Create(UIParent, { link = "A", popOut = true })
    eq(watch.popOutButton ~= nil, true)
    Fake.fire(watch.popOutButton, "OnClick")
    local slot = S.PopOut.Slot("watchlist", 1)
    eq(slot ~= nil and slot.win.frame.shown, true)
    eq(slot.panel.popOutButton, nil, "no pop-out button inside a pop-out")
    eq(slot.panel.link, "A", "a popped-out watchlist still drives the group")
    local plain = S.Watchlist.Create(UIParent, {})
    eq(plain.popOutButton, nil)
    Fake.uninstall()
end)

test("a popped-out watchlist selecting an item drives the workspace charts", function()
    local S = setup()
    S.Workspace.Show(7)
    local ws = S.ChartPanel.Create(UIParent, { link = "A" })
    local slot = S.PopOut.Open("watchlist", { link = "A" })
    slot.panel.list:SetSize(220, 300); slot.panel:Refresh()
    local row
    for _, r in ipairs(slot.panel.rowFrames) do if r.itemID == 8 then row = r end end
    Fake.fire(row, "OnClick", "LeftButton")
    eq(S.Link.Get("A"), 8)
    eq(ws:GetItem(), 8)
    Fake.uninstall()
end)

test("window titles name the panel and the item, and follow the item", function()
    local S = setup()
    local slot = S.PopOut.Open("chart", { itemID = 7 })
    eq(slot.win.title.text, "Stockist - Linen Cloth (Price chart)")
    slot.panel:SetItem(8)
    eq(slot.win.title.text, "Stockist - Mageweave Cloth (Price chart)", "changes with the item")
    slot.panel:Pick(99)
    eq(slot.win.title.text, "Stockist - item:99 (Price chart)", "an uncached name falls back to the ID")
    NAMES[99] = "Late Arrival"
    slot.panel:Refresh()
    eq(slot.win.title.text, "Stockist - Late Arrival (Price chart)", "and fills in when the name arrives")
    NAMES[99] = nil
    local wl = S.PopOut.Open("watchlist")
    eq(wl.win.title.text, "Stockist - Watchlist")
    Fake.uninstall()
end)

test("a title with no item is just the panel name", function()
    local S = setup()
    local slot = S.PopOut.Open("chart", {})
    eq(slot.win.title.text, "Stockist - Price chart")
    Fake.uninstall()
end)

test("the window title is cut off before it reaches the buttons", function()
    local S = setup()
    local slot = S.PopOut.Open("chart", { itemID = 7 })
    local rightAnchored
    for _, pt in ipairs(slot.win.title.points) do if pt[1] == "RIGHT" then rightAnchored = pt end end
    eq(rightAnchored ~= nil and rightAnchored[2], slot.win.helpButton, "bounded by the help button")
    Fake.uninstall()
end)

test("items dropped on a pop-out go to that pop-out only, whatever its type", function()
    local S = setup()
    GetCursorInfo = function() return "item", 9 end
    ClearCursor = function() end
    local chart = S.PopOut.Open("chart", { itemID = 7 })
    local list = S.PopOut.Open("watchlist")
    Fake.fire(chart.win.frame, "OnReceiveDrag")
    eq(chart.panel:GetItem(), 9)
    Fake.fire(list.win.frame, "OnReceiveDrag")
    eq(S.tracked:Has(9), true, "dropping on a watchlist window tracks it")
    GetCursorInfo, ClearCursor = nil, nil
    Fake.uninstall()
end)

test("opening a panel type that does not exist is a clear error", function()
    local S = setup()
    local ok, err = pcall(S.PopOut.Open, "nonsense")
    eq(ok, false)
    eq(tostring(err):find("no panel type 'nonsense'", 1, true) ~= nil, true, tostring(err))
    Fake.uninstall()
end)

test("the shared window used by /stockist chart is one slot, separate from windows of their own", function()
    local S = setup()
    S.PriceChart.Show(7)
    local first = S.PopOut.Slot("chart", 1)
    S.PriceChart.Show(8)
    eq(S.PopOut.Slot("chart", 1), first, "same slot")
    eq(first.panel:GetItem(), 8)
    local own = S.PopOut.Open("chart", { itemID = 9 })
    eq(own ~= first, true, "a window of its own does not disturb the shared one")
    eq(first.panel:GetItem(), 8)
    eq(S.PriceChart.PopOutPanel(), first.panel)
    Fake.uninstall()
end)
