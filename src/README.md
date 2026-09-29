# MarketPilot — MP-05 Market Intelligence

Copy the entire `src/MarketPilot/` directory into the beta client's
`Interface/AddOns/`. Use this branch's files, not a sale-assistant addon directory.
Interface 16001 was observed on Forever beta 1.60.1 build 69893. For a newer build,
check `/dump GetBuildInfo()` rather than guessing a TOC change.

## Normal use

Open AH -> **Scan Gathering Markets** -> watch sequential progress -> select a
row for detail -> **Market Report**. No scan starts on login/open/reopen. There are
56 configured Classic raw materials: 14 Mining, 31 Herbalism and 11 Skinning.
Use All/Mining/Herbalism/Skinning and six-row paging to browse. The category filter
changes the display; **Scan Gathering Markets always scans all configured items**.
Current and History are separate detail tabs; Market Report is a separate view,
showing up to four supported items per section with an explicit remaining count.
Close hides the window; collapse preserves only its header. History/report views
remain available through `/mp watch` and `/mp report` outside AH.

IDs are checked against the [Classic item dataset](https://github.com/nexus-devs/wow-classic-items/blob/master/data/json/data.json).
Names/icons stay client-owned. The list includes ores/stones, standard herbs plus
Wildvine/Bloodvine, leather/scraps/hides. It excludes crafted bars/cured hides,
specialty scales/zone skins, gems and unverified custom Forever items.
Copper, Tin, Silver, Peacebloom and Light Leather have produced live commodity
results; inclusion of other IDs does not claim Forever availability/result support.
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
save its observation, but starts no next query. AH close cancels/resets and hides
the automatic AH panel; explicitly requested watch returns to standalone.
Reopen does not resume. A safely failed item is recorded and the batch continues.
An item-key failure before dispatch safely skips that item. An ambiguous dispatch
stops the batch until AH close/reopen. If the client exposes `C_Timer.After`, one
30-second deadline covers each accepted scan, including throttle wait. Timeout
stops the batch without retry or another deadline/query. If nothing was sent, use
Scan again explicitly; if a query was dispatched, close/reopen AH first. Old timer
callbacks cannot change completed/cancelled/new scans. `/mp status` shows deadline
support as `30s` or `UNAVAILABLE`; without it, manual AH close remains recovery.

Normal scan trace is quiet; errors and batch completion remain visible.
`/mp debug on` enables detailed trace, `/mp debug off` disables it. This saved
preference also appears as **Detailed scan log** in Settings; both stay synchronized.
Debug helpers: `/mp status`, `/mp dbstatus`, `/mp svdebug`, `/mp svmark`, `/mp scan`, `/mp batch`, `/mp cancel`, `/mp report`.
The UI has no sale, bag, purchase or posting workflow.

## Launcher and independent settings

Left-click the minimap icon to toggle Market Watch. Right-click it, click the
panel's **Settings** button, or use `/mp settings` for independent settings.
Without an icon container, drag the minimap icon and release to place it around
the rim. When a container owns the icon, it also owns its placement/drag behavior.
No MarketPilot update loop runs. Settings stays independent of Watch and AH:

- **Market Watch size:** 80%, 90%, 100%, 110% or 120%; changes apply immediately
  to Watch only, keeping Settings readable and standalone position intact.
- **Start category:** All, Mining, Herbalism or Skinning. Selecting a default
  also changes the current filter; ordinary category browsing stays session-only.
  This is a display filter, not a change to which materials a batch scans.
- **Lock window positions:** blocks title dragging for both standalone windows.
- **Detailed scan log:** saved verbose trace preference; errors remain visible.
- **Show minimap icon** and **Reset window positions** remain available.

Drag either unlocked standalone window by its title. AH-side Watch stays attached.
Reset affects positions only, preserving history and the other preferences.

The launcher now has the discoverable name `MarketPilotMinimapButton` and `icon`
texture field. The installed EllesmereUI collector previously skipped unnamed
buttons, explaining the user screenshot. MarketPilot respects reparented/changed
anchors and does not force Show on routine AH/login refreshes. Own click/visibility
guards preserve an explicit hide preference even if a collector attempts to show
it. For the installed EllesmereUI revision, an optional adapter uses its exported
button-visibility table and ApplyMinimap bridge only on an explicit checkbox
change, and only for the already tracked MarketPilot button. EllesmereUI rebuilds
its own layout (and may close its flyout). This handles its visibility tracking
being frozen while the flyout is open. No library or external file changes are
required. Other collectors use the generic behavior and may retain an empty cell
until their next layout rebuild. Changed/missing Ellesmere exports fall back safely.

The addon-list logo uses `## IconTexture` and the same bundled `Media/Icon.tga`.
Its actual display in Forever's addon selection screen remains a client check;
there are no Blizzard addon-list hooks or title markup fallbacks.

Runtime demo mode, button and commands are removed in 0.5.3. Month-long synthetic
data lives only in offline regression fixtures, including the 100000g outlier.
The addon always displays real current/stored observations.

Normal display labels now distinguish **No scan** (no observation), **No price**
(a scan returned no usable price), **Failed** (scan/storage error), and
**Needs history** (metric guards not met). Historical table dashes are explained
in the footer. Raw UNKNOWN/INSUFFICIENT codes remain internal/debug-only; prices
are never invented to fill a gap.

## Stored Market Watch anywhere

Use `/mp watch` or the minimap icon away from AH to toggle a standalone, read-only
window parented to `UIParent`, initially centered. It does not require
`AuctionHouseFrame`. Drag its title to move it; the next open/reload restores that
position, clamped to the screen. Watchlist, selected-item
detail, history, Market Report, scrolling and collapse use the same Market and
UIViewModel data as the AH panel. Item clicks only select stored detail. Scan
Gathering Markets, Scan/Refresh and Cancel are disabled; forced handlers and scan
debug commands are guarded too. UNKNOWN remains UNKNOWN for items without history.

The same frame docks beside AH when it opens and normal scan controls become
available. If explicitly opened with `/mp watch`, it returns to standalone on AH
close. Otherwise the existing AH-only lifecycle still hides it. `/mp watch` on a
visible window hides it and clears that standalone preference; on a hidden window
it opens in the current context (AH mode when AH is open). Hiding an AH panel does
not cancel a running batch; use Cancel for that. Visibility/selection/collapse are
session-only, so use the minimap icon or `/mp watch` again after reload or character
switch. Window positions and minimap preferences are saved account-wide.

Opening/closing, selecting and reporting in standalone neither initializes nor
writes/prunes history. Normal database initialization/retention runs at addon
load. PLAYER_LOGIN and PLAYER_ENTERING_WORLD revalidate realm/faction even if an
early binding succeeded; AH open retains its initialization fallback. A changed
key rebinds the same root without pruning or migrating stored history, clears
partition-specific session data, and displays the last persisted snapshot.
Same-realm/same-faction characters read the
same account-wide partition. Database schema, key and retention rules are unchanged.

For a missing `Now` value after reload, use `/mp dbstatus`: it prints DB status,
active market key, `globalSameRoot`, and each configured item's snapshot count, latest timestamp and
latest cleanMedian (integer copper, or UNKNOWN). It reads persisted data directly
and does not scan, bind, prune, or add information to the normal panel. Early-key
partitions remain preserved rather than being guessed to belong to another market.

## Persistence diagnostics (no new persistence fix)

The earlier real-client report reproduced lost visible snapshots after a full
client exit/relaunch, then scan/reload, with an unchanged active key. On 2026-09-28,
the explicit canary test produced a real saved file with five items, ten snapshots
and the canary intact. The user's post-reload dbstatus also retained all ten
snapshots with identical timestamps/prices. That run confirms production reload
persistence; it does not establish the cause of the earlier failure. No root
reset or migration was introduced.

`/mp svdebug` prints observations from Core file load (before any DB.Open), and
pre/post bind for ADDON_LOADED, PLAYER_LOGIN and PLAYER_ENTERING_WORLD. It retains
the first occurrence of each of those seven phases for this session as detached
text, then adds a fresh CURRENT observation on each command. It does not persist
the diagnostic log. Each phase/current report includes global type/schema, market
key count, computed key, active key, global/root equality, canary presence/value,
and every global market key's total item/snapshot counts, including unconfigured
items. Counts are raw container-entry counts; malformed/missing containers show
UNKNOWN. At Core file load equality is NO_DB because Market has not been created.

`globalSameRoot=false` means the actual saved global differs from the bound DB
root. `/mp dbstatus` reads bound history; `/mp svdebug` reads the raw global and
does not repair a mismatch. Neither diagnostic command binds, prunes, scans,
changes history or updates the normal dashboard.

`/mp svmark` explicitly writes only `MarketPilotDB._svCanary = time()` as an integer
primitive. It does not create a missing root or change schema, keys or snapshots.
No second SavedVariables name is added. The canary is excluded from market/history
math and changes only when this command is invoked again. It is a serialization
marker, not evidence that serialization succeeded until checked after reload.

Diagnostic sequence in the real client:

1. `/mp svmark`.
2. Run the normal batch at AH.
3. Capture `/mp dbstatus` and `/mp svdebug` output.
4. `/reload`.
5. Before opening/interacting with AH or scanning, capture `/mp svdebug` and
   `/mp dbstatus` again. Compare canary, phase counts and root equality.

All current binding, pruning and scanning behavior is unchanged by this diagnostic
follow-up. A nil global at Core load alone is not a diagnosis; compare later
pre-bind observations before deciding whether data was loaded or replaced.

## Implementation and persistence

UI preferences are an optional extension within the same `MarketPilotDB` root:
`preferences.version=1`, minimap visibility/angle, two window positions, Watch scale,
default category, window lock and detailed-log preference. New optional fields
read safe defaults on older version-1 data, with no migration/reset.
Defaults are read without writes; only an explicit change, drag or position reset
saves them. Unsupported preference versions remain untouched and use session-only
defaults/overrides. The history schema remains 1 with no migration or reset; reset
positions never clears history. [Preference contract](../docs/ARCHITECTURE.md#dashboard-and-report).

TOC order:

```text
Items.lua / AuctionAPI.lua / Statistics.lua
HistoryMath.lua / Database.lua / Significance.lua / HistoricalAnalytics.lua
MarketSignal.lua / Scanner.lua / BatchScanner.lua / Market.lua / Preferences.lua
UIViewModel.lua / UI.lua / Settings.lua / Minimap.lua / Core.lua
```

AuctionAPI remains the only production AH API boundary; Statistics is unchanged.
Core feeds successful scanner analysis to Market, which stores whitelist snapshots
and caches pure analytics. UI formats those existing results. No dependencies,
per-frame polling, background scans or timer chains. The optional scan deadline is
one bounded failure notification; it never dispatches or retries a query.

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
8 UI units right, 440 x 650 before user scaling. Mouse wheel scrolls; +/- collapses to 42
high. Standalone uses the same frame, parent `UIParent`, anchor CENTER to CENTER.
No deep Blizzard hooks/replacement. Six rows are visible per page, filtered by
category. Numeric history is implemented; the optional sparkline is deferred.
Native screen fit/font wrapping
at different UI scales need MP-05 client review. Anchor/render errors print a
panel UNKNOWN diagnostic and leave scanner debugging available.

Report lists rising markets, low 30d historical position, unusual return volatility,
meaningful shifts and maturity. Each item is analyzed as of its latest stored
observation; age is explicit. It is not a synchronized live feed. Dedupe does not
inflate history; after reload scan age refers to the last retained observation.
No idle age-refresh timer. Approximate p-values, serial dependence, sparse windows
and irregular observation intervals limit inference; see the model document.

The optional single 30-second deadline stops a stalled batch; no retry is automatic.
Without client timer support, close/reopen AH for a missing result/ready event.
Result completeness/paging and
request identity remain UNKNOWN. During validation avoid competing queries from
the probe, other addons or default AH for the same item: a matching late event
cannot be distinguished from the requested result. No auction identifier is used.

## Offline tests

Run all suites from the repository root with Lua 5.1:

```text
python tools/test.py
python tools/package.py --check
```

On the development host these also run under Python's installed `lupa.lua51`
(runtime reports Lua 5.1), with a fresh runtime per suite. No runtime library is
bundled with the addon. History tests use only a pure Lua environment; UI/batch
fixtures mock native frames and events. They do not prove rendered beta behavior.

## In-game acceptance for 0.5.7

The release archive is built explicitly with `python tools/package.py`.
CI validates the source manifest without producing a ZIP. The archive contains
only the `MarketPilot/` runtime folder; SavedVariables remain in the client.
This checklist records in-client checks separately from offline test coverage.

For 0.5.7, finish a gathering batch, then click Gold Ore in Market Watch. Its
commodity analysis should refresh, followed by a native Browse Auctions search
with Gold Ore in the search box and matching results on the left, without another
manual Search click. Compare with pressing Search: both paths must use the same
native search/filter semantics (including other name matches such as Gold Power
Core). Repeat for Firebloom, Copper Ore and Light Leather, including from an
unrelated AH category or tab. The category is cleared; current native filter and
level settings are respected rather than replaced with a forced exact match.
An item with no listings should show Blizzard's empty result rather than an old row.
Click repeatedly while scanning/opening search: only one commodity request and
one subsequent browse request should occur. Refresh and batch must not navigate
the native list. Close AH during the wait, then reopen: no stale search should run.
Outside AH, selecting stored items must remain read-only. If native navigation is
unavailable, retain scan data and report `/mp status` output; do not infer success.

1. Check the logo in the character-screen addon list. The minimap icon should
   enter the EllesmereUI container; open/close the container, AH and Settings
   without the icon jumping out or forcing the container open.
   Left-click opens/closes stored Watch, right-click opens independent Settings.
2. Drag Watch by its title away from AH. Close/reopen and `/reload`: restore its
   position and real prices. Item buttons/report must not scan outside AH.
3. Move Settings separately; close Watch and open/close AH: Settings stays in
   place. Hide the minimap icon, reload, then use `/mp settings` to restore it.
   Without the collector, icon drag/release/reload retains its rim angle.
4. Open AH with Watch already visible: it docks on the right and cannot be dragged
   off AH. Scan controls work. Close AH: return to the saved standalone position.
   Test AH open or Watch close while a title drag is in progress.
5. Reset window positions in Settings: both standalone windows center; an active
   AH panel stays docked. History, filters and minimap visibility stay intact.
6. No Demo button/banner remains. `/mp demo on` only prints command help; no
   synthetic data appears and existing snapshot counts stay unchanged.
7. Exercise all five Watch sizes while standalone/docked; Settings retains its
   own size. Set a start category, lock/unlock titles and enable/disable logs;
   reload retains these preferences without altering stored prices/counts.
8. Up/Down buttons are gone. Mouse wheel reaches all Current/History details
   and the bottom of Market Report at each size.
9. Place standalone Watch over the action bars and player frame: its contents and
   buttons should remain in front. Open Settings, then reopen Watch: Settings
   should remain on top. Repeat after AH docking/closing and scale changes.
10. The addon-selection description contains the general gathering-analysis
    description without milestone/beta branding. Fully restart the client if its
    cached metadata still shows an earlier version/description.

The original five-item batch and post-reload database retention were confirmed.
The expanded 56-item batch and the new launcher/settings/drag behavior need a
fresh client check; offline frame mocks do not establish client compatibility.

Reload binding acceptance: scan on bank alt and record `Now` plus `/mp dbstatus`.
Run `/reload` -> `/mp watch` without scanning: the same Now values, active key,
counts and latest stored timestamps/medians should return. Then normal logout ->
same-realm/same-faction main, away from AH -> `/mp watch` and `/mp dbstatus`: the
same values must appear without a fresh query. Production cross-character
retention is still pending; return debug output if the key/count differs.

1. On the bank alt, scan at AH and note values/counts. Close AH, then use
   `/mp watch`: centered read-only panel, stored detail/report, scan/refresh/cancel
   disabled. Select other items, scroll and collapse without new scan debug output.
2. Toggle `/mp watch` closed and open again: same stored values/counts. Open AH
   while watch is visible: dock right, scan normally. Close AH: return to standalone.
   Hide with `/mp watch`, then repeat AH open/close: default AH-only hide behavior.
3. `/reload` away from AH, then `/mp watch`: stored values visible without scanning.
   Normal logout -> different same-realm/same-faction main, away from AH ->
   `/mp watch`: same partition/observations/report. Selection and visibility reset
   between sessions; stored observations do not.
4. Check centered window fit, read-only label, missing-history UNKNOWN values and
   absence of Lua errors. Compare snapshot contents/counts before and after browsing;
   standalone actions must not add, remove or change snapshots.

## Broader MP-05 checklist

1. Install/reload, open AH: readable right-side panel, category filters and six-row
   pages, names/icons, Current/History tabs, collapse/expand, scrolling, no Lua errors,
   no automatic query. Verify
   screen fit at your UI scale. History status should report account-wide storage.
2. Click Scan Gathering Markets once. Observe 0/56 -> 56/56, each item sent once,
   correct WAITING/QUERYING/DONE progress. Repeated batch/refresh clicks must not
   create another query. Selecting another row during batch should only change
   detail. Record unavailable/non-commodity beta items without inventing results.
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
