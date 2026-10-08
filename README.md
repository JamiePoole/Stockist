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

## Release
```powershell
./scripts/release.ps1 -Bump patch -DryRun   # preview
./scripts/release.ps1 -Bump patch           # bump, update changelog stub, build dist/Stockist-<version>.zip
./scripts/release.ps1 -Bump patch -Upload   # ...and upload to CurseForge (needs .env)
```
Copy `.env.example` to `.env` and fill in the CurseForge token and project ID.
