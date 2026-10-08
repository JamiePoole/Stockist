load_support("fake_wow")

local DAY, HOUR = 86400, 3600
local NOON = 40 * DAY + 12 * HOUR

local FILES = {
    "Core/Clock.lua", "Core/EventBus.lua", "Core/Registry.lua", "Core/Panels.lua", "Core/Link.lua", "Core/Format.lua",
    "Core/Calendar.lua", "Core/ItemInfo.lua", "Core/Help.lua", "Core/HelpTopics.lua", "Data/Rollup.lua",
    "Data/Indicators.lua", "Data/ReadingStore.lua", "UI/Charts/Charts.lua", "UI/Charts/Util.lua",
    "UI/Charts/Scale.lua", "UI/Charts/Formatters.lua", "UI/Charts/Theme.lua", "UI/Charts/Series/Line.lua",
    "UI/Charts/Series/Candle.lua", "UI/Charts/Series/Bar.lua", "UI/Charts/Overlays/Overlays.lua",
    "UI/Charts/Core.lua", "UI/Charts/FrameCanvas.lua", "UI/Charts/ChartFrame.lua", "UI/Kit/Tooltip.lua",
    "UI/Kit/Button.lua", "UI/Kit/IconButton.lua", "UI/Kit/Window.lua", "Features/PriceChart.lua", "Features/ChartPanel.lua",
}

--- A fresh addon with the fake client installed. Item 7 has two days of hourly history, item 8 only
--- three scans, item 9 nothing.
local function setup()
    Fake.install()
    local S = load_addon(unpack(FILES))
    S.settings = {}
    S.Clock.now = function() return NOON end
    S.store = S.ReadingStore.New({})
    for h = 0, 47 do S.store:Add({ item = 7, ts = NOON - h * HOUR, price = 1000 + h * 5, qty = 40 }) end
    for i = 0, 2 do S.store:Add({ item = 8, ts = NOON - i * 900, price = 500 + i, qty = 3 }) end
    return S
end

local function drawChart(panel)
    Fake.fire(panel.chart.frame, "OnUpdate")
end

test("a panel shows the item's name, price and age", function()
    local S = setup()
    local panel = S.ChartPanel.Create(UIParent)
    panel:SetItem(7)
    eq(panel.nameText.text, "item:7", "uncached item falls back to its id")
    eq(panel.priceText.text, "10|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t", "1000 copper shown with the silver coin icon")
    eq(panel.metaText.text:find("updated", 1, true) ~= nil, true)
    eq(panel:GetItem(), 7)
    Fake.uninstall()
end)

test("an item with no data says so instead of failing", function()
    local S = setup()
    local panel = S.ChartPanel.Create(UIParent)
    panel:SetItem(9)
    eq(panel.priceText.text, "")
    eq(panel.metaText.text, "no data yet")
    Fake.uninstall()
end)

