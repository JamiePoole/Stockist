local ADDON_NAME, Stockist = ...

-- Price window for one item: candles (or one point per scan when there is little history) with
-- moving average / Bollinger bands on top, supply bars below. BuildConfig is pure (store in, chart
-- config out); Show and the window are the game-facing part.
local Format = Stockist.Format

local PriceChart = {}
Stockist.PriceChart = PriceChart

-- `prefer` lists the data kinds to try, best first: "ticks" (one point per scan), "hourly" and
-- "daily" candles. The first kind with at least MIN_POINTS points is used, so a young data set
-- falls back to finer detail instead of showing a single mark. The scopes are rolling windows that
-- end now (the last 24 hours, 7 days, 30 days), as on any chart for a market that never closes.
-- Not offered yet: ALL (everything stored); see docs/ROADMAP.md.
local TIMEFRAMES = {
    { key = "1D", span = 86400, label = "24h", prefer = { "hourly", "ticks" } },
    { key = "1W", span = 7 * 86400, label = "7d", prefer = { "hourly", "ticks" } },
    { key = "1M", span = 30 * 86400, label = "30d", prefer = { "daily", "hourly", "ticks" } },
}
-- The "recent" move beside the price compares the latest scan with the average of the scans in this window.
local RECENT_WINDOW = 2 * 3600
PriceChart.RECENT_WINDOW = RECENT_WINDOW
-- Indicator settings. A moving average needs `period` points before its first value, so a line needs
-- period + 1. The periods are modest because Auction House history is sparse (the textbook Bollinger
-- period of 20 would rarely be available).
local SMA_PERIOD, BOLLINGER_PERIOD, BOLLINGER_K = 7, 10, 2
-- Fixed colours for the indicators, so they never depend on how many series came before them: amber for the
-- moving average (the trend line), purple for the Bollinger bands (the envelope). Both stand apart from the
-- green / red candles and from each other.
local SMA_COLOR = { 1.00, 0.78, 0.25, 1 }
local BOLLINGER_COLOR = { 0.75, 0.50, 1.00, 0.85 }
PriceChart.SMA_COLOR, PriceChart.BOLLINGER_COLOR = SMA_COLOR, BOLLINGER_COLOR
local FORWARD_MARGIN = 0.03 -- empty space after "now", as a fraction of the window
local MIN_POINTS = 3
local RESOLUTION = { ticks = 60, hourly = 3600, daily = 86400 }
local KIND_NAME = { ticks = "one point per scan", hourly = "hourly candles", daily = "daily candles" }
PriceChart.TIMEFRAMES = TIMEFRAMES

