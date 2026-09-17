# API Findings

Observed WoW Forever beta behavior only. Do not fill this file from memory or from another WoW branch without clearly labelling it as external reference.

## Client

```text
Version: UNKNOWN
Build: UNKNOWN
Interface: UNKNOWN
Observed on: UNKNOWN
```

## Auction House open/close

```text
AUCTION_HOUSE_SHOW: UNKNOWN
AUCTION_HOUSE_CLOSED: UNKNOWN
```

## Candidate API surface

| Capability | Candidate | Observed status | Notes |
|---|---|---|---|
| Make item key | `C_AuctionHouse.MakeItemKey` | UNKNOWN | |
| Send search | `C_AuctionHouse.SendSearchQuery` | UNKNOWN | |
| Commodity count | `C_AuctionHouse.GetNumCommoditySearchResults` | UNKNOWN | |
| Commodity row | `C_AuctionHouse.GetCommoditySearchResultInfo` | UNKNOWN | |
| Item count | `C_AuctionHouse.GetNumItemSearchResults` | UNKNOWN | |
| Item row | `C_AuctionHouse.GetItemSearchResultInfo` | UNKNOWN | |
| Throttle readiness | `C_AuctionHouse.IsThrottledMessageSystemReady` | UNKNOWN | |

## Result events

```text
COMMODITY_SEARCH_RESULTS_UPDATED: UNKNOWN
ITEM_SEARCH_RESULTS_UPDATED: UNKNOWN
AUCTION_HOUSE_THROTTLED_SYSTEM_READY: UNKNOWN
AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED: UNKNOWN
```

## Result semantics

```text
Gathering items treated as commodity: UNKNOWN
unitPrice unit: UNKNOWN
quantity meaning: UNKNOWN
row aggregation behavior: UNKNOWN
```

## Throttle behavior

```text
Ready event required: UNKNOWN
Observed query cadence: UNKNOWN
Rejected/queued premature query behavior: UNKNOWN
```

## SavedVariables

```text
Survives /reload: UNKNOWN
Survives normal logout: UNKNOWN
Visible after character switch: UNKNOWN
```

## Confirmed deviations from candidate APIs

None yet.

## Raw notes

Add dated observations here. Keep errors verbatim when they help identify a signature or event mismatch.
