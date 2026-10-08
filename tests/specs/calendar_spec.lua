local DAY, HOUR = 86400, 3600

local function cal() return load_addon("Core/Calendar.lua").Calendar end

test("NextBoundary returns the first round local time at or after a timestamp", function()
    local C = cal()
    eq(C.NextBoundary(0, DAY, 0), 0)
    eq(C.NextBoundary(1, DAY, 0), DAY)
    eq(C.NextBoundary(5 * HOUR, 3 * HOUR, 0), 6 * HOUR)
    eq(C.NextBoundary(6 * HOUR, 3 * HOUR, 0), 6 * HOUR, "already on a boundary")
end)

test("NextBoundary respects the timezone", function()
    local C = cal()
    -- local midnight in UTC+10 is 14:00 UTC the day before
    local t = C.NextBoundary(40 * DAY + 3 * HOUR, DAY, 10 * HOUR)
    eq(t, 40 * DAY + 14 * HOUR)
    eq((t + 10 * HOUR) % DAY, 0)
    -- 3-hour boundaries in UTC-5
    local u = C.NextBoundary(40 * DAY + 1, 3 * HOUR, -5 * HOUR)
    eq((u - 5 * HOUR) % (3 * HOUR), 0)
    eq(u > 40 * DAY and u <= 40 * DAY + 3 * HOUR, true)
end)

test("WeekStart is the Monday midnight at or before the timestamp", function()
    local C = cal()
    -- 1970-02-10 is a Tuesday; its Monday is day 39
    eq(C.WeekStart(40 * DAY + 12 * HOUR, 0), 39 * DAY)
    eq(C.WeekStart(39 * DAY, 0), 39 * DAY, "a Monday midnight is its own week start")
    eq(C.WeekStart(39 * DAY - 1, 0), 32 * DAY, "just before: the previous Monday")
    eq(C.WeekStart(45 * DAY + 23 * HOUR, 0), 39 * DAY, "Sunday night is still that week")
    eq(C.WeekStart(46 * DAY + 1, 0), 46 * DAY)
end)

test("WeekStart uses local time near midnight", function()
    local C = cal()
    -- day 45 (Sunday) 20:00 UTC is Monday 06:00 in UTC+10
    local ts = 45 * DAY + 20 * HOUR
    eq(C.WeekStart(ts, 10 * HOUR), 46 * DAY - 10 * HOUR)
    eq(C.WeekStart(ts, 0), 39 * DAY)
end)
