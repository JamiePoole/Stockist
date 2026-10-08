local ADDON_NAME, Stockist = ...

local Rollup = Stockist.Rollup

-- Holds price history for one market inside a SavedVariables table (`db`). Every reading is folded
-- straight into hourly and daily candles; raw readings are not kept, so the table stays small.
--   db.items[itemID] = { last = reading, hourly = { [t] = candle }, daily = { [t] = candle } }
--   db.meta[itemID]  = { class, sub }   item class and subclass, for grouping
local Store = {}
Store.__index = Store
Stockist.ReadingStore = Store

local RESOLUTIONS = { hourly = Rollup.HOUR, daily = Rollup.DAY }

function Store.New(db, opts)
    opts = opts or {}
    db.items = db.items or {}
    db.meta = db.meta or {}
    return setmetatable({
        db = db,
        hourlyKeep = opts.hourlyKeepSec or 7 * 86400,
        dailyKeep = opts.dailyKeepSec or 180 * 86400,
    }, Store)
end

local function validReading(r)
    return type(r) == "table"
        and type(r.item) == "number" and r.item > 0
        and type(r.ts) == "number" and r.ts > 0
        and type(r.price) == "number" and r.price > 0
        and type(r.qty) == "number" and r.qty >= 0
end

local function validCandle(c)
    if type(c) ~= "table" then return false end
    for _, k in ipairs({ "t", "o", "h", "l", "c", "q", "n", "ot", "ct" }) do
        if type(c[k]) ~= "number" then return false end
    end
    return c.n > 0 and c.l <= c.h
end

function Store:_item(itemID)
    local it = self.db.items[itemID]
    if not it then
        it = { hourly = {}, daily = {} }
        self.db.items[itemID] = it
    end
    return it
end

-- Recent ticks: every individual reading from the last day, kept as three parallel arrays (time,
-- price, quantity) so the file stays small. They let short views show one point per scan instead
-- of one flat candle per hour.
local TICK_KEEP_SEC = 86400
local TICK_MAX = 96

local function addTick(it, r)
    local tt, tp, tq = it.tt, it.tp, it.tq
    if not tt then
        tt, tp, tq = {}, {}, {}
        it.tt, it.tp, it.tq = tt, tp, tq
    end
    local n = #tt
    if n > 0 and r.ts <= tt[n] then return end -- ticks are append-only and in time order
    n = n + 1
    tt[n], tp[n], tq[n] = r.ts, r.price, r.qty

    local drop = 0
    local cutoff = r.ts - TICK_KEEP_SEC
    while drop < n and tt[drop + 1] < cutoff do drop = drop + 1 end
    if n - drop > TICK_MAX then drop = n - TICK_MAX end
    if drop > 0 then
        for i = 1, n - drop do
            tt[i], tp[i], tq[i] = tt[i + drop], tp[i + drop], tq[i + drop]
        end
        for i = n - drop + 1, n do tt[i], tp[i], tq[i] = nil, nil, nil end
    end
end

--- Individual readings since `fromTs` (default: all kept), oldest first, as { x = time, y = price, q = qty }.
function Store:Ticks(itemID, fromTs)
    local it = self.db.items[itemID]
    local out = {}
    if not (it and it.tt) then return out end
    for i = 1, #it.tt do
        if not fromTs or it.tt[i] >= fromTs then
            out[#out + 1] = { x = it.tt[i], y = it.tp[i], q = it.tq[i] }
        end
    end
    return out
end

--- Record one reading { item, ts, price, min?, qty }. `price` is the headline price in copper.
--- Returns false (and records nothing) if the reading is malformed.
function Store:Add(reading)
    if not validReading(reading) then return false end
    local it = self:_item(reading.item)
    addTick(it, reading)
    if not it.last or reading.ts >= it.last.ts then
        it.last = {
            ts = reading.ts,
            price = reading.price,
            min = reading.min or reading.price,
            qty = reading.qty,
        }
    end
    for res, size in pairs(RESOLUTIONS) do
        local t = Rollup.BucketStart(reading.ts, size)
        local candle = Rollup.NewCandle(t, reading.price, reading.qty, reading.ts)
        local existing = it[res][t]
        it[res][t] = existing and Rollup.Merge(existing, candle) or candle
    end
    return true
end

--- Merge a whole candle received from another player. `res` is "hourly" or "daily".
function Store:MergeCandle(itemID, res, candle)
    if not RESOLUTIONS[res] or type(itemID) ~= "number" or not validCandle(candle) then return false end
    if candle.t % RESOLUTIONS[res] ~= 0 then return false end
    local it = self:_item(itemID)
    local existing = it[res][candle.t]
    it[res][candle.t] = existing and Rollup.Merge(existing, candle) or candle
    return true
end

function Store:SetMeta(itemID, class, sub)
    self.db.meta[itemID] = { class = class, sub = sub }
end

function Store:GetMeta(itemID)
    return self.db.meta[itemID]
end

--- Most recent reading for an item, or nil.
function Store:Latest(itemID)
    local it = self.db.items[itemID]
    return it and it.last
end

--- Sorted array of item IDs we hold data for.
function Store:Items()
    local out = {}
    for id in pairs(self.db.items) do out[#out + 1] = id end
    table.sort(out)
    return out
end

--- Candles for an item, oldest first, with fromTs <= t <= toTs (both optional).
function Store:GetCandles(itemID, res, fromTs, toTs)
    local it = self.db.items[itemID]
    local out = {}
    if not it or not it[res] then return out end
    for t, candle in pairs(it[res]) do
        if (not fromTs or t >= fromTs) and (not toTs or t <= toTs) then
            out[#out + 1] = candle
        end
    end
    table.sort(out, function(a, b) return a.t < b.t end)
    return out
end

--- The closing price as of `ts`: the close of the newest candle (either resolution) that closed at
--- or before `ts`. Returns nil if there is no data that old.
function Store:PriceAt(itemID, ts)
    local it = self.db.items[itemID]
    if not it then return nil end
    local bestCt, bestPrice
    for res in pairs(RESOLUTIONS) do
        for _, candle in pairs(it[res]) do
            if candle.ct <= ts and (not bestCt or candle.ct > bestCt) then
                bestCt, bestPrice = candle.ct, candle.c
            end
        end
    end
    return bestPrice
end

--- Percent change of the latest price versus the price `windowSec` before `now`.
--- Returns percent, referencePrice; nil if there is no latest reading or no data that old.
function Store:Change(itemID, windowSec, now)
    local last = self:Latest(itemID)
    if not last then return nil end
    local ref = self:PriceAt(itemID, now - windowSec)
    if not ref or ref == 0 then return nil end
    return (last.price - ref) / ref * 100, ref
end

--- Drop candles older than the retention windows. Returns how many were removed.
function Store:Prune(now)
    local removed = 0
    local keep = { hourly = self.hourlyKeep, daily = self.dailyKeep }
    for _, it in pairs(self.db.items) do
        for res, size in pairs(keep) do
            local cutoff = now - size
            for t in pairs(it[res]) do
                if t < cutoff then
                    it[res][t] = nil
                    removed = removed + 1
                end
            end
        end
    end
    return removed
end
