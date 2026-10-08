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

Auctionator (installed in the same client) uses the same modern commodity AH. Its full scan is the
model for `Market/AuctionScanner.lua`.

## Decisions

- Primary transport: a shared hidden custom channel carrying addon messages. Fallback: guild.
- History catch-up is peer to peer (request, randomised reply delay, suppression of duplicates).
- Message authenticity: signed readings (HMAC with a rotating time-window key and a per-release
  secret, bound to the verified sender name) plus consensus and sanity checks. This is abuse
  resistance, not cryptographic security, because the client code is readable.
