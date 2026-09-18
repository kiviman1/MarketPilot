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
Peacebloom (2447) and Light Leather (2318) result paths: CONFIRMED commodity via MP-03 click scans
Other configured gathering items' result paths: UNKNOWN
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

## MP-03 validation — CONFIRMED

2026-09-18 (user report received): the right panel works in the real Forever beta
client. Copper Ore, Peacebloom and Light Leather scan through item clicks. Outlier
information displays correctly; collapse/expand works; AH close hides the panel
and reopening restores it without Lua errors. This confirms the tested MP-03
layout, not every resolution/UI scale or the new MP-04 controls.

Sub-silver commodity listing prices (20 copper Peacebloom) were also reported.
This is display/search evidence only, not proof of copper-valued posting support.

## MP-04 sell-side and inventory — UNKNOWN / awaiting beta validation

No MP-04 client observation has been supplied. Offline fixtures do not change any
of the statuses below. Runtime `PRESENT` means only that a function exists;
`CANDIDATE_OBSERVED` means the explicit read-only candidate call returned the
expected primitive type. Neither label claims its semantics are beta-confirmed.

| Candidate | Read-only probe shape | Forever status |
|---|---|---|
| `IsSellItemValid` | `(ItemLocation, false)`; boolean result | UNKNOWN |
| `CalculateCommodityDeposit` | `(itemID, durationIndex, quantity)`; non-negative integer candidate deposit | UNKNOWN |
| `SupportsCopperValues` | `()`; boolean result, including false | UNKNOWN |
| `ShouldAutoPopulatePrice` | `()`; boolean result, including false | UNKNOWN |
| `PostCommodity` | Presence check only; NEVER CALLED | UNKNOWN |

These candidate shapes are external references, not signature guesses or Forever
findings: [Blizzard API declarations](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/AuctionHouseDocumentation.lua).
The [external sell UI](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseSellFrame.lua)
uses duration indices. The probe tests candidate mapping 12h/24h/48h to 1/2/3 and
logs both; the mapping, deposit unit/amount and return semantics still require
comparison in Forever. No alternate signatures are attempted on failure.

The bag boundary uses the documented namespaced readers and primitive itemID /
stackCount fields: [container declarations](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ContainerDocumentation.lua).
It enumerates backpack 0 through the client's equipped bag count, including a
reagent bag when exposed by NUM_TOTAL_EQUIPPED_BAG_SLOTS; otherwise NUM_BAG_SLOTS.
See [external bag constants](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_FrameXMLBase/Constants.lua).
The candidate [ItemLocation constructor](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_ObjectAPI/Mainline/ItemLocation.lua)
is called only for the explicit check, after rereading bags and verifying the slot.
Bag readers, their shapes, equipped-bag coverage, `BAG_UPDATE_DELAYED`, ItemLocation
acceptance and the new scrolling/edit controls remain UNKNOWN in Forever.

Use **Check sell API (no post)** or `/mp sellstatus` with AH open and a bag item
selected. The command reports each presence/status/value, attempted argument
shape and any original error. Missing APIs, errors, nil or malformed results stay
UNKNOWN. False booleans and a valid candidate zero deposit remain visible.
Deposit is labelled candidate, invalidated by quantity/duration/bag changes and
only recalculated by another explicit check. It is not rounded to silver.

Real posting remains disabled and has no action handler. Hardware-event gating,
non-zero-copper posting acceptance, commodity matching/undercut order and deposit
semantics are UNKNOWN. A true SupportsCopperValues result alone cannot confirm a
real post. No runtime result enables posting; that requires a subsequent scoped
task after user-provided beta evidence. `auctionID` semantics remain UNKNOWN and
production code never reads it. No production SavedVariables/schema changes.
