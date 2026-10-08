local ADDON_NAME, Stockist = ...

-- Round local-time boundaries on unix timestamps, for chart ticks. `tz` is local time minus UTC in
-- seconds (see Clock.tzOffset). Pure functions: no game API, so they are unit-tested.
local Calendar = {}
Stockist.Calendar = Calendar

local DAY = 86400
Calendar.DAY = DAY

--- The first local time at or after `ts` that is a multiple of `step` seconds since local midnight
--- of 1970-01-01 (so a 3-hour step lands on 00:00, 03:00, 06:00 ... local; a day step on midnight).
function Calendar.NextBoundary(ts, step, tz)
    return math.ceil((ts + tz) / step) * step - tz
end

--- Monday 00:00 local at or before `ts`.
function Calendar.WeekStart(ts, tz)
    local d = math.floor((ts + tz) / DAY)
    return (d - (d + 3) % 7) * DAY - tz -- 1970-01-01 was a Thursday
end
