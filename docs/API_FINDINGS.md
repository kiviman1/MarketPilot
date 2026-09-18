# API Findings

Observed WoW Forever beta behavior only. Do not fill this file from memory or from another WoW branch without clearly labelling it as external reference.

Evidence source: the user's real Forever beta client validation report, received
2026-09-18. CONFIRMED below is limited to those reported observations; no new
in-client testing was performed while recording this update. The exact client
version/build/interface and test timestamp were not supplied.

## Client

```text
Version: 1.60.1
Build: 69893
Interface: 16001
Build date: Sep 16 2026
Observed on: 2026-09-18
```

## Auction House open/close

```text
AUCTION_HOUSE_SHOW: CONFIRMED — fires when AH opens
AUCTION_HOUSE_CLOSED: CONFIRMED — fires when AH closes
```

## Candidate API surface

| Capability | Candidate | Observed status | Notes |
|---|---|---|---|
| Make item key | `C_AuctionHouse.MakeItemKey` | CONFIRMED | `MakeItemKey(2770)` works. |
| Send search | `C_AuctionHouse.SendSearchQuery` | CONFIRMED | `SendSearchQuery(itemKey, {}, true)` leads to a real commodity result event. |
| Commodity count | `C_AuctionHouse.GetNumCommoditySearchResults` | CONFIRMED | `GetNumCommoditySearchResults(2770)` works; exact returned count was not supplied. |
| Commodity row | `C_AuctionHouse.GetCommoditySearchResultInfo` | CONFIRMED | `GetCommoditySearchResultInfo(2770, 1)` works. |
| Item count | `C_AuctionHouse.GetNumItemSearchResults` | UNKNOWN | |
| Item row | `C_AuctionHouse.GetItemSearchResultInfo` | UNKNOWN | |
| Throttle readiness | `C_AuctionHouse.IsThrottledMessageSystemReady` | CONFIRMED | Probe readiness changes `true -> false` during query, then returns to `true` after the system-ready event. |

## Result events

```text
COMMODITY_SEARCH_RESULTS_UPDATED: CONFIRMED — fires for the Copper Ore query
ITEM_SEARCH_RESULTS_UPDATED: UNKNOWN
AUCTION_HOUSE_THROTTLED_SYSTEM_READY: CONFIRMED — fires before readiness returns to true
AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED: UNKNOWN
AUCTION_HOUSE_THROTTLED_MESSAGE_SENT: UNKNOWN
AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED: UNKNOWN
AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED: UNKNOWN
AUCTION_HOUSE_THROTTLED_SPECIFIC_SEARCH_READY: CONFIRMED unavailable — registration reports an unknown event in the tested beta build
```

## Result semantics

```text
Copper Ore (2770) result path: CONFIRMED — commodity
Peacebloom (2447), Light Leather (2318) result paths: CONFIRMED — MP-03 click scans succeeded
Tin Ore (2771) current commodity values: CONFIRMED — MP-05 live batch report
Silver Ore (2775) nonempty commodity result: UNKNOWN — MP-05 panel showed UNKNOWN
unitPrice unit: CONFIRMED — per-unit price in copper; 200 matches 2 silver/unit in AH UI
quantity meaning: CONFIRMED — total quantity at that commodity price level; 285 matches the AH UI total of 285
row aggregation behavior: CONFIRMED — observed commodity quantity is aggregated at its price level
totalNumberOfOwners field presence: CONFIRMED — values 19 and 20 observed
totalNumberOfOwners exact semantics: UNKNOWN — owner identity/counting rules not independently verified
auctionID field presence: CONFIRMED — 25442 in both scans
auctionID semantics: UNKNOWN
Result completeness/paging: UNKNOWN
```

These semantics are confirmed for the observed Copper Ore commodity result, not
for the untested normal-item result path. The reported primitive fields were:

| Field | Earlier scan | Later scan | Evidence / interpretation |
|---|---|---|---|
| `unitPrice` | UNKNOWN (not supplied) | `200` | Later value matches 2 silver per unit in the AH UI. |
| `quantity` | `265` | `285` | Later value matches 285 total units at that commodity price level. |
| `totalNumberOfOwners` | `19` | `20` | Raw observed values only; exact semantics remain UNKNOWN. |
| `auctionID` | `25442` | `25442` | Unchanged while quantity/owners changed; meaning remains UNKNOWN. |

