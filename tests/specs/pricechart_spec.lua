load_support("recording_canvas")

local DAY, HOUR = 86400, 3600
-- 1970-02-10 12:00 UTC: a Tuesday, in a 28-day month. With tz = 0 the windows are easy to state.
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

local function scans(S, item, count, from, step, price)
    local store = S.ReadingStore.New({})
    for i = 0, count - 1 do store:Add({ item = item, ts = from + i * step, price = (price or 100) + i, qty = 10 }) end
    return store
end

-- Windows -------------------------------------------------------------------------------------

test("each scope covers a whole calendar period, including the part still to come", function()
    local S = load()
    local d0, d1, dticks = S.PriceChart.Window("1D", NOON, 0)
    eq(d0, 40 * DAY); eq(d1, 41 * DAY); eq(#dticks, 8, "every 3 hours")
    eq(dticks[2] - dticks[1], 3 * HOUR)

    local w0, w1, wticks = S.PriceChart.Window("1W", NOON, 0)
    eq(w0, 39 * DAY, "Monday"); eq(w1, 46 * DAY, "next Monday"); eq(#wticks, 7, "one tick per day")

    local m0, m1, mticks = S.PriceChart.Window("1M", NOON, 0)
    eq(m0, 31 * DAY, "1 Feb"); eq(m1, 59 * DAY, "1 Mar"); eq(#mticks, 4, "1st, 8th, 15th, 22nd of a 28-day month")
    eq(mticks[1], m0)
end)

test("the windows follow the local timezone", function()
    local S = load()
    local d0, d1 = S.PriceChart.Window("1D", NOON, 10 * HOUR)
    eq(d0, 40 * DAY - 10 * HOUR); eq(d1 - d0, DAY)
    eq(NOON >= d0 and NOON < d1, true)
end)

test("a 31-day month gets ticks on the 1st, 8th, 15th, 22nd and 29th", function()
    local S = load()
    local oct8 = S.Calendar.DaysFromCivil(2026, 10, 8) * DAY + 15 * HOUR
    local s, e, ticks = S.PriceChart.Window("1M", oct8, 0)
    eq(s, S.Calendar.DaysFromCivil(2026, 10, 1) * DAY)
    eq(e, S.Calendar.DaysFromCivil(2026, 11, 1) * DAY)
    eq(#ticks, 5)
    eq(ticks[5], s + 28 * DAY)
    local _, _, leap = S.PriceChart.Window("1M", S.Calendar.DaysFromCivil(2024, 2, 10) * DAY, 0)
    eq(#leap, 5, "leap February reaches the 29th")
end)

test("BuildConfig puts the calendar window on the x axis, with its ticks", function()
    local S, store, now = setup()
    for key, win in pairs({ ["1D"] = { 40 * DAY, 41 * DAY }, ["1W"] = { 39 * DAY, 46 * DAY }, ["1M"] = { 31 * DAY, 59 * DAY } }) do
        local x = S.PriceChart.BuildConfig(store, 7, key, {}, now, 0).x
        eq(x.range[1], win[1], key .. " start"); eq(x.range[2], win[2], key .. " end")
        eq(#x.ticks > 3, true, key .. " ticks")
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
    eq(#day, 8)
    for _, s in ipairs(day) do eq(s:match("^%d%d:%d%d$") ~= nil, true, "1D hour label " .. s) end
    local week = xLabels("1W")
    eq(#week, 7)
    for _, s in ipairs(week) do eq(s:match("^%a%a%a %d%d$") ~= nil, true, "1W day-name label " .. s) end
    local month = xLabels("1M")
    eq(#month, 4)
    for _, s in ipairs(month) do eq(s:match("^%d%d %a%a%a$") ~= nil, true, "1M date label " .. s) end
end)

test("readings sit at their real place in the window, not squeezed to the right", function()
    local S, store, now = setup()
    local model = S.Charts.Build(S.PriceChart.BuildConfig(store, 7, "1D", {}, now, 0), 640, 360)
    local noonX = model.xs:Map(NOON)
    -- NOON is halfway through the day, so it is about halfway across the plot
    near(noonX, model.plot.x + model.plot.w / 2, 1)
    local weekModel = S.Charts.Build(S.PriceChart.BuildConfig(store, 7, "1W", {}, now, 0), 640, 360)
    eq(weekModel.xs:Map(NOON) < weekModel.plot.x + weekModel.plot.w * 0.5, true, "Tuesday noon is in the first half of the week")
end)

-- Data choice ---------------------------------------------------------------------------------

test("BuildConfig uses hourly candles for 1D and 1W and daily candles for 1M", function()
    local S, store, now = setup()
    local day = S.PriceChart.BuildConfig(store, 7, "1D", {}, now, 0)
    local week = S.PriceChart.BuildConfig(store, 7, "1W", {}, now, 0)
    local month = S.PriceChart.BuildConfig(store, 7, "1M", {}, now, 0)
    eq(day.panes[1].series[1].type, "candle"); eq(#day.panes[1].series[1].points, 13)
    eq(week.panes[1].series[1].type, "candle"); eq(#week.panes[1].series[1].points, 37)
    eq(month.panes[1].series[1].type, "candle"); eq(#month.panes[1].series[1].points, 10)
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
    local dots = canvas:find("rect", function(o) return o.w == 4 and o.h == 4 end)
    eq(#dots, 4)
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

test("indicators turn into overlays sized to the data", function()
    local S, store, now = setup()
    eq(#S.PriceChart.BuildConfig(store, 7, "1W", {}, now, 0).panes[1].overlays, 0)
    local both = S.PriceChart.BuildConfig(store, 7, "1W", { sma = true, bollinger = true }, now, 0)
    eq(#both.panes[1].overlays, 2)
    eq(both.panes[1].overlays[1].of, "price")
    eq(both.panes[1].overlays[1].period, 7); eq(both.panes[1].overlays[2].period, 10)

    local few = S.PriceChart.BuildConfig(scans(S, 7, 4, NOON - 4 * HOUR, HOUR), 7, "1D", { sma = true, bollinger = true }, NOON, 0)
    eq(few.panes[1].overlays[1].period, 3, "4 points -> a 3-point average")
    eq(few.panes[1].overlays[2].period, 3)
end)

test("SMA and BB visibly do something even with little data", function()
    local S = load()
    local store = scans(S, 7, 5, NOON - 5 * HOUR, HOUR)
    local config = S.PriceChart.BuildConfig(store, 7, "1D", { sma = true }, NOON, 0)
    local model = S.Charts.Build(config, 640, 360)
    eq(#model.panes[1].entries, 2, "price + sma line")
    eq(#model.panes[1].entries[2].spec.points >= 2, true)
end)

test("an indicator that has too little data says so instead of silently doing nothing", function()
    local S = load()
    local store = scans(S, 7, 2, NOON - 3600, 900)
    local config = S.PriceChart.BuildConfig(store, 7, "1D", { sma = true, bollinger = true }, NOON, 0)
    eq(#config.panes[1].overlays, 0)
    eq(config.note:find("SMA needs at least 3 points", 1, true) ~= nil, true)
    eq(config.note:find("BB needs at least 3 points", 1, true) ~= nil, true)
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
