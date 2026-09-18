# Architecture

## Design target

MarketPilot should remain small enough to understand at a glance while still separating volatile WoW API behavior from stable market logic.

## Module boundaries

### Core.lua
Owns addon initialization, top-level events, slash-command registration, and module wiring. It must not contain scan algorithms or price mathematics.

### AuctionAPI.lua
The only production module allowed to call `C_AuctionHouse` or future Forever-specific AH APIs directly. Converts Blizzard-specific responses into MarketPilot-owned data structures.

Public surface should stay narrow, for example:

```lua
AuctionAPI:IsAvailable()
AuctionAPI:IsReady()
AuctionAPI:QueryItem(itemID)
AuctionAPI:ReadCurrentResults(itemID)
```

Exact signatures remain provisional until MP-00 finishes.

### Items.lua
Static catalogue of gathering-related item IDs and categories. Names/icons should be resolved through the client when practical rather than duplicated manually.

### Scanner.lua
Owns the scan queue and scan state machine. It requests one item at a time through `AuctionAPI` and advances only when the API/event state allows it.

Planned states:

```text
IDLE
WAITING
QUERYING
COLLECTING
PROCESSING
DONE
ERROR
```

No nested timer chains. No per-frame AH polling.

### Statistics.lua
Pure Lua. Input is normalized price-level data; output is robust descriptive statistics and anomaly classifications. No WoW APIs and no SavedVariables writes.

### Database.lua
Owns account-wide persistence, schema versioning, compact snapshots, retention, and migration. It does not decide sale prices.

### Pricing.lua
Pure Lua consuming current MP-02 analysis. MP-04 exposes Fast (lowest NORMAL row),
Normal (clean weighted median) and Patient (clean Q3), gated on anomaly sufficiency.
No history or pricing arithmetic/rounding. Each target has OK/UNKNOWN/INSUFFICIENT
status; unavailable targets have no copper value.

### Inventory.lua / SaleAssistant.lua
Inventory owns guarded read-only bag calls and aggregate configured-item counts.
Each refresh replaces slot addresses and increments a generation. Missing readers,
invalid rows or unavailable bag events make inventory UNKNOWN, not an empty bag.
ItemLocation is constructed only for the explicit read-only sell probe after a
fresh bag read and slot check, never retained or persisted.

SaleAssistant owns bag-item selection, bounded quantity, 12/24/48-hour duration,
scan reuse and candidate observations. It shares Scanner's single in-flight gate.
It consumes a DONE analysis only when sample itemID matches the sale selection;
browsing another item cannot accidentally price the sale item. No second cache,
queue, background query or posting action is introduced.

### UI.lua
Owns a separate AH side panel and item/refresh click handlers. It requests scans
through Scanner and consumes the stored sample/analysis; it never calls the AH
API or recalculates statistics. `UIViewModel.lua` maps scanner state to display
fields and formats integer copper, separately from native frame creation.

## Dependency direction

Implemented through MP-04 foundation:

```text
Core -> Scanner -> AuctionAPI
                -> Statistics
     -> SaleAssistant -> Inventory
                      -> Scanner (request / existing analysis)
                      -> Pricing
                      -> AuctionAPI (read-only candidate sell probe)
     -> UI -> Scanner (manual item/refresh requests)
           -> SaleUI -> SaleAssistant
           -> UIViewModel (presentation only)
```

`Items` contains a small Mining/Herbalism/Skinning ID catalogue and cached client
display metadata. Copper Ore remains the default and the confirmed commodity.
Statistics is a pure
`Analyze(sample)` function returning raw/clean descriptors and log-price anomaly
diagnostics. Scanner keeps the original normalized sample and a separate analysis
in memory, calls analysis once per completed scan, and clears both on reset.
The MP-02-v1 formulas/thresholds are specified in `MARKET_MODEL.md`.

Core updates the panel on scanner notifications and AH lifecycle events. Metadata
arrivals refresh cached labels/icons. There are no per-frame scripts or timers.
The panel uses its own frame parented to the top-level `AuctionHouseFrame`, anchored
`TOPLEFT -> TOPRIGHT` with offsets `(8, 0)`. No Blizzard child frames are accessed
or hooked. Missing anchors/rendering errors hide the panel and emit a diagnostic;
scanner debugging remains available. Collapse hides our body/scroll/footer. AH
close hides the panel, resets the scan and clears sale selection/observations.
The 320x650 panel now uses its own ScrollFrame with mouse-wheel and Up/Down
controls, keeping Sale Assistant below the market without extending over native AH.
Widgets are reused; no deep Blizzard child access or scroll polling is needed.

Inventory updates on AH open and BAG_UPDATE_DELAYED while AH is open, plus a
fresh read for explicit bag selection/candidate checks. Bag changes clear previous
deposit observations, clamp quantity to remaining ownership, and clear a vanished
selection. An unavailable bag event disables inventory without blocking browsing.
Quantity/duration edits clear observations too. The Check sell API button and
`/mp sellstatus` alone run the non-destructive candidates. Presence inspection is
separate and never invokes a candidate. API errors stay UNKNOWN; zero deposit and
false booleans are preserved. Post is permanently disabled with no click handler.

External source references (not evidence of Forever compatibility):
[Blizzard AH frame source mirror](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseFrame.xml)
and [client item API declarations](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua).
MP-03 layout/browsing was user-validated; new MP-04 bag/sell/scroll behavior still
requires client validation. Candidate API references/status are in API_FINDINGS.

The broader graph below remains a future plan; production still has no Database:

```text
Core
 ├─ Scanner ──> AuctionAPI
 │    └─> Statistics
 │          └─> Database
 └─ Pricing ──> Database
      └─> UI
```

The exact wiring can vary, but these rules must hold:

- no cyclic dependencies;
- no AH API calls from UI/Statistics/Database/Pricing;
- no pricing logic inside Database;
- no persistence logic inside Statistics.

## Data contracts

### Normalized current market sample

Candidate shape after MP-00 confirms live result semantics:

```lua
{
  itemID = 2770,
  capturedAt = 0,
  priceLevels = {
    { unitPrice = 4200, quantity = 80 },
    { unitPrice = 4300, quantity = 120 },
  },
}
```

All prices use integer copper internally.

### Compact snapshot

```lua
{
  timestamp = 0,
  median = 0,
  q1 = 0,
  q3 = 0,
  mad = 0,
  lowestValid = 0,
  validPriceLevels = 0,
  validQuantity = 0,
  suspiciousCount = 0,
  extremeCount = 0,
}
```

Raw scan rows should normally die after processing.

## Persistence

Production SavedVariables will be account-wide and partitioned at least by market identity (realm/region/faction only if the live Forever AH rules make those dimensions relevant). Do not hard-code a realm/faction partition until beta behavior is confirmed.

Suggested root:

```lua
MarketPilotDB = {
  schema = 1,
  markets = {},
}
```

## Performance principles

- Scan only configured gathering items.
- Event-driven queue advancement.
- No full-market replication in v1.
- No repeated sorting when cached sorted data can be reused inside one calculation.
- Persist summaries, not thousands of raw rows.
- UI refreshes on state/data changes, not every frame.

## Compatibility principle

Forever beta may change. Compatibility work must be localized to `AuctionAPI` and, before that exists, to the isolated probe. A Blizzard API rename should not require edits to Statistics, Database, Pricing, or UI.
