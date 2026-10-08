local ADDON_NAME, Stockist = ...

local F = Stockist.Charts.formatters
local Format = Stockist.Format

F:Register("money", function(v) return Format.MoneyShort(v) end)
F:Register("percent", function(v) return Format.Percent(v) end)
F:Register("int", function(v) return ("%d"):format(math.floor(v + 0.5)) end)
F:Register("number", function(v) return Format.Number(v) end)

--- Unix time; the label gets less precise as the visible span grows.
F:Register("time", function(v, ctx)
    local fmt = date or os.date
    local span = ctx and ctx.span or 0
    if span <= 2 * 86400 then return fmt("%H:%M", v) end
    if span <= 150 * 86400 then return fmt("%d %b", v) end
    return fmt("%b %Y", v)
end)
