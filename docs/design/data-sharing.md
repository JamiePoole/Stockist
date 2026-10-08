# Design: sharing scan results between players

Status: draft with a recommendation; nothing here is verified in game yet (see "Unknowns"). Tracks [#10](https://github.com/JamiePoole/Stockist/issues/10) and [#11](https://github.com/JamiePoole/Stockist/issues/11); transport findings are in [transport-findings.md](../transport-findings.md).

## Goal

Not "send data around" but: **everyone's records end up as up to date and complete as the whole community can make them.** A player who just logged in should have the last 24 hours, week and month of charts filled in, from whoever scanned while they were away.

## What is shared

Only the results of scans over time, per item. Everything else is computed locally.

| Data | Shared? |
|---|---|
| Scan results: price, lowest price, quantity, per item per time | Yes |
| Hourly and daily candles | Yes, as a compact form of the above for older history |
| Indexes, movers, craft margins, indicators | No, derived from scan results |
| Depth (price levels) | No, local scan only |
| Your auctions, gold, inventory, watchlist, alerts, layout | Never |

## Canonical units

Peers can only fill each other's gaps if they agree on what a "piece" is. So data is cut into pieces whose identity everyone can compute:

- **Time slots** of 15 minutes for the last day, hourly for the last week, daily for the last month (the same three scopes as the chart). Slot boundaries are UTC.
- A piece is `(item, resolution, slot)`; a **chunk** is a run of pieces for one item over one window, sized to fit a few messages.
- Prices are delta-coded and an unchanged price costs almost nothing, which matters because most items do not move between scans.

Rough sizes (before compression): one scan result about 14 bytes; one candle about 17 bytes. One message holds at most 255 bytes, so 15-18 results per message.

## Distribution: swarm, not a single provider

A custom channel is a **broadcast medium**: one message reaches every listener. That makes a torrent-like swarm natural, and cheaper than one player serving another.

1. **Live publishing.** After a scan, a client broadcasts its results for the current slot, unless it has already heard another player publish that slot (it waits a short random time and listens). The channel's load stays roughly constant however many players there are, and every listener's recent history fills in for free.
2. **Backfill by request.** A client that is missing data broadcasts a small "I need item X, this window, from slot S". Anyone who has it replies after a random delay, longer if they hold less; a reply someone else already sent cancels yours. One reply therefore fills the gap for **every** player who asked, not just one. This is the approach of scalable reliable multicast (SRM) and anti-entropy gossip.
3. **Order of requests.** The watchlist first, then items with the most recent activity, then the rest. Candles for long ranges before fine slots.
4. **Fairness.** Each client spends only part of the send throttle on answering, and ignores peers who send junk.

Compared with one player updating another:

| | Single provider | Swarm (recommended) |
|---|---|---|
| Messages for N players wanting the same data | N transfers | about 1 |
| Provider goes offline mid-transfer | transfer fails | someone else answers |
| Load on one player | all of it | spread out |
| Complexity | sessions and retries | timers and suppression, no sessions |

Whispers (1-to-1) are the fallback for a targeted repair. The wiki states whispers outside instances are exempt from the addon throttle, which is worth testing.

## Trust

A swarm has no trusted source, so integrity cannot come from a published hash.

- Every message carries a tag bound to the sender (signing design in the earlier discussion: HMAC with a rotating time-window key, secret injected at release). It stops casual abuse, not a determined forger, because client code is readable.
- Accept a piece only if it passes sanity bounds against the local median, and prefer pieces that two independent players agree on. A slot holds up to three reports and the displayed value is their median.
- A peer whose data keeps disagreeing with the rest loses weight and is ignored.

## Throughput

Sustained send rate is about one message per second per prefix after a burst of 10, so roughly 15 KB a minute per player.

- A full scan of about 300 items is around 17 messages.
- A week of hourly candles for a 20-item watchlist is around 3,400 candles, about 225 messages: 4 minutes for one sender, much less when several answer.

Hence: live results are cheap; history backfill is watchlist-first and prefers daily candles for long ranges.

## Unknowns to verify before building (#17)

- Does another player receive channel messages at all, and across connected realms or factions?
- Behaviour under bursts of full-length (255-byte) messages, and with several senders at once.
- Whether very large channels have flood limits beyond the addon throttle.
- Whether whispers are exempt from the throttle on Forever.
- The cold start: with few players there is little to share. A bundled snapshot of recent daily candles in each release could seed new installs.
