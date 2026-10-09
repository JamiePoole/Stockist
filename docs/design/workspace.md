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
| Ticker | a thin strip scrolling the tracked items with price and 24h move | v1. Built (`Features/Ticker.lua`): hover pauses, click selects, drop tracks; always moves, repeating a short list to fill the window |
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

Answers "is it worth cancelling?". For each of your listings: your price, the lowest price, how many units are listed cheaper than you, the trend, and the **cost of cancelling**. Measured on Forever: cancelling **forfeits the deposit** (no refund came back), while `C_AuctionHouse.GetCancelCost` reports 0 for a listing with no bid, so the deposit is the number to show. The API does not report the deposit of an existing listing; it is proportional to the duration (2h : 8h : 24h = 1 : 4 : 12) and `timeLeftSeconds` bounds which one it was. The reliable way is to record the deposit when the player posts. Present the numbers and a plain-language summary ("12 units are cheaper than yours; cancelling loses your 92c deposit"). No sales-speed data exists in the AH, so we only report what is visible, never a promise. To confirm on Forever: the cut taken from a sale (read from a sale invoice with `/stkprobe mailcut`).

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

1. ~~Split `Features/PriceChart.lua` into a reusable **chart panel** and a thin window around it.~~ Done: `Features/ChartPanel.lua` (`ChartPanel.Create(parent, opts)`, one object per panel with its own item, scope and indicators), registered as `Stockist.Panels:Get("chart")`; `PriceChart.Show` puts one in a window. `Features/PriceChart.lua` keeps the pure config logic.
2. ~~Panel registry and a workspace host with a fixed first layout.~~ Done: `Features/Workspace.lua` (`/stockist workspace [item]`). A layout is a list of cells placed by fractions of the frame (`Workspace.LAYOUTS`, with a pure `CellRects`); the first layout is a watchlist cell and a chart cell. A panel type that does not exist yet shows a labelled placeholder.
3. ~~Link groups~~ Done: `Core/Link.lua`. Panels in the same group follow the same selected item (`Link.Select(group, item)` fires `LINK_SELECTED`). The item picker (#6) is still to do.
4. ~~Pop-out~~ Done: `Features/PopOut.lua` lifts a panel out of the workspace into a window of its own, one per panel type (popping out again reuses and updates the same window; several windows of one type, such as extra item charts, are a possible later feature). A panel type opts in with a `popout` size table. The window holds its own panel, independent of the workspace, remembers its position and size, and is titled after its panel and item ("Stockist - Linen Cloth (Price chart)"). The chart and the watchlist have a pop-out button. Still to do: compact modes for strips like the ticker (borderless, locked, opacity), reopening pop-outs at login, saved layouts.

5. ~~Item picker~~ Done: `Features/ItemPicker.lua`. Click the item name in a chart header for a searchable dropdown (watchlist first, then everything else; an ID or link can be pasted to open an item with no data). `/stockist chart <name>` searches the same list. Items can also be dropped on the workspace (#43): carry an item on the cursor, then let go or click over a chart, the watchlist, the window or its title bar; the item goes back to its slot. A track toggle in the picker is still to do.

The chart engine, window kit, tooltips and help topics are already reusable and stay as they are.

## Open questions

- Layout mechanics: a grid of resizable cells, free-floating panels, or presets only for v1? (Presets first is the cheapest.)
- How the simple layout and the trader layout are chosen the first time.
- Where the "My auctions" cancel numbers come from when the AH window is closed (the client only reports owned auctions while it is open).
