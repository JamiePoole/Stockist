local DAY, HOUR = 86400, 3600

local function ns()
    return load_addon("Core/Config.lua", "Core/EventBus.lua", "Core/Registry.lua", "Core/Format.lua",
        "Data/Rollup.lua", "Data/ReadingStore.lua", "Data/Retention.lua", "Data/Tracked.lua")
end

-- Add `perDay` readings (at 01:00, 02:00...) on each of the `days` days before `now` (a midnight),
-- so every day gets exactly `perDay` hourly candles and one daily candle.
local function fill(store, item, now, days, perDay)
    for d = days - 1, 0, -1 do
        local dayStart = now - (d + 1) * DAY
        for h = 1, perDay do
            store:Add({ item = item, ts = dayStart + h * HOUR, price = 100, qty = 1 })
        end
    end
end

-- Tracked ---------------------------------------------------------------------------------------

test("Tracked adds, removes and lists", function()
    local S = ns()
    local set = {}
    local t = S.Tracked.New(set)
    eq(t:Add(5), true); eq(t:Add(5), false, "already tracked")
    eq(t:Add(2), true)
    eq(t:Has(5), true); eq(t:Has(9), false)
    eq(table.concat(t:List(), ","), "2,5")
    eq(t:Count(), 2)
    eq(t:Remove(5), true); eq(t:Remove(5), false)
    eq(set[2], true, "state lives in the table passed in")
    eq(t:Add("x"), false); eq(t:Add(-1), false)
end)

-- Retention settings ---------------------------------------------------------------------------

test("Retention.Effective uses defaults and valid overrides, ignoring bad ones", function()
    local S = ns()
    local e = S.Retention.Effective({ hourlyDays = 14, dailyDays = -5, idleDays = "x", bogus = 3 })
    eq(e.hourlyDays, 14)
    eq(e.dailyDays, S.Config.retention.dailyDays)
    eq(e.idleDays, S.Config.retention.idleDays)
    eq(S.Retention.Effective(nil).hourlyDays, S.Config.retention.hourlyDays)
end)

test("Retention.Set validates names and ranges", function()
    local S = ns()
    local o = {}
    eq(S.Retention.Set(o, "hourly", 10), true)
    eq(o.hourlyDays, 10)
    local ok, why = S.Retention.Set(o, "nope", 10)
    eq(ok, false); eq(why:find("unknown setting", 1, true) ~= nil, true)
    eq(S.Retention.Set(o, "hourly", 0), false)
    eq(S.Retention.Set(o, "hourly", 5000), false)
    eq(S.Retention.Set(o, "hourly", 2.5), false)
    eq(S.Retention.Set(o, "hourly", nil), false)
    eq(S.Retention.Set(o, "cap", 500), false, "cap has its own range")
    eq(S.Retention.Set(o, "cap", 20000), true)
    eq(o.maxCandles, 20000)
    eq(o.hourlyDays, 10, "failed sets change nothing")
end)

test("Retention.Reset clears one override or all", function()
    local S = ns()
    local o = { hourlyDays = 10, dailyDays = 20 }
    S.Retention.Reset(o, "hourly")
    is_nil(o.hourlyDays); eq(o.dailyDays, 20)
    S.Retention.Reset(o)
    is_nil(o.dailyDays)
    eq(S.Retention.Reset(o, "nope"), false)
end)

test("Retention.StoreOptions converts days to seconds", function()
    local S = ns()
    local o = S.Retention.StoreOptions(S.Retention.Effective({ hourlyDays = 2 }), function() return true end)
    eq(o.hourlyKeepSec, 2 * DAY)
    eq(o.isTracked(1), true)
    eq(o.maxCandles, S.Config.retention.maxCandles)
end)

-- Store pruning --------------------------------------------------------------------------------

