local ADDON_NAME, Stockist = ...

local Charts = Stockist.Charts
local Scale = Charts.Scale
local Util = Charts.Util

-- Config:
--   {
--     theme = "dark", minimal = false (no axes or padding: sparklines), padding = {left,right,top,bottom},
--     x = { format = "time", range = {min, max}?, tzOffset = seconds?, resolution = seconds per data point? },
--     panes = {
--       { id = "price", weight = 3, title = "Price" (shown in the corner), axis = { format = "money" },
--         y = { range = {min, max}? },
--         series   = { { type = "candle", id = "price", points = ... } },
--         overlays = { { type = "sma", of = "price", period = 20 } } },
--       { id = "supply", weight = 1, axis = { format = "int" }, series = { { type = "bar", points = ... } } },
--     },
--   }
-- A chart with one pane can use the shorthand { series = ..., overlays = ..., axis = ..., y = ... }.
--
-- Build(config, w, h) resolves plugins, domains, scales and pixel rectangles into a model.
-- Draw(model, canvas) paints it. Hover(model, canvas, px, py) paints the crosshair and tooltip.

local DEFAULT_PADDING = { left = 58, right = 10, top = 8, bottom = 22 }
local PANE_GAP = 6
local Y_MARGIN = 0.05

local function normalize(config)
    if config.panes then return config end
    local cfg = {}
    for k, v in pairs(config) do cfg[k] = v end -- keep every top-level option (emptyText, transparent...)
    cfg.panes = { {
        id = "main", weight = 1, axis = config.axis, y = config.y,
        series = config.series or {}, overlays = config.overlays or {},
    } }
    return cfg
end

local function unionExtent(entries)
    local xmin, xmax, ymin, ymax
    for _, e in ipairs(entries) do
        local x0, x1, y0, y1 = e.plugin.extent(e.spec)
        if x0 then
            xmin = xmin and math.min(xmin, x0) or x0
            xmax = xmax and math.max(xmax, x1) or x1
            ymin = ymin and math.min(ymin, y0) or y0
            ymax = ymax and math.max(ymax, y1) or y1
        end
    end
    return xmin, xmax, ymin, ymax
end

