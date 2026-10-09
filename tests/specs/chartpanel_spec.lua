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
    "UI/Kit/Button.lua", "UI/Kit/IconButton.lua", "UI/Kit/Window.lua", "Features/PopOut.lua", "Features/PriceChart.lua", "Features/ItemPicker.lua", "Features/ChartPanel.lua",
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
        eq(active[key].desaturated, true, key .. " is turned grey, which keeps the border and the shading")
    end
    local glow = active.selectedGlow
    eq(glow.shown, true, "a blue layer over the centre")
    eq(glow.blendMode, "ADD", "added to the grey art, so it brightens the shading instead of darkening it")
    eq(glow.color[3] > glow.color[1], true, "and it is blue")
    eq(glow.color[3] > 0.7, true, "a bright blue")
    -- it sits inside the border, so the grey bevel stays visible
    local topLeft, bottomRight = glow.points[1], glow.points[2]
    eq(topLeft[1], "TOPLEFT"); eq(topLeft[2] > 0 and -topLeft[3] > 0, true, "inset from the top-left")
    eq(bottomRight[1], "BOTTOMRIGHT"); eq(bottomRight[2] < 0 and bottomRight[3] > 0, true, "inset from the bottom-right")
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
    eq(other.selectedGlow.shown, false, "and no blue layer")
    local gold = other:GetFontString().textColor
    eq(gold[1] == 1 and gold[2] == 0.82 and gold[3] == 0, true, "inactive scopes keep the normal gold text")
    eq(other:GetHighlightTexture().alpha, 1, "inactive scopes keep their hover effect")
    eq(other:GetPushedTexture().alpha, 1)
    eq(other.pushedTextOffset[1], 1); eq(other.pushedTextOffset[2], -1, "the stock indent on press")
    eq(other.clickButtons[1], "LeftButtonUp")
    Fake.uninstall()
end)

