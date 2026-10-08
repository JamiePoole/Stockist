load_support("recording_canvas")

local DAY, HOUR = 86400, 3600
-- 1970-02-10 12:00 UTC (a Tuesday). With tz = 0 the windows are easy to state.
local NOON = 40 * DAY + 12 * HOUR

local function load()
    return load_addon(
        "Core/EventBus.lua", "Core/Registry.lua", "Core/Format.lua", "Core/Calendar.lua", "Data/Rollup.lua",
        "Data/Indicators.lua", "Data/ReadingStore.lua", "UI/Charts/Charts.lua", "UI/Charts/Util.lua",
        "UI/Charts/Scale.lua", "UI/Charts/Formatters.lua", "UI/Charts/Theme.lua", "UI/Charts/Series/Line.lua",
        "UI/Charts/Series/Candle.lua", "UI/Charts/Series/Bar.lua", "UI/Charts/Overlays/Overlays.lua",
        "UI/Charts/Core.lua", "Core/Help.lua", "Core/HelpTopics.lua", "Features/PriceChart.lua")
end

local function setup()
    local S = load()
    local store = S.ReadingStore.New({})
    -- ten days of hourly readings ending at NOON, price rising 101 -> 340 with supply 50
    for h = 1, 240 do
        store:Add({ item = 7, ts = NOON - (240 - h) * HOUR, price = 100 + h, qty = 50 })
    end
    return S, store, NOON
end

--- A store with `count` readings `step` seconds apart starting at `from`.
local function scans(S, item, count, from, step, price)
    local store = S.ReadingStore.New({})
    for i = 0, count - 1 do store:Add({ item = item, ts = from + i * step, price = (price or 100) + i, qty = 10 }) end
    return store
end

-- Windows -------------------------------------------------------------------------------------

test("each scope is a rolling window ending a little after now", function()
    local S = load()
    for key, span in pairs({ ["1D"] = DAY, ["1W"] = 7 * DAY, ["1M"] = 30 * DAY }) do
        local from, to = S.PriceChart.Window(key, NOON, 0)
        eq(from, NOON - span, key .. " starts one span ago")
        eq(to, NOON + math.floor(span * 0.03), key .. " ends just after now")
    end
end)

