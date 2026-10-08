load_support("recording_canvas")

local DAY, HOUR = 86400, 3600

local function setup()
    local S = load_addon(
        "Core/EventBus.lua", "Core/Registry.lua", "Core/Format.lua", "Data/Rollup.lua", "Data/Indicators.lua",
        "Data/ReadingStore.lua", "UI/Charts/Charts.lua", "UI/Charts/Util.lua", "UI/Charts/Scale.lua",
        "UI/Charts/Formatters.lua", "UI/Charts/Theme.lua", "UI/Charts/Series/Line.lua",
        "UI/Charts/Series/Candle.lua", "UI/Charts/Series/Bar.lua", "UI/Charts/Overlays/Overlays.lua",
        "UI/Charts/Core.lua", "Core/Help.lua", "Core/HelpTopics.lua", "Features/PriceChart.lua")
    local store = S.ReadingStore.New({})
    local now = 40 * DAY
    -- ten days of hourly readings, price rising 100 -> 340 with supply 50
    for h = 1, 240 do
        store:Add({ item = 7, ts = now - (240 - h) * HOUR, price = 100 + h, qty = 50 })
    end
    return S, store, now
end

test("BuildConfig uses hourly candles for 1W and daily for 1M", function()
    local S, store, now = setup()
    local week = S.PriceChart.BuildConfig(store, 7, "1W", {}, now, 0)
    local month = S.PriceChart.BuildConfig(store, 7, "1M", {}, now, 0)
    eq(#week.panes[1].series[1].points <= 7 * 24 + 1, true)
    eq(#week.panes[1].series[1].points > 24, true)
    eq(#month.panes[1].series[1].points <= 11, true, "daily candles")
    eq(week.panes[1].series[1].type, "candle")
    eq(week.panes[2].series[1].type, "bar")
end)

test("BuildConfig 1D only includes the last day", function()
    local S, store, now = setup()
    local day = S.PriceChart.BuildConfig(store, 7, "1D", {}, now, 0)
    eq(#day.panes[1].series[1].points <= 25, true)
end)

test("1D plots one point per scan, so two scans in the same hour are two points", function()
    local S = setup()
    local store = S.ReadingStore.New({})
    local now = 40 * DAY
    for i = 0, 4 do store:Add({ item = 9, ts = now - 3600 + i * 900, price = 100 + i, qty = 10 }) end
    local day = S.PriceChart.BuildConfig(store, 9, "1D", {}, now, 0)
    eq(day.panes[1].series[1].type, "line")
    eq(#day.panes[1].series[1].points, 5)
    eq(#day.panes[2].series[1].points, 5)
    eq(#store:GetCandles(9, "hourly"), 2, "hourly candles would have shown one or two dashes")
    local week = S.PriceChart.BuildConfig(store, 9, "1W", {}, now, 0)
    eq(week.panes[1].series[1].type, "candle")
end)

test("1D falls back to candles when there are no recorded scans", function()
    local S = setup()
    local store = S.ReadingStore.New({})
    local now = 40 * DAY
    store:MergeCandle(3, "hourly", S.Rollup.NewCandle(now - 7200, 50, 5, now - 7200)) -- e.g. received from another player
    local day = S.PriceChart.BuildConfig(store, 3, "1D", {}, now, 0)
    eq(day.panes[1].series[1].type, "candle")
    eq(#day.panes[1].series[1].points, 1)
end)

test("the 1D line chart renders with indicators", function()
    local S = setup()
    local store = S.ReadingStore.New({})
    local now = 40 * DAY
    for i = 0, 11 do store:Add({ item = 9, ts = now - 3 * 3600 + i * 900, price = 100 + (i % 4) * 10, qty = 10 }) end
    local config = S.PriceChart.BuildConfig(store, 9, "1D", { sma = true, bollinger = true }, now, 0)
    local model = S.Charts.Build(config, 640, 360)
    eq(#model.warnings, 0)
    local canvas = new_recording_canvas()
    S.Charts.Draw(model, canvas)
    eq(canvas:count("line") > 20, true)
end)

test("every help key the window uses has a registered topic", function()
    local S = setup()
    S.settings = {}
    for _, key in ipairs(S.PriceChart.HELP_KEYS) do
        eq(S.Help.topics:Get(key) ~= nil, true, key)
    end
    for _, tf in ipairs(S.PriceChart.TIMEFRAMES) do
        eq(S.Help.topics:Get("timeframe-" .. tf.key) ~= nil, true, tf.key)
    end
end)

test("BuildConfig turns indicator flags into overlays", function()
    local S, store, now = setup()
    eq(#S.PriceChart.BuildConfig(store, 7, "1W", {}, now, 0).panes[1].overlays, 0)
    local both = S.PriceChart.BuildConfig(store, 7, "1W", { sma = true, bollinger = true }, now, 0)
    eq(#both.panes[1].overlays, 2)
    eq(both.panes[1].overlays[1].of, "price")
end)

test("BuildConfig output renders end to end", function()
    local S, store, now = setup()
    local config = S.PriceChart.BuildConfig(store, 7, "1W", { sma = true, bollinger = true }, now, 0)
    local model = S.Charts.Build(config, 640, 360)
    eq(model.empty, false)
    eq(#model.warnings, 0)
    local canvas = new_recording_canvas()
    S.Charts.Draw(model, canvas)
    eq(canvas:count("rect") > 100, true, "candle bodies and supply bars")
    eq(canvas:count("line") > 100, true, "wicks, grid and overlays")
    eq(canvas:count("text") > 4, true, "axis labels")
end)

test("BuildConfig for an item with no data renders the empty message", function()
    local S, store, now = setup()
    local config = S.PriceChart.BuildConfig(store, 999, "1W", {}, now, 0)
    local model = S.Charts.Build(config, 640, 360)
    eq(model.empty, true)
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
