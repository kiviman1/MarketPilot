# MarketPilot — MP-05 Market Intelligence

Copy the entire `src/MarketPilot/` directory into the beta client's
`Interface/AddOns/`. Use this branch's files, not a sale-assistant addon directory.
Interface 16001 was observed on Forever beta 1.60.1 build 69893. For a newer build,
check `/dump GetBuildInfo()` rather than guessing a TOC change.

## Normal use

Open AH -> **Scan Gathering Markets** -> watch sequential progress -> select a
row for detail -> **Market Report**. No scan starts on login/open/reopen. The five
configured IDs are Mining 2770/2771/2775, Herbalism 2447 and Skinning 2318. Copper
Ore, Peacebloom and Light Leather query paths were reported live-tested in MP-03;
2771/2775 remain candidates. Additional beta level-range items are not guessed.
Names/icons resolve from the client and retain an ID/UNKNOWN fallback.

The watchlist has current clean median, 7d change, trend arrow, 30d percentile,
supply and maturity. Detail adds raw/clean current statistics, 24h/7d/30d references,
change, robust trend/volatility, supply, p-value/meaningful shift, scan age and
observation count. UNKNOWN/INSUFFICIENT never becomes a zero price. Prices preserve
copper. A conventional historical median may be half-copper and is labelled as a
statistic; no actual listing price is rounded. Current 7d/30d references require
history age plus observation guards; NEW/EARLY is expected on initial installation.

During a batch, clicking a row selects detail without another request. Outside a
batch, MP-03 click-to-scan and Scan/Refresh remain. Repeated clicks cannot create
parallel queries. Cancel drops unsent items; a dispatched reply may finish and
save its observation, but starts no next query. AH close cancels/reset/hides;
reopen does not resume. A safely failed item is recorded and the batch continues.
An ambiguous dispatch stops the batch until AH close/reopen.

Debug helpers: `/mp status`, `/mp scan`, `/mp batch`, `/mp cancel`, `/mp report`.
The UI has no sale, bag, purchase or posting workflow.

## Implementation and persistence

TOC order:

```text
Items.lua / AuctionAPI.lua / Statistics.lua
HistoryMath.lua / Database.lua / Significance.lua / HistoricalAnalytics.lua
MarketSignal.lua / Scanner.lua / BatchScanner.lua / Market.lua
UIViewModel.lua / UI.lua / Core.lua
```

AuctionAPI remains the only production AH API boundary; Statistics is unchanged.
Core feeds successful scanner analysis to Market, which stores whitelist snapshots
and caches pure analytics. UI formats those existing results. No dependencies,
per-frame polling, background scans or timer chains.

Account-wide `MarketPilotDB`, schema 1, partitions by conservative beta namespace
plus runtime realm/faction strings. Same-key characters share history; missing
identity blocks writes without breaking current scans. This partition does not
claim cross-faction/realm sharing is known. Snapshot fields:

```text
t, rawMedian, cleanMedian, q1, q3, lowest, totalQuantity,
levelCount, suspicious, extreme, anomalySufficient
```

No raw AH rows. Unchanged core facts within less than 600 seconds are deduped;
changed facts or exactly 600 seconds are retained. Per item: max 200 observations
AND max 60 days, oldest first; prune on open/append. Unsupported/corrupt schemas
are preserved and disabled with UNKNOWN, never silently reset. Back up an existing
SavedVariables file before any manual repair; no migration is performed by MP-05.
More detail: [architecture](../docs/ARCHITECTURE.md),
[exact formulas and thresholds](../docs/MARKET_MODEL.md),
[beta evidence](../docs/API_FINDINGS.md).

## Dashboard layout and limits

Own native frame, parent `AuctionHouseFrame`, anchored TOPLEFT to its TOPRIGHT,
8 UI units right, 440 x 650. Mouse wheel and Up/Down scroll; +/- collapses to 42
high. No deep Blizzard hooks/replacement. Five reusable rows grouped by category;
7d sparkline has a small deferred placeholder. Native screen fit/font wrapping
at different UI scales need MP-05 client review. Anchor/render errors print a
panel UNKNOWN diagnostic and leave scanner debugging available.

Report lists rising markets, low 30d historical position, unusual return volatility,
meaningful shifts and maturity. Each item is analyzed as of its latest stored
observation; age is explicit. It is not a synchronized live feed. Dedupe does not
inflate history; after reload scan age refers to the last retained observation.
No idle age-refresh timer. Approximate p-values, serial dependence, sparse windows
and irregular observation intervals limit inference; see the model document.

No automatic timeout/retry exists. Missing result/ready events leave QUERYING or
WAITING: cancel or close/reopen AH as appropriate. Result completeness/paging and
request identity remain UNKNOWN. During validation avoid competing queries from
the probe, other addons or default AH for the same item: a matching late event
cannot be distinguished from the requested result. No auction identifier is used.

## Offline tests

Run all suites from the repository root with Lua 5.1:

```text
lua tests/marketpilot_spec.lua
lua tests/statistics_spec.lua
lua tests/history_spec.lua
lua tests/ui_spec.lua
lua probe/tests/probe_spec.lua
```

On the development host these also run under Python's installed `lupa.lua51`
(runtime reports Lua 5.1), with a fresh runtime per suite. No runtime library is
bundled with the addon. History tests use only a pure Lua environment; UI/batch
fixtures mock native frames and events. They do not prove rendered beta behavior.

## In-game MP-05 checklist — not yet performed

1. Install/reload, open AH: readable right-side panel, five category rows, names/
   icons, collapse/expand, scrolling, no Lua errors, no automatic query. Verify
   screen fit at your UI scale. History status should report account-wide storage.
2. Click Scan Gathering Markets once. Observe 0/5 -> 5/5, each item sent once,
   correct WAITING/QUERYING/DONE progress. Repeated batch/refresh clicks must not
   create another query. Selecting another row during batch should only change
   detail. Record behavior for candidate Tin Ore/Silver Ore.
3. Compare Copper Ore, Peacebloom and Light Leather current quantities/prices/
   anomaly exclusions with the live AH. Empty results show known zero quantity
   but UNKNOWN price. A per-item API error must not save a fake observation.
4. Cancel while waiting and while querying. No next item should start; a dispatched
   item may finish. Close AH mid-batch: hide/cancel, no background work. Reopen:
   stored values visible with age; no automatic restart.
5. Complete a scan and inspect `/dump MarketPilotDB` as needed. Root schema=1,
   one conservative market partition, compact eleven-field facts only. Refresh
   unchanged data within ten minutes: count unchanged. Changed core values should
   add an observation; unchanged after ten minutes should also add one.
6. `/reload`, then reopen AH. Stored observations/count survive with zero new
   queries. Normal logout and switch to a same-realm/same-faction character: same
   history. Different realm/faction should use an isolated partition. Report actual
   identity/persistence observations without inferring AH sharing semantics.
7. Initially expect NEW/EARLY, absent 7d/30d metrics and no unsupported report
   entries. With >=5 samples across >=24h, available-points trend may appear.
   After 7/30 days and adequate samples, compare mature windows to retained
   timestamps. Recent>=3 and prior>=7 are needed for a p-value; meaningful shift
   additionally requires >=10% median change. Do not generate artificial history
   in the real account DB just to accelerate maturity.
8. Open Market Report: only supported configured facts, clear maturity counts,
   no sale controls. Return any errors, query/progress output, and panel layout
   observations. Long-window mathematics is verified offline; real longitudinal
   beta history must accumulate over time.