test("ticks fall on round local times", function()
    local S = load()
    local tz = 10 * HOUR
    local _, _, day = S.PriceChart.Window("1D", NOON, tz)
    eq(#day >= 8 and #day <= 9, true, "a rolling day holds 8 or 9 three-hour boundaries, depending on the offset")
    for _, t in ipairs(day) do eq((t + tz) % (3 * HOUR), 0, "3-hour boundary") end
    local _, _, week = S.PriceChart.Window("1W", NOON, tz)
    eq(#week >= 7, true)
    for _, t in ipairs(week) do eq((t + tz) % DAY, 0, "local midnight") end
    local _, _, month = S.PriceChart.Window("1M", NOON, tz)
    eq(#month >= 4 and #month <= 5, true)
    for _, t in ipairs(month) do
        eq((t + tz) % DAY, 0, "midnight")
        eq(S.Calendar.WeekStart(t, tz), t, "a Monday")
    end
end)

test("all ticks lie inside the window", function()
    local S = load()
    for _, key in ipairs({ "1D", "1W", "1M" }) do
        local from, to, ticks = S.PriceChart.Window(key, NOON, 3 * HOUR)
        for _, t in ipairs(ticks) do eq(t >= from and t <= to, true, key) end
    end
end)

test("BuildConfig puts the window and its ticks on the x axis", function()
    local S, store, now = setup()
    for _, key in ipairs({ "1D", "1W", "1M" }) do
        local from, to, ticks = S.PriceChart.Window(key, now, 0)
        local x = S.PriceChart.BuildConfig(store, 7, key, {}, now, 0).x
        eq(x.range[1], from); eq(x.range[2], to)
        eq(#x.ticks, #ticks)
    end
    eq(#S.PriceChart.TIMEFRAMES, 3, "ALL is not offered yet")
end)

test("the axis labels follow the scope: hours, day names, dates", function()
    local S = load()
    local store = scans(S, 4, 6, NOON - 3600, 600)
    local function xLabels(key)
        local model = S.Charts.Build(S.PriceChart.BuildConfig(store, 4, key, {}, NOON, 0), 640, 360)
        local canvas = new_recording_canvas()
        S.Charts.Draw(model, canvas)
        local out = {}
        for _, t in ipairs(canvas:find("text", function(o) return o.anchor == "TOP" end)) do out[#out + 1] = t.str end
        return out
    end
    local day = xLabels("1D")
    eq(#day, 9)
    for _, s in ipairs(day) do eq(s:match("^%d%d:%d%d$") ~= nil, true, "1D hour label " .. s) end
    local week = xLabels("1W")
    eq(#week, 7)
    for _, s in ipairs(week) do eq(s:match("^%a%a%a %d%d$") ~= nil, true, "1W day-name label " .. s) end
    local month = xLabels("1M")
    eq(#month >= 4, true)
    for _, s in ipairs(month) do eq(s:match("^%d%d %a%a%a$") ~= nil, true, "1M date label " .. s) end
end)

test("the newest reading sits just inside the right edge and older ones to its left", function()
    local S, store, now = setup()
    local model = S.Charts.Build(S.PriceChart.BuildConfig(store, 7, "1W", {}, now, 0), 640, 360)
    local right = model.plot.x + model.plot.w
    local newest = model.xs:Map(NOON)
    eq(newest < right and newest > right - 0.05 * model.plot.w, true, "a small forward margin")
    -- two days ago is 5/7 of the way through the window's 7 days (plus the margin)
    near(model.xs:Map(NOON - 2 * DAY), model.plot.x + model.plot.w * (5 / 7) / 1.03, 1)
end)

-- Data choice ---------------------------------------------------------------------------------

test("BuildConfig uses hourly candles for 1D and 1W and daily candles for 1M", function()
    local S, store, now = setup()
    local day = S.PriceChart.BuildConfig(store, 7, "1D", {}, now, 0)
    local week = S.PriceChart.BuildConfig(store, 7, "1W", {}, now, 0)
    local month = S.PriceChart.BuildConfig(store, 7, "1M", {}, now, 0)
    eq(day.panes[1].series[1].type, "candle"); eq(#day.panes[1].series[1].points, 25)
    eq(week.panes[1].series[1].type, "candle"); eq(#week.panes[1].series[1].points, 169)
    eq(month.panes[1].series[1].type, "candle"); eq(#month.panes[1].series[1].points, 11)
    eq(month.x.resolution, 86400)
    eq(week.panes[2].series[1].type, "bar")
end)

test("a day with only a little history shows one marked point per scan", function()
    local S = load()
    local store = scans(S, 9, 5, NOON - 3600, 900)
    local day = S.PriceChart.BuildConfig(store, 9, "1D", {}, NOON, 0)
    local price = day.panes[1].series[1]
    eq(price.type, "line"); eq(price.markers, true)
    eq(#price.points, 5)
    eq(#day.panes[2].series[1].points, 5)
    eq(#store:GetCandles(9, "hourly"), 2, "hourly candles would have been two lonely dashes")
    eq(day.x.resolution, 60)
    eq(day.note ~= nil, true)
end)

test("scan markers are drawn as dots on the line", function()
    local S = load()
    local store = scans(S, 9, 4, NOON - 3600, 900)
    local model = S.Charts.Build(S.PriceChart.BuildConfig(store, 9, "1D", {}, NOON, 0), 640, 360)
    local canvas = new_recording_canvas()
    S.Charts.Draw(model, canvas)
    eq(#canvas:find("rect", function(o) return o.w == 4 and o.h == 4 end), 4)
end)

test("a month with a single day of history falls back to finer detail and says so", function()
    local S = load()
    local store = scans(S, 4, 8, NOON - 2 * HOUR, 900)
    eq(#store:GetCandles(4, "daily"), 1)
    local month = S.PriceChart.BuildConfig(store, 4, "1M", {}, NOON, 0)
    eq(month.panes[1].series[1].type, "line", "scan points, not one lonely daily candle")
    eq(#month.panes[1].series[1].points, 8)
    eq(month.x.resolution, 60)
    eq(month.note:find("daily candles", 1, true) ~= nil, true)
end)

test("a month with enough daily candles stays daily, with no note", function()
    local S = load()
    local store = S.ReadingStore.New({})
    for d = 1, 5 do store:Add({ item = 4, ts = NOON - d * DAY + HOUR, price = 100 + d, qty = 5 }) end
    local month = S.PriceChart.BuildConfig(store, 4, "1M", {}, NOON, 0)
    eq(month.panes[1].series[1].type, "candle")
    eq(#month.panes[1].series[1].points, 5)
    eq(month.x.resolution, 86400)
    is_nil(month.note)
end)

test("the fallback note is drawn on the chart", function()
    local S = load()
    local store = scans(S, 4, 8, NOON - 2 * HOUR, 900)
    local model = S.Charts.Build(S.PriceChart.BuildConfig(store, 4, "1M", {}, NOON, 0), 640, 360)
    local canvas = new_recording_canvas()
    S.Charts.Draw(model, canvas)
    local notes = canvas:find("text", function(o) return o.anchor == "TOPRIGHT" end)
    eq(#notes, 1)
    eq(notes[1].str:find("Not enough history", 1, true) ~= nil, true)
end)

test("1D falls back to candles when there are no recorded scans", function()
    local S = load()
    local store = S.ReadingStore.New({})
    store:MergeCandle(3, "hourly", S.Rollup.NewCandle(NOON - 2 * HOUR, 50, 5, NOON - 2 * HOUR)) -- e.g. received from another player
    local day = S.PriceChart.BuildConfig(store, 3, "1D", {}, NOON, 0)
    eq(day.panes[1].series[1].type, "candle")
    eq(#day.panes[1].series[1].points, 1)
end)

-- Indicators ----------------------------------------------------------------------------------

test("an indicator is available only when the view has enough points for a line", function()
    local S = load()
    local function avail(count)
        local config = S.PriceChart.BuildConfig(scans(S, 7, count, NOON - 20 * HOUR, HOUR), 7, "1D", {}, NOON, 0)
        return config.indicators
    end
    local five = avail(5)
    eq(five.sma.ok, false); eq(five.sma.need, 8); eq(five.sma.have, 5)
    eq(five.bollinger.ok, false); eq(five.bollinger.need, 11)
    eq(avail(8).sma.ok, true); eq(avail(8).bollinger.ok, false)
    eq(avail(11).bollinger.ok, true)
end)

test("a switched-on indicator is drawn only while it is available", function()
    local S = load()
    local on = { sma = true, bollinger = true }
    local sparse = S.PriceChart.BuildConfig(scans(S, 7, 5, NOON - 5 * HOUR, HOUR), 7, "1D", on, NOON, 0)
    eq(#sparse.panes[1].overlays, 0, "not enough points: nothing is drawn")
    is_nil(sparse.note, "and no clutter about it")

    local rich = S.PriceChart.BuildConfig(scans(S, 7, 12, NOON - 12 * HOUR, HOUR), 7, "1D", on, NOON, 0)
    eq(#rich.panes[1].overlays, 2)
    eq(rich.panes[1].overlays[1].of, "price")
    eq(rich.panes[1].overlays[1].period, 7); eq(rich.panes[1].overlays[2].period, 10)
    local model = S.Charts.Build(rich, 640, 360)
    eq(#model.warnings, 0)
    eq(#model.panes[1].entries, 1 + 1 + 2, "price + sma + two bands")
end)

test("an indicator that is switched off draws nothing even when available", function()
    local S, store, now = setup()
    local config = S.PriceChart.BuildConfig(store, 7, "1W", {}, now, 0)
    eq(#config.panes[1].overlays, 0)
    eq(config.indicators.sma.ok, true)
end)

-- Rendering -----------------------------------------------------------------------------------

test("the chart is transparent so it inherits the window background", function()
    local S = load()
    local config = S.PriceChart.BuildConfig(scans(S, 4, 3, NOON - 3600, 900), 4, "1D", {}, NOON, 0)
    eq(config.transparent, true)
    local canvas = new_recording_canvas()
    S.Charts.Draw(S.Charts.Build(config, 640, 360), canvas)
    eq(#canvas:find("rect", function(o) return o.w >= 640 and o.h >= 360 end), 0, "no full-size background rectangle")
end)

test("BuildConfig output renders end to end", function()
    local S, store, now = setup()
    local config = S.PriceChart.BuildConfig(store, 7, "1W", { sma = true, bollinger = true }, now, 0)
    local model = S.Charts.Build(config, 640, 360)
    eq(model.empty, false)
    eq(#model.warnings, 0)
    local canvas = new_recording_canvas()
    S.Charts.Draw(model, canvas)
    eq(canvas:count("rect") > 60, true, "candle bodies and supply bars")
    eq(canvas:count("line") > 60, true, "wicks, grid and overlays")
    eq(canvas:count("text") > 4, true, "axis labels")
end)

test("BuildConfig for an item with no data renders the empty message", function()
    local S, store, now = setup()
    local model = S.Charts.Build(S.PriceChart.BuildConfig(store, 999, "1W", {}, now, 0), 640, 360)
    eq(model.empty, true)
end)

-- Header --------------------------------------------------------------------------------------

test("HeaderParts and MetaText describe the latest reading", function()
    local S, store, now = setup()
    local parts = S.PriceChart.HeaderParts(store, 7, now)
    eq(parts.price, 340); eq(parts.age, 0)
    eq(parts.change > 0, true)
    is_nil(S.PriceChart.HeaderParts(store, 999, now))
    local text = S.PriceChart.MetaText(parts)
    eq(text:find("24h", 1, true) ~= nil, true)
    eq(text:find("updated just now", 1, true) ~= nil, true)
    eq(text:find("|cff33c773", 1, true) ~= nil, true, "a rise is green")
    eq(S.PriceChart.MetaText({ change = -2, age = 120 }):find("|cffeb4d4d", 1, true) ~= nil, true, "a fall is red")
    eq(S.PriceChart.MetaText({ age = 3000 }), "updated 50m ago", "no change shown when unknown")
end)

test("Header summarises price, 24h change and age", function()
    local S, store, now = setup()
    local header = S.PriceChart.Header(store, 7, now, "Linen Cloth")
    eq(header:find("Linen Cloth", 1, true) ~= nil, true)
    eq(header:find("3s 40c", 1, true) ~= nil, true) -- 340 copper
    eq(header:find("24h +", 1, true) ~= nil, true)
    eq(header:find("updated just now", 1, true) ~= nil, true)
    eq(S.PriceChart.Header(store, 999, now, "Nothing"), "Nothing  (no data)")
end)

test("every help key the window uses has a registered topic", function()
    local S = load()
    S.settings = {}
    for _, key in ipairs(S.PriceChart.HELP_KEYS) do
        eq(S.Help.topics:Get(key) ~= nil, true, key)
    end
    for _, tf in ipairs(S.PriceChart.TIMEFRAMES) do
        eq(S.Help.topics:Get("timeframe-" .. tf.key) ~= nil, true, tf.key)
    end
end)

test("the scope tooltips say the windows are rolling, not calendar periods", function()
    local S = load()
    S.settings = {}
    for _, tf in ipairs(S.PriceChart.TIMEFRAMES) do
        local _, short, detail = S.Help.Lines("timeframe-" .. tf.key)
        eq(short:lower():find("rolling", 1, true) ~= nil, true, tf.key .. " short")
        eq(detail:lower():find("rolling", 1, true) ~= nil, true, tf.key .. " detail")
    end
    eq(select(3, S.Help.Lines("timeframe-1D")):find("not \"today\"", 1, true) ~= nil, true)
end)
