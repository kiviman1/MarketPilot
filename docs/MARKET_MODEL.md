# Robust Market Model

This document defines the initial statistical model. Thresholds are deliberately versioned and may be tuned after real beta data is collected.

## 1. Normalize price

All calculations use integer copper per unit:

```text
unitPrice = buyout / quantity
```

If the live API already returns unit price, keep the Blizzard value after validating its semantics in MP-00.

Never compare raw stack totals.

## 2. Work in log-price space for anomaly detection

For positive prices:

```text
x = ln(unitPrice)
```

AH prices are typically right-skewed. Log space reduces the leverage of very large values while preserving proportional differences.

Zero/negative/invalid prices are rejected as malformed observations.

## 3. Robust center

Primary descriptive center is the median, not arithmetic mean.

Where the API aggregates commodity supply into price levels, calculate both of these after anomaly filtering:

- **price-level median** — each distinct returned price level contributes once;
- **quantity-weighted median** — each level is weighted by available quantity.

Use price-level behavior for anomaly detection so that one huge quantity at one absurd price does not dominate the detector. The production reference price can use the cleaned quantity-weighted median if beta data shows it behaves sensibly.

## 4. MAD detector

```text
M   = median(x)
MAD = median(abs(x - M))
robustZ = 0.6745 * (x - M) / MAD
```

If `MAD == 0`, do not divide by zero; fall back to IQR rules.

Initial flags:

```text
abs(robustZ) > 3.5  => suspicious
abs(robustZ) > 6.0  => extreme candidate
```

These are starting thresholds, not eternal constants.

## 5. IQR detector

```text
IQR = Q3 - Q1
innerLow  = Q1 - 1.5 * IQR
innerHigh = Q3 + 1.5 * IQR
outerLow  = Q1 - 3.0 * IQR
outerHigh = Q3 + 3.0 * IQR
```

Initial classification:

- outside inner fence => suspicious candidate;
- outside outer fence => extreme candidate.

When MAD and IQR disagree, preserve the reason flags. Do not erase diagnostic information.

## 6. Small-sample guard

Do not pretend robust filtering is reliable on tiny markets.

Initial rule:

```text
< 8 usable price levels => no automatic exclusion; confidence LOW
```

Observations can still be flagged for display, but the addon should not silently delete them from the market calculation solely on weak statistics.

## 7. Clean market set

For adequate sample sizes:

- **extreme** observations are excluded from clean market reference calculations;
- **suspicious** observations stay visible and are excluded from `lowestValid` when they are on the low side;
- keep counts and reasons for every excluded/flagged level.

The market panel should tell the user that anomalies were ignored rather than hiding them.

## 8. Lowest valid price

The raw lowest auction is not automatically the market floor.

`lowestValid` is the lowest price level that survives the low-side anomaly rules. This is the value used when deciding whether a one-off undercut should be followed.

Example:

```text
clean market: 42s, 43s, 44s, 45s, 47s
raw lowest:   8s
```

The 8s level can be shown as anomalous while `lowestValid` remains around the normal market band.

## 9. Snapshot history

The user is expected to scan roughly 2–3 times per day, not hourly.

Persist compact scan summaries. Build daily summaries from those snapshots:

```text
daily median
 daily Q1/Q3
 daily low/high of clean medians
 scan count
```

Retention target for v1:

- recent raw compact snapshots: keep enough for intraday context;
- long history: daily summaries;
- no raw auction-row archive by default.

## 10. Significance

Do not show a p-value during the first few days just because a function can calculate one.

Historical significance should use daily values or another defensible de-correlated series, not repeated observations of the same auction listings.

Initial plan after enough history exists:

- compare recent daily market values with a prior baseline using a non-parametric test such as Mann–Whitney U;
- require `p < 0.05`;
- also require a practical median price move of at least 10%.

A statistically significant but economically tiny move should not be labelled a meaningful market movement.

## 11. Confidence

Confidence is separate from price direction.

Inputs may include:

- current usable price-level count;
- current usable quantity;
- percentage of observations flagged;
- number of historical days;
- recency of last scan;
- disagreement between price-level and quantity-weighted medians.

Initial UI labels:

```text
LOW
MEDIUM
HIGH
```

Do not expose false precision such as `93.7% confidence` unless a calibrated model is later developed.

## 12. Outputs

Statistics should return facts, not trading commands:

```text
marketMedian
quantityWeightedMedian
q1
q3
mad
lowestValid
validQuantity
validPriceLevels
suspiciousCount
extremeCount
confidenceInputs
```

The separate Pricing module decides how these values are presented as reference sale targets.
