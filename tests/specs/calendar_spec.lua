local DAY, HOUR = 86400, 3600

local function cal() return load_addon("Core/Calendar.lua").Calendar end

test("civil dates round-trip, including leap days and century years", function()
    local C = cal()
    eq(C.DaysFromCivil(1970, 1, 1), 0)
    eq(C.DaysFromCivil(1970, 2, 1), 31)
    eq(C.DaysFromCivil(2024, 2, 29) + 1, C.DaysFromCivil(2024, 3, 1))
    eq(C.DaysFromCivil(2100, 2, 28) + 1, C.DaysFromCivil(2100, 3, 1), "2100 is not a leap year")
    eq(C.DaysFromCivil(2000, 2, 28) + 2, C.DaysFromCivil(2000, 3, 1), "2000 is a leap year")
    for _, days in ipairs({ -400, -1, 0, 1, 58, 59, 365, 10957, 20000, 20733 }) do
        local y, m, d = C.CivilFromDays(days)
        eq(C.DaysFromCivil(y, m, d), days)
    end
    local y, m, d = C.CivilFromDays(C.DaysFromCivil(2026, 10, 8))
    eq(y, 2026); eq(m, 10); eq(d, 8)
end)

test("DayRange is local midnight to local midnight", function()
    local C = cal()
    local noon = 40 * DAY + 12 * HOUR
    local s, e = C.DayRange(noon, 0)
    eq(s, 40 * DAY); eq(e, 41 * DAY)
    -- in UTC+10 local midnight is 14:00 UTC the day before
    local s10, e10 = C.DayRange(noon, 10 * HOUR)
    eq(s10, 40 * DAY - 10 * HOUR); eq(e10, s10 + DAY)
    eq(noon >= s10 and noon < e10, true)
end)

test("WeekRange runs Monday to Monday", function()
    local C = cal()
    -- 2026-10-08 is a Thursday; its week is Mon 5 Oct to Mon 12 Oct
    local thu = C.DaysFromCivil(2026, 10, 8) * DAY + 15 * HOUR
    local s, e = C.WeekRange(thu, 0)
    eq(s, C.DaysFromCivil(2026, 10, 5) * DAY)
    eq(e, C.DaysFromCivil(2026, 10, 12) * DAY)
    -- a Monday and a Sunday belong to the right week
    local mon = C.DaysFromCivil(2026, 10, 5) * DAY
    eq(select(1, C.WeekRange(mon, 0)), mon)
    local sun = C.DaysFromCivil(2026, 10, 11) * DAY + 23 * HOUR
    eq(select(1, C.WeekRange(sun, 0)), mon)
    eq(select(1, C.WeekRange(sun + 2 * HOUR, 0)), mon + 7 * DAY, "Monday 01:00 starts a new week")
end)

test("WeekRange uses local time near midnight", function()
    local C = cal()
    -- Sunday 2026-10-11 20:00 UTC is already Monday 06:00 in UTC+10
    local ts = C.DaysFromCivil(2026, 10, 11) * DAY + 20 * HOUR
    local s = C.WeekRange(ts, 10 * HOUR)
    eq(s, C.DaysFromCivil(2026, 10, 12) * DAY - 10 * HOUR)
end)

test("MonthRange covers the calendar month and reports its length", function()
    local C = cal()
    local s, e, n = C.MonthRange(C.DaysFromCivil(2026, 10, 8) * DAY, 0)
    eq(s, C.DaysFromCivil(2026, 10, 1) * DAY); eq(e, C.DaysFromCivil(2026, 11, 1) * DAY); eq(n, 31)
    local _, _, feb = C.MonthRange(C.DaysFromCivil(2024, 2, 10) * DAY, 0)
    eq(feb, 29)
    local _, _, feb25 = C.MonthRange(C.DaysFromCivil(2025, 2, 10) * DAY, 0)
    eq(feb25, 28)
    local ds, de, dn = C.MonthRange(C.DaysFromCivil(2026, 12, 31) * DAY + 5 * HOUR, 0)
    eq(ds, C.DaysFromCivil(2026, 12, 1) * DAY); eq(de, C.DaysFromCivil(2027, 1, 1) * DAY); eq(dn, 31)
    local apr = select(3, C.MonthRange(C.DaysFromCivil(2026, 4, 30) * DAY, 0))
    eq(apr, 30)
end)
