local ADDON_NAME, Stockist = ...

-- The chart engine. One engine draws every chart in the addon; features supply data and a config
-- and never draw anything themselves. Behaviour is added by registering plugins:
--   Charts.series      how to draw one kind of data (line, candle, bar...)
--   Charts.overlays    derive extra series from an existing one (sma, bollinger, hline...)
--   Charts.formatters  turn an axis or tooltip value into text
--   Charts.themes      colour sets
--
-- Series plugin:   { extent(spec) -> xmin, xmax, ymin, ymax | nil
--                    draw(spec, ctx)
--                    hit(spec, ctx, xValue) -> { x, rows = { {text, color} ... } } | nil }
-- Overlay plugin:  { build(spec, source) -> array of derived series specs }
-- Formatter:       function(value, ctx) -> string        (ctx.span = size of the axis range)
--
-- Drawing goes through a Canvas (see FrameCanvas.lua). Canvas coordinates: x right, y up, origin at
-- the bottom-left of the chart.
local Charts = {
    series = Stockist.NewRegistry("chart series"),
    overlays = Stockist.NewRegistry("chart overlay"),
    formatters = Stockist.NewRegistry("chart formatter"),
    themes = Stockist.NewRegistry("chart theme"),
}
Stockist.Charts = Charts
