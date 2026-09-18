# MarketPilot — MP-03 Auction House side panel

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
UIViewModel.lua
UI.lua
Core.lua
```

`Core` wires AH/scanner events to the panel; slash commands remain debug helpers.
`Items` contains Mining IDs 2770/2771/2775, Herbalism ID 2447 and Skinning ID 2318.
Only Copper Ore (2770) is beta-confirmed; the other IDs are representative query
candidates. Display names/icons come from guarded client item-info calls, with
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
hides the panel; selection/collapse state is session-only. The Sale Assistant
section is just `Coming in MP-04`: no bag selection, price fill or sell actions.

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
all production state. There is no persistence, pricing, full
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
659 high for this five-item catalogue, shrinking to a 42-high header when collapsed.
It is not clamped back over Blizzard controls; screen fit at the user's UI scale
must be checked in the beta client. This small list uses reusable row widgets;
an eventual full catalogue would need a separate scrolling/filtering task.

If the top-level frame is unavailable or anchoring fails, the panel stays hidden
and logs `panel UNKNOWN`; debug commands remain usable. A later `ADDON_LOADED`
while AH is open retries a missing anchor. Native rendering errors are isolated
from completed scanner data. Namespaced `C_Item.GetItemInfo` or the legacy global
`GetItemInfo` resolves display metadata only; no alternative AH signatures are used.
Forever frame/metadata compatibility is still unverified for MP-03.

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
or calibrated confidence. There is no history, p-value or pricing recommendation.

## Offline tests

Run from repository root with Lua 5.1:

```text
lua tests/marketpilot_spec.lua
lua tests/statistics_spec.lua
lua tests/ui_spec.lua
lua probe/tests/probe_spec.lua
```

The production suite includes TOC and static boundary/scope checks. Fixtures do
not establish new beta facts. Probe persistence, the MP-01 query flow and MP-02
four-level statistics were validated in-client; see `docs/API_FINDINGS.md`.
MP-03 adds no persistence. UI tests use mocked native frames, not a game renderer.

## In-game checklist (MP-03 not yet performed)

1. Copy the entire updated addon directory, reload, then open AH. The panel should
   appear on the right, without covering AH controls or leaving the screen. Confirm
   category labels, resolved item names/icons and the MP-04 placeholder.
2. Click Copper Ore once. Confirm one query, WAITING if throttled, then DONE.
   Repeat clicks while active must not add queries or change selection.
3. Compare panel lowest, medians, quantity, levels and anomaly counts with
   `/mp status` and visible AH data. For the reported four-level cases expect
   INSUFFICIENT, zero extreme levels and equal raw/clean medians. 199 copper must
   render as `0g 1s 99c`; 200 as `0g 2s 0c`. Check the clean Q1–Q3 range too.
4. Click Refresh; one new scan should replace values. Toggle collapse/expand
   during idle and an active scan. No query should be sent by toggling the panel.
5. Select a representative item in each other category. Record whether the item
   exists, names/icons resolve and the commodity result path works. These are
   unverified items; missing APIs/data must remain UNKNOWN/ERROR, not zero prices.
6. Close AH while waiting/querying: the panel must disappear and the scan reset.
   Reopen and click Copper Ore again; no Lua errors, extra panels or parallel queries.
7. Confirm Sale Assistant has no actionable selling controls. Return output and
   a screenshot at your resolution/UI scale. MP-03's visual acceptance requires
   this actual client test; offline fixtures alone do not establish it.
