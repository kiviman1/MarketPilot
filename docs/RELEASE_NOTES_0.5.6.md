# MarketPilot 0.5.6

- Clicking a material while the Auction House is open now refreshes its market
  analysis, then opens an exact-name search in Blizzard's Browse Auctions list.
- Native navigation waits for the commodity scan and throttle readiness. Repeated
  clicks cannot create parallel requests. Closing AH cancels pending navigation.
- Batch scans and Refresh preserve the native browse selection. Away from AH,
  item clicks continue to show stored history without sending queries.
- If the native search interface is unavailable, the scan remains usable and
  reports the navigation limitation. Successful price observations are kept.

No pricing/statistics formulas, SavedVariables schema, or stored history format
changed. No buying, selling, posting, or automatic retry was added. Native search
integration is source-backed and offline-tested; actual client rendering remains
part of the `src/README.md` acceptance checklist.
