# Changelog

## 0.1.0
- Project scaffold, build and release scripts, capability probe.
- Core: event bus, plugin registry, config, clock, formatting.
- Data: OHLC rollups, indicators (SMA, EMA, Bollinger, RSI), reading store with retention.
- Market: Auction House full-scan adapter, price aggregation (min, median of cheapest units, supply).
- Chat commands: `/stockist` (status, scan, item, movers).
- Unit tests under Lua 5.1 (`scripts/test.ps1`).
