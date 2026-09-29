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
| Preferences | Versioned optional UI settings; safe defaults, validation and position conversion |
| MarketInsight | Pure explanation codes and validated parameters from existing Market facts; no analytics rerun |
| UIViewModel | Presentation: formatting, missing-data labels, watch/detail/report text |
| UI | Native side panel; consumes Market/Scanner, never recalculates statistics |
| Settings | Independent UIParent window for display, category, lock, trace and launcher preferences |
| Minimap | Native click/drag launcher; injected watch/settings callbacks |

```text
Core -> Scanner -> AuctionAPI
                -> Statistics
     -> BatchScanner -> Scanner
     -> Market -> Database -> HistoryMath
               -> HistoricalAnalytics -> Significance -> HistoryMath
                                      -> HistoryMath
               -> MarketSignal
     -> UI -> Scanner / BatchScanner / Market / Items
           -> MarketInsight (snapshot/analytics/signals + selected-item context)
           -> UIViewModel -> HistoryMath (numeric guard only)
     -> Preferences (optional root.preferences)
     -> Settings / Minimap -> Preferences
```

Core records a completed sample before updating the panel. Queue advancement
happens after the scanner event handler returns, not recursively from its state
notifications. Analytics are cached per item until a scan/error changes them.
Metadata, collapse and report rendering reuse the cache. No OnUpdate, automatic
login scans or scans with AH closed. Core optionally injects one bounded deadline
per accepted scan; this is failure handling, never polling/retry.

## Query lifecycle

`IDLE -> WAITING -> QUERYING -> COLLECTING -> DONE`; errors enter ERROR. Next batch
item starts only after completion or safe failure. Scanner checks readiness on
each request and the system-ready event. Result-read errors are recorded and the
batch proceeds. An item-key error before dispatch is safely isolated; once
SendSearchQuery is attempted, a failure is ambiguous and stops further requests
until AH close/reopen. There is no automatic retry.

When `C_Timer.After` exists, Scanner starts one 30-second token-guarded deadline
covering throttle wait and result wait. Any timeout stops the batch. Before
dispatch, the user may explicitly retry; after dispatch, close/reopen is required.
Old callbacks after completion/cancel/close are ignored. No timer starts another
query or timer, and readiness remains event-driven. The scheduling function is
injected, so deadline/cancellation behavior is deterministic in offline tests.
Timer capability is reported by Scanner:Summary; absent support retains manual
AH-close recovery. Actual beta scheduling remains a client check.

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
output is recorded in API_FINDINGS; production cross-character persistence awaits
beta validation. Changing
sharing semantics later requires an explicit migration.

An ADDON_LOADED binding is provisional even when its status is OK. Core recomputes
the key at PLAYER_LOGIN and PLAYER_ENTERING_WORLD, and checks both key and root
identity before reusing a binding. A changed key binds the existing root to that
partition, clears Market's cache/latest/errors/scanTimes, and refreshes an open
panel. Market:Get then reads `history[#history]` without a new scan. The old
partition stays intact; no automatic merge/rename or schema migration occurs.
The last processed sample marker is retained so an old completed scan cannot be
recorded again into a different partition.

Dedupe compares all core fields except `t` with the last stored observation:
unchanged and less than 600 seconds apart -> no new row. Exactly 600 seconds or
any changed core value -> store. Dedupe neither moves the retained timestamp nor
inflates historical count. Actual last-scan time is session-only; after reload
age refers to the last retained observation.

Retention runs on initial open for all partitions and append for the touched item: keep
at most 200 snapshots and remove timestamps older than 60 days, oldest first.
The exact 60-day boundary is retained. No background pruning. Full schema
validation precedes mutation. Unsupported/malformed roots are preserved without
automatic reset/migration; history is blocked with a diagnostic. Backward clocks
reject the append without rewriting history. Revalidation of an already held root
uses Database.Open's preserveHistory option: validate/bind without pruning either
partition. Reads return detached whitelist copies.

## Dashboard and report

Runtime demo mode was removed in 0.5.3. The deterministic month-long market
generator now lives only in `tests/fixtures/SyntheticMarket.lua`; it is not in the
TOC/source manifest. The same mathematical regression checks remain offline.

The minimap icon dispatches injected callbacks: left click toggles Watch; right
click toggles Settings. Drag/release computes a rim angle once, without polling.
`/mp settings` and the panel Settings button provide access when the icon is hidden.
Settings is an independent UIParent frame; AH lifecycle never hides or reparents it.
Both standalone windows move using a title-only drag region. A mode change or
hide stops dragging; the AH-side panel remains fixed to the existing anchor.

