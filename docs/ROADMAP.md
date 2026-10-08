# Roadmap: deferred items

Things we decided to leave out for now, with enough detail to pick them up later.

## Chart window
- **ALL timeframe** (removed for now). Meant to show everything stored for the item, up to the
  retention limits (180 days of daily candles by default). Needs a decision on what the x axis shows
  (probably dates from the first stored candle to today) and on how it behaves with very little data.
  The help text and `TIMEFRAMES` entry were removed; restore both when it is wanted:
  `{ key = "ALL", span = nil, prefer = { "daily", "hourly", "ticks" } }` plus a `timeframe-ALL`
  help topic. `span = nil` needs `BuildConfig` to fall back to the data's own x range.
- Zoom and pan (mouse wheel and drag). The chart's `x.range` option is the hook.
- Area and depth series; colour-blind theme variants.

## Commands
- `/stockist tutorial [on|off]`, once the command registry is on `main` (PR for data retention).
