local ADDON_NAME, Stockist = ...

local Charts = Stockist.Charts
local Util = Charts.Util

-- spec: { type = "line", points = { {x, y}... }, color?, width?, label? }
Charts.series:Register("line", {
    extent = function(spec)
        return Util.Extent(spec.points, "y", "y")
    end,

    draw = function(spec, ctx)
        local points = Util.Decimate(spec.points, math.max(2, ctx.rect.w * 2))
        local width = spec.width or 1.5
        local lo, hi = ctx.rect.y, ctx.rect.y + ctx.rect.h
        for i = 2, #points do
            local a, b = points[i - 1], points[i]
            local x1, y1, x2, y2 = Util.ClipSegmentX(a.x, a.y, b.x, b.y, ctx.xs.d0, ctx.xs.d1)
            if x1 then
                ctx.canvas:line(
                    ctx.xs:Map(x1), Util.Clamp(ctx.ys:Map(y1), lo, hi),
                    ctx.xs:Map(x2), Util.Clamp(ctx.ys:Map(y2), lo, hi),
                    ctx.color, width)
            end
        end
        -- Dots at the data points: always for a lone point (no segment to see), and on request
        -- (`markers = true`) so each individual reading is visible on a sparse line.
        if spec.markers or #points == 1 then
            for _, p in ipairs(points) do
                if p.x >= ctx.xs.d0 and p.x <= ctx.xs.d1 then
                    local x, y = ctx.xs:Map(p.x), Util.Clamp(ctx.ys:Map(p.y), lo, hi)
                    ctx.canvas:rect(x - 2, y - 2, 4, 4, ctx.color)
                end
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
