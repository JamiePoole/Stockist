# Chart engine

One engine draws every chart. A feature supplies data and a config; it never draws.

```lua
local chart = Stockist.Charts.Create(parentFrame, {
    x = { format = "time" },
    panes = {
        { id = "price", weight = 3, axis = { format = "money" },
          series   = { { type = "candle", id = "price", points = candlePoints } },
          overlays = { { type = "sma", of = "price", period = 7 } } },
        { id = "supply", weight = 1, axis = { format = "int" },
          series = { { type = "bar", points = supplyPoints } } },
    },
})
chart.frame:SetAllPoints()
chart:SetConfig(newConfig) -- redraws
```

A one-pane chart can use `{ series = ..., overlays = ..., axis = ... }` directly. `minimal = true`
removes axes and padding (sparklines).

## Layers

| File | Role | Needs the game? |
|---|---|---|
| `Core.lua` | `Build` (layout, scales, plugin resolution), `Draw`, `Hover` | no |
| `Scale.lua`, `Util.lua`, `Formatters.lua` | maths, ticks, labels | no |
| `Series/*.lua`, `Overlays/*.lua` | plugins | no |
| `FrameCanvas.lua`, `ChartFrame.lua` | pooled WoW textures, mouse handling | yes |

Everything above the Canvas is tested with a recording canvas (`tests/support/recording_canvas.lua`).

## Adding behaviour (no engine edits)

**Series type** - how to draw one kind of data:

```lua
Stockist.Charts.series:Register("dots", {
    extent = function(spec) return Stockist.Charts.Util.Extent(spec.points, "y", "y") end, -- xmin, xmax, ymin, ymax
    draw   = function(spec, ctx) ctx.canvas:rect(ctx.xs:Map(p.x), ctx.ys:Map(p.y), 3, 3, ctx.color) end,
    hit    = function(spec, ctx, xValue) ... end, -- optional: tooltip rows for the nearest point
})
```

`ctx` has `canvas, xs, ys, rect, theme, color, format`. Canvas calls: `line`, `rect`, `text`.

**Overlay** - derives extra line series from an existing series:

```lua
Stockist.Charts.overlays:Register("ema", {
    build = function(spec, source) return { { type = "line", points = ..., label = "EMA" } } end,
})
```

**Formatter** (`Charts.formatters`) and **theme** (`Charts.themes`) follow the same pattern.

## Built in

Series: `line`, `candle`, `bar`. Overlays: `sma`, `ema`, `bollinger`, `hline`. Formatters: `money`,
`percent`, `int`, `number`, `time`.

## Not yet

Mouse-wheel zoom and drag-pan (the `x.range` option is the hook), area fills, depth charts, and
colour-blind theme variants.