test("the chart draws through the real canvas code", function()
    local S = setup()
    local panel = S.ChartPanel.Create(UIParent)
    panel:SetItem(7)
    drawChart(panel)
    eq(#panel.chart.main.pools.line > 0, true, "lines (wicks, grid)")
    eq(#panel.chart.main.pools.rect > 0, true, "rectangles (candle bodies, bars)")
    eq(#panel.chart.main.pools.text > 0, true, "axis labels")
    Fake.uninstall()
end)

test("the scope buttons change the chart and show the chosen one as pressed", function()
    local S = setup()
    local panel = S.ChartPanel.Create(UIParent)
    panel:SetItem(7)
    local dayRange = panel.chart.config.x.range
    local Button = S.UI.Button
    eq(Button.IsSelected(panel.tfButtons["1D"]), true, "1D is the active scope at first")
    eq(Button.IsSelected(panel.tfButtons["1W"]), false)

    Fake.fire(panel.tfButtons["1W"], "OnClick")
    eq(panel.state.timeframe, "1W")
    eq(Button.IsSelected(panel.tfButtons["1W"]), true); eq(Button.IsSelected(panel.tfButtons["1D"]), false)
    local weekRange = panel.chart.config.x.range
    eq(weekRange[2] - weekRange[1] > dayRange[2] - dayRange[1], true, "a wider window")
    Fake.uninstall()
end)

test("the active scope keeps the button art but recoloured blue, with white text and no mouse effects", function()
    local S = setup()
    local panel = S.ChartPanel.Create(UIParent)
    panel:SetItem(7)
    local active, other = panel.tfButtons["1D"], panel.tfButtons["1W"]

    eq(active.enabled, true, "still enabled, so its tooltip works")
    for _, key in ipairs({ "Left", "Middle", "Right" }) do
        local tex = active[key]
        eq(tex.desaturated, true, key .. " is desaturated first, so the shading is kept")
        eq(tex.vertexColor[3] > tex.vertexColor[1], true, key .. " is tinted blue")
    end
    local text = active:GetFontString().textColor
    eq(text[1] == 1 and text[2] == 1 and text[3] == 1, true, "white text")
    eq(active:GetHighlightTexture().alpha, 0, "no hover effect")
    eq(active:GetPushedTexture().alpha, 0, "no pressed effect")
    eq(active.pushedTextOffset[1], 0); eq(active.pushedTextOffset[2], 0, "the label does not indent")
    eq(#active.clickButtons, 0, "it takes no clicks, so it never enters the pressed state")

    eq(other.enabled, true)
    for _, key in ipairs({ "Left", "Middle", "Right" }) do
        eq(other[key].desaturated, false, "inactive scopes keep the stock red art")
        eq(other[key].vertexColor[1] == 1 and other[key].vertexColor[2] == 1 and other[key].vertexColor[3] == 1, true)
    end
    local gold = other:GetFontString().textColor
    eq(gold[1] == 1 and gold[2] == 0.82 and gold[3] == 0, true, "inactive scopes keep the normal gold text")
    eq(other:GetHighlightTexture().alpha, 1, "inactive scopes keep their hover effect")
    eq(other:GetPushedTexture().alpha, 1)
    eq(other.pushedTextOffset[1], 1); eq(other.pushedTextOffset[2], -1, "the stock indent on press")
    eq(other.clickButtons[1], "LeftButtonUp")
    Fake.uninstall()
end)

test("clicking the active scope does nothing, and the blue moves when the scope changes", function()
    local S = setup()
    local panel = S.ChartPanel.Create(UIParent)
    panel:SetItem(7)
    local drawn = panel.chart.config
    Fake.fire(panel.tfButtons["1D"], "OnClick")
    eq(panel.chart.config, drawn, "no redraw for a click on the active scope")

    Fake.fire(panel.tfButtons["1M"], "OnClick")
    eq(S.UI.Button.IsSelected(panel.tfButtons["1M"]), true)
    eq(S.UI.Button.IsSelected(panel.tfButtons["1D"]), false, "the old one is released")
    eq(panel.tfButtons["1M"].Left.desaturated, true)
    eq(panel.tfButtons["1D"].Left.desaturated, false, "and has its red art back")
    eq(panel.tfButtons["1D"]:GetHighlightTexture().alpha, 1, "and its hover effect")
    eq(panel.tfButtons["1D"].clickButtons[1], "LeftButtonUp", "and can be clicked again")
    eq(panel.tfButtons["1D"].pushedTextOffset[2], -1)
    Fake.uninstall()
end)

test("scope buttons go back to normal when a message replaces the chart", function()
    local S = setup()
    local panel = S.ChartPanel.Create(UIParent)
    panel:SetItem(7)
    panel:SetItem(9)
    for key, btn in pairs(panel.tfButtons) do
        eq(btn.enabled, false, key .. " is unavailable while there is nothing to chart")
        eq(S.UI.Button.IsSelected(btn), false, key .. " is not shown as selected")
        eq(btn.Left.desaturated, false, key .. " has the stock art")
    end
    panel:SetItem(7)
    for key, btn in pairs(panel.tfButtons) do eq(btn.enabled, true, key .. " is usable again") end
    eq(S.UI.Button.IsSelected(panel.tfButtons["1D"]), true)
    eq(panel.tfButtons["1D"].Left.desaturated, true)
    Fake.uninstall()
end)

test("indicator buttons toggle overlays while the view has enough points", function()
    local S = setup()
    local panel = S.ChartPanel.Create(UIParent)
    panel:SetItem(7)
    eq(panel.toggleButtons.sma.enabled, true, "48 hourly candles: SMA is available")
    eq(#panel.chart.config.panes[1].overlays, 1, "SMA is on by default")

    Fake.fire(panel.toggleButtons.sma, "OnClick")
    eq(panel.state.indicators.sma, false)
    eq(#panel.chart.config.panes[1].overlays, 0)

    Fake.fire(panel.toggleButtons.bollinger, "OnClick")
    eq(panel.state.indicators.bollinger, true)
    eq(#panel.chart.config.panes[1].overlays, 1)
    Fake.uninstall()
end)

test("an indicator the view cannot draw is disabled and ignores clicks, and its tooltip says why", function()
    local S = setup()
    local panel = S.ChartPanel.Create(UIParent)
    panel:SetItem(8)
    eq(panel.toggleButtons.sma.enabled, false)
    eq(panel.toggleButtons.bollinger.enabled, false)
    local before = panel.state.indicators.sma
    Fake.fire(panel.toggleButtons.sma, "OnClick")
    eq(panel.state.indicators.sma, before, "a disabled button does nothing")

    Fake.fire(panel.toggleButtons.sma, "OnEnter")
    eq(Fake.called(GameTooltip, "AddLine"), true, "the tooltip is shown even while disabled")
    Fake.uninstall()
end)

test("two panels keep their own item, scope and indicators", function()
    local S = setup()
    local a, b = S.ChartPanel.Create(UIParent), S.ChartPanel.Create(UIParent)
    a:SetItem(7)
    b:SetItem(8)
    Fake.fire(a.tfButtons["1W"], "OnClick")
    Fake.fire(a.toggleButtons.sma, "OnClick")
    eq(a.state.timeframe, "1W"); eq(b.state.timeframe, "1D")
    eq(a.state.indicators.sma, false); eq(b.state.indicators.sma, true)
    eq(a:GetItem(), 7); eq(b:GetItem(), 8)
    eq(a.state.indicators ~= b.state.indicators, true, "no shared tables")
    Fake.uninstall()
end)

test("turning tutorial mode off hides the legend and gives the room back to the chart", function()
    local S = setup()
    local panel = S.ChartPanel.Create(UIParent)
    panel:SetItem(7)
    eq(panel.legendKey.shown, true)
    eq(panel.legendKey.text:find("Reading the chart", 1, true) ~= nil, true)
    S.Help.SetTutorial(false)
    eq(panel.legendKey.shown, false); eq(panel.legendTips.shown, false)
    S.Help.SetTutorial(true)
    eq(panel.legendKey.shown, true)
    Fake.uninstall()
end)

test("a finished scan refreshes a visible panel, and a destroyed one stops listening", function()
    local S = setup()
    local panel = S.ChartPanel.Create(UIParent)
    panel:SetItem(7)
    local before = panel.priceText.text
    S.store:Add({ item = 7, ts = NOON + 60, price = 99999, qty = 1 })
    S.Events:Fire("SCAN_COMPLETE", 1, NOON + 60)
    eq(panel.priceText.text ~= before, true, "price updated")

    panel:Destroy()
    local after = panel.priceText.text
    S.store:Add({ item = 7, ts = NOON + 120, price = 12, qty = 1 })
    S.Events:Fire("SCAN_COMPLETE", 1, NOON + 120)
    eq(panel.priceText.text, after, "no refresh after Destroy")
    Fake.uninstall()
end)

test("hovering the item name asks the game for its tooltip", function()
    local S = setup()
    local panel = S.ChartPanel.Create(UIParent)
    panel:SetItem(7)
    Fake.fire(panel.nameHit, "OnEnter")
    eq(Fake.called(GameTooltip, "SetItemByID"), true)
    Fake.fire(panel.nameHit, "OnLeave")
    eq(GameTooltip.shown, false, "the tooltip is hidden again")
    Fake.uninstall()
end)

test("a resize re-lays out the chart for the legend", function()
    local S = setup()
    local panel = S.ChartPanel.Create(UIParent)
    panel:SetItem(7)
    local before = panel.chart.frame.points
    Fake.fire(panel.frame, "OnSizeChanged")
    eq(panel.chart.frame.points ~= before, true, "the chart was cleared and re-anchored")
    eq(#panel.chart.frame.points, 2, "top-left and bottom-right")
    Fake.uninstall()
end)

test("panels register themselves by name for the workspace", function()
    local S = setup()
    local type = S.Panels:Get("chart")
    eq(type ~= nil, true)
    eq(type.create, S.ChartPanel.Create)
    local panel = type.create(UIParent, { itemID = 7, timeframe = "1W" })
    eq(panel:GetItem(), 7)
    eq(S.UI.Button.IsSelected(panel.tfButtons["1W"]), true, "starts on the requested scope")
    Fake.uninstall()
end)

test("PriceChart.Show opens one window and reuses it for other items", function()
    local S = setup()
    S.PriceChart.Show(7)
    local win = StockistChartWindow
    eq(win ~= nil, true, "the window was created")
    eq(win.shown, true)
    S.PriceChart.Show(8)
    eq(StockistChartWindow, win, "same window")
    Fake.flush() -- the deferred second layout pass runs without error
    eq(#UISpecialFrames, 1, "registered for Esc once")
    Fake.uninstall()
end)
