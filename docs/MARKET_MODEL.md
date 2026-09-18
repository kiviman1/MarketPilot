# Robust Market Model

Sections 1–8 define the implemented **MP-02-v1** current-scan model. Changes to
quantiles, thresholds or guards require an explicit model-version/documentation
and deterministic-test update. Sections 9–12 are future design notes, not MP-02
features. MP-02 returns descriptors and classifications, never a sale recommendation.

## 1. Normalize price

Input is the MP-01 sample's dense `priceLevels` array of primitive rows:

```text
{ unitPrice = <positive integer copper per unit>, quantity = <positive integer> }
```

Preserve the API's already verified unitPrice as-is: no division, conversion,
rounding or inferred values. Reject missing, non-number, zero, negative, fractional,
NaN, infinite or greater-than-9007199254740991 values for either field. Reject a
sparse/malformed array and any total quantity exceeding that exact-integer limit.
Invalid input returns `nil, "UNKNOWN: ..."`; no partial analysis is returned.

The input sample is never mutated. Output rows are sorted by price, then quantity,
so permutations of the same input produce identical output. Empty input produces
zero counts/quantity, absent price descriptors, and INSUFFICIENT status.

## 2. Work in log-price space for anomaly detection

For positive prices:

```text
x = ln(unitPrice)
```

AH prices are typically right-skewed. Log space reduces the leverage of very large values while preserving proportional differences.

Zero/negative/invalid prices are rejected as malformed observations.

## 3. Robust center

Raw and clean descriptors each contain `levelCount`, `totalQuantity`, `min`, `max`,
`weightedMedian`, `q1` and `q3`. Prices are selected original integer copper values.

For sorted rows `(price_i, quantity_i)`, let `W = sum(quantity_i)` and
`C_i = sum(quantity_1 .. quantity_i)`. The discrete weighted quantile is exactly:

```text
Qw(p) = first price_i with C_i >= p * W
p = 1/4 (Q1), 1/2 (median), 3/4 (Q3)
```

Equality selects the current price, with no averaging/interpolation. The code
compares cumulative integer quantities against `ceil(p*W)`. To avoid floating
rounding near the exact-integer boundary, for `p = r/4` it computes the rank as:

```text
floor(W/4) * r + ceil((W mod 4) * r / 4), r in {1,2,3}
```

For example, prices/quantities `(100,1), (200,3), (300,6)` yield Q1=200,
median=300 and Q3=300. `(100,1), (200,1)` yields median=100, not 150.

Anomaly detection uses one observation per **distinct unitPrice**, ignoring
quantity. Repeated returned prices remain separate raw/clean rows but contribute
only once to detector sample size and scale; splitting a price into multiple rows
cannot inflate confidence. No quantity-sized observation arrays are constructed.

For sorted log observations `x[1..n]`, use the unweighted type-7 quantile:

```text
h = 1 + (n - 1) * p; j = floor(h); f = h - j
Qlog(p) = x[j]                         if f = 0
          x[j] + f * (x[j+1] - x[j])   otherwise
```

The log median and the median absolute deviation both use this rule at p=0.5.
Only log-space metrics interpolate; copper descriptors never do.

## 4. MAD detector

```text
M   = median(x)
MAD = median(abs(x - M))
robustZ = 0.6745 * (x - M) / MAD
```

MAD is usable only if `MAD > 1e-12` in natural-log units. Otherwise modified Z is
absent (UNKNOWN), never infinite, and IQR can flag SUSPICIOUS only. This absolute
epsilon avoids amplifying floating-point noise in a nearly flat log distribution.

MP-02-v1 flags (strict comparisons):

```text
abs(robustZ) > 3.5  => suspicious
abs(robustZ) > 6.0  => extreme candidate
```

The strong MAD flag alone never produces EXTREME.

## 5. IQR detector

```text
IQR = Q3 - Q1
innerLow  = Q1 - 1.5 * IQR
innerHigh = Q3 + 1.5 * IQR
outerLow  = Q1 - 3.0 * IQR
outerHigh = Q3 + 3.0 * IQR
```

Use unweighted type-7 Q1/Q3 of log prices. IQR is usable for strong classification
only if `IQR > 1e-12`. Fence comparisons are strict; equality is inside the fence.

Diagnostic flags:

- outside inner fence => suspicious candidate;
- outside outer fence => extreme candidate.

Every annotated level retains `modifiedZ` when usable and the booleans
`madSuspicious`, `madExtreme`, `iqrSuspicious`, `iqrExtreme`. When IQR is degenerate,
the collapsed fences may still flag SUSPICIOUS; they cannot authorize EXTREME.

