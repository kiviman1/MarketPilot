# MarketPilot — MP-04 Sale Assistant foundation (posting disabled)

Copy `src/MarketPilot/` into the beta client's `Interface/AddOns/` directory.
Enable MarketPilot and open AH after login (or close/reopen it after `/reload`).
Interface `16001` was confirmed on Forever beta 1.60.1 build 69893. If testing a
newer build, compare `/dump GetBuildInfo()` before changing the TOC.

Production files in TOC load order:

```text
MarketPilot.toc
Items.lua
AuctionAPI.lua
Statistics.lua
Scanner.lua
Pricing.lua
Inventory.lua
SaleAssistant.lua
UIViewModel.lua
SaleUI.lua
UI.lua
Core.lua
```

`Core` wires AH/scanner events to the panel; slash commands remain debug helpers.
`Items` contains Mining IDs 2770/2771/2775, Herbalism ID 2447 and Skinning ID 2318.
Copper Ore (2770), Peacebloom (2447) and Light Leather (2318) click scans are
beta-confirmed; the remaining IDs are representative candidates.
Display names/icons come from guarded client item-info calls, with
an `Item #ID (UNKNOWN)` label and question-mark icon until resolved. Metadata is
cached and refreshed on successful `GET_ITEM_INFO_RECEIVED`, without polling.
`Scanner` calls `AuctionAPI`, the sole production compatibility
boundary, and owns a single in-memory sample plus a separate pure Statistics result:

```text
{ itemID = 2770, capturedAt = <timestamp>, priceLevels = {
    { unitPrice = <integer copper>, quantity = <integer quantity> }, ...
} }
```

## Behavior and boundaries

Open AH to show the right-hand MarketPilot panel. Click an item to select it and
start one scan; click the selected item again or Scan/Refresh to repeat. Active
scans disable selection and refresh, with a second guard in Scanner. There is no
queue of clicked items. Switching items after completion clears the old values
until the new matching result arrives. A scan never changes the Blizzard AH tab,
default search field or item selected for sale.

The panel displays current lowest, raw/clean medians, clean Q1–Q3 range, raw total
quantity and level count, suspicious/extreme counts, anomaly sufficiency and
scanner state. All market values come from the existing analysis. EXTREME
exclusions are stated explicitly; SUSPICIOUS levels are retained. Known prices
remain visible for INSUFFICIENT samples, with the limitation labelled; missing or
invalid prices display UNKNOWN, never zero. Money presentation uses gold/silver/
copper; Statistics continues to use integer copper.

The header +/- control collapses/expands only the MarketPilot body. AH close
hides the panel; selection/collapse state is session-only. Scroll inside the panel
(mouse wheel or Up/Down) to reach Sale Assistant below the market section.

Sale Assistant lists only configured materials currently in bags with client
icon/name and aggregated counts. Click a bag item to scan it, or reuse the current
DONE result for that same item. Active scans prevent parallel selection/queries.
Sale selection is independent of subsequent market browsing; another item's result
never supplies its prices. Use the market Refresh button for a fresh selected-item
scan. No age-based cache or automatic refresh is added.

Enter a whole-number quantity (Enter or leaving the input commits it); Max selects
all owned units. Escape restores the prior quantity. Choose 12h/24h/48h. Bag events
refresh counts, clamp quantity when ownership falls, and clear missing selections.
Quantity/duration/bag changes invalidate candidate deposit observations. Bag API
errors display UNKNOWN and leave market browsing usable.

Fast/Normal/Patient all display INSUFFICIENT unless `anomaly.sufficient == true`.
With sufficient data, Fast is the lowest NORMAL row (never suspicious/extreme;
no undercut), Normal the clean weighted median, and Patient clean Q3. Exact copper
is retained, including 20c; these reference levels do not guarantee sale speed.
The raw current lowest is factual and may remain visible on insufficient samples.

**Check sell API (no post)** performs only the four read-only candidates and logs
presence, argument shape, primitive result or error. `/mp sellstatus` performs the
same check. Select a bag item first for validation/deposit, then rerun after changing
quantity/duration. Deposit is labelled **candidate**; absent/malformed/error results
stay UNKNOWN. The fifth candidate is presence-only. Post is always disabled and
has no handler. There is no price filling, secure proxy, bag mutation or real post.

`IDLE -> WAITING -> QUERYING -> COLLECTING -> DONE`; errors enter `ERROR`,
and AH close cancels/resets to `IDLE`. `/mp scan` also scans the selected item.
`WAITING` advances only when readiness is true, checking it on the initial command
and the confirmed system-ready event. Extra scan commands/ready events cannot send
a second in-flight query. Missing/non-boolean readiness is ERROR/UNKNOWN.

Only matching commodity events while QUERYING can complete a scan. All currently
returned rows are read, in API order, with separate owned tables even when prices
repeat. No five-row cap, regrouping, conversion or rounding. Positive, finite,
exact integers are required for unitPrice/quantity; missing, zero, negative,
fractional, string or out-of-range values reject the entire sample as ERROR/UNKNOWN.
No partial sample is presented as complete. Zero result rows are a valid empty
sample with total quantity 0 and UNKNOWN lowest/highest prices.

`/mp status` and completion output show state, itemID, session query count, level
count, summed quantity and lowest/highest copper prices. These are debugging
summaries only. Samples/analysis are cleared on new scans and AH close; reload clears
all production state. There is no persistence, full
item list, paging, automatic buying/posting, timers or per-frame polling.

