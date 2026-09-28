# 30-day model preview

Open **30d Demo** in Market Watch, or type `/mp demo on`. No Auction House visit is
needed. The panel displays **DEMO ONLY** and uses simulated data for all 56
configured materials. The scenario explanation is in the selected item's Current
tab. History shows the calculated medians, change, trend, volatility, percentile,
supply and significance; Market Report uses these same results.

Use **Exit demo** or `/mp demo off` to return to the real market. The earlier
standalone-watch preference is restored, so a window opened only for the demo may
close on exit. Closing the window merely hides it; demo mode stays active until
explicitly exited or reloaded. Reload starts with real data and demo disabled.

## What to check

| Item | Scenario | Expected result |
|---|---|---|
| Copper Ore | Gradual rise | Current 3243c; 7d median 2809c; 30d median 1789.5c; trend about +4%/day; percentile 100 |
| Tin Ore | Gradual fall | Current 1000c; 7d median 1155c; falling trend; percentile 0 |
| Silver Ore | Stable market | Current/medians 1000c; percentile 50; supply 1x; volatility 0; p=1, no meaningful shift |
| Iron Ore | Last-day price/supply drop | Current 600c; 7d change -40%; supply 0.4x; meaningful shift yes |
| Gold Ore | Last-day price/supply increase | Current 1600c; 7d change +60%; supply 2x; meaningful shift yes |
| Mithril Ore | One large latest move | Current 1800c; unusual-return class HIGH; robust dispersion about 0.3371% |
| Peacebloom | Dominant-quantity 100000g outlier | Raw median 100000g; clean median 10s; one extreme level excluded; 30d median stays 10s |

Other configured materials repeat these seven deterministic scenarios. No random
seed or real market price is used. Iron/Gold can have a meaningful last-day shift
while the robust 7d trend remains stable: the window comparisons describe different
facts. Likewise Mithril's latest jump is unusual even though robust return
dispersion stays small; one shock is not the whole distribution.

Peacebloom's supply ratio rises because supply intentionally uses the raw factual
quantity, including extreme levels. The price reference excludes the extreme
level. This distinction is part of the documented model, not a synthetic-data bug.

## Isolation and model checks

Each item has 91 observations, eight hours apart, from exactly 30 days before the
demo timestamp through that timestamp. Each synthetic scan goes through the real
Statistics -> compact Snapshot -> Database -> Market/HistoricalAnalytics/Signals
pipeline. Only a private in-memory root is supplied to Database; real saved data
is neither read for seeding nor modified. No second SavedVariables name or schema
change is introduced. The demo does not persist across reload or characters.

Activation is refused while a scan/batch is active or a dispatched query remains
uncertain. During demo, item clicks only select details; scan/batch/refresh/cancel
buttons and commands cannot start or affect real queries. `/mp svmark` is blocked
too. `/mp dbstatus` and `/mp svdebug` continue to describe the **real** database.
AH open/close does not turn demo data into a live source or enable its scan controls.

Tests independently check median, percent changes, percentile tie handling,
Theil-Sen slopes, MAD volatility, supply ratios, tie-corrected Mann-Whitney p-values,
the practical-move guard and the dominant outlier case. Existing insufficient-data
tests still apply; a new real installation continues to need real history.

This is a deterministic calculation/UI check, not evidence that synthetic
p-values predict real market behavior. Serial dependence, sparse actual sampling
and the other [model limitations](MARKET_MODEL.md) remain applicable.
