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
    -- two hourly candles are too few for the week view, so it shows the scan points too
    local week = S.PriceChart.BuildConfig(store, 9, "1W", {}, now, 0)
    eq(week.panes[1].series[1].type, "line")
    eq(week.note ~= nil, true)
end)

test("each scope's x axis covers its whole window, however little data there is", function()
    local S = setup()
    local store = S.ReadingStore.New({})
    local now = 40 * DAY
    for i = 0, 5 do store:Add({ item = 4, ts = now - 3600 + i * 600, price = 100 + i, qty = 5 }) end
    for key, span in pairs({ ["1D"] = DAY, ["1W"] = 7 * DAY, ["1M"] = 30 * DAY }) do
        local x = S.PriceChart.BuildConfig(store, 4, key, {}, now, 0).x
        eq(x.range[1], now - span, key .. " start")
        eq(x.range[2], now, key .. " end")
    end
    eq(#S.PriceChart.TIMEFRAMES, 3, "ALL is not offered yet")
end)

test("the axis labels follow the scope: hours, day names, dates", function()
    local S = setup()
    local store = S.ReadingStore.New({})
    local now = 40 * DAY
    for i = 0, 5 do store:Add({ item = 4, ts = now - 3600 + i * 600, price = 100 + i, qty = 5 }) end
    local function xLabels(key)
        local model = S.Charts.Build(S.PriceChart.BuildConfig(store, 4, key, {}, now, 0), 640, 360)
        local canvas = new_recording_canvas()
        S.Charts.Draw(model, canvas)
        local out = {}
        for _, t in ipairs(canvas:find("text", function(o) return o.anchor == "TOP" end)) do out[#out + 1] = t.str end
        return out
    end
    for _, s in ipairs(xLabels("1D")) do eq(s:match("^%d%d:%d%d$") ~= nil, true, "1D hour label " .. s) end
    local week = xLabels("1W")
    eq(#week >= 5, true)
    for _, s in ipairs(week) do eq(s:match("^%a%a%a %d%d$") ~= nil, true, "1W day-name label " .. s) end
    local month = xLabels("1M")
    for _, s in ipairs(month) do eq(s:match("^%d%d %a%a%a$") ~= nil, true, "1M date label " .. s) end
end)

test("the chart is transparent so it inherits the window background", function()
    local S = setup()
    local store = S.ReadingStore.New({})
    store:Add({ item = 4, ts = 40 * DAY, price = 100, qty = 5 })
    local config = S.PriceChart.BuildConfig(store, 4, "1D", {}, 40 * DAY, 0)
    eq(config.transparent, true)
    local canvas = new_recording_canvas()
    S.Charts.Draw(S.Charts.Build(config, 640, 360), canvas)
    local full = canvas:find("rect", function(o) return o.w >= 640 and o.h >= 360 end)
    eq(#full, 0, "no full-size background rectangle")
end)

test("HeaderParts and MetaText describe the latest reading", function()
    local S, store, now = setup()
    local parts = S.PriceChart.HeaderParts(store, 7, now)
    eq(parts.price, 340)
    eq(parts.age, 0)
    eq(parts.change > 0, true)
    is_nil(S.PriceChart.HeaderParts(store, 999, now))
    local text = S.PriceChart.MetaText(parts)
    eq(text:find("24h", 1, true) ~= nil, true)
    eq(text:find("updated just now", 1, true) ~= nil, true)
    eq(text:find("|cff33c773", 1, true) ~= nil, true, "a rise is green")
    local down = S.PriceChart.MetaText({ change = -2, age = 120 })
    eq(down:find("|cffeb4d4d", 1, true) ~= nil, true, "a fall is red")
    eq(S.PriceChart.MetaText({ age = 3000 }), "updated 50m ago", "no change shown when unknown")
end)

test("a month view with a single day of history falls back to finer detail and says so", function()
    local S = setup()
    local store = S.ReadingStore.New({})
    local now = 40 * DAY + 5 * HOUR
    for i = 0, 7 do store:Add({ item = 4, ts = now - 2 * HOUR + i * 900, price = 100 + i, qty = 5 }) end
    eq(#store:GetCandles(4, "daily"), 1)
    local month = S.PriceChart.BuildConfig(store, 4, "1M", {}, now, 0)
    eq(month.panes[1].series[1].type, "line", "scan points, not one lonely daily candle")
    eq(#month.panes[1].series[1].points, 8)
    eq(month.x.resolution, 60)
    eq(month.note ~= nil and month.note:find("daily candles", 1, true) ~= nil, true)
end)

test("a month view with enough daily candles stays daily, with no note", function()
    local S = setup()
    local store = S.ReadingStore.New({})
    local now = 40 * DAY
    for d = 1, 5 do store:Add({ item = 4, ts = now - d * DAY + HOUR, price = 100 + d, qty = 5 }) end
    local month = S.PriceChart.BuildConfig(store, 4, "1M", {}, now, 0)
    eq(month.panes[1].series[1].type, "candle")
    eq(#month.panes[1].series[1].points, 5)
    eq(month.x.resolution, 86400)
    is_nil(month.note)
end)

test("the fallback note is drawn on the chart", function()
    local S = setup()
    local store = S.ReadingStore.New({})
    local now = 40 * DAY + 5 * HOUR
    for i = 0, 7 do store:Add({ item = 4, ts = now - 2 * HOUR + i * 900, price = 100 + i, qty = 5 }) end
    local model = S.Charts.Build(S.PriceChart.BuildConfig(store, 4, "1M", {}, now, 0), 640, 360)
    local canvas = new_recording_canvas()
    S.Charts.Draw(model, canvas)
    local notes = canvas:find("text", function(o) return o.anchor == "TOPRIGHT" end)
    eq(#notes, 1)
    eq(notes[1].str:find("Not enough history", 1, true) ~= nil, true)
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
