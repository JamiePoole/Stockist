local ADDON_NAME, Stockist = ...

-- Scales map data values to canvas pixels; ticks pick "nice" axis marks.
local Scale = {}
Stockist.Charts.Scale = Scale

--- Linear map from the data domain [d0, d1] to the pixel range [r0, r1]. A zero-width domain is
--- widened so a single value still has a position.
function Scale.Linear(d0, d1, r0, r1)
    if d0 == d1 then d0, d1 = d0 - 1, d1 + 1 end
    local k = (r1 - r0) / (d1 - d0)
    return {
        d0 = d0, d1 = d1, r0 = r0, r1 = r1,
        Map = function(_, v) return r0 + (v - d0) * k end,
        Invert = function(_, r) return d0 + (r - r0) / k end,
    }
end

local function log10(x) return math.log(x) / math.log(10) end

--- A step of 1, 2 or 5 times a power of ten giving about `count` marks across `range`.
function Scale.NiceStep(range, count)
    local raw = range / count
    local mag = 10 ^ math.floor(log10(raw))
    local norm = raw / mag
    local step
    if norm <= 1 then step = 1 elseif norm <= 2 then step = 2 elseif norm <= 5 then step = 5 else step = 10 end
    return step * mag
end

--- Tick values inside [d0, d1], about `count` of them.
function Scale.Ticks(d0, d1, count)
    if d1 <= d0 then return { d0 } end
    local step = Scale.NiceStep(d1 - d0, count)
    local first = math.ceil(d0 / step - 1e-9)
    local out = {}
    local i = first
    while i * step <= d1 + step * 1e-9 do
        local v = i * step
        if v == 0 then v = 0 end -- turns negative zero into zero, so labels never read "-0"
        out[#out + 1] = v
        i = i + 1
    end
    return out
end

local TIME_STEPS = {
    60, 300, 900, 1800, 3600, 7200, 10800, 21600, 43200,
    86400, 172800, 604800, 1209600, 2592000,
}

--- Tick times in [d0, d1] (unix seconds) on round clock boundaries. `tzOffset` is local time minus
--- UTC in seconds, so day ticks land on local midnight. Returns ticks, stepSeconds.
function Scale.TimeTicks(d0, d1, count, tzOffset)
    tzOffset = tzOffset or 0
    local span = d1 - d0
    local step = TIME_STEPS[#TIME_STEPS]
    for _, s in ipairs(TIME_STEPS) do
        if span / s <= count then step = s break end
    end
    local out = {}
    local t = math.ceil((d0 + tzOffset) / step) * step - tzOffset
    while t <= d1 do
        out[#out + 1] = t
        t = t + step
    end
    return out, step
end
