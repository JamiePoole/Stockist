# Design: the Stockist workspace

Status: agreed shape, details open (see the end). Tracks [#5](https://github.com/JamiePoole/Stockist/issues/5).

## Who it is for

Stock and finance hobbyists who play WoW, and casual players (a high schooler, say) who want more gold and know no finance. Both must be able to use it, so:

- **Plain words first, jargon second.** Panels say "cheaper than usual", not "below the lower Bollinger band". Jargon appears with its explanation (tutorial mode, tooltips).
- **Two layouts out of the box**: a simple one (watchlist, one chart, my auctions) and a trader one (everything).
- Nothing in the addon gives instructions to buy or sell. It shows facts and general hints.

## Shape

One **workspace** frame holds many **panels**. The frame can be maximised to cover the screen, and closed without stopping the addon (scanning and sharing run with no window open).

Any panel can be **popped out** into its own window. The chart window we have today is exactly "the price chart panel, popped out". Closing the workspace leaves popped-out panels open.

Popping out is remembered for the session only: after a relog `/stockist` opens the workspace. A setting, off by default, can reopen the previous pop-outs at login. Position and size of each window are always remembered.

## Panels

| Panel | What it shows | Notes |
|---|---|---|
| Watchlist | tracked items: price, change, sparkline | v1. Uses `Data/Tracked.lua` |
| Price chart | candles or line, indicators, supply | v1. Exists (`Features/PriceChart.lua`) |
| Movers | biggest risers and fallers | v1. Command version exists |
| Depth | units listed at each price | v1. Local scan only, never shared |
| Status bar | data age, peers, next scan | v1 |
| My auctions | your listings and where they sit | next. See below |
| Craft margins | cost to craft vs sale price over time | next. Needs recipe data |
| Compare | several items rebased to 0% | later |
| Indexes | Herb / Cloth / Ore baskets | later |
| Alerts log | triggered alerts and warnings | later |
| Screener, seasonality, events calendar | | later |

### My auctions

Answers "is it worth cancelling?". For each of your listings: your price, the lowest price, how many units are listed cheaper than you, the trend, and the **real cost of cancelling** (the client provides `C_AuctionHouse.GetCancelCost`, which Auctionator's Cancelling tab uses; cancelling can forfeit the deposit). Present the numbers and a plain-language summary ("12 units are cheaper than yours; cancelling costs 30s"). No sales-speed data exists in the AH, so we only report what is visible, never a promise. To confirm on Forever: the 5% cut on sales and what exactly a cancel forfeits.

### Craft margins

Margin = sale price of the product minus the cost of its reagents (minus the AH cut), charted over time like any item. Our price history already covers reagents and products. Open question: where recipe and reagent data comes from on Forever (`C_TradeSkillUI`, or a bundled recipe table). Needs a probe before design.

## Components

```text
Stockist.Panels            registry of panel types (same pattern as Charts.series)
  panel = { id, title, minSize, create(parent) -> frame, refresh(ctx), helpKeys }

Workspace                  the frame: layout manager, link groups, maximise, saved layouts
  layout  = list of { panel id, rect, link group }
  link group: panels with the same colour follow the same selected item

PopOut                     hosts one panel in its own Window (UI/Kit/Window.lua)
```

Steps that fall out of this:

1. Split `Features/PriceChart.lua` into a reusable **chart panel** (header, scopes, indicators, chart, legend) and a thin window around it.
2. Panel registry and a workspace host with a fixed first layout.
3. Link groups and the item picker (#6), both per panel.
4. Saved layouts and pop-out.

The chart engine, window kit, tooltips and help topics are already reusable and stay as they are.

## Open questions

- Layout mechanics: a grid of resizable cells, free-floating panels, or presets only for v1? (Presets first is the cheapest.)
- How the simple layout and the trader layout are chosen the first time.
- Where the "My auctions" cancel numbers come from when the AH window is closed (the client only reports owned auctions while it is open).
