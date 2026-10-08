local ADDON_NAME, Stockist = ...

-- Price window for one item: candles (or one point per scan on the 1D view) with moving average /
-- Bollinger bands on top, supply bars below. BuildConfig is pure (store in, chart config out);
-- Show and the window are the game-facing part.
local Format = Stockist.Format

local PriceChart = {}
Stockist.PriceChart = PriceChart

-- `prefer` lists the data kinds to try, best first: "ticks" (one point per scan), "hourly" and
-- "daily" candles. The first kind with at least MIN_POINTS points is used, so a young data set
-- falls back to finer detail instead of showing a single mark.
local TIMEFRAMES = {
    { key = "1D", span = 86400, prefer = { "ticks", "hourly" } },
    { key = "1W", span = 7 * 86400, prefer = { "hourly", "ticks" } },
    { key = "1M", span = 30 * 86400, prefer = { "daily", "hourly", "ticks" } },
    { key = "ALL", span = nil, prefer = { "daily", "hourly", "ticks" } },
}
local MIN_POINTS = 3
local RESOLUTION = { ticks = 60, hourly = 3600, daily = 86400 }
local KIND_NAME = { ticks = "one point per scan", hourly = "hourly candles", daily = "daily candles" }
PriceChart.TIMEFRAMES = TIMEFRAMES

--- Help topics the window attaches to its widgets (checked by tests against Core/HelpTopics.lua).
PriceChart.HELP_KEYS = {
    "timeframe-1D", "timeframe-1W", "timeframe-1M", "timeframe-ALL", "sma", "bollinger", "tutorial", "legend",
}

local function timeframe(key)
    for _, tf in ipairs(TIMEFRAMES) do
        if tf.key == key then return tf end
    end
    return TIMEFRAMES[2]
end