test("the selected button has a gentle blue layer and a vignette that darkens the edges", function()
    local S = setup()
    local panel = S.ChartPanel.Create(UIParent)
    panel:SetItem(7)
    local btn = panel.tfButtons["1D"]
    local glow = btn.selectedGlow

    eq(glow.blendMode, "ADD")
    eq(glow.color[4] > 0.5 and glow.color[4] <= 0.7, true, "bright but not flat: the art's own shading still shows through (not 90%)")
    eq(#btn.selectedLayers, 5, "the blue layer and four vignette fades")

    local horizontal, vertical = 0, 0
    for i = 2, 5 do
        local strip = btn.selectedLayers[i]
        eq(strip.blendMode, "BLEND", "fades use normal blending")
        eq(strip.shown, true)
        local orientation, from, to = strip.gradient[1], strip.gradient[2], strip.gradient[3]
        if orientation == "HORIZONTAL" then horizontal = horizontal + 1 else vertical = vertical + 1 end
        eq(from.r == 0 and from.g == 0 and from.b == 0 and to.r == 0 and to.g == 0 and to.b == 0, true, "black fades")
        local darker, clearer = math.max(from.a, to.a), math.min(from.a, to.a)
        eq(clearer, 0, "one end is fully transparent")
        eq(darker > 0 and darker < 1, true, "the other end is a soft dark")
    end
    eq(horizontal, 2); eq(vertical, 2, "left and right, top and bottom")

    -- the dark end is at the outer edge, the clear end towards the centre
    local left, right, top, bottom = btn.selectedLayers[2], btn.selectedLayers[3], btn.selectedLayers[4], btn.selectedLayers[5]
    eq(left.gradient[2].a > 0 and left.gradient[3].a == 0, true, "left: dark at the left edge")
    eq(right.gradient[2].a == 0 and right.gradient[3].a > 0, true, "right: dark at the right edge")
    eq(top.gradient[2].a == 0 and top.gradient[3].a > 0, true, "top: dark at the top (vertical gradients run bottom to top)")
    eq(bottom.gradient[2].a > 0 and bottom.gradient[3].a == 0, true, "bottom: dark at the bottom")

    -- an inactive button shows none of it
    for _, layer in ipairs(panel.tfButtons["1W"].selectedLayers) do eq(layer.shown, false) end
    Fake.uninstall()
end)

test("the vignette falls back to the older gradient call, and is dropped if neither works", function()
    local S = setup()
    local function buttonWith(gradientCall)
        local btn = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
        local make = btn.CreateTexture
        btn.CreateTexture = function(self, ...)
            local tex = make(self, ...)
            gradientCall(tex)
            return tex
        end
        S.UI.Button.SetSelected(btn, true)
        return btn
    end

    local old = buttonWith(function(tex)
        tex.SetGradient = function() error("not in this client") end
        tex.SetGradientAlpha = function(t, orientation, ...) t.legacyGradient = { orientation, ... } end
    end)
    eq(#old.selectedLayers, 5, "all four fades are kept via SetGradientAlpha")
    eq(old.selectedLayers[2].legacyGradient[1], "HORIZONTAL")
    eq(#old.selectedLayers[2].legacyGradient, 9, "orientation + two RGBA colours")

    local none = buttonWith(function(tex)
        tex.SetGradient = function() error("no") end
        tex.SetGradientAlpha = function() error("no") end
    end)
    eq(#none.selectedLayers, 1, "only the blue layer: no solid white blocks")
    eq(none.selectedGlow.shown, true)
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
    eq(panel.tfButtons["1D"].selectedGlow.shown, false); eq(panel.tfButtons["1M"].selectedGlow.shown, true, "the blue moved")
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

test("a switched-on indicator button is coloured but stays fully clickable; off is plain", function()
    local S = setup()
    local panel = S.ChartPanel.Create(UIParent)
    panel:SetItem(7)
    local Button = S.UI.Button
    local sma, bb = panel.toggleButtons.sma, panel.toggleButtons.bollinger

    eq(Button.IsActive(sma), true, "SMA is on by default")
    local glow = sma.selectedGlow.color
    eq(glow[2] > glow[1] and glow[2] > glow[3], true, "green by default")
    eq(sma.selectedGlow.shown, true)
    for _, key in ipairs({ "Left", "Middle", "Right" }) do eq(sma[key].desaturated, true) end
    local white = sma:GetFontString().textColor
    eq(white[1] == 1 and white[2] == 1 and white[3] == 1, true, "white text on the colour")
    -- unlike the selected scope, a switch keeps its hover, press and click behaviour so it can be turned off
    eq(sma:GetHighlightTexture().alpha, nil, "hover effect untouched")
    eq(sma.pushedTextOffset, nil, "press behaviour untouched")
    eq(sma.clickButtons, nil, "click handling untouched")
    eq(sma.enabled, true)

    eq(Button.IsActive(bb), false, "Bollinger is off by default")
    eq(bb.selectedGlow.shown, false, "no colour while off")
    local gold = bb:GetFontString().textColor
    eq(gold[1] == 1 and gold[2] == 0.82 and gold[3] == 0, true, "plain gold text while off")

    Fake.fire(sma, "OnClick")
    eq(Button.IsActive(sma), false, "clicking it switches it off")
    eq(sma.selectedGlow.shown, false)
    Fake.fire(bb, "OnClick")
    eq(Button.IsActive(bb), true, "and the other one on")
    Fake.uninstall()
end)

test("the hover glow of a switched-on button is a lighter shade of its colour, and back to stock when off", function()
    local S = setup()
    local panel = S.ChartPanel.Create(UIParent)
    panel:SetItem(7)
    local sma = panel.toggleButtons.sma
    local hover = sma:GetHighlightTexture()
    eq(hover.desaturated, true, "no yellow: the stock glow is made grey first")
    local c = hover.vertexColor
    eq(c[2] > c[1] and c[2] > c[3], true, "still green")
    eq(c[1] > S.UI.Button.STYLES.green[1], true, "but lighter than the button colour")
    Fake.fire(sma, "OnClick")
    hover = sma:GetHighlightTexture()
    eq(hover.desaturated, false, "stock yellow glow when off")
    eq(hover.vertexColor[1] == 1 and hover.vertexColor[3] == 1, true)
    Fake.uninstall()
end)

test("an indicator the view cannot draw is greyed, not coloured, even if switched on", function()
    local S = setup()
    local panel = S.ChartPanel.Create(UIParent)
    panel:SetItem(8)
    eq(panel.state.indicators.sma, true, "the player's choice is remembered")
    eq(S.UI.Button.IsActive(panel.toggleButtons.sma), false, "but it is not shown as on")
    eq(panel.toggleButtons.sma.selectedGlow.shown, false)
    local grey = panel.toggleButtons.sma:GetFontString().textColor
    eq(grey[1] == 0.5 and grey[2] == 0.5 and grey[3] == 0.5, true, "greyed text")
    panel:SetItem(7)
    eq(S.UI.Button.IsActive(panel.toggleButtons.sma), true, "back on once there is data")
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

test("the scope's move sits right beside the price, with the smaller recent move after it", function()
    local S = setup()
    local panel = S.ChartPanel.Create(UIParent)
    for h = 47, 0, -1 do S.store:Add({ item = 11, ts = NOON - h * HOUR, price = 1000 + (47 - h) * 10, qty = 5 }) end
    panel:SetItem(11)
    eq(panel.changeText.text:find("24h", 1, true) ~= nil, true, "1D scope: the 24h move " .. panel.changeText.text)
    eq(panel.changeText.text:find("\226\150\178", 1, true) ~= nil, true, "it rose: an up triangle")
    eq(panel.recentText.text:find("recent", 1, true) ~= nil, true, panel.recentText.text)
    eq(panel.recentText.points[#panel.recentText.points][2], panel.changeText, "the recent move follows the scope's move")
    eq(panel.metaText.text, "updated just now")
    panel.state.timeframe = "1W"; panel:Refresh()
    eq(panel.changeText.text:find("24h", 1, true), nil, "the label follows the scope (only two days exist, so not 7d either)")
    eq(panel.changeText.text:find("7d", 1, true) ~= nil, true, "less than half of a week of history: a dim '- 7d'")
    eq(panel.changeText.text:find("%", 1, true), nil, "no percentage is claimed")
    eq(panel.changeText.text:find("|cff33c773", 1, true), nil, "and it is neither green nor red")
    local hint = panel:ChangeHint()
    eq(hint:find("needs about 3d", 1, true) ~= nil, true, hint)
    eq(hint:find("we have 47h", 1, true) ~= nil, true, "says how much exists: " .. hint)
    panel.state.timeframe = "1D"; panel:Refresh()
    eq(panel:ChangeHint(), nil, "no hint when the move is shown")
    panel:SetItem(9)
    eq(panel.changeText.text, "", "cleared when there is no data")
    eq(panel.recentText.text, "")
    Fake.uninstall()
end)

-- The header when the panel is too narrow for everything ----------------------------------------------

--- An item with two days of scans every hour, so every part of the header has something to show.
local function longNamePanel(S)
    for h = 47, 0, -1 do S.store:Add({ item = 12, ts = NOON - h * HOUR, price = 1000 + (47 - h) * 10, qty = 5 }) end
    S.ItemInfo.ColoredName = function() return "Craftsman's Writ: Shadow Goggles" end
    local panel = S.ChartPanel.Create(UIParent, { popOut = true })
    panel:SetItem(12)
    return panel
end

--- The header pieces' widths, so the tests pick sizes from the measured text, not magic numbers.
local function measure(panel)
    local m = { name = panel.nameText:GetStringWidth(), price = panel.priceText:GetStringWidth(),
        change = panel.changeText:GetStringWidth() }
    panel.recentText:SetText(panel.recentFull); m.recent = panel.recentText:GetStringWidth()
    panel.metaText:SetText(panel.metaChoices[1]); m.meta = panel.metaText:GetStringWidth()
    m.base = 12 + m.price + 8 + m.change              -- name excluded: price and scope move, with their gaps
    m.withRecent = m.base + 8 + m.recent
    m.full = m.withRecent + 12 + m.meta
    return m
end

local function widthFor(panel, m, name, rest) return panel.controlsWidth + 10 + name + rest end

test("a wide panel shows the whole header", function()
    local S = setup()
    local panel = longNamePanel(S)
    local m = measure(panel)
    eq(m.recent > 0 and m.change > 0, true, "the fixture really has both moves")
    panel.frame:SetWidth(widthFor(panel, m, m.name, m.full))
    panel:LayoutHeader()
    eq(panel.metaText.text:find("updated", 1, true) ~= nil, true, "everything fits")
    eq(panel.recentText.text ~= "", true)
    eq(panel.nameText.size[1] >= m.name, true, "the name is not cut")
    Fake.uninstall()
end)

test("with less room 'updated' goes first, then the recent move, then the name is cut", function()
    local S = setup()
    local panel = longNamePanel(S)
    local m = measure(panel)

    panel.frame:SetWidth(widthFor(panel, m, m.name, m.full) - 1)
    panel:LayoutHeader()
    eq(panel.metaText.text, "", "'updated ...' dropped first")
    eq(panel.recentText.text ~= "", true, "the recent move stays")
    eq(panel.changeText.text ~= "", true)
    eq(panel.nameText.size[1] >= m.name, true, "the name is still whole")

    panel.frame:SetWidth(widthFor(panel, m, m.name, m.withRecent) - 1)
    panel:LayoutHeader()
    eq(panel.recentText.text, "", "then the recent move goes")
    eq(panel.changeText.text ~= "", true, "the scope's move stays")
    eq(panel.nameText.size[1] >= m.name, true, "the name is still whole")

    panel.frame:SetWidth(widthFor(panel, m, m.name, m.base) - 30)
    panel:LayoutHeader()
    eq(panel.nameText.size[1], m.name - 30, "now the name is shortened (the client adds the '...')")
    eq(panel.priceText.text ~= "" and panel.changeText.text ~= "", true, "the price and the scope's move are never cut")
    eq(panel.nameHit.size[1] <= panel.nameText.size[1], true, "the hover area matches the shown name")
    Fake.uninstall()
end)

test("the text never reaches the buttons, however narrow the panel gets", function()
    local S = setup()
    local panel = longNamePanel(S)
    local m = measure(panel)
    eq(panel.controlsWidth > 0, true)
    for _, w in ipairs({ 900, 700, 560, 480, 430, 400, 380 }) do
        panel.frame:SetWidth(w)
        panel:LayoutHeader()
        local used = panel.nameText.size[1] + m.base
        if panel.recentText.text ~= "" then used = used + 8 + panel.recentText:GetStringWidth() end
        if panel.metaText.text ~= "" then used = used + 12 + panel.metaText:GetStringWidth() end
        local limit = w - panel.controlsWidth - 10
        if limit >= 1 + m.base then eq(used <= limit, true, "width " .. w) end
    end
    panel.frame:SetWidth(100) -- absurdly narrow: the name has no room left, but nothing breaks
    panel:LayoutHeader()
    eq(panel.nameText.size[1], 1)
    Fake.uninstall()
end)

test("'no data yet' outranks the item name", function()
    local S = setup()
    S.ItemInfo.ColoredName = function() return "Craftsman's Writ: Shadow Goggles" end
    local panel = S.ChartPanel.Create(UIParent)
    panel:SetItem(9)
    panel.frame:SetWidth(panel.controlsWidth + 10 + 150)
    panel:LayoutHeader()
    eq(panel.metaText.text, "no data yet", "the reason for the empty chart stays")
    local m = panel.metaText:GetStringWidth()
    eq(panel.nameText.size[1] + 12 + m, 150, "name, one gap and the message fill the room exactly")
    eq(panel.nameText.size[1] < panel.nameText:GetStringWidth(), true, "the name is what gets shortened")
    Fake.uninstall()
end)

test("resizing the panel re-fits the header", function()
    local S = setup()
    local panel = longNamePanel(S)
    local m = measure(panel)
    panel.frame:SetWidth(widthFor(panel, m, m.name, m.base) - 40)
    Fake.fire(panel.frame, "OnSizeChanged")
    eq(panel.nameText.size[1] < m.name, true, "shortened by the size change alone")
    panel.frame:SetWidth(2000)
    Fake.fire(panel.frame, "OnSizeChanged")
    eq(panel.metaText.text:find("updated", 1, true) ~= nil, true, "everything returns when there is room")
    eq(panel.recentText.text ~= "", true)
    Fake.uninstall()
end)

test("the moving average and the Bollinger bands are drawn in different colours, whatever else is on the chart", function()
    local S = setup()
    local panel = S.ChartPanel.Create(UIParent, { indicators = { sma = true, bollinger = true } })
    panel:SetItem(7)
    local model = S.Charts.Build(panel.chart.config, 600, 300)
    local colours = {}
    for _, pane in ipairs(model.panes) do
        for _, e in ipairs(pane.entries) do
            if e.spec.label then colours[e.spec.label] = e.color end
        end
    end
    local sma, upper, lower = colours["SMA 7"], colours["upper band"], colours["lower band"]
    eq(sma ~= nil and upper ~= nil and lower ~= nil, true, "all three lines are drawn")
    eq(sma[1], S.PriceChart.SMA_COLOR[1]); eq(sma[3], S.PriceChart.SMA_COLOR[3])
    eq(upper[1], S.PriceChart.BOLLINGER_COLOR[1]); eq(upper[3], S.PriceChart.BOLLINGER_COLOR[3])
    eq(upper[3] ~= sma[3], true, "amber average, purple bands")
    eq(lower[3], upper[3], "both bands share a colour")
    -- order of the other series must not change them: only bollinger on gives the same band colour
    panel.state.indicators.sma = false
    panel:Refresh()
    model = S.Charts.Build(panel.chart.config, 600, 300)
    local only
    for _, e in ipairs(model.panes[1].entries) do if e.spec.label == "upper band" then only = e.color end end
    eq(only[3], upper[3])
    Fake.uninstall()
end)