An unchanged `auctionID` does not establish a unique auction, price-level identity,
stable identifier, or unchanged result. Do not use it to infer those properties.

## Throttle behavior

```text
Readiness transition: CONFIRMED — true -> false during query, then true after AUCTION_HOUSE_THROTTLED_SYSTEM_READY
Ready event required before every query: UNKNOWN
Observed query cadence: UNKNOWN
Rejected/queued premature query behavior: UNKNOWN
```

## SavedVariables

```text
Survives /reload: CONFIRMED — user manually verified retained MarketPilotProbe data in the beta client
Survives normal logout: CONFIRMED — user logged out normally after a successful probe observation
Visible after character switch: CONFIRMED — the same account-wide probe observation was visible on a different character
```

## Confirmed deviations from candidate APIs

`AUCTION_HOUSE_THROTTLED_SPECIFIC_SEARCH_READY` cannot be registered in the
tested beta build: the client reports an unknown event. Removed from the probe's
candidate list. Exact error text and numeric build were not supplied; no verbatim
error is reconstructed here. `AUCTION_HOUSE_THROTTLED_SYSTEM_READY` remains the
observed ready event. No alternative function signatures were needed or inferred.

## MP-00 persistence status

Probe SavedVariables persistence is CONFIRMED across both `/reload` and a normal
logout followed by login on a different character. The preserved observation still
contained the prior Copper Ore sample and client metadata without rescanning.

This confirmation applies to the probe's account-wide SavedVariables only.
MP-01 itself has no production persistence layer yet. Other UNKNOWN entries above
remain unverified, including `auctionID` semantics and result completeness/paging.

## Raw notes

2026-09-18 (report received): user confirmed the query/result/UI comparison and
throttle observations recorded above in the real Forever beta client. Actual test
timestamp is UNKNOWN. Raw chat logs/screenshots were not included in this update.

2026-09-18 (MP-01 follow-up received): user confirmed probe SavedVariables survive
`/reload`, normal logout, and subsequent login on a different character. The
preserved sample still showed itemID 2770, quantity 285, unitPrice 200, build 69893,
interface 16001 and version 1.60.1.

2026-09-18 (MP-01 production validation): the production scanner completed two
separate manual Copper Ore scans in the live Forever beta client. Each scan sent
exactly one query and reached DONE. One observed snapshot contained 2 price levels,
total quantity 472, lowest unit price 199 copper and highest unit price 200 copper.
The live AH UI at the same moment matched those values. Closing the AH reset the
scanner to IDLE; reopening and scanning again incremented the session query count
by exactly one.

## MP-02 production validation — CONFIRMED

2026-09-18 (user report received): MP-02 was tested in the real Forever beta
client. Reported current-scan outputs:

| Scan | Levels | Total quantity | Lowest | Highest | Raw median | Clean median | Suspicious | Extreme | Anomaly sufficient |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 4 | 735 | 170 | 200 | 200 | 200 | 0 | 0 | no |
| 2 | 4 | 775 | 170 | 200 | 199 | 199 | 0 | 0 | no |

Prices are copper per unit. The insufficient classification with four price
levels is expected and was confirmed in-client. Per-level quantities were not
provided; do not reconstruct them from these aggregate observations.

## MP-03 validation — CONFIRMED (user report)

The user reported real Forever beta validation before the MP-05 direction change:
the right-side panel works; Copper Ore, Peacebloom and Light Leather scan by click;
outlier information displays correctly; collapse/expand works; AH close hides the
panel and reopen restores it; no Lua error was observed. Issue #7 additionally
records that the Peacebloom absurd-price test correctly excluded extreme levels.
Exact rows, prices, UI scale and screenshots for that test were not supplied here.
Do not reconstruct them or generalize screen fit to other resolutions.

## MP-05 first batch — CONFIRMED (user live-validation comment)

