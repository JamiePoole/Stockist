# Stockist

A trading-terminal style window for the WoW: Forever Auction House. It tracks commodity prices (cloth, herbs, skins, ore...) over time with charts, tickers, watches and alerts, and shares readings between addon users.

Status: early scaffold. Targets WoW: Forever (Interface 16001).

## Layout
- `Stockist/` - the addon (what gets shipped).
- `dev/StockistProbe/` - dev-only addon that tests which chat channels and Auction House APIs the client allows.
- `scripts/build.ps1` - copy the addon into the WoW AddOns folder.
- `scripts/release.ps1` - bump the version, build the release zip, optionally upload to CurseForge.

## Develop
```powershell
./scripts/build.ps1 -IncludeProbe     # copy to the Forever beta AddOns folder
./scripts/build.ps1 -Watch            # re-copy on every file change
```
In game: `/reload`, then `/stkprobe` for the capability probe.

## Test
```powershell
./scripts/test.ps1              # pure-Lua specs under Lua 5.1 (creates .venv on first run)
./scripts/test.ps1 -Filter data # only specs whose file name contains "data"
```
In game, once an Auction House is open: `/stockist scan`, `/stockist`, `/stockist item <id>`, `/stockist movers`, `/stockist chart [id]`.

The chart engine and how to extend it: [docs/charts.md](docs/charts.md).

Data cleanup (`/stockist keep`, `track`, `cleanup`): untracked items keep 7 days of hourly and 180 days of daily candles and are dropped after 90 days without a reading; tracked items keep 30 / 730 days and are never dropped. Every limit can be changed with `/stockist keep <name> <days>`.

Findings about what the Forever client allows (chat channels, Communities, AH API) are in [docs/transport-findings.md](docs/transport-findings.md).

## Release
```powershell
./scripts/release.ps1 -Bump patch -DryRun   # preview
./scripts/release.ps1 -Bump patch           # bump, update changelog stub, build dist/Stockist-<version>.zip
./scripts/release.ps1 -Bump patch -Upload   # ...and upload to CurseForge (needs .env)
```
Copy `.env.example` to `.env` and fill in the CurseForge token and project ID.
