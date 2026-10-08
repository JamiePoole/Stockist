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

--- Retention options (all optional; seconds):
---   hourlyKeepSec, dailyKeepSec          how long candles are kept
---   trackedHourlyKeepSec, trackedDailyKeepSec   the same for tracked items (default: same as above)
---   idleKeepSec     remove an untracked item whose newest reading is older than this (default: never)
---   maxCandles      hard cap on stored candles (default: none)
---   isTracked       function(itemID) -> boolean
function Store.New(db, opts)
    db.items = db.items or {}
    db.meta = db.meta or {}
    local store = setmetatable({ db = db }, Store)
    store:Configure(opts)
    return store
end

--- Replace the retention options (used when the player changes a limit).
function Store:Configure(opts)
    opts = opts or {}
    self.hourlyKeep = opts.hourlyKeepSec or 7 * 86400
    self.dailyKeep = opts.dailyKeepSec or 180 * 86400
    self.trackedHourlyKeep = opts.trackedHourlyKeepSec or self.hourlyKeep
    self.trackedDailyKeep = opts.trackedDailyKeepSec or self.dailyKeep
    self.idleKeep = opts.idleKeepSec
    self.maxCandles = opts.maxCandles
    self.isTracked = opts.isTracked
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

--- Record one reading { item, ts, price, min?, qty }. `price` is the headline price in copper.
--- Returns false (and records nothing) if the reading is malformed.
function Store:Add(reading)
    if not validReading(reading) then return false end
    local it = self:_item(reading.item)
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

local function countKeys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

--- When we last heard about an item: its latest reading, else its newest candle.
local function lastSeen(it)
    if it.last then return it.last.ts end
    local newest = 0
    for _, c in pairs(it.hourly) do if c.ct > newest then newest = c.ct end end
    for _, c in pairs(it.daily) do if c.ct > newest then newest = c.ct end end
    return newest
end

function Store:_tracked(itemID)
    return self.isTracked ~= nil and self.isTracked(itemID) == true
end

--- Counts: { items, tracked, hourly, daily, candles }.
function Store:Stats()
    local s = { items = 0, tracked = 0, hourly = 0, daily = 0, candles = 0 }
    for id, it in pairs(self.db.items) do
        s.items = s.items + 1
        if self:_tracked(id) then s.tracked = s.tracked + 1 end
        s.hourly = s.hourly + countKeys(it.hourly)
        s.daily = s.daily + countKeys(it.daily)
    end
    s.candles = s.hourly + s.daily
    return s
end

--- Delete the oldest candles of one kind until the total is back under the cap.
--- Returns how many were deleted.
function Store:_trim(resolution, tracked, excess)
    local victims = {}
    for id, it in pairs(self.db.items) do
        if self:_tracked(id) == tracked then
            for t in pairs(it[resolution]) do victims[#victims + 1] = { id = id, t = t } end
        end
    end
    table.sort(victims, function(a, b) return a.t < b.t end)
    local removed = 0
    for i = 1, math.min(excess, #victims) do
        self.db.items[victims[i].id][resolution][victims[i].t] = nil
        removed = removed + 1
    end
    return removed
end

--- Enforce retention. Untracked items use the normal windows and are removed entirely once idle;
--- tracked items use the longer windows and are never removed. If the candle total still exceeds
--- the cap, the oldest untracked hourly data goes first, then untracked daily, then tracked.
--- Returns the number of candles removed and a stats table { candles, items, capped }.
function Store:Prune(now)
    local removedCandles, removedItems = 0, 0

    for id, it in pairs(self.db.items) do
        local tracked = self:_tracked(id)
        if not tracked and self.idleKeep and lastSeen(it) < now - self.idleKeep then
            removedCandles = removedCandles + countKeys(it.hourly) + countKeys(it.daily)
            self.db.items[id] = nil
            self.db.meta[id] = nil
            removedItems = removedItems + 1
        else
            local keep = {
                hourly = tracked and self.trackedHourlyKeep or self.hourlyKeep,
                daily = tracked and self.trackedDailyKeep or self.dailyKeep,
            }
            for res, seconds in pairs(keep) do
                local cutoff = now - seconds
                for t in pairs(it[res]) do
                    if t < cutoff then
                        it[res][t] = nil
                        removedCandles = removedCandles + 1
                    end
                end
            end
        end
    end

    local capped = 0
    if self.maxCandles then
        local excess = self:Stats().candles - self.maxCandles
        for _, pass in ipairs({ { "hourly", false }, { "daily", false }, { "hourly", true }, { "daily", true } }) do
            if excess <= 0 then break end
            local n = self:_trim(pass[1], pass[2], excess)
            capped, excess = capped + n, excess - n
        end
    end

    local total = removedCandles + capped
    return total, { candles = total, items = removedItems, capped = capped }
end