There is no automatic timeout/retry: if no result or ready event arrives, status
remains QUERYING/WAITING; close/reopen AH to cancel. Result completeness/paging and
request identity remain UNKNOWN. Do not query the same item concurrently through
the probe, default AH UI or another addon during validation: a late/concurrent
same-item event cannot be distinguished without a verified request identifier.
`auctionID` is not read or used. The first matching update completes the scan;
subsequent updates are ignored until another manual scan.

## Anchor and compatibility limits

The panel is its own frame, parented only to the top-level `AuctionHouseFrame` and
anchored `TOPLEFT` to its `TOPRIGHT`, 8 UI units to the right. No deep frame hooks,
Blizzard repositioning or replacement. It is 320 UI units wide and approximately
650 high with internal scrolling, shrinking to a 42-high header when collapsed.
It is not clamped back over Blizzard controls; screen fit at the user's UI scale
must be checked in the beta client. Both small lists use reusable row widgets;
an eventual full catalogue/filtering remains out of scope.

If the top-level frame is unavailable or anchoring fails, the panel stays hidden
and logs `panel UNKNOWN`; debug commands remain usable. A later `ADDON_LOADED`
while AH is open retries a missing anchor. Native rendering errors are isolated
from completed scanner data. Namespaced `C_Item.GetItemInfo` or the legacy global
`GetItemInfo` resolves display metadata only; no alternative AH signatures are used.
MP-03 was user-validated in Forever; the MP-04 scroll/edit/bag/sell controls are
still pending in-client validation. `Inventory` currently uses namespaced
`C_Container` readers and the client's equipped bag count; there is no guessed
legacy signature fallback. Unsupported readers, events or shapes remain UNKNOWN.

## MP-02 analysis

On successful result collection, Scanner calls `Statistics.Analyze(sample)` once.
Raw rows remain intact. `scanner.analysis` retains raw and clean level count,
quantity, min/max and discrete quantity-weighted Q1/median/Q3, along with log-price
MAD/IQR metrics and annotated NORMAL/SUSPICIOUS/EXTREME rows. Output is deterministic
and has model version `MP-02-v1`; details and exact thresholds are in
`docs/MARKET_MODEL.md`.

The debug summary adds only `rawMedian`, `cleanMedian`, `suspicious`, `extreme` and
`anomalySufficient=yes/no`. Fewer than five distinct prices, or unusable MAD/IQR,
means INSUFFICIENT; raw/clean descriptors are still available and no EXTREME level
is removed. With sufficient data EXTREME requires both |modified Z| > 6 and a
3*IQR fence violation. SUSPICIOUS uses |Z| > 3.5 or a 1.5*IQR violation and stays
in all clean calculations. These are current-scan descriptions, not trade advice
or calibrated confidence. Statistics has no history or p-value; the separate pure
Pricing module now interprets these descriptors using MP-04-v1 rules.

## Offline tests

Run from repository root with Lua 5.1:

```text
lua tests/marketpilot_spec.lua
lua tests/statistics_spec.lua
lua tests/ui_spec.lua
lua tests/pricing_spec.lua
lua tests/sale_spec.lua
lua probe/tests/probe_spec.lua
```

The production suite includes TOC and static boundary/scope checks. Fixtures do
not establish new beta facts. Probe persistence, the MP-01 query flow and MP-02
four-level statistics were validated in-client; see `docs/API_FINDINGS.md`.
MP-04 adds no persistence. UI tests use mocked native frames, not a game renderer.
The pricing suite runs in a restricted pure-Lua environment; inventory/sale tests
exercise stale slots, counts, input bounds, API failures and the no-post boundary.

## In-game checklist (MP-04 pending; no posting)

1. Copy the entire updated addon directory, reload, then open AH. The panel should
   appear on the right, without covering AH controls or leaving the screen. Confirm
   category labels, collapse/expand, mouse-wheel and Up/Down scrolling.
2. Have configured materials in multiple bag slots. Check Sale Assistant icons,
   names and aggregate counts; unrelated items must not appear. Change bag contents
   manually and verify counts update, stale selection/deposit clears, and quantity
   cannot exceed the new total. Include an equipped reagent bag if applicable.
3. Click a bag item. Confirm one scan, WAITING if throttled, then DONE. Repeated
   clicks while active cannot send another query or change the sale selection.
   Selecting the same completed item reuses its current result; market Refresh
   sends one new query. Browsing another item must not price the selected sale item.
4. Compare lowest and target values. Four distinct levels must produce INSUFFICIENT
   Fast/Normal/Patient while preserving known raw lowest. With sufficient data,
   check Fast against the lowest NORMAL row, Normal against clean median and
   Patient against clean Q3. 20 copper must stay `0g 0s 20c`.
5. Edit quantity, try more than owned, use Max, and select each duration. Confirm
   quantity remains a positive integer within ownership and no scan is added.
6. Click Check sell API and run `/mp sellstatus`. Record presence/status, attempted
   signatures and exact returns/errors for each duration and more than one quantity.
   Deposit starts UNKNOWN and is only a candidate even after a successful call.
   Compare duration/deposit with native UI if available; do not submit a sale.
7. Verify Post stays disabled throughout, including API success, scan completion,
   repeated checks and closing/reopening AH. No auction must be created. Close AH
   during a scan; reopen and verify browsing still works without Lua errors.
8. Return debug output, build/interface and screenshots at your UI scale. Bag APIs,
   new controls and all sell semantics await this evidence. Hardware/copper posting
   acceptance remains UNKNOWN and is intentionally not tested by this commit.
