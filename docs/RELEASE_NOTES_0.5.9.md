# MarketPilot 0.5.9

Changes since 0.5.5.

## New

- Selecting a material in Market Watch while the Auction House is open now
  refreshes its market data and opens the matching search in Browse Auctions.
- Added **Market Summary** to the Current tab: plain-language explanations of
  the reference price, central price range, lowest listing, listed quantity,
  and retained/excluded outliers.
- Added **Historical Context** to the History tab: explanations of price changes,
  trend direction, listed supply, and historical price position when enough
  observations are available. Each comparison checks its own data requirements.
- Prices now use the game's gold, silver, and copper icons throughout Market
  Watch, Current, History, and summaries.

## Improvements and fixes

- Fixed native searches showing no results when pressing the Auction House's
  Search button manually would find the item.
- Native search waits for the market scan and Auction House readiness. Repeated
  clicks cannot launch overlapping requests; closing the Auction House cancels
  pending navigation.
- Summaries show the recorded scan's age and explain missing or insufficient
  data. If a new scan fails, an available previous observation is clearly identified.
- Widened the price column for coin icons and kept wrapped summaries above the
  detailed statistics with mouse-wheel scrolling.
- Preserved exact copper prices and fractional copper in historical medians.
  Missing prices are never displayed as zero.

## Existing data

Existing market history and settings are preserved. No SavedVariables reset or
migration is required. Statistical formulas, thresholds, and history retention
are unchanged.

MarketPilot remains a descriptive market-analysis addon with no automated buying,
selling, or posting. Stored market information remains available outside the
Auction House without starting a scan.
