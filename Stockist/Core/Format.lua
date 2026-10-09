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

--- The other way: "1g20s5c", "5s", "12g", "250c", "1g 5s" -> copper. Nil for anything else; a bare number is
--- refused on purpose, because "5" could be five copper or five silver and the player must say which.
function Format.ParseMoney(text)
    text = (text or ""):lower():gsub("%s+", "")
    if text == "" then return nil end
    local value = { g = 10000, s = 100, c = 1 }
    local total, seen, rest = 0, {}, text
    while rest ~= "" do
        local number, unit, tail = rest:match("^(%d+%.?%d*)([gsc])(.*)$")
        if not number or seen[unit] then return nil end
        seen[unit] = true
        total = total + tonumber(number) * value[unit]
        rest = tail
    end
    return math.floor(total + 0.5)
end

-- Coin colours as in the game's money display.
local GOLD, SILVER, COPPER = { 1, 0.82, 0 }, { 0.78, 0.78, 0.81 }, { 0.93, 0.65, 0.37 }

--- Like Money, but each part carries its coin colour: gold, silver and copper.
function Format.MoneyColored(copper)
    local c = math.floor(copper + 0.5)
    local g = math.floor(c / 10000)
    local s = math.floor((c % 10000) / 100)
    local cc = c % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = Format.Colored(g .. "g", GOLD[1], GOLD[2], GOLD[3]) end
    if s > 0 then parts[#parts + 1] = Format.Colored(s .. "s", SILVER[1], SILVER[2], SILVER[3]) end
    if cc > 0 or #parts == 0 then parts[#parts + 1] = Format.Colored(cc .. "c", COPPER[1], COPPER[2], COPPER[3]) end
    return table.concat(parts, " ")
end

-- The game's coin art. Width 0 / height 0 scale it to the font; the 2 is a small gap before it.
local COIN_ICONS = {
    g = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
    s = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
    c = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}

--- Money with the real gold, silver and copper coin icons after each number (like the bags).
function Format.MoneyIcons(copper)
    local c = math.floor(copper + 0.5)
    local g = math.floor(c / 10000)
    local s = math.floor((c % 10000) / 100)
    local cc = c % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. COIN_ICONS.g end
    if s > 0 then parts[#parts + 1] = s .. COIN_ICONS.s end
    if cc > 0 or #parts == 0 then parts[#parts + 1] = cc .. COIN_ICONS.c end
    return table.concat(parts, " ")
end

--- Money for on-screen text.
function Format.MoneyDisplay(copper)
    return Format.MoneyIcons(copper)
end

--- Up to two decimals, trailing zeros dropped: 12.5 -> "12.5", 12 -> "12".
function Format.Number(n)
    local s = ("%.2f"):format(n)
    s = s:gsub("0+$", "")
    s = s:gsub("%.$", "")
    return s
end

--- Copper as a compact label for axes and tooltips: "12.35g", "50.5s", "37c".
function Format.MoneyShort(copper)
    local sign = copper < 0 and "-" or ""
    local c = math.abs(copper)
    if c >= 10000 then
        local g = c / 10000
        return sign .. (g >= 100 and ("%.0f"):format(g) or Format.Number(g)) .. "g"
    elseif c >= 100 then
        return sign .. Format.Number(c / 100) .. "s"
    end
    return sign .. Format.Number(c) .. "c"
end

--- "|cffRRGGBB" colour escape for 0-1 components.
function Format.ColorCode(r, g, b)
    return ("|cff%02x%02x%02x"):format(
        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

function Format.Colored(text, r, g, b)
    return Format.ColorCode(r, g, b) .. text .. "|r"
end

--- A length of time as one short unit, rounded down so it never claims more than it covers: "45m", "6h", "3d".
function Format.Span(seconds)
    if seconds < 3600 then return math.max(1, math.floor(seconds / 60)) .. "m" end
    if seconds < 2 * 86400 then return math.floor(seconds / 3600) .. "h" end
    return math.floor(seconds / 86400) .. "d"
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

-- Up and down triangles. They are small textures shipped with the addon (Textures/ArrowUp.tga, ArrowDown.tga),
-- drawn inline in the text, because the glyphs are missing from some of the fonts the panels use.
local ARROW_SIZE = 10
local UP = "|TInterface\\AddOns\\Stockist\\Textures\\ArrowUp:" .. ARROW_SIZE .. ":" .. ARROW_SIZE .. "|t"
local DOWN = "|TInterface\\AddOns\\Stockist\\Textures\\ArrowDown:" .. ARROW_SIZE .. ":" .. ARROW_SIZE .. "|t"
Format.ARROW_UP, Format.ARROW_DOWN = UP, DOWN

--- A move as the markets show it: a green up triangle or a red down triangle, then the size (green or red
--- too), up-triangle 3.10% or down-triangle 0.42%. A move that rounds to nothing is a plain grey "0.00%". Nil gives "".
function Format.Change(p)
    if p == nil then return "" end
    local text = ("%.2f%%"):format(math.abs(p))
    local rounded = tonumber(("%.2f"):format(p))
    if rounded > 0 then return UP .. Format.Colored(text, 0.2, 0.78, 0.45) end
    if rounded < 0 then return DOWN .. Format.Colored(text, 0.92, 0.3, 0.3) end
    return Format.Colored(text, 0.6, 0.6, 0.6)
end