Preferences are an optional, separately versioned extension of the schema-1 root:
`preferences = { version=1, minimapShown=<boolean>, minimapAngle=<degrees>,
watchPosition={x,y}, settingsPosition={x,y}, watchScale=<0.8/0.9/1/1.1/1.2>,
defaultCategory=<All/Mining/Herbalism/Skinning>, lockWindows=<boolean>,
debugLogging=<boolean> }`. Scale defaults to 1, category to All, lock/trace to false.
Absent fields use defaults without
writing anything. Positions are offsets from UIParent center in its scale. Only
an explicit setting/drag/reset writes validated primitive preferences; opening
windows does not seed settings. Reads return position copies. Unknown preference
versions or unsupported roots are preserved, with session-only fallback settings.
This additive extension does not migrate/reset market schema, keys, snapshots or
the diagnostic canary, and adds no second SavedVariables name. Reset clears only
the two positions. Core rebinds the preferences owner alongside lifecycle history
binding so a replaced global is not written through a stale root.

UIViewModel translates missing/failed facts into plain display labels and short
actionable explanations; internal UNKNOWN/INSUFFICIENT and other enums remain
unchanged. Watch columns use No scan, No price, Failed and explained history dashes.
Known zero counts remain zero; unknown prices remain absent internally.

AH parent remains top-level `AuctionHouseFrame`, anchor `TOPLEFT -> TOPRIGHT`, `(8,0)`.
An explicit item-row click also requests native Browse Auctions navigation.
Scanner completes and records the commodity sample first, then waits for throttle
readiness before AuctionAPI invokes Blizzard SearchBar's `StartSearch` method,
the same path as its Search button. Blizzard supplies the current level/filter
parameters; MarketPilot adds no exact-match filter. The selected category is
cleared before switching to Browse and filling the client-owned item name.
This optional browse phase participates in `IsActive` and shares the scan's
one deadline; repeated clicks, batch starts, and manual refreshes cannot dispatch
alongside it. Browse completion requires the optional `AUCTION_HOUSE_BROWSE_RESULTS_UPDATED`
event plus throttle readiness and `HasFullBrowseResults() == true`. The event has
no request ID and can accompany commodity results, so it alone cannot unlock the
scanner. These checks run only on result/ready events. The optional native browse
failure event ends navigation immediately; missing failure-event support retains
the deadline. Browse rows are not read or saved by MarketPilot. A failed browse preserves
the commodity observation; an ambiguous dispatch blocks further scans until AH
is closed/reopened. Missing navigation capabilities do not disable ordinary scans.
Batch, Refresh, slash scans and read-only standalone selections never navigate AH.
Watch explicitly uses DIALOG strata and frame level 100, reapplied after reparenting
on open. Its children inherit the dialog layer. Settings uses DIALOG level 200 so
it stays above Watch regardless of open order. A guarded fixed-frame-level option
prevents parent propagation where available. No foreign HUD frame is changed and
there is no per-frame raise loop; ordinary game tooltips remain on their own layer.
MP-05 uses a 440 x 650 frame with native mouse-wheel scrolling; no Up/Down buttons.
Collapse leaves a 42-high header. No Blizzard child hooks or framework. Missing
anchor/render failures hide the panel and print diagnostics.

Category filters and six-row paging keep the expanded catalogue bounded onscreen.
Market Summary (Current) and Historical Context (History) precede the unchanged
raw tables. MarketInsight consumes the selected item's Market result and explicit
scanner/time context; UIViewModel formats its codes. Wrapped summary font height
determines the table anchor and scroll extent during existing UI refreshes, with
no polling. Stored observation age and unavailable metrics remain visible. See
[Market Summary rules and scenario matrix](MARKET_SUMMARY.md) for the contract,
independent availability checks, mixed situations and regression fixtures.
Current and History are separate detail tabs. Market Report replaces the list
and detail temporarily, with four items per section plus a remaining count.
Close clears the explicit-watch preference. Screen clamping is guarded by method
availability; the real client still needs font/scale/layout validation.
`/mp report` can open a hidden standalone report directly. Normal scan trace is
quiet; `/mp debug on/off` and Settings share the saved verbose-log preference, while errors and
batch completion remain visible.

Watch scaling preserves UIParent-coordinate offsets; Settings is not scaled by
that option. The default category applies at initial preference binding and when
its configured value changes, so lifecycle refreshes do not erase manual browsing.
Title-drag guards enforce the lock; explicit position reset remains available.
These options do not change scanner scope, statistical rules or retention.

