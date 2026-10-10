local ADDON_NAME, Stockist = ...

-- Candles: one OHLC bucket of readings for one item.
--   t  bucket start (unix seconds)    o/h/l/c  open, high, low, close price (copper)
--   q  average quantity listed        n        number of readings merged in
--   ot/ct  timestamps of the open and close readings (needed to merge buckets in any order)
local Rollup = { HOUR = 3600, DAY = 86400 }
Stockist.Rollup = Rollup

function Rollup.BucketStart(ts, size)
    return ts - (ts % size)
end

--- `price` is the value the candle follows (the median of the cheapest units); `low` (optional) is the cheapest
--- unit price seen, which sets the candle's low so it shows the lowest price, not just the lowest median.
function Rollup.NewCandle(t, price, qty, ts, low)
    return { t = t, o = price, h = price, l = math.min(low or price, price), c = price, q = qty, n = 1, ot = ts, ct = ts }
end

local FIELDS = { "t", "o", "h", "l", "c", "q", "n", "ot", "ct" }

local function identical(a, b)
    for _, k in ipairs(FIELDS) do
        if a[k] ~= b[k] then return false end
    end
    return true
end

--- Combine two candles for the same bucket. Order-independent, and merging a candle with an
--- identical copy of itself is a no-op, so receiving the same bucket twice is harmless.
--- (Overlapping but different candles can over-count `n`; `n` only weights the average quantity.)
function Rollup.Merge(a, b)
    if identical(a, b) then return a end
    local first = (a.ot <= b.ot) and a or b
    local last = (a.ct >= b.ct) and a or b
    local n = a.n + b.n
    return {
        t = a.t,
        o = first.o, ot = first.ot,
        c = last.c, ct = last.ct,
        h = math.max(a.h, b.h),
        l = math.min(a.l, b.l),
        q = (a.q * a.n + b.q * b.n) / n,
        n = n,
    }
end
