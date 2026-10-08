local ADDON_NAME, Stockist = ...

local Charts = Stockist.Charts
local Util = Charts.Util
local Indicators = Stockist.Indicators

-- An overlay turns an existing series (its `source`) into extra line series, so overlays need no
-- drawing code of their own. spec.of names the source series by id; default is the pane's first.

--- Line spec from an indicator array aligned with the source points (nil entries are skipped).
local function lineFrom(source, values, label, extra)
    local points = {}
    for i, p in ipairs(source.points) do
        if values[i] ~= nil then points[#points + 1] = { x = p.x, y = values[i] } end
    end
    local spec = { type = "line", points = points, label = label, width = 1.2 }
    if extra then for k, v in pairs(extra) do spec[k] = v end end
    return spec
end

-- { type = "sma", period = 20 }
Charts.overlays:Register("sma", {
    build = function(spec, source)
        local period = spec.period or 20
        local out = Indicators.SMA(Util.Values(source.points), period)
        return { lineFrom(source, out, "SMA " .. period, { color = spec.color }) }
    end,
})

-- { type = "ema", period = 20 }
Charts.overlays:Register("ema", {
    build = function(spec, source)
        local period = spec.period or 20
        local out = Indicators.EMA(Util.Values(source.points), period)
        return { lineFrom(source, out, "EMA " .. period, { color = spec.color }) }
    end,
})

-- { type = "bollinger", period = 20, k = 2 } -> upper and lower bands
Charts.overlays:Register("bollinger", {
    build = function(spec, source)
        local period, k = spec.period or 20, spec.k or 2
        local b = Indicators.Bollinger(Util.Values(source.points), period, k)
        local color = spec.color or { 0.75, 0.5, 1, 0.75 }
        return {
            lineFrom(source, b.upper, "upper band", { color = color, width = 1 }),
            lineFrom(source, b.lower, "lower band", { color = color, width = 1 }),
        }
    end,
})

-- { type = "hline", value = 1500, label = "target" } -> a horizontal reference line
Charts.overlays:Register("hline", {
    build = function(spec, source)
        local pts = source.points
        if #pts == 0 then return {} end
        return { {
            type = "line",
            label = spec.label or "level",
            color = spec.color or { 1, 1, 1, 0.5 },
            width = 1,
            points = { { x = pts[1].x, y = spec.value }, { x = pts[#pts].x, y = spec.value } },
        } }
    end,
})
