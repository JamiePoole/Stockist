local ADDON_NAME, Stockist = ...

local Charts = Stockist.Charts
local Util = Charts.Util

-- spec: { type = "candle", points = { {x, o, h, l, c}... }, barWidth? (pixels), label? }
-- Up candles (close >= open) use the theme's `up` colour, down candles `down`.
Charts.series:Register("candle", {
    extent = function(spec)
        local xmin, xmax, ymin, ymax = Util.Extent(spec.points, "l", "h")
        if not xmin then return nil end
        xmin, xmax = Util.PadHalfStep(spec.points, xmin, xmax)
        return xmin, xmax, ymin, ymax
    end,

    draw = function(spec, ctx)
        local points = spec.points
        local bw = Util.BarWidth(points, ctx.xs, spec.barWidth)
        local lo, hi = ctx.rect.y, ctx.rect.y + ctx.rect.h
        for _, p in ipairs(points) do
            if p.x >= ctx.xs.d0 and p.x <= ctx.xs.d1 then
                local x = ctx.xs:Map(p.x)
                local color = (p.c >= p.o) and ctx.theme.up or ctx.theme.down
                local yo, yc = ctx.ys:Map(p.o), ctx.ys:Map(p.c)
                local top, bottom = math.max(yo, yc), math.min(yo, yc)
                ctx.canvas:line(x, Util.Clamp(ctx.ys:Map(p.h), lo, hi),
                    x, Util.Clamp(ctx.ys:Map(p.l), lo, hi), color, 1)
                -- A candle whose open and close match has no height; keep it a visible 2px dash.
                local height = math.max(2, top - bottom)
                ctx.canvas:rect(x - bw / 2, bottom - (height - (top - bottom)) / 2, bw, height, color)
            end
        end
    end,

    hit = function(spec, ctx, xValue)
        local i = Util.Nearest(spec.points, xValue)
        if not i then return nil end
        local p = spec.points[i]
        local up = p.c >= p.o
        local color = up and ctx.theme.up or ctx.theme.down
        return {
            x = p.x,
            y = ctx.ys:Map(p.c),
            rows = {
                { text = "open " .. ctx.format(p.o), color = color },
                { text = "high " .. ctx.format(p.h), color = color },
                { text = "low " .. ctx.format(p.l), color = color },
                { text = "close " .. ctx.format(p.c), color = color },
            },
        }
    end,
})
