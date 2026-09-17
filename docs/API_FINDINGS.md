# API Findings

Observed WoW Forever beta behavior only. Do not fill this file from memory or from another WoW branch without clearly labelling it as external reference.

Evidence source: the user's real Forever beta client validation report, received
2026-09-18. CONFIRMED below is limited to those reported observations; no new
in-client testing was performed while recording this update. The exact client
version/build/interface and test timestamp were not supplied.

## Client

```text
Version: UNKNOWN
Build: UNKNOWN
Interface: UNKNOWN
Observed on: UNKNOWN
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
Other gathering items' result paths: UNKNOWN
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
Survives normal logout: EXPECTED/UNVERIFIED — deferred; not an MP-01 blocker
Visible after character switch: EXPECTED/UNVERIFIED — deferred; not an MP-01 blocker
```

## Confirmed deviations from candidate APIs

`AUCTION_HOUSE_THROTTLED_SPECIFIC_SEARCH_READY` cannot be registered in the
tested beta build: the client reports an unknown event. Removed from the probe's
candidate list. Exact error text and numeric build were not supplied; no verbatim
error is reconstructed here. `AUCTION_HOUSE_THROTTLED_SYSTEM_READY` remains the
observed ready event. No alternative function signatures were needed or inferred.

## Remaining important MP-00 validations

`/reload` persistence is now CONFIRMED by the user's real beta test. Normal logout
and character-switch persistence remains EXPECTED/UNVERIFIED and deferred. It is
explicitly **not an MP-01 blocker**; the user authorized the small production
AuctionAPI/single-item Scanner slice in Issue #2. This does not confirm future
production persistence: MP-01 has no SavedVariables.

For the deferred check, query on the AH alt, log out normally, log into the main
character and run `/mpprobe dump`. Confirm the saved item, timestamp, build and
samples survive without rescanning. Do not run `/mpprobe clear` between checks.
Offline fixtures do not substitute for this test. Other UNKNOWN entries above
remain unverified, including the missing build metadata and `auctionID` semantics.

## Raw notes

2026-09-18 (report received): user confirmed the query/result/UI comparison and
throttle observations recorded above in the real Forever beta client. Actual test
timestamp is UNKNOWN. Raw chat logs/screenshots were not included in this update.

2026-09-18 (MP-01 follow-up received): user additionally confirmed probe
SavedVariables survive `/reload` in the real beta client. Normal logout and
switching to another character were not tested and remain deferred/unverified.