Source: [Issue #7 comment, 2026-09-18](https://github.com/kiviman1/MarketPilot/issues/7#issuecomment-5727232767).
The user reported:

- Market Watch renders correctly and the serial batch completes `DONE 5 / 5`.
- Copper Ore, Tin Ore, Peacebloom and Light Leather produce current values.
- Silver Ore displays UNKNOWN rather than an invented zero price. The cause of
  missing values was not supplied; do not infer a successful nonempty result.
- Light Leather: levels=20, totalQuantity=1925, lowest=25c, highest=500c,
  rawMedian=27c, cleanMedian=27c, suspicious=0, extreme=0, anomalySufficient=yes.
- First-history items show NEW with insufficient historical columns (`?`).
- Market Report shows no supported historical findings yet.
- History status shows account-wide / realm + faction.

The reported remaining UX gap was inability to open stored history away from AH.
The account-wide declaration/status is not itself evidence of persistence after
logout or of realm/faction market-sharing rules.

## MP-05 standalone follow-up — UNKNOWN / pending

The new `/mp watch` standalone lifecycle is tested only in offline Lua fixtures.
No client test was performed by the coding agent. Remaining in-client checks:

- `MarketPilotDB` save/load, dedupe and retention in the actual client;
- production history after `/reload`, logout and same-key character switch;
- actual guarded realm/faction identity strings and key stability;
- cross-faction/cross-realm AH market-sharing semantics (UNKNOWN; conservative
  separate partitions are an implementation choice, not a verified AH rule);
- cancellation, error recovery and long batch sessions beyond the reported run;
- standalone UIParent anchor, read-only controls, toggling and AH docking/return;
- standalone detail/report after reload and same-key main-character login away
  from AH, without rescanning or changing stored history;
- accumulated 7d/30d market history and its client presentation.

Probe persistence remains the previously confirmed account-wide observation;
it does not itself validate the new production schema. Silver Ore (2775) nonempty
results, broader beta material catalogue, result completeness/paging, request
identity and normal-item search semantics remain UNKNOWN. No sell-side APIs or
sale workflows are introduced in this MP-03-based branch. The in-game checklist
is in [src/README.md](../src/README.md).

## MP-05 reload binding bug — user report and offline fix

[Latest live bug comment, 2026-09-18](https://github.com/kiviman1/MarketPilot/issues/7#issuecomment-5727479247)
reports successful batch -> `/reload` -> `/mp watch` showing `?` in Now instead
of the saved current values. This is a confirmed reported symptom, not evidence
that the snapshots were deleted. Actual early/stable identity strings and the
saved root contents were not provided.

Code review found that initializeHistory returned before recomputing identity
whenever db.status was OK. A deterministic early-key-A -> stable-key-B fixture
failed on that code, then passed with stable-event revalidation. The fix binds
the existing root to the current key, invalidates partition-local cached values,
and leaves saved history intact. `/mp dbstatus` now exposes the active key and
stored count/latest timestamp/latest cleanMedian for each configured item.

The later diagnostic report below confirms that the reload symptom still occurs.
No new client API signature or cross-market sharing rule is inferred from the
offline key-change fixture.

## MP-05 persistence diagnostic report — unresolved live failure

Source: [Issue #7 correction, 2026-09-18](https://github.com/kiviman1/MarketPilot/issues/7#issuecomment-5727768062).
The user explicitly performed the reproduction after a **full WoW beta client
exit/relaunch** with the current addon. TOC metadata caching does not explain this
reported run.

Reported facts:

- Active key before scan, after scan and after reload was unchanged:
  `forever-beta:v1:18:Classic Beta PvE2:5:Horde` (verbatim reported key).
- Before scan: snapshots=0.
- After batch: snapshots=1 for all five configured IDs; Silver's cleanMedian was
  UNKNOWN even though its snapshot existed.
- After `/reload`: snapshots=0 again.

Cause is UNKNOWN. These counts alone do not distinguish failure to serialize/load
the saved global from runtime replacement/detachment of that root. The earlier
synthetic A-to-B key fix does not establish the cause of this unchanged-key failure.

This follow-up adds diagnostics only: frozen Core/startup pre/post-bind observations,
read-only `/mp svdebug`, globalSameRoot in `/mp dbstatus`, and an explicit primitive
canary through `/mp svmark`. No further binding/retention fix, schema change, second
SavedVariables name, or guessed migration is introduced. The canary's real reload
survival and actual phase/global/root observations remain UNKNOWN until the user
returns the command output; the diagnostic sequence is in [src/README.md](../src/README.md).
