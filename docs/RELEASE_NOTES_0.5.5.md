# MarketPilot 0.5.5

Market intelligence for Mining, Herbalism, and Skinning materials in WoW Forever.

- Browse 56 configured gathering materials and scan their markets one item at a time.
- View current prices, robust medians, price ranges, supply, and outlier counts.
- Keep compact account-wide history, separated by realm and faction, and view
  trends, historical comparisons, and Market Reports as observations accumulate.
- Open stored market information anywhere with the minimap icon or `/mp watch`.
- Use an independent settings window for size, category, position lock,
  minimap visibility, and diagnostic logging.
- Keep Market Watch above ordinary action bars and unit frames, with Settings
  above Market Watch. Scroll details and reports with the mouse wheel.

Prices remain exact copper values. Missing observations are shown with explanatory
labels instead of invented prices. There is no buying, selling, posting, or
background scanning while the Auction House is closed.

## Package and validation

The ZIP contains a single `MarketPilot/` folder with 19 runtime files, including
`MarketPilot.toc` and the addon icon. Probe code, tests, synthetic demo data, and
player SavedVariables are excluded. The existing DB schema remains version 1.

All 237 deterministic Lua 5.1 tests pass. Offline tests do not establish
compatibility with additional client versions; the existing client interface
declaration is preserved. The detailed live-check checklist and remaining
validation limits are in `src/README.md` and `docs/API_FINDINGS.md`.
