# Transport and API findings (WoW: Forever 1.60.1, build 70245, Interface 16001)

Measured with `dev/StockistProbe` on the Forever beta client on 2026-10-08. Re-run the probe after
client updates; Blizzard can change any of this.

## Sending addon messages (`C_ChatInfo.SendAddonMessage`)

| Distribution | Result |
|---|---|
| `CHANNEL` (custom channel) | Success, and our own message came back as `CHAT_MSG_ADDON` |
| `GUILD` | Success, and the message came back |
| `WHISPER` | Success |
| `PARTY` / `RAID` / `INSTANCE_CHAT` | `NotInGroup` (not tested in a group) |
| `SAY` / `YELL` | `InvalidChatType`: blocked by the client |

Not yet verified: delivery to a different player (needs a second character), burst throttling.
Documented limits: 255 bytes per message, 16-character prefix, per-prefix allowance of about 10
messages refilling at 1 per second.

## Communities (`C_Club`): not usable

- `FocusStream`, `GetStreams`, `GetMessageRanges` and `GetMessagesBefore` exist and work.
- `C_Club.SendMessage` is blocked for addons: every call raised `ADDON_ACTION_BLOCKED` and nothing
  was posted, with no Lua error.
- Message content read back through `GetMessageInfo` / `GetMessagesBefore` is an opaque protected
  string (`|Kw104|k`), not readable text.

Conclusion: Communities can neither carry nor store our data.

## Auction House API

All of these exist as functions: `ReplicateItems`, `GetNumReplicateItems`, `GetReplicateItemInfo`,
`SendBrowseQuery`, `GetBrowseResults`, `HasFullBrowseResults`, `SendSearchQuery`,
`GetNumCommoditySearchResults`, `GetCommoditySearchResultInfo`,
`GetCommoditySearchResultsQuantity`, `GetItemKeyInfo`, `MakeItemKey`.

`ReplicateItems` (the full scan) has a server-side wait of about 15 minutes. A request made during the wait is not answered: no `REPLICATE_ITEM_LIST_UPDATE` arrives. Observed 2026-10-08: closing the window mid-scan and reopening made the next request hang forever. Auctionator starts its own wait when it makes the request, not when the scan finishes, and so does Stockist now (`db.scan.requested`); a request unanswered after 45 seconds is given up. Not yet confirmed: whether a request cancelled by closing the window really counts toward the wait (consistent with what we saw).

Auctionator (installed in the same client) uses the same modern commodity AH. Its full scan is the
model for `Market/AuctionScanner.lua`.

## Crafting data (`C_TradeSkillUI`): usable

Measured 2026-10-08 with `/stkprobe craft`, two professions opened.

- Present: `GetAllRecipeIDs`, `GetRecipeInfo`, `GetRecipeSchematic`, `GetBaseProfessionInfo`, `GetChildProfessionInfo`, `IsTradeSkillReady`, `GetRecipeItemLink`. Missing: `GetRecipeNumItemsProduced`. The classic `GetTradeSkill*` globals do not exist.
- Events as on mainline: `TRADE_SKILL_SHOW`, `TRADE_SKILL_LIST_UPDATE`, `TRADE_SKILL_DATA_SOURCE_CHANGED`. The data is only readable while a profession window is open.
- 132 and 507 recipes were listed, including unlearned ones (`learned = true/false`).
- A recipe's schematic gives `outputItemID` and reagents as `{ itemID, quantityRequired }`.
- Not yet checked: items produced per craft, reagent slots with alternatives.

## Own auctions: readable

Measured with `/stkprobe owned` at the Auction House with three buyout listings.

- Present: `QueryOwnedAuctions`, `GetNumOwnedAuctions`, `GetOwnedAuctionInfo`, `GetCancelCost`, `CanCancelAuction`, `CalculateCommodityDeposit`, `CalculateItemDeposit`, `IsThrottledMessageSystemReady`, `GetAvailablePostCount`. Missing: `GetMaxOwnedAuctionCount`, `GetAuctionHouseFee`, `GetAuctionDuration` (so the sale cut is not exposed by an API).
- Events: `OWNED_AUCTIONS_UPDATED`, `AUCTION_HOUSE_THROTTLED_SYSTEM_READY`.
- A listing gives `auctionID`, `itemKey.itemID`, `quantity`, `buyoutAmount`, `status`, `timeLeftSeconds` (exact seconds) and sometimes `itemLink`.
- `GetCancelCost` returned 0 for all three buyout listings. Auctionator warns "Someone has bid on this auction so cancelling will cost you your deposit and:" before cancelling a listing with a bid, which suggests the cost only applies when there is a bid. Whether a cancel returns the deposit is untested (`/stkprobe cancelwatch`).
- Deposit for one unit at durations 1/2/3 was e.g. 3/12/36, 16/64/192, 23/92/276 copper: proportional 1 : 4 : 12, matching Classic's 2-hour, 8-hour and 24-hour auctions. `timeLeftSeconds` of 28,784 is 8 hours minus 16 seconds.
- The AH cut is not exposed; read it from a sale invoice with `/stkprobe mailcut`.

## Decisions

- Primary transport: a shared hidden custom channel carrying addon messages. Fallback: guild.
- History catch-up is peer to peer (request, randomised reply delay, suppression of duplicates).
- Message authenticity: signed readings (HMAC with a rotating time-window key and a per-release
  secret, bound to the verified sender name) plus consensus and sanity checks. This is abuse
  resistance, not cryptographic security, because the client code is readable.
