local ADDON_NAME, Stockist = ...

local F = Stockist.Charts.formatters
local Format = Stockist.Format

F:Register("money", function(v) return Format.MoneyShort(v) end)
F:Register("percent", function(v) return Format.Percent(v) end)
F:Register("int", function(v) return ("%d"):format(math.floor(v + 0.5)) end)
F:Register("number", function(v) return Format.Number(v) end)

--- Unix time. ctx.span is the visible range, ctx.resolution the size of one data point in seconds
--- (a daily candle has no meaningful time of day, so it is labelled with the date only), and
--- ctx.long asks for the fuller form used in tooltips.
F:Register("time", function(v, ctx)
    local fmt = date or os.date
    ctx = ctx or {}
    local span = ctx.span or 0
    local daily = ctx.resolution and ctx.resolution >= 86400
    if ctx.long then
        return daily and fmt("%a %d %b", v) or fmt("%d %b %H:%M", v)
    end
    if not daily and span <= 2 * 86400 then return fmt("%H:%M", v) end
    if span <= 150 * 86400 then return fmt("%d %b", v) end
    return fmt("%b %Y", v)
end)
