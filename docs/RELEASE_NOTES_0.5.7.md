# MarketPilot 0.5.7

- Use Blizzard's normal Search button method when opening a material in Browse
  Auctions. The previous custom exact-match query could display no results even
  though a manual Search found the item in the tested Forever client.
- Keep native level and filter handling consistent with a manual search. Other
  matching names may appear in the native list, while MarketPilot's statistics
  still come from its separate item-ID commodity scan.

Sequential queries, throttle/deadline guards, and read-only stored browsing are
unchanged. There is no automatic retry or extra fallback query. SavedVariables
schema and market calculations are unchanged. Recheck Gold Ore in-client without
pressing the native Search button after selecting it in Market Watch.
