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
    "Features/PriceChart.lua", "Features/ItemPicker.lua", "Features/ChartPanel.lua", "Features/Watchlist.lua", "Features/Ticker.lua", "Features/Movers.lua", "Features/StatusBar.lua",
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

test("each panel type has one pop-out window of its own, with its own panel", function()
    local S = setup()
    local chart = S.PopOut.Open("chart", { itemID = 7 })
    local list = S.PopOut.Open("watchlist")
    eq(chart.win ~= list.win, true)
    eq(chart.panel ~= list.panel, true)
    eq(chart.panel:GetItem(), 7)
    eq(S.PopOut.IsOpen("chart"), true); eq(S.PopOut.IsOpen("watchlist"), true)
    eq(S.PopOut.IsOpen("nothing"), false)
    Fake.uninstall()
end)

test("popping out again reuses the same window and updates it, never a second one", function()
    local S = setup()
    local first = S.PopOut.Open("chart", { itemID = 7 })
    local windows = 0
    for _, o in ipairs(Fake.objects) do if o.kind == "Frame" and o.scripts.OnDragStart then windows = windows + 1 end end
    local again = S.PopOut.Open("chart", { itemID = 8 })
    eq(again, first, "the same slot")
    eq(again.panel:GetItem(), 8, "pointed at the new item")
    local after = 0
    for _, o in ipairs(Fake.objects) do if o.kind == "Frame" and o.scripts.OnDragStart then after = after + 1 end end
    eq(after, windows, "no window was created")
    first.win.frame:Hide()
    eq(S.PopOut.Open("chart", { itemID = 9 }), first, "also after it was closed")
    eq(first.win.frame.shown, true)
    Fake.uninstall()
end)

test("the chart window keeps its old name so its saved position survives", function()
    local S = setup()
    local a = S.PopOut.Open("chart", { itemID = 7 })
    local c = S.PopOut.Open("watchlist")
    eq(StockistChartWindow, a.win.frame)
    eq(StockistPopout_watchlist, c.win.frame)
    Fake.uninstall()
end)

test("pop-outs of different types open at different spots, and one with a saved position stays put", function()
    local S = setup()
    local a = S.PopOut.Open("chart", { itemID = 7 })
    local b = S.PopOut.Open("watchlist")
    local last = b.win.frame.points[#b.win.frame.points]
    eq(last[1], "CENTER"); eq(last[4], 28, "down and right of the first"); eq(last[5], -28)
    Fake.uninstall()

    S = setup()
    S.settings.windows = { StockistPopout_watchlist = { point = "TOP", relPoint = "TOP", x = 5, y = -5, w = 300, h = 400 } }
    S.PopOut.Open("chart", { itemID = 7 })
    local d = S.PopOut.Open("watchlist")
    local p = d.win.frame.points[#d.win.frame.points]
    eq(p[1], "TOP"); eq(p[4], 5, "the remembered position wins")
    Fake.uninstall()
end)

test("choosing an item in the chart pop-out changes only the pop-out, not the workspace", function()
    local S = setup()
    S.Workspace.Show(7)
    local pop = S.PopOut.Open("chart", { itemID = 7 })
    pop.panel:Pick(9)
    eq(pop.panel:GetItem(), 9)
    eq(S.Link.Get("A"), 7, "the workspace's group is untouched")
    Fake.uninstall()
end)

test("the chart pop-out carries the scope and indicators of the panel it came from", function()
    local S = setup()
    local panel = S.ChartPanel.Create(UIParent, { link = "A", timeframe = "1M", indicators = { sma = false, bollinger = true } })
    panel:SetItem(7)
    panel:PopOut()
    local slot = S.PopOut.Slot("chart")
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
    local slot = S.PopOut.Slot("watchlist")
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

test("/stockist chart and the chart panel's pop-out button share the one chart pop-out", function()
    local S = setup()
    S.PriceChart.Show(7)
    local slot = S.PopOut.Slot("chart")
    local panel = S.ChartPanel.Create(UIParent, { link = "A", popOut = true })
    panel:SetItem(8)
    Fake.fire(panel.popOutButton, "OnClick")
    eq(S.PopOut.Slot("chart"), slot, "same window")
    eq(slot.panel:GetItem(), 8, "now showing the popped-out item")
    eq(S.PriceChart.PopOutPanel(), slot.panel)
    Fake.uninstall()
end)

local function raises(slot)
    local n = 0
    for _, c in ipairs(slot.win.frame.calls) do if c == "Raise" then n = n + 1 end end
    return n
end

test("popping out brings the window to the front, also when it is already open", function()
    local S = setup()
    local slot = S.PopOut.Open("chart", { itemID = 7 })
    eq(raises(slot), 1, "raised when first opened")
    S.PopOut.Open("chart", { itemID = 8 })
    eq(raises(slot), 2, "and again when asked for while already open")
    slot.win.frame:Hide()
    S.PopOut.Open("chart", { itemID = 9 })
    eq(raises(slot), 3, "and when reopened")
    local other = S.PopOut.Open("watchlist")
    eq(raises(other), 1)
    eq(raises(slot), 3, "raising one does not touch another")
    Fake.uninstall()
end)

test("a hidden panel that missed an item name catches up as soon as it is shown", function()
    local S = setup()
    local names = {}
    S.ItemInfo.Name = function(id) return names[id] end
    local panel = S.Watchlist.Create(UIParent, { link = "A" })
    panel.list:SetSize(220, 300); panel:Refresh()
    local function firstRowName()
        for _, row in ipairs(panel.rowFrames) do if row.itemID == 7 then return row.name.text end end
    end
    eq(firstRowName(), "item:7", "not cached yet")

    panel.frame.shown = false -- not on screen when the name arrives
    names[7] = "Linen Cloth"
    for _, o in ipairs(Fake.objects) do
        if o.events and o.events["GET_ITEM_INFO_RECEIVED"] then Fake.fire(o, "OnEvent", "GET_ITEM_INFO_RECEIVED", 7, true) end
    end
    eq(firstRowName(), "item:7", "a hidden panel does not redraw")
    panel.frame.shown = true
    Fake.fire(panel.frame, "OnShow")
    eq(firstRowName(), "Linen Cloth", "but catches up when shown")
    Fake.uninstall()
end)

test("a hidden chart panel also catches up when shown", function()
    local S = setup()
    local names = {}
    S.ItemInfo.Name = function(id) return names[id] end
    local panel = S.ChartPanel.Create(UIParent)
    panel:SetItem(7)
    eq(panel.nameText.text, "item:7")
    panel.frame.shown = false
    names[7] = "Linen Cloth"
    for _, o in ipairs(Fake.objects) do
        if o.events and o.events["GET_ITEM_INFO_RECEIVED"] then Fake.fire(o, "OnEvent", "GET_ITEM_INFO_RECEIVED", 7, true) end
    end
    eq(panel.nameText.text, "item:7")
    panel.frame.shown = true
    Fake.fire(panel.frame, "OnShow")
    eq(panel.nameText.text, "Linen Cloth")
    Fake.uninstall()
end)