--- The price series and supply bars for one kind of data: { price = series spec, supply = points, count }.
local function seriesFor(store, itemID, kind, fromTs)
    local supply = {}
    if kind == "ticks" then
        local ticks = store:Ticks(itemID, fromTs)
        local line = {}
        for i, t in ipairs(ticks) do
            line[i] = { x = t.x, y = t.y }
            supply[i] = { x = t.x, y = t.q, up = (i == 1) or t.y >= ticks[i - 1].y }
        end
        return { price = { type = "line", id = "price", label = "price", points = line }, supply = supply, count = #line }
    end
    local points = {}
    for i, c in ipairs(store:GetCandles(itemID, kind, fromTs, nil)) do
        points[i] = { x = c.t, o = c.o, h = c.h, l = c.l, c = c.c }
        supply[i] = { x = c.t, y = c.q, up = c.c >= c.o }
    end
    return { price = { type = "candle", id = "price", points = points }, supply = supply, count = #points }
end

--- Chart config for an item.
---   indicators = { sma = bool, bollinger = bool }
--- Each view prefers one kind of data (see TIMEFRAMES) and falls back to a finer kind while it has
--- fewer than MIN_POINTS points; the chart says so in a corner note.
function PriceChart.BuildConfig(store, itemID, key, indicators, now, tzOffset)
    local tf = timeframe(key)
    local fromTs = tf.span and (now - tf.span) or nil

    local chosen, chosenKind, richest, richestKind
    for _, kind in ipairs(tf.prefer) do
        local s = seriesFor(store, itemID, kind, fromTs)
        if s.count >= MIN_POINTS then chosen, chosenKind = s, kind break end
        if not richest or s.count > richest.count then richest, richestKind = s, kind end
    end
    if not chosen then chosen, chosenKind = richest, richestKind end

    local pricePane, supply, resolution = chosen.price, chosen.supply, RESOLUTION[chosenKind]
    local note
    if chosenKind ~= tf.prefer[1] then
        note = ("Not enough history yet for %s: showing %s"):format(KIND_NAME[tf.prefer[1]], KIND_NAME[chosenKind])
    end

    local overlays = {}
    indicators = indicators or {}
    if indicators.sma then overlays[#overlays + 1] = { type = "sma", of = "price", period = 7 } end
    if indicators.bollinger then overlays[#overlays + 1] = { type = "bollinger", of = "price", period = 10, k = 2 } end

    return {
        x = { format = "time", tzOffset = tzOffset or 0, resolution = resolution },
        emptyText = "No readings in this range yet",
        note = note,
        panes = {
            {
                id = "price", weight = 3, title = "Price", axis = { format = "money" },
                series = { pricePane }, overlays = overlays,
            },
            {
                id = "supply", weight = 1, title = "Listed for sale", axis = { format = "int" },
                series = { { type = "bar", label = "listed", points = supply } },
            },
        },
    }
end

--- One-line summary: "Linen Cloth  1g 20s (24h +3.10%)  updated 12m ago". `name` may carry colour codes.
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

local state = { itemID = nil, timeframe = "1D", indicators = { sma = true, bollinger = false } }
local win, chart, header, legend, tfButtons, toggleButtons

local function paintToggle(btn, on)
    local fs = btn:GetFontString()
    if on then fs:SetTextColor(0.3, 1, 0.5) else fs:SetTextColor(1, 0.82, 0) end
end

local LEGEND_HEIGHT = 30

local function refresh()
    if not (win and state.itemID and Stockist.store) then return end
    local now = Stockist.Clock.now()
    chart:SetConfig(PriceChart.BuildConfig(Stockist.store, state.itemID, state.timeframe,
        state.indicators, now, Stockist.Clock.tzOffset()))
    header:SetText(PriceChart.Header(Stockist.store, state.itemID, now,
        Stockist.ItemInfo.ColoredName(state.itemID)))
    for key, btn in pairs(tfButtons) do btn:SetEnabled(key ~= state.timeframe) end
    for key, btn in pairs(toggleButtons) do paintToggle(btn, state.indicators[key]) end

    -- The legend under the chart is part of tutorial mode (toggled from the window header).
    local tutorial = Stockist.Help.TutorialEnabled()
    local _, short, detail = Stockist.Help.Lines("legend")
    legend:SetText((short or "") .. (detail and ("\n" .. detail) or ""))
    legend:SetShown(tutorial)
    chart.frame:ClearAllPoints()
    chart.frame:SetPoint("TOPLEFT", win.content, "TOPLEFT", 0, -28)
    chart.frame:SetPoint("BOTTOMRIGHT", win.content, "BOTTOMRIGHT", 0, tutorial and LEGEND_HEIGHT + 4 or 0)
end

local function button(parent, text, width, helpKey)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 20)
    b:SetText(text)
    Stockist.UI.Tooltip.Attach(b, helpKey)
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
        local b = button(content, tf.key, 40, "timeframe-" .. tf.key)
        if prev then b:SetPoint("RIGHT", prev, "LEFT", -2, 0) else b:SetPoint("TOPRIGHT", 0, 0) end
        b:SetScript("OnClick", function() state.timeframe = tf.key; refresh() end)
        tfButtons[tf.key] = b
        prev = b
    end
    for _, def in ipairs({ { "bollinger", "BB", "bollinger" }, { "sma", "SMA", "sma" } }) do
        local b = button(content, def[2], 40, def[3])
        b:SetPoint("RIGHT", prev, "LEFT", -10, 0)
        b:SetScript("OnClick", function()
            state.indicators[def[1]] = not state.indicators[def[1]]
            refresh()
        end)
        toggleButtons[def[1]] = b
        prev = b
    end
    chart = Stockist.Charts.Create(content, { series = {} })

    legend = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    legend:SetPoint("BOTTOMLEFT", 2, 0)
    legend:SetPoint("BOTTOMRIGHT", -2, 0)
    legend:SetJustifyH("LEFT")
    legend:SetTextColor(0.6, 0.65, 0.72)
    legend:SetWordWrap(true)

    -- Item names arrive from the server a moment after the first request.
    local loader = CreateFrame("Frame")
    loader:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    loader:SetScript("OnEvent", function(_, _, itemID)
        if win.frame:IsShown() and itemID == state.itemID then refresh() end
    end)
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

Stockist.Events:On("TUTORIAL_CHANGED", function()
    if win and win.frame:IsShown() then refresh() end
end)
