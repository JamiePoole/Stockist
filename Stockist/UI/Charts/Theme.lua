local ADDON_NAME, Stockist = ...

-- Colours are { r, g, b, a } in 0-1. A theme must define every key below.
Stockist.Charts.themes:Register("dark", {
    background = { 0.06, 0.07, 0.09, 0.92 },
    grid = { 1, 1, 1, 0.07 },
    axis = { 1, 1, 1, 0.25 },
    text = { 0.80, 0.83, 0.88, 1 },
    up = { 0.20, 0.78, 0.45, 1 },
    down = { 0.92, 0.30, 0.30, 1 },
    crosshair = { 1, 1, 1, 0.35 },
    tooltipBackground = { 0.09, 0.10, 0.13, 0.96 },
    -- Cycled for series and overlays that do not set their own colour.
    series = {
        { 0.35, 0.65, 1.00, 1 },
        { 1.00, 0.78, 0.25, 1 },
        { 0.75, 0.50, 1.00, 1 },
        { 0.30, 0.85, 0.85, 1 },
        { 1.00, 0.55, 0.55, 1 },
    },
})