--- Help topics the window attaches to its widgets (checked by tests against Core/HelpTopics.lua).
PriceChart.HELP_KEYS = {
    "timeframe-1D", "timeframe-1W", "timeframe-1M", "sma", "bollinger", "tutorial", "change-recent", "change-scope",
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
        return {
            price = { type = "line", id = "price", label = "price", points = line, markers = true },
            supply = supply, count = #line,
        }
    end
    local points = {}
    for i, c in ipairs(store:GetCandles(itemID, kind, fromTs, nil)) do
        points[i] = { x = c.t, o = c.o, h = c.h, l = c.l, c = c.c, n = c.n }
        supply[i] = { x = c.t, y = c.q, up = c.c >= c.o }
    end
    return { price = { type = "candle", id = "price", points = points }, supply = supply, count = #points }
end

--- The rolling window a scope covers: start, end and the axis tick times. The window ends a little
--- after `now` (FORWARD_MARGIN) so the newest candle does not sit on the edge. Ticks fall on round
--- local times:
---   1D  every 3 hours (00:00, 03:00 ...)
---   1W  every local midnight
---   1M  every Monday midnight
function PriceChart.Window(key, now, tz)
    local Calendar = Stockist.Calendar
    local tf = timeframe(key)
    local from = now - tf.span
    local to = now + math.floor(tf.span * FORWARD_MARGIN)
    local ticks = {}
    if tf.key == "1D" then
        for t = Calendar.NextBoundary(from, 3 * 3600, tz), to, 3 * 3600 do ticks[#ticks + 1] = t end
    elseif tf.key == "1W" then
        for t = Calendar.NextBoundary(from, 86400, tz), to, 86400 do ticks[#ticks + 1] = t end
    else
        local monday = Calendar.WeekStart(from, tz)
        if monday < from then monday = monday + 7 * 86400 end
        for t = monday, to, 7 * 86400 do ticks[#ticks + 1] = t end
    end
    return from, to, ticks
end

--- Chart config for an item.
---   indicators = { sma = bool, bollinger = bool }
--- The x axis is the scope's rolling window (see Window). Each view prefers one kind of data (see
--- TIMEFRAMES) and falls back to a finer kind while it has fewer than MIN_POINTS points; a corner note
--- says so. The result also carries `indicators`, saying for each one how many points it needs and
--- has, so the window can disable a button that could not draw anything.
function PriceChart.BuildConfig(store, itemID, key, indicators, now, tzOffset)
    local tf = timeframe(key)
    tzOffset = tzOffset or 0
    local windowStart, windowEnd, ticks = PriceChart.Window(tf.key, now, tzOffset)

    local chosen, chosenKind, richest, richestKind
    for _, kind in ipairs(tf.prefer) do
        local s = seriesFor(store, itemID, kind, windowStart)
        if s.count >= MIN_POINTS then chosen, chosenKind = s, kind break end
        if not richest or s.count > richest.count then richest, richestKind = s, kind end
    end
    if not chosen then chosen, chosenKind = richest, richestKind end

    local notes = {}
    if chosenKind ~= tf.prefer[1] then
        notes[#notes + 1] = ("Not enough history yet for %s: showing %s"):format(
            KIND_NAME[tf.prefer[1]], KIND_NAME[chosenKind])
    end

    -- An indicator is only drawn when the view has enough points for it. Whether the player switched
    -- it on is remembered separately, so it comes back by itself once the data is there.
    local n = chosen.count
    local available = {
        sma = { need = SMA_PERIOD + 1, have = n, ok = n >= SMA_PERIOD + 1 },
        bollinger = { need = BOLLINGER_PERIOD + 1, have = n, ok = n >= BOLLINGER_PERIOD + 1 },
    }
    local overlays = {}
    indicators = indicators or {}
    if indicators.sma and available.sma.ok then
        overlays[#overlays + 1] = { type = "sma", of = "price", period = SMA_PERIOD, color = SMA_COLOR }
    end
    if indicators.bollinger and available.bollinger.ok then
        overlays[#overlays + 1] = { type = "bollinger", of = "price", period = BOLLINGER_PERIOD, k = BOLLINGER_K, color = BOLLINGER_COLOR }
    end
    local note = #notes > 0 and table.concat(notes, ". ") or nil

    return {
        indicators = available,
        transparent = true, -- the window supplies the background
        x = {
            format = "time", tzOffset = tzOffset, resolution = RESOLUTION[chosenKind],
            range = { windowStart, windowEnd }, ticks = ticks,
        },
        emptyText = "No readings in this range yet",
        note = note,
        panes = {
            {
                id = "price", weight = 3, title = "Price", axis = { format = "money" },
                series = { chosen.price }, overlays = overlays,
            },
            {
                id = "supply", weight = 1, title = "Listed for sale", axis = { format = "int" },
                series = { { type = "bar", label = "listed", points = chosen.supply } },
            },
        },
    }
end

--- What to show for an item before any chart: { kind = "ok" } when there is data to chart, otherwise a
--- message for the panel. `exists` is ItemInfo.Exists (true / false / nil for unknown), `lastScan` the
--- time of the last completed scan or nil.
---   notfound  no such item (a bad ID): a "404"
---   nodata    a real item we have no price for (it was not on the Auction House, or no scan has run)
function PriceChart.Status(store, itemID, exists, lastScan, now)
    if exists == false then
        return {
            kind = "notfound",
            text = ("No item has the ID %d. Check the number, or shift-click an item into the command."):format(itemID),
        }
    end
    if not store:Latest(itemID) then
        if lastScan then
            return {
                kind = "nodata",
                text = ("No prices recorded for this item. It wasn't on the Auction House at the last scan (%s). "
                    .. "Items that are soulbound or only sold by vendors never appear there."):format(Format.Age(now - lastScan)),
            }
        end
        return { kind = "nodata", text = "No prices recorded yet. Open the Auction House to take the first scan." }
    end
    return { kind = "ok" }
end

--- The numbers the header shows: { price, min, change (24h percent), age (seconds) }; nil when the
--- item has no reading.
function PriceChart.HeaderParts(store, itemID, now, key)
    local last = store:Latest(itemID)
    if not last then return nil end
    local tf = timeframe(key or "1D")
    local change, covered = store:ChangeOver(itemID, tf.span, now)
    -- Say how long the move really covers when there is less history than the scope: "+3% 4d", not "+3% 30d".
    local label = tf.label
    if change and covered < tf.span * 0.9 then label = Format.Span(covered) end
    return {
        price = last.price, min = last.min, age = now - last.ts,
        recent = (store:SmoothedChange(itemID, RECENT_WINDOW)),
        change = change, changeLabel = label,
    }
end

--- Plain one-line summary: "Linen Cloth  1g 20s (24h +3.10%)  updated 12m ago". `name` may carry colour codes.
function PriceChart.Header(store, itemID, now, name, key)
    local p = PriceChart.HeaderParts(store, itemID, now, key)
    if not p then return name .. "  (no data)" end
    local line = ("%s  %s"):format(name, Format.Money(p.price))
    if p.change then line = line .. "  (" .. p.changeLabel .. " " .. Format.Percent(p.change) .. ")" end
    return line .. "  updated " .. Format.Age(p.age)
end

--- The main move in the header, over the chart's scope: "+3.10% 7d", the figure coloured green or red and
--- the span in grey. Empty when there is no move to show.
function PriceChart.ChangeText(parts)
    if not parts.change then return "" end
    return Format.Change(parts.change) .. " " .. Format.Colored(parts.changeLabel or "24h", 0.6, 0.63, 0.68)
end

--- The smaller move next to it: "recent +0.80%" (the latest scan against the average of the last couple of
--- hours). Empty until there are enough scans.
function PriceChart.RecentText(parts)
    if not parts.recent then return "" end
    return Format.Colored("recent", 0.6, 0.63, 0.68) .. " " .. Format.Change(parts.recent)
end

--- The text after the moves: "updated 12m ago".
function PriceChart.MetaText(parts)
    return "updated " .. Format.Age(parts.age)
end

--- The text after the moves, fullest first, for a panel to pick from by the room it has.
function PriceChart.MetaChoices(parts)
    return { PriceChart.MetaText(parts), "" }
end

---------------------------------------------------------------------------------------------------
-- Window (game only): the chart panel (Features/ChartPanel.lua) in a pop-out window (Features/PopOut.lua)
---------------------------------------------------------------------------------------------------

--- The chart pop-out's panel (nil until it has been opened once).
function PriceChart.PopOutPanel()
    local slot = Stockist.PopOut.Slot("chart")
    return slot and slot.panel or nil
end

--- Open the chart pop-out (the window /stockist chart uses) for an item.
function PriceChart.Show(itemID)
    Stockist.PopOut.Open("chart", { itemID = itemID })
end
