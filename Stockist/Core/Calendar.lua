local ADDON_NAME, Stockist = ...

-- Calendar maths on unix timestamps, in the player's local time. `tz` is local time minus UTC in
-- seconds (see Clock.tzOffset). Pure functions: no game API, so they are unit-tested.
-- Days are counted from 1970-01-01; the civil-date conversions are Howard Hinnant's algorithms.
local Calendar = {}
Stockist.Calendar = Calendar

local DAY = 86400
Calendar.DAY = DAY

--- Days since 1970-01-01 -> year, month (1-12), day (1-31).
function Calendar.CivilFromDays(z)
    z = z + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
    local y = yoe + era * 400
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = mp < 10 and mp + 3 or mp - 9
    if m <= 2 then y = y + 1 end
    return y, m, d
end

--- Year, month, day -> days since 1970-01-01.
function Calendar.DaysFromCivil(y, m, d)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = (m > 2) and (m - 3) or (m + 9)
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

local function localDay(ts, tz)
    return math.floor((ts + tz) / DAY)
end

--- Local midnight at or before `ts`, and the next local midnight.
function Calendar.DayRange(ts, tz)
    local d = localDay(ts, tz)
    return d * DAY - tz, (d + 1) * DAY - tz
end

--- Monday 00:00 local at or before `ts`, and the following Monday.
function Calendar.WeekRange(ts, tz)
    local d = localDay(ts, tz)
    local monday = d - (d + 3) % 7 -- 1970-01-01 was a Thursday
    return monday * DAY - tz, (monday + 7) * DAY - tz
end

--- The 1st of the month 00:00 local, the 1st of the next month, and the number of days in the month.
function Calendar.MonthRange(ts, tz)
    local y, m = Calendar.CivilFromDays(localDay(ts, tz))
    local first = Calendar.DaysFromCivil(y, m, 1)
    local nextY, nextM = y, m + 1
    if nextM == 13 then nextY, nextM = y + 1, 1 end
    local nextFirst = Calendar.DaysFromCivil(nextY, nextM, 1)
    return first * DAY - tz, nextFirst * DAY - tz, nextFirst - first
end
