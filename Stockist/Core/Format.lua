local ADDON_NAME, Stockist = ...

local Format = {}
Stockist.Format = Format

--- Copper -> "12g 34s 56c", dropping zero parts.
function Format.Money(copper)
    local c = math.floor(copper + 0.5)
    local g = math.floor(c / 10000)
    local s = math.floor((c % 10000) / 100)
    local cc = c % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if cc > 0 or #parts == 0 then parts[#parts + 1] = cc .. "c" end
    return table.concat(parts, " ")
end

--- Seconds ago -> "just now", "12m ago", "3h ago", "2d ago".
function Format.Age(seconds)
    if seconds < 60 then return "just now" end
    if seconds < 3600 then return math.floor(seconds / 60) .. "m ago" end
    if seconds < 86400 then return math.floor(seconds / 3600) .. "h ago" end
    return math.floor(seconds / 86400) .. "d ago"
end

--- 1.234 -> "+1.23%", -0.5 -> "-0.50%".
function Format.Percent(p)
    return ("%+.2f%%"):format(p)
end