test("tracked items keep history longer than untracked ones", function()
    local S = ns()
    local tracked = { [1] = true }
    local store = S.ReadingStore.New({}, {
        hourlyKeepSec = 2 * DAY, dailyKeepSec = 10 * DAY,
        trackedHourlyKeepSec = 6 * DAY, trackedDailyKeepSec = 30 * DAY,
        isTracked = function(id) return tracked[id] == true end,
    })
    local now = 100 * DAY
    for _, id in ipairs({ 1, 2 }) do fill(store, id, now, 20, 1) end
    store:Prune(now)
    eq(#store:GetCandles(1, "hourly") > #store:GetCandles(2, "hourly"), true)
    eq(#store:GetCandles(2, "hourly"), 2, "untracked: last 2 days")
    eq(#store:GetCandles(1, "hourly"), 6, "tracked: last 6 days")
    eq(#store:GetCandles(1, "daily"), 20, "tracked daily window covers all 20 days")
    eq(#store:GetCandles(2, "daily"), 10, "untracked daily window is 10 days")
end)

test("an untracked item with no recent reading is removed entirely, a tracked one is not", function()
    local S = ns()
    local store = S.ReadingStore.New({}, {
        idleKeepSec = 30 * DAY, dailyKeepSec = 500 * DAY, hourlyKeepSec = 500 * DAY,
        isTracked = function(id) return id == 1 end,
    })
    local now = 200 * DAY
    store:Add({ item = 1, ts = now - 100 * DAY, price = 5, qty = 1 })
    store:Add({ item = 2, ts = now - 100 * DAY, price = 5, qty = 1 })
    store:Add({ item = 3, ts = now - 1 * DAY, price = 5, qty = 1 })
    store:SetMeta(2, 7, 5)
    local removed, stats = store:Prune(now)
    eq(stats.items, 1)
    eq(table.concat(store:Items(), ","), "1,3")
    is_nil(store:GetMeta(2), "meta goes with the item")
    eq(removed, 2, "its hourly and daily candles")
    eq(store:Latest(1).price, 5, "tracked item keeps its latest reading")
end)

test("idle removal is off unless configured", function()
    local S = ns()
    local store = S.ReadingStore.New({}, { hourlyKeepSec = 900 * DAY, dailyKeepSec = 900 * DAY })
    store:Add({ item = 1, ts = 1000, price = 5, qty = 1 })
    store:Prune(500 * DAY)
    eq(#store:Items(), 1)
end)

test("the candle cap removes the oldest untracked hourly data first", function()
    local S = ns()
    local store = S.ReadingStore.New({}, {
        hourlyKeepSec = 900 * DAY, dailyKeepSec = 900 * DAY, maxCandles = 30,
        isTracked = function(id) return id == 1 end,
    })
    local now = 100 * DAY
    fill(store, 1, now, 5, 3) -- tracked: 15 hourly + 5 daily = 20
    fill(store, 2, now, 5, 3) -- untracked: 20 more -> 40 total
    eq(store:Stats().candles, 40)
    local _, stats = store:Prune(now)
    eq(stats.capped, 10)
    eq(store:Stats().candles, 30)
    eq(#store:GetCandles(1, "hourly"), 15, "tracked data untouched while untracked data remains")
    eq(#store:GetCandles(2, "daily"), 5, "daily kept while hourly could be trimmed")
    -- the 5 survivors are the newest: all 3 of yesterday's and the last 2 of the day before
    local left = store:GetCandles(2, "hourly")
    eq(#left, 5)
    eq(left[1].t, (now - 2 * DAY) + 2 * HOUR)
end)

test("the cap falls through to daily then tracked data when needed", function()
    local S = ns()
    local store = S.ReadingStore.New({}, {
        hourlyKeepSec = 900 * DAY, dailyKeepSec = 900 * DAY, maxCandles = 4,
        isTracked = function(id) return id == 1 end,
    })
    local now = 100 * DAY
    fill(store, 1, now, 3, 1) -- tracked: 3 hourly + 3 daily
    fill(store, 2, now, 3, 1) -- untracked: 3 + 3
    store:Prune(now)
    eq(store:Stats().candles, 4)
    eq(#store:GetCandles(2, "hourly"), 0)
    eq(#store:GetCandles(2, "daily"), 0)
end)

test("Stats counts items, tracked items and candles", function()
    local S = ns()
    local store = S.ReadingStore.New({}, { isTracked = function(id) return id == 1 end })
    fill(store, 1, 100 * DAY, 2, 2)
    fill(store, 2, 100 * DAY, 1, 1)
    local s = store:Stats()
    eq(s.items, 2); eq(s.tracked, 1)
    eq(s.hourly, 5); eq(s.daily, 3); eq(s.candles, 8)
end)

test("Configure changes limits on a live store", function()
    local S = ns()
    local store = S.ReadingStore.New({}, { hourlyKeepSec = 30 * DAY, dailyKeepSec = 30 * DAY })
    local now = 100 * DAY
    fill(store, 1, now, 10, 1)
    store:Prune(now)
    eq(#store:GetCandles(1, "hourly"), 10)
    store:Configure({ hourlyKeepSec = 3 * DAY, dailyKeepSec = 30 * DAY })
    store:Prune(now)
    eq(#store:GetCandles(1, "hourly"), 3)
end)
