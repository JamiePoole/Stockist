local function ns()
    return load_addon("Data/Rollup.lua", "Data/Indicators.lua", "Data/ReadingStore.lua", "Market/Aggregate.lua")
end

local HOUR, DAY = 3600, 86400

-- Rollup ---------------------------------------------------------------------------------------

test("Rollup.BucketStart floors to the bucket", function()
    local S = ns()
    eq(S.Rollup.BucketStart(7300, HOUR), 7200)
    eq(S.Rollup.BucketStart(7200, HOUR), 7200)
    eq(S.Rollup.BucketStart(100000, DAY), 86400)
end)

test("Rollup.Merge takes open from earliest and close from latest, regardless of order", function()
    local S = ns()
    local early = S.Rollup.NewCandle(0, 100, 10, 5)
    local late = S.Rollup.NewCandle(0, 140, 30, 50)
    for _, m in ipairs({ S.Rollup.Merge(early, late), S.Rollup.Merge(late, early) }) do
        eq(m.o, 100); eq(m.c, 140); eq(m.h, 140); eq(m.l, 100)
        eq(m.ot, 5); eq(m.ct, 50); eq(m.n, 2)
        near(m.q, 20)
    end
end)

test("Rollup.Merge of identical candles is a no-op", function()
    local S = ns()
    local a = S.Rollup.NewCandle(0, 100, 10, 5)
    local b = S.Rollup.NewCandle(0, 100, 10, 5)
    eq(S.Rollup.Merge(a, b).n, 1)
end)

-- Indicators -----------------------------------------------------------------------------------

test("SMA", function()
    local S = ns()
    local out = S.Indicators.SMA({ 1, 2, 3, 4, 5 }, 3)
    is_nil(out[1]); is_nil(out[2])
    eq(out[3], 2); eq(out[4], 3); eq(out[5], 4)
    eq(out.n, 5)
end)

test("EMA seeds with the SMA", function()
    local S = ns()
    local out = S.Indicators.EMA({ 1, 2, 3, 4, 5 }, 3)
    is_nil(out[2])
    eq(out[3], 2); eq(out[4], 3); eq(out[5], 4)
end)

test("EMA with fewer values than the period is empty", function()
    local S = ns()
    local out = S.Indicators.EMA({ 1, 2 }, 3)
    is_nil(out[1]); is_nil(out[2])
end)

test("Bollinger matches the textbook example", function()
    local S = ns()
    -- mean 5, population standard deviation 2
    local b = S.Indicators.Bollinger({ 2, 4, 4, 4, 5, 5, 7, 9 }, 8, 2)
    near(b.mid[8], 5); near(b.upper[8], 9); near(b.lower[8], 1)
    is_nil(b.upper[7])
end)

test("RSI is 100 for a rising series and 0 for a falling one", function()
    local S = ns()
    near(S.Indicators.RSI({ 1, 2, 3, 4, 5, 6 }, 3)[4], 100)
    near(S.Indicators.RSI({ 6, 5, 4, 3, 2, 1 }, 3)[4], 0)
end)

test("RSI Wilder smoothing on an alternating series", function()
    local S = ns()
    local out = S.Indicators.RSI({ 1, 2, 1, 2, 1, 2 }, 2)
    is_nil(out[2])
    -- changes: +1 -1 +1 -1 +1. After the seed (gain .5, loss .5): gain .75 / loss .25, then .375 / .625
    near(out[3], 50); near(out[4], 75); near(out[5], 37.5)
end)

test("PercentChange and Percentile", function()
    local S = ns()
    near(S.Indicators.PercentChange(100, 110), 10)
    near(S.Indicators.PercentChange(200, 100), -50)
    is_nil(S.Indicators.PercentChange(0, 5))
    near(S.Indicators.Percentile({ 10, 20, 30, 40 }, 30), 75)
    is_nil(S.Indicators.Percentile({}, 1))
end)

-- Aggregate ------------------------------------------------------------------------------------

test("Aggregate.Reduce takes the median of the cheapest units", function()
    local S = ns()
    local tiers = { { price = 30, qty = 100 }, { price = 10, qty = 5 }, { price = 20, qty = 5 } }
    local r = S.Aggregate.Reduce(tiers, 10) -- cheapest 10 units: 5 @ 10, 5 @ 20 -> median 15
    eq(r.min, 10); near(r.median, 15); eq(r.qty, 110)
    eq(S.Aggregate.Reduce(tiers, 1000).median, 30) -- all 110 units, middle ones are @ 30
end)

test("Aggregate.Reduce handles odd counts and empty input", function()
    local S = ns()
    eq(S.Aggregate.Reduce({ { price = 10, qty = 3 } }, 200).median, 10)
    is_nil(S.Aggregate.Reduce({}, 200))
    is_nil(S.Aggregate.Reduce({ { price = 0, qty = 5 } }, 200))
end)

