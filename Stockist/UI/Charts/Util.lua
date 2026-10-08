local ADDON_NAME, Stockist = ...

local Util = {}
Stockist.Charts.Util = Util

function Util.Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

--- Index of the point (points sorted by x) whose x is closest to `x`, or nil for no points.
function Util.Nearest(points, x)
    local n = #points
    if n == 0 then return nil end
    local lo, hi = 1, n
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        if points[mid].x < x then lo = mid + 1 else hi = mid end
    end
    if points[lo].x < x then return lo end
    if lo > 1 and (x - points[lo - 1].x) <= (points[lo].x - x) then return lo - 1 end
    return lo
end

--- A point's single value: `y`, or the close `c` of a candle.
function Util.Values(points)
    local out = { n = #points }
    for i, p in ipairs(points) do out[i] = p.y or p.c end
    return out
end

--- xmin, xmax, ymin, ymax over points, where `lows`/`highs` name the fields holding each point's
--- lowest/highest y (e.g. "l" and "h" for candles). Returns nil for no points.
function Util.Extent(points, lowField, highField)
    if #points == 0 then return nil end
    local xmin, xmax = points[1].x, points[1].x
    local ymin, ymax = math.huge, -math.huge
    for _, p in ipairs(points) do
        if p.x < xmin then xmin = p.x end
        if p.x > xmax then xmax = p.x end
        local lo, hi = p[lowField], p[highField]
        if lo < ymin then ymin = lo end
        if hi > ymax then ymax = hi end
    end
    return xmin, xmax, ymin, ymax
end

--- Widen an x range by half the closest spacing between points, so bars and candles centred on the
--- first and last point fit inside the plot instead of hanging over its edges.
function Util.PadHalfStep(points, xmin, xmax)
    local gap
    for i = 2, #points do
        local dx = points[i].x - points[i - 1].x
        if dx > 0 and (not gap or dx < gap) then gap = dx end
    end
    if not gap then return xmin, xmax end
    return xmin - gap / 2, xmax + gap / 2
end

--- Clip a segment (x1 <= x2) to xmin <= x <= xmax, interpolating y. Returns nil if fully outside.
function Util.ClipSegmentX(x1, y1, x2, y2, xmin, xmax)
    if x2 < xmin or x1 > xmax then return nil end
    if x1 == x2 then return x1, y1, x2, y2 end
    local slope = (y2 - y1) / (x2 - x1)
    if x1 < xmin then y1 = y1 + slope * (xmin - x1); x1 = xmin end
    if x2 > xmax then y2 = y1 + slope * (xmax - x1); x2 = xmax end
    return x1, y1, x2, y2
end

--- Thin a long series to roughly `maxPoints` by striding, always keeping the last point.
function Util.Decimate(points, maxPoints)
    local n = #points
    if n <= maxPoints then return points end
    local stride = math.ceil(n / maxPoints)
    local out = {}
    for i = 1, n, stride do out[#out + 1] = points[i] end
    if out[#out] ~= points[n] then out[#out + 1] = points[n] end
    return out
end

--- Width in pixels for bars/candles: 60% of the closest spacing between points, kept between 2 and
--- 16px so a few sparse candles do not turn into fat blocks.
function Util.BarWidth(points, xs, explicit)
    if explicit then return explicit end
    local best
    for i = 2, #points do
        local dx = xs:Map(points[i].x) - xs:Map(points[i - 1].x)
        if dx > 0 and (not best or dx < best) then best = dx end
    end
    if not best then return 8 end
    return Util.Clamp(best * 0.6, 2, 16)
end