function Charts.Build(config, w, h)
    local cfg = normalize(config)
    local theme = Charts.themes:Require(cfg.theme or "dark")
    local pad = cfg.padding or (cfg.minimal and { left = 0, right = 0, top = 0, bottom = 0 } or DEFAULT_PADDING)
    local plot = {
        x = pad.left, y = pad.bottom,
        w = math.max(1, w - pad.left - pad.right),
        h = math.max(1, h - pad.top - pad.bottom),
    }
    local model = {
        config = cfg, theme = theme, w = w, h = h, plot = plot, panes = {}, warnings = {},
        xformat = (cfg.x and cfg.x.format) or "number",
    }

    -- Panes stack top to bottom, sharing the x axis; heights follow their weights.
    local totalWeight = 0
    for _, p in ipairs(cfg.panes) do totalWeight = totalWeight + (p.weight or 1) end
    local usable = math.max(1, plot.h - PANE_GAP * (#cfg.panes - 1))
    local yTop = plot.y + plot.h
    local colorIndex = 0
    local function nextColor()
        colorIndex = colorIndex + 1
        return theme.series[(colorIndex - 1) % #theme.series + 1]
    end

    local allEntries = {}
    for i, p in ipairs(cfg.panes) do
        local height = usable * (p.weight or 1) / totalWeight
        local pane = {
            id = p.id or ("pane" .. i), def = p,
            rect = { x = plot.x, y = yTop - height, w = plot.w, h = height },
            entries = {},
            formatName = (p.axis and p.axis.format) or "number",
        }
        yTop = yTop - height - PANE_GAP
        for _, spec in ipairs(p.series or {}) do
            local entry = { spec = spec, plugin = Charts.series:Require(spec.type), color = spec.color or nextColor() }
            pane.entries[#pane.entries + 1] = entry
        end
        model.panes[#model.panes + 1] = pane
    end

    -- Overlays derive extra line series from a source series, wherever the source lives.
    for _, pane in ipairs(model.panes) do
        for _, ospec in ipairs(pane.def.overlays or {}) do
            local source
            for _, other in ipairs(model.panes) do
                for _, e in ipairs(other.entries) do
                    if (ospec.of == nil and other == pane) or (ospec.of ~= nil and e.spec.id == ospec.of) then
                        source = source or e.spec
                    end
                end
            end
            if not source then
                model.warnings[#model.warnings + 1] = "overlay '" .. tostring(ospec.type) .. "' has no source series"
            else
                local overlay = Charts.overlays:Require(ospec.type)
                for _, derived in ipairs(overlay.build(ospec, source)) do
                    pane.entries[#pane.entries + 1] = {
                        spec = derived, plugin = Charts.series:Require(derived.type),
                        color = derived.color or nextColor(), derived = true,
                    }
                end
            end
        end
        for _, e in ipairs(pane.entries) do allEntries[#allEntries + 1] = e end
    end

    -- Domains: x is shared; y is per pane, with a small margin (bars keep their zero baseline).
    local xmin, xmax = unionExtent(allEntries)
    model.empty = xmin == nil
    local xr = cfg.x and cfg.x.range
    if xr then xmin, xmax = xr[1], xr[2] end
    xmin, xmax = xmin or 0, xmax or 1
    model.xs = Scale.Linear(xmin, xmax, plot.x, plot.x + plot.w)

    for _, pane in ipairs(model.panes) do
        local _, _, y0, y1 = unionExtent(pane.entries)
        local yr = pane.def.y and pane.def.y.range
        if yr then
            y0, y1 = yr[1], yr[2]
        elseif y0 then
            local margin = (y1 - y0) * Y_MARGIN
            if y0 ~= 0 then y0 = y0 - margin end
            y1 = y1 + margin
        end
        pane.ys = Scale.Linear(y0 or 0, y1 or 1, pane.rect.y, pane.rect.y + pane.rect.h)
        pane.format = function(v)
            return Charts.formatters:Require(pane.formatName)(v, { span = pane.ys.d1 - pane.ys.d0 })
        end
    end
    return model
end

local function axisLabel(model, value, long)
    local x = model.config.x or {}
    return Charts.formatters:Require(model.xformat)(value, {
        span = model.xs.d1 - model.xs.d0, resolution = x.resolution, long = long,
    })
end

local function paneContext(model, pane, entry, canvas)
    return {
        canvas = canvas, xs = model.xs, ys = pane.ys, rect = pane.rect, theme = model.theme,
        color = entry.color, format = pane.format,
    }
end

local function drawAxes(model, canvas)
    local t = model.theme
    local plot = model.plot
    local xs = model.xs

    -- Vertical grid and x labels
    local ticks
    if model.xformat == "time" then
        -- Daily candles sit on UTC midnights (so every player's buckets agree). Put the ticks there
        -- too, so each tick lines up with its candle; only finer data uses local clock boundaries.
        local x = model.config.x
        local daily = x.resolution and x.resolution >= 86400
        ticks = Scale.TimeTicks(xs.d0, xs.d1, math.max(2, math.floor(plot.w / 80)), daily and 0 or x.tzOffset)
    else
        ticks = Scale.Ticks(xs.d0, xs.d1, math.max(2, math.floor(plot.w / 80)))
    end
    for _, v in ipairs(ticks) do
        local x = xs:Map(v)
        canvas:line(x, plot.y, x, plot.y + plot.h, t.grid, 1)
        canvas:text(x, plot.y - 4, axisLabel(model, v), t.text, "TOP")
    end

    -- Horizontal grid and y labels, per pane
    for _, pane in ipairs(model.panes) do
        local r = pane.rect
        canvas:line(r.x, r.y, r.x, r.y + r.h, t.axis, 1)
        if pane.def.title then
            canvas:text(r.x + 6, r.y + r.h - 4, pane.def.title, { t.text[1], t.text[2], t.text[3], 0.6 }, "TOPLEFT")
        end
        for _, v in ipairs(Scale.Ticks(pane.ys.d0, pane.ys.d1, math.max(2, math.floor(r.h / 40)))) do
            local y = pane.ys:Map(v)
            canvas:line(r.x, y, r.x + r.w, y, t.grid, 1)
            canvas:text(r.x - 6, y, pane.format(v), t.text, "RIGHT")
        end
    end
end

function Charts.Draw(model, canvas)
    canvas:begin(model.w, model.h)
    local t = model.theme
    if not model.config.transparent then
        canvas:rect(0, 0, model.w, model.h, t.background)
    end
    if model.empty then
        canvas:text(model.w / 2, model.h / 2, model.config.emptyText or "No data yet", t.text, "CENTER")
        canvas:finish()
        return
    end
    if not model.config.minimal then drawAxes(model, canvas) end
    for _, pane in ipairs(model.panes) do
        for _, entry in ipairs(pane.entries) do
            entry.plugin.draw(entry.spec, paneContext(model, pane, entry, canvas))
        end
    end
    canvas:finish()
end

local function inside(rect, px, py)
    return px >= rect.x and px <= rect.x + rect.w and py >= rect.y and py <= rect.y + rect.h
end

--- Crosshair and tooltip for the mouse at (px, py). Returns the hit info, or nil when the mouse is
--- outside the plot (the canvas is still cleared).
function Charts.Hover(model, canvas, px, py)
    canvas:begin(model.w, model.h)
    local result
    local t = model.theme
    local plot = model.plot
    if not model.empty and px and inside(plot, px, py) then
        local xValue = model.xs:Invert(px)
        local rows, snapped = {}, nil
        for _, pane in ipairs(model.panes) do
            for _, entry in ipairs(pane.entries) do
                local hit = entry.plugin.hit and entry.plugin.hit(entry.spec, paneContext(model, pane, entry, canvas), xValue)
                if hit then
                    snapped = snapped or hit.x
                    for _, row in ipairs(hit.rows) do rows[#rows + 1] = row end
                end
            end
        end
        if snapped then
            local sx = model.xs:Map(snapped)
            canvas:line(sx, plot.y, sx, plot.y + plot.h, t.crosshair, 1)
            canvas:line(plot.x, py, plot.x + plot.w, py, t.crosshair, 1)

            local header = axisLabel(model, snapped, true)
            local lines = { { text = header, color = t.text } }
            for _, row in ipairs(rows) do lines[#lines + 1] = row end

            local widest = 0
            for _, l in ipairs(lines) do widest = math.max(widest, #l.text) end
            local bw, bh = widest * 6.5 + 12, #lines * 13 + 8
            local bx = sx + 12
            if bx + bw > model.w then bx = sx - 12 - bw end
            local by = Util.Clamp(py - bh / 2, 0, model.h - bh)
            canvas:rect(bx, by, bw, bh, t.tooltipBackground)
            for i, l in ipairs(lines) do
                canvas:text(bx + 6, by + bh - 4 - (i - 1) * 13, l.text, l.color, "TOPLEFT")
            end
            result = { x = snapped, rows = lines, box = { x = bx, y = by, w = bw, h = bh } }
        end
    end
    canvas:finish()
    return result
end
