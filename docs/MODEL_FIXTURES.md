# Offline synthetic market fixtures

Runtime demo mode was removed in 0.5.3. There is no preview command, seeding
button or synthetic data generator in the addon. These fixtures run only through
`python tools/test.py` and cannot populate the player's saved history.

`tests/fixtures/SyntheticMarket.lua` creates 91 observations eight hours apart,
covering 30 days, for each configured item. Every synthetic scan goes through
the real Statistics -> compact Snapshot -> Database -> Market/Analytics/Signal
pipeline with a private in-memory root. Tests use independently calculated
references rather than a second implementation of the production math.

| Example | Scenario | Expected result |
|---|---|---|
| Copper Ore | Gradual rise | Current 3243c; 7d median 2809c; 30d median 1789.5c; trend about +4%/day; percentile 100 |
| Tin Ore | Gradual fall | Current 1000c; 7d median 1155c; falling trend; percentile 0 |
| Silver Ore | Stable | Current/medians 1000c; percentile 50; supply 1x; volatility 0; p=1 |
| Iron Ore | Last-day price/supply drop | Current 600c; 7d change -40%; supply 0.4x; meaningful shift |
| Gold Ore | Last-day price/supply rise | Current 1600c; 7d change +60%; supply 2x; meaningful shift |
| Mithril Ore | Large latest move | Current 1800c; unusual-return class HIGH; robust dispersion about 0.3371% |
| Peacebloom | Dominant-quantity 100000g outlier | Raw median 100000g; clean median 10s; one excluded extreme; historical median stays 10s |

Other materials repeat these seven deterministic scenarios. Raw supply includes
extreme levels; clean price references exclude them. A meaningful last-day shift
can coexist with a stable robust 7d trend because they describe different facts.
A latest-return shock can be HIGH while overall MAD dispersion remains small.

The suite retains independent checks for medians, changes, tied percentile,
Theil-Sen slope, MAD volatility, supply, Mann-Whitney p-values, practical-move
guards, isolation and insufficient history. See [MARKET_MODEL.md](MARKET_MODEL.md)
for exact definitions and real-world sampling limitations. These checks establish
deterministic calculation behavior, not that synthetic p-values predict markets.