## 6. Small-sample guard

Do not pretend robust filtering is reliable on tiny markets.

The old draft's 8-level guard is superseded by Issue #3's MP-02 rule:

```text
n < 5 distinct prices => anomaly.sufficient=false; status=INSUFFICIENT
MAD <= 1e-12 or IQR <= 1e-12 => anomaly.sufficient=false; status=INSUFFICIENT
otherwise => anomaly.sufficient=true; status=OK
```

INSUFFICIENT still has valid raw/clean descriptors. Reason is TOO_FEW_PRICE_LEVELS
or DEGENERATE_SCALE; an adequate model reports CURRENT_SCAN_ONLY, not calibrated
historical confidence. Tiny/degenerate samples may be SUSPICIOUS but never EXTREME.

## 7. Clean market set

Classification is mutually exclusive and symmetric on the low/high sides:

```text
EXTREME    if sufficient AND abs(robustZ) > 6.0 AND outside the 3.0*IQR fence
SUSPICIOUS otherwise, if abs(robustZ) > 3.5 OR outside the 1.5*IQR fence
NORMAL     otherwise
```

Clean descriptors exclude **only EXTREME** rows. SUSPICIOUS rows are retained in
every clean calculation, including min/max, weighted quantiles and total quantity.
Counts are mutually exclusive row counts; `anomaly.observationCount` is the distinct
price count. Filtering is a single pass using the raw distribution's scale, with
no iterative reclassification. Raw descriptors and the scanner sample retain all
original normalized rows. One high-quantity extreme cannot tilt the detector and
is removed before the clean weighted median is calculated.

## 8. Current-scan limitations and integration

`Statistics.Analyze(sample)` returns `modelVersion`, `status`, `raw`, `clean` and
`anomaly` (metrics, sufficiency/reason, counts and sorted annotated primitive rows).
Scanner calls it once after a successful result read, retains both sample and
analysis in memory, and appends raw/clean weighted medians, suspicious/extreme
counts and anomaly sufficiency to completion and `/mp status` output.

No `lowestValid` trading rule, history, p-value, confidence score or pricing target
is implemented. Broad/multimodal markets, several simultaneous anomalies and
tiny/degenerate distributions may mask anomalies. Suspicious or undetected levels
with large quantities can affect weighted descriptors because they are deliberately
retained. Classification is evidence of an unusual current-scan price, not proof
of manipulation or an instruction to trade. Log metrics are floating-point;
values extremely near a strict threshold can be numerically sensitive.

## 9. Snapshot history (future; not MP-02)

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

## 10. Significance (future; not MP-02)

Do not show a p-value during the first few days just because a function can calculate one.

Historical significance should use daily values or another defensible de-correlated series, not repeated observations of the same auction listings.

Initial plan after enough history exists:

- compare recent daily market values with a prior baseline using a non-parametric test such as Mann–Whitney U;
- require `p < 0.05`;
- also require a practical median price move of at least 10%.

A statistically significant but economically tiny move should not be labelled a meaningful market movement.

## 11. Confidence (future; not MP-02)

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

## 12. Planned broader outputs (future; not MP-02)

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

## 13. MP-04-v1 current-scan reference targets (implemented)

`Pricing.Targets(analysis)` consumes the existing MP-02 analysis without modifying
it or running Statistics again. It is pure Lua with no client calls or persistence.
Each of `fast`, `normal`, `patient` returns `{ status, copper? }`.

- If `analysis.anomaly.sufficient ~= true` (including missing analysis), all three
  targets have status INSUFFICIENT and no copper value. Raw current lowest may
  still be shown as a factual descriptor when the sample exists.
- Fast is the minimum original unitPrice among rows classified exactly NORMAL.
  SUSPICIOUS and EXTREME rows cannot set Fast. There is no 1-copper undercut.
- Normal is exactly `analysis.clean.weightedMedian`.
- Patient is exactly `analysis.clean.q3`.
- Available values have status OK and must be positive exact integer copper
  (at most 9007199254740991). Missing/invalid values or no NORMAL rows produce
  UNKNOWN for the affected target; never zero, interpolation or silver rounding.

No thresholds or quantiles in MP-02 change. Clean still retains SUSPICIOUS rows,
so Normal/Patient can legitimately reflect them even though Fast excludes them;
the targets are not forced into ascending order. These are current-scan reference
levels, not guarantees of sale speed. No history, p-value, demand model or posting
semantics are inferred. The future notes above remain unimplemented.
