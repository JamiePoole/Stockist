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
- Unit tests under Lua 5.1 (`scripts/test.ps1`).
