local ADDON_NAME, Stockist = ...

-- Price window for one item: candles + moving average / Bollinger bands on top, supply bars below.
-- BuildConfig is pure (store in, chart config out); Show/the window are the game-facing part.
local Format = Stockist.Format

local PriceChart = {}
Stockist.PriceChart = PriceChart

local TIMEFRAMES = {
    { key = "1D", res = "hourly", span = 86400 },
    { key = "1W", res = "hourly", span = 7 * 86400 },
    { key = "1M", res = "daily", span = 30 * 86400 },
    { key = "ALL", res = "daily", span = nil },
}
PriceChart.TIMEFRAMES = TIMEFRAMES

local function timeframe(key)
    for _, tf in ipairs(TIMEFRAMES) do
        if tf.key == key then return tf end
    end
    return TIMEFRAMES[2]
end

--- Chart config for an item.
---   indicators = { sma = bool, bollinger = bool }
function PriceChart.BuildConfig(store, itemID, key, indicators, now, tzOffset)
    local tf = timeframe(key)
    local candles = store:GetCandles(itemID, tf.res, tf.span and (now - tf.span) or nil, nil)

    local price, supply = {}, {}
    for i, c in ipairs(candles) do
        price[i] = { x = c.t, o = c.o, h = c.h, l = c.l, c = c.c }
        supply[i] = { x = c.t, y = c.q, up = c.c >= c.o }
    end

    local overlays = {}
    indicators = indicators or {}
    if indicators.sma then overlays[#overlays + 1] = { type = "sma", of = "price", period = 7 } end
    if indicators.bollinger then overlays[#overlays + 1] = { type = "bollinger", of = "price", period = 10, k = 2 } end

    return {
        x = { format = "time", tzOffset = tzOffset or 0 },
        emptyText = "No readings in this range yet",
        panes = {
            {
                id = "price", weight = 3, axis = { format = "money" },
                series = { { type = "candle", id = "price", points = price } },
                overlays = overlays,
            },
            {
                id = "supply", weight = 1, axis = { format = "int" },
                series = { { type = "bar", label = "listed", points = supply } },
            },
        },
    }
end

--- One-line summary: "Linen Cloth  1g 20s (24h +3.10%)  updated 12m ago".
function PriceChart.Header(store, itemID, now, name)
    local last = store:Latest(itemID)
    if not last then return name .. "  (no data)" end
    local line = ("%s  %s"):format(name, Format.Money(last.price))
    local pct = store:Change(itemID, 86400, now)
    if pct then line = line .. "  (24h " .. Format.Percent(pct) .. ")" end
    return line .. "  updated " .. Format.Age(now - last.ts)
end

---------------------------------------------------------------------------------------------------
-- Window (game only)
---------------------------------------------------------------------------------------------------

local state = { itemID = nil, timeframe = "1W", indicators = { sma = true, bollinger = false } }
local win, chart, header, tfButtons, toggleButtons

local function paintToggle(btn, on)
    local fs = btn:GetFontString()
    if on then fs:SetTextColor(0.3, 1, 0.5) else fs:SetTextColor(1, 0.82, 0) end
end

local function refresh()
    if not (win and state.itemID and Stockist.store) then return end
    local now = Stockist.Clock.now()
    chart:SetConfig(PriceChart.BuildConfig(Stockist.store, state.itemID, state.timeframe,
        state.indicators, now, Stockist.Clock.tzOffset()))
    header:SetText(PriceChart.Header(Stockist.store, state.itemID, now, Stockist.ItemName(state.itemID)))
    win.title:SetText("Stockist")
    for key, btn in pairs(tfButtons) do btn:SetEnabled(key ~= state.timeframe) end
    for key, btn in pairs(toggleButtons) do paintToggle(btn, state.indicators[key]) end
end

local function button(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 20)
    b:SetText(text)
    return b
end

local function createWindow()
    win = Stockist.UI.Window.Create({ name = "StockistChartWindow", title = "Stockist", width = 680, height = 440 })
    local content = win.content

    header = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", 2, -2)

    tfButtons, toggleButtons = {}, {}
    local prev
    for i = #TIMEFRAMES, 1, -1 do
        local tf = TIMEFRAMES[i]
        local b = button(content, tf.key, 40)
        if prev then b:SetPoint("RIGHT", prev, "LEFT", -2, 0) else b:SetPoint("TOPRIGHT", 0, 0) end
        b:SetScript("OnClick", function() state.timeframe = tf.key; refresh() end)
        tfButtons[tf.key] = b
        prev = b
    end
    for _, def in ipairs({ { "bollinger", "BB" }, { "sma", "SMA" } }) do
        local b = button(content, def[2], 40)
        b:SetPoint("RIGHT", prev, "LEFT", -10, 0)
        b:SetScript("OnClick", function()
            state.indicators[def[1]] = not state.indicators[def[1]]
            refresh()
        end)
        toggleButtons[def[1]] = b
        prev = b
    end

    chart = Stockist.Charts.Create(content, { series = {} })
    chart.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -28)
    chart.frame:SetPoint("BOTTOMRIGHT")
end

--- Open the price window for an item.
function PriceChart.Show(itemID)
    if not win then createWindow() end
    state.itemID = itemID
    refresh()
    win.frame:Show()
end

Stockist.Events:On("SCAN_COMPLETE", function()
    if win and win.frame:IsShown() then refresh() end
end)