The named native `MarketPilotMinimapButton` exposes its `icon` texture to button
collectors. The installed EllesmereUI source gathers named minimap Buttons at
least 20 units wide, then owns their parent/anchors/visibility in its flyout or row.
Launcher refresh respects foreign parents and changed anchor tuples, and only an
explicit false-to-true visibility change requests Show after initial creation.
An own-button OnShow/SetShown guard keeps an explicitly hidden icon noninteractive
even with a collector's force-Show hook. The installed EllesmereUI freezes wanted
visibility while its flyout is open. A small optional adapter writes only our
already tracked entry in its exported `_EBS_AddonVisible` table and requests its
exported `_EMM_ApplyMinimap` on an explicit visibility transition. Both exports
are type-checked; callback errors are reported. Ellesmere owns the rebuild, which
may close its flyout. There is no external-file edit, container hierarchy hook,
library or polling. Other collectors retain the generic path and may leave a
vacant cell until they rebuild. Native drag is disabled while placement is managed.

`/mp watch` toggles that same frame anywhere. Away from AH its mode is STANDALONE,
parent/anchor `UIParent`, `CENTER -> CENTER` plus the saved title-drag offset, with
a READ ONLY label. Item clicks
select stored detail; batch/refresh/cancel controls and their handlers are disabled.
Core also rejects scanning debug commands in this mode. Market/UIViewModel are
shared with AH mode; no duplicate analytics or database mutation on window actions.

AH open re-parents/re-anchors the frame in AH mode and restores normal scan actions.
AH close returns it to standalone only when `/mp watch` or the minimap explicitly requested it;
otherwise it hides as before. Toggling a visible window off clears this session-only
preference. Toggling a hidden window on uses AH mode if AH is already open.
Selection/report/collapse state survives mode changes. No automatic show after
login/reload. Core revalidates realm/faction at PLAYER_LOGIN and PLAYER_ENTERING_WORLD;
the watch command itself does not initialize the DB or run retention. Partition,
schema and retention are unchanged.

`/mp dbstatus` is a read-only debug command: DB status/active key/globalSameRoot, then configured
item ID, stored snapshot count, latest timestamp and latest cleanMedian in copper.
It reads Database:History directly rather than Market's session cache/overlays.
No identity binding, retention, scan or normal UI change is triggered by the command.

Core's diagnostic-only startup observations capture the raw global before any
Market construction/DB.Open and before/after the existing ADDON_LOADED, PLAYER_LOGIN
and PLAYER_ENTERING_WORLD binds. The first occurrence of each phase is kept as
detached text in session memory (seven phases maximum, no raw rows or saved log).
The existing key calculation is shared unchanged between binding and observation.

`/mp svdebug` prints those observations plus CURRENT: global type/schema, computed
and active keys, global/root equality, canary presence/value, and raw item/snapshot
entry counts for every global market key, including unconfigured items. It does
not call Database.Open/History/Prune/Append, Scanner, Market analytics or UI.
Raw inspection uses rawget/next and primitive formatting so malformed tables do
not invoke their callbacks; absent/malformed containers remain UNKNOWN.

Only `/mp svmark` writes the diagnostic `_svCanary=time()` primitive directly on
the existing global table. It never creates a root or alters schema/history; no
second SavedVariables variable is declared. This field is outside `markets` and
is not part of any history calculation. Binding/retention behavior is unchanged.

Watchlist: last observed clean median, 7d change, trend arrow, 30d percentile,
supply and maturity. Selecting during batch changes detail without another query.
Outside batch in AH mode, MP-03 item-click scan and Scan/Refresh remain. Detail includes
current robust descriptors, history, significance, age and count. Market Report
lists supported rising, cheap, unusual-return and meaningful-shift observations
with a maturity summary; failed items are excluded from those lists. Reports use
each item's latest retained scan, not a synchronized live market. The optional
sparkline is deferred with a placeholder; numeric history is implemented.

Catalogue covers 56 known Classic raw materials: 14 Mining ores/stones, 31 herbs
(including Wildvine/Bloodvine), 11 leather/scraps/hides. `Items.List(category)`
returns a detached filtered list; Batch calls unfiltered List() and scans all.
IDs are verified against the nexus-devs/wow-classic-items dataset, not guessed
from display names. Client metadata supplies names/icons. Forever-specific
availability and result paths beyond 2770/2771/2775/2447/2318 remain UNKNOWN.
Crafted products, specialty scales/zone skins, gems and custom items are outside
the configured catalogue. See [MARKET_MODEL.md](MARKET_MODEL.md)
for exact mathematics and statistical limitations.