test("Aggregate.DepthWithin counts units near the lowest price", function()
    local S = ns()
    local tiers = { { price = 10, qty = 5 }, { price = 15, qty = 7 }, { price = 16, qty = 100 } }
    eq(S.Aggregate.DepthWithin(tiers, 50), 12)
    eq(S.Aggregate.DepthWithin({}, 50), 0)
end)

-- ReadingStore ---------------------------------------------------------------------------------

test("Store folds readings into hourly and daily candles", function()
    local S = ns()
    local store = S.ReadingStore.New({})
    store:Add({ item = 1, ts = HOUR * 10 + 5, price = 100, qty = 10 })
    store:Add({ item = 1, ts = HOUR * 10 + 50, price = 130, qty = 20 })
    store:Add({ item = 1, ts = HOUR * 10 + 90, price = 90, qty = 30 })
    local hourly = store:GetCandles(1, "hourly")
    eq(#hourly, 1)
    eq(hourly[1].o, 100); eq(hourly[1].h, 130); eq(hourly[1].l, 90); eq(hourly[1].c, 90); eq(hourly[1].n, 3)
    eq(#store:GetCandles(1, "daily"), 1)
end)

test("Store accepts out-of-order readings without corrupting open/close", function()
    local S = ns()
    local store = S.ReadingStore.New({})
    store:Add({ item = 1, ts = 100, price = 150, qty = 1 })
    store:Add({ item = 1, ts = 50, price = 100, qty = 1 })
    local c = store:GetCandles(1, "hourly")[1]
    eq(c.o, 100); eq(c.c, 150)
    eq(store:Latest(1).price, 150)
end)

test("Store rejects malformed readings", function()
    local S = ns()
    local store = S.ReadingStore.New({})
    eq(store:Add(nil), false)
    eq(store:Add({ item = 1, ts = 100, price = 0, qty = 1 }), false)
    eq(store:Add({ item = "x", ts = 100, price = 5, qty = 1 }), false)
    eq(store:Add({ item = 1, ts = -1, price = 5, qty = 1 }), false)
    eq(#store:Items(), 0)
end)

test("Store.Change compares the latest price to the price a window ago", function()
    local S = ns()
    local store = S.ReadingStore.New({})
    store:Add({ item = 1, ts = 1000, price = 100, qty = 1 })
    store:Add({ item = 1, ts = 1000 + DAY, price = 110, qty = 1 })
    local pct, ref = store:Change(1, DAY, 1000 + DAY)
    near(pct, 10); eq(ref, 100)
    is_nil(store:Change(1, DAY * 10, 1000 + DAY), "no data that old")
    is_nil(store:Change(99, DAY, 1000 + DAY), "unknown item")
end)

test("Store.GetCandles filters by time and sorts", function()
    local S = ns()
    local store = S.ReadingStore.New({})
    for h = 5, 1, -1 do store:Add({ item = 1, ts = h * HOUR, price = h, qty = 1 }) end
    local out = store:GetCandles(1, "hourly", 2 * HOUR, 4 * HOUR)
    eq(#out, 3); eq(out[1].t, 2 * HOUR); eq(out[3].t, 4 * HOUR)
end)

test("Store.Prune drops candles past retention", function()
    local S = ns()
    local store = S.ReadingStore.New({}, { hourlyKeepSec = 2 * HOUR, dailyKeepSec = 10 * DAY })
    for h = 1, 9 do store:Add({ item = 1, ts = h * HOUR, price = 10, qty = 1 }) end
    local removed = store:Prune(9 * HOUR)
    eq(removed, 6) -- hourly candles at t < 7h (1h..6h) are gone
    eq(#store:GetCandles(1, "hourly"), 3)
    eq(#store:GetCandles(1, "daily"), 1)
end)

test("Store.MergeCandle merges received buckets and is idempotent", function()
    local S = ns()
    local store = S.ReadingStore.New({})
    store:Add({ item = 1, ts = 100, price = 100, qty = 10 })
    local theirs = S.Rollup.NewCandle(0, 120, 20, 200)
    eq(store:MergeCandle(1, "hourly", theirs), true)
    eq(store:MergeCandle(1, "hourly", theirs), true)
    local c = store:GetCandles(1, "hourly")[1]
    eq(c.o, 100); eq(c.c, 120); eq(c.h, 120)
    eq(store:MergeCandle(1, "hourly", { t = 1 }), false, "malformed candle")
    eq(store:MergeCandle(1, "hourly", S.Rollup.NewCandle(7, 1, 1, 7)), false, "misaligned bucket")
end)

test("Store keeps meta", function()
    local S = ns()
    local store = S.ReadingStore.New({})
    store:SetMeta(5, 7, 9)
    eq(store:GetMeta(5).sub, 9)
    is_nil(store:GetMeta(6))
end)
