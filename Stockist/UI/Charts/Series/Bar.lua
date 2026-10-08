local ADDON_NAME, Stockist = ...

local Charts = Stockist.Charts
local Util = Charts.Util

-- spec: { type = "bar", points = { {x, y, up?}... }, barWidth? (pixels), label? }
-- Bars rise from zero. If a point has `up` (true/false) it is coloured with the theme's up/down
-- colour, otherwise the series colour is used. Handy for volume or supply under a price chart.
Charts.series:Register("bar", {
    extent = function(spec)
        local xmin, xmax, ymin, ymax = Util.Extent(spec.points, "y", "y")
        if not xmin then return nil end
        xmin, xmax = Util.PadHalfStep(spec.points, xmin, xmax)
        return xmin, xmax, math.min(0, ymin), math.max(0, ymax)
    end,

    draw = function(spec, ctx)
        local bw = Util.BarWidth(spec.points, ctx.xs, spec.barWidth)
        local lo, hi = ctx.rect.y, ctx.rect.y + ctx.rect.h
        local base = Util.Clamp(ctx.ys:Map(0), lo, hi)
        for _, p in ipairs(spec.points) do
            if p.x >= ctx.xs.d0 and p.x <= ctx.xs.d1 then
                local color = ctx.color
                if p.up ~= nil then color = p.up and ctx.theme.up or ctx.theme.down end
                color = { color[1], color[2], color[3], 0.55 }
                local y = Util.Clamp(ctx.ys:Map(p.y), lo, hi)
                ctx.canvas:rect(ctx.xs:Map(p.x) - bw / 2, math.min(base, y), bw, math.max(1, math.abs(y - base)), color)
            end
        end
    end,

    hit = function(spec, ctx, xValue)
        local i = Util.Nearest(spec.points, xValue)
        if not i then return nil end
        local p = spec.points[i]
        return {
            x = p.x,
            y = ctx.ys:Map(p.y),
            rows = { { text = (spec.label or "value") .. ": " .. ctx.format(p.y), color = ctx.color } },
        }
    end,
})
