# Architecture

## MP-05 direction

MarketPilot is a lightweight gathering-market intelligence terminal. This branch
starts at validated MP-03, not the sale-assistant branches. The workflow is scan
-> robust statistics -> compact history -> descriptive analytics -> dashboard.
There is no Inventory, Pricing, Sale Assistant or posting module. Probe is unchanged.

## Module boundaries

| Module | Responsibility |
|---|---|
| Core | Initialization, guarded runtime identity, root binding, events, debug commands and wiring |
| AuctionAPI | Sole AH API boundary: IsAvailable, IsReady, QueryCommodity, ReadCommodityResults |
| Items | Category IDs, flat ordered List(), cached client names/icons |
| Scanner | One request; WAITING/QUERYING/COLLECTING/DONE/ERROR state machine |
| BatchScanner | Configured-item queue, serial progress, cancel, per-item outcomes |
| Statistics | Unchanged pure MP-02-v1 current-scan raw/clean descriptors and anomaly rows |
| Database | Schema validation, whitelist snapshots, dedupe and retention; injected root/key/time |
| HistoryMath | Pure median, MAD and numeric guards |
| HistoricalAnalytics | Pure rolling references, Theil-Sen trends, robust returns and supply |
| Significance | Pure two-sided, tie-corrected Mann-Whitney normal approximation |
| MarketSignal | Pure descriptive price/trend/supply/volatility labels |
| Market | Completed-scan persistence, latest observations, cached analytics and report aggregation |
| UIViewModel | Presentation: formatting, missing-data labels, watch/detail/report text |
| UI | Native side panel; consumes Market/Scanner, never recalculates statistics |

```text
Core -> Scanner -> AuctionAPI
                -> Statistics
     -> BatchScanner -> Scanner
     -> Market -> Database -> HistoryMath
               -> HistoricalAnalytics -> Significance -> HistoryMath
                                      -> HistoryMath
               -> MarketSignal
     -> UI -> Scanner / BatchScanner / Market / Items
           -> UIViewModel -> HistoryMath (numeric guard only)
```

Core records a completed sample before updating the panel. Queue advancement
happens after the scanner event handler returns, not recursively from its state
notifications. Analytics are cached per item until a scan/error changes them.
Metadata, collapse and report rendering reuse the cache. No timers, OnUpdate,
automatic login scans or scans with AH closed.

## Query lifecycle

`IDLE -> WAITING -> QUERYING -> COLLECTING -> DONE`; errors enter ERROR. Next batch
item starts only after completion or safe failure. Scanner checks readiness on
each request and the system-ready event. Result-read errors are recorded and the
batch proceeds; a failed dispatch is ambiguous and stops further requests until
AH close/reopen. No automatic retry or timeout.

Cancel discards the unsent queue. WAITING cancels immediately. A dispatched query
drains its single reply and may save that requested observation; new requests
remain blocked until it finishes. AH close cancels batch and resets Scanner; late
events while closed are ignored. Reopen never starts a scan. Concurrent queries
from other addons/default AH UI cannot be correlated without a verified request ID.

Batch outcomes are session-only `{ state, error }` per item. Errors never become
zero-price history. A valid empty scan persists zero counts and absent prices,
with `anomalySufficient=false`.

## Persistence contract

Account-wide TOC variable:

```lua
MarketPilotDB = {
  schema = 1,
  markets = {
    [marketKey] = { items = {
      [itemID] = { snapshots = {
        { t = 0, rawMedian = 200, cleanMedian = 199, q1 = 190, q3 = 200,
          lowest = 170, totalQuantity = 775, levelCount = 4,
          suspicious = 0, extreme = 0, anomalySufficient = false },
      } },
    } },
  },
}
```

`t` uses the existing scanner's `time()` Unix timestamp, not a newly assumed AH
timestamp. Prices are positive exact integer copper, counts nonnegative exact
integers. Unknown prices are absent (`nil`), never zero. Writer copies only these
eleven primitive fields. Raw levels, anomaly rows, API tables and historical
metrics are never persisted. Scanner's raw sample is session memory and is cleared
on the next request/AH close.

Conservative identity:
`forever-beta:v1:<realm-length>:<realm>:<faction-length>:<faction>`.
Core accepts successful nonempty strings from guarded `GetRealmName()` and
`UnitFactionGroup("player")`. Length prefixes avoid ambiguous keys. Same-realm,
same-faction characters share history; other partitions are isolated. This does
**not** assert Forever's actual faction/realm market-sharing semantics. Character
name and guessed region are not included. Missing identity disables persistence,
preserves saved data and reports UNKNOWN; scanning still works. Actual identity
output and production cross-character persistence await beta validation. Changing
sharing semantics later requires an explicit migration.

Dedupe compares all core fields except `t` with the last stored observation:
unchanged and less than 600 seconds apart -> no new row. Exactly 600 seconds or
any changed core value -> store. Dedupe neither moves the retained timestamp nor
inflates historical count. Actual last-scan time is session-only; after reload
age refers to the last retained observation.

Retention runs on open for all partitions and append for the touched item: keep
at most 200 snapshots and remove timestamps older than 60 days, oldest first.
The exact 60-day boundary is retained. No background pruning. Full schema
validation precedes mutation. Unsupported/malformed roots are preserved without
automatic reset/migration; history is blocked with a diagnostic. Backward clocks
reject the append without rewriting history. Reads return detached whitelist copies.

## Dashboard and report

Parent remains top-level `AuctionHouseFrame`, anchor `TOPLEFT -> TOPRIGHT`, `(8,0)`.
MP-05 uses a 440 x 650 frame with native scrolling, mouse wheel and Up/Down buttons;
collapse leaves a 42-high header. No Blizzard child hooks or framework. Missing
anchor/render failures hide the panel and print diagnostics.

Watchlist: last observed clean median, 7d change, trend arrow, 30d percentile,
supply and maturity. Selecting during batch changes detail without another query.
Outside batch, MP-03 item-click scan and Scan/Refresh remain. Detail includes
current robust descriptors, history, significance, age and count. Market Report
lists supported rising, cheap, unusual-return and meaningful-shift observations
with a maturity summary; failed items are excluded from those lists. Reports use
each item's latest retained scan, not a synchronized live market. The optional
sparkline is deferred with a placeholder; numeric history is implemented.

Catalogue remains 2770/2771/2775 (Mining), 2447 (Herbalism), 2318 (Skinning).
Query paths are live-confirmed for 2770/2447/2318. Additional beta level-range
materials remain unconfigured until verified. See [MARKET_MODEL.md](MARKET_MODEL.md)
for exact mathematics and statistical limitations.
