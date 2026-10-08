# Changelog

## 0.1.0
- Project scaffold, build and release scripts, capability probe.
- Core: event bus, plugin registry, config, clock, formatting.
- Data: OHLC rollups, indicators (SMA, EMA, Bollinger, RSI), reading store with retention.
- Market: Auction House full-scan adapter, price aggregation (min, median of cheapest units, supply).
- Chat commands: `/stockist` (status, scan, item, movers, auto).
- Re-scans automatically every 15 minutes while the Auction House stays open (`/stockist auto off` to disable).
- Chart engine: plugin series (line, candle, bar), overlays (SMA, EMA, Bollinger, reference line), formatters, themes, multi-pane layout, crosshair and tooltip.
- `/stockist chart [id]`: resizable price window with 1D/1W/1M/ALL, SMA and Bollinger toggles.
- Data cleanup: runs at login and logout; untracked items keep 7 days hourly / 180 days daily and are removed after 90 idle days; tracked items keep 30 / 730 days and are never removed; hard cap of 80,000 candles. `/stockist track|untrack|tracked|keep|cleanup`.
- `/stockist` commands are now a registry (`Stockist.Commands`), so features add their own.
- The price chart is now a reusable panel (`ChartPanel`) with its own state, registered in a panel registry; the price window hosts one. A stand-in WoW frame layer lets the window code be tested.
- The chart window shows "Item not found" for an ID no item has, and explains a real item with no prices; `/stockist chart|item|track` reject bad IDs instead of guessing.
- `/stockist workspace [item]`: the first version of the trader workspace, one window holding panels in a layout (a watchlist placeholder and a price chart), with link groups so linked panels follow the same item, and a "Pop out" button on the chart.
- Unit tests under Lua 5.1 (`scripts/test.ps1`).
