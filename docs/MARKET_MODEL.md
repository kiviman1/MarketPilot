# Robust Market Model

Sections 1–8 define the implemented **MP-02-v1** current-scan model. Changes to
quantiles, thresholds or guards require an explicit model-version/documentation
and deterministic-test update. Sections 9–14 define **MP-05-v1** history and
descriptive signals. Neither model produces trading commands or sale targets.

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

Statistics itself has no history, p-value, confidence score or pricing target.
Broad/multimodal markets, several simultaneous anomalies and
tiny/degenerate distributions may mask anomalies. Suspicious or undetected levels
with large quantities can affect weighted descriptors because they are deliberately
retained. Classification is evidence of an unusual current-scan price, not proof
of manipulation or an instruction to trade. Log metrics are floating-point;
values extremely near a strict threshold can be numerically sensitive.

## 9. Snapshot history and rolling references (MP-05-v1)

History consumes compact snapshots, never auction rows. Retention, schema and
market identity are specified in [ARCHITECTURE.md](ARCHITECTURE.md). Snapshots with
`anomalySufficient=false` retain that limitation; their positive cleanMedian is a
valid descriptor, not proof of reliable outlier filtering, and remains eligible
for history. Empty/invalid prices never become zeros or previous-price carry-forwards.

Analysis is **as of the latest observation's timestamp**, not wall-clock now.
Reports do not extrapolate while the AH is closed. Last scan age is shown separately.
Future observations and values older than 60 days relative to that timestamp are
excluded. Valid prices are positive exact integer copper. Equal timestamps count
once (last input wins; explicit current replaces that timestamp), preventing
zero-time slope pairs. Input tables are never mutated.

Each snapshot gets equal historical weight, irrespective of its item quantity.
The conventional median is the middle sorted value for odd n, or the average of
the two central values for even n. A historical median can therefore be half a
copper; UI labels it as a statistic without rounding an actual observed price.
Current-scan weighted quantiles remain discrete integer copper (section 3).

For D = 1, 7, 30 days, historical baseline is `[t-D*86400, t)`; the current point
is excluded so it cannot be its own reference. To publish a window median/change/
supply ratio require at least three valid prior prices within that window **and**
at least D days since the oldest retained valid observation. Otherwise those
metrics are INSUFFICIENT. This is an age/count guard, not a claim of continuous
coverage. Missing days are not interpolated. Boundary observations are included.

```text
medianD = median(valid cleanMedian in baseline D)
changeD = 100 * (current.cleanMedian / medianD - 1)
quantityMedianD = median(valid totalQuantity in baseline D)
supplyRatioD = current.totalQuantity / quantityMedianD
```

No zero denominator or missing value is substituted. Quantity is the factual raw
total across levels, not the clean quantity. A real current zero quantity gives
ratio zero when a positive historical denominator exists. Supply is unavailable
when historical median quantity is zero.

30d percentile also requires the mature 30d window above:

```text
percentile30d = 100 * (count(history < current) + 0.5*count(history == current)) / n
```

This midrank tie rule gives 50 for all equal prices, 0 below every observation,
and 100 above every observation. The current point is excluded from n.

Maturity uses valid distinct-time observations including current: NEW if n<3;
otherwise EARLY if span<7 days, 7D READY if 7<=span<30 days, 30D READY if span>=30
days. A mature but sparse history may still fail individual metric guards.

## 10. Robust trend

Use valid observations in `[t-D*86400, t]`, including current, for D=7 and D=30.
Let x be timestamp in days and y=ln(cleanMedian):

```text
slope_ij = (ln(price_j) - ln(price_i)) / ((t_j-t_i)/86400), i<j
slope = median(all pairwise slopes)
trendPctPerDay = 100 * (exp(slope) - 1)
```

At least five distinct-time valid snapshots and at least 86400 seconds between
first and last are required. 30d trend additionally requires 30-day history age.
The 7d trend can be available during EARLY: it explicitly uses **available points
within the last 7 days**, with the five-point/24h guard, not an invented full week.
Full 7d median/change/supply still require seven-day age. Nonfinite output is
UNKNOWN. At the 200-observation cap there are at most 19,900 slopes per window.
A single odd snapshot usually cannot dominate their median; robustness is not an
unconditional guarantee against multiple bad observations.

This is the median-pairwise-slope Theil-Sen estimator, with no fitted-price prediction
or confidence interval. [SciPy method reference](https://docs.scipy.org/doc/scipy/reference/generated/scipy.stats.theilslopes.html).

## 11. Robust return volatility

Use chronological valid observations within the 7d window, including current.
Require at least five observations spanning at least 24h, as for trend.

```text
r_i = ln(price_i) - ln(price_(i-1))
MAD(r) = median(abs(r_i - median(r)))
sigma = 1.4826 * MAD(r)
volatilityPct = 100 * (exp(sigma) - 1)
```

This is robust dispersion **per observation interval**, not annualized/daily
volatility; irregular scan cadence matters. The 1.4826 scale is the rounded normal
consistency factor. [MAD reference](https://docs.scipy.org/doc/scipy/reference/generated/scipy.stats.median_abs_deviation.html).

Relative LOW/NORMAL/HIGH classification describes the **latest unusual return**
against the same item's preceding returns in that window. With at least four
returns total, the reference has at least three:

```text
center = median(preceding returns)
scale = 1.4826 * MAD(preceding returns)
zReturn = abs(latest return - center) / scale
LOW if zReturn <= 1
NORMAL if 1 < zReturn <= 3
HIGH if zReturn > 3
```

If scale<=1e-12 log units: LOW if deviation<=1e-12, otherwise HIGH. This avoids
infinite scores for flat histories; the numeric score stays absent. Classification
and dispersion are different facts: a single latest shock can be HIGH while MAD
volatility is zero. The report calls this 'Unusual return volatility', not a copper
threshold or a prediction of future volatility.

## 12. Significance

Recent window is `[t-86400, t]`; baseline is `[t-8*86400, t-86400)` (prior seven
days). They never overlap. Include current in recent. Require recent n>=3 and
baseline m>=7 valid observations; otherwise return INSUFFICIENT with no p-value,
significant/practical/meaningful booleans. Invalid prices return UNKNOWN.

Two-sided Mann-Whitney U uses original positive prices; log transformation would
preserve their ranks. Equal prices receive average pooled ranks. With N=n+m and
pooled tie-group sizes k:

```text
U = sum(recent ranks) - n*(n+1)/2
mu = n*m/2
variance = n*m/12 * ((N+1) - sum(k^3-k)/(N*(N-1)))
z = max(0, abs(U-mu)-0.5) / sqrt(variance)
p = 2 * (1-Phi(z))
```

Variance zero (all identical) gives p=1. Normal CDF uses the standard five-term
polynomial tail approximation; two-sided numerical approximation error <1.5e-7.
This error bound concerns CDF evaluation only, **not** the small-sample accuracy
of the normal approximation. p is clamped to [0,1]. It is not an exact/permutation
test. Method tag is `MW_NORMAL_TIE_CONTINUITY`; tie correction and 0.5 continuity
correction are tested against independent erfc reference values.
[Method and approximation caveats](https://docs.scipy.org/doc/scipy/reference/generated/scipy.stats.mannwhitneyu.html).

```text
practicalChange = 100 * (median(recent) / median(baseline) - 1)
significant = p < 0.05
practical = abs(median(recent)-median(baseline)) >= median(baseline)/10
meaningfulMove = significant AND practical
```

The difference-based practical comparison includes exactly +/-10% without
floating cancellation at the percentage boundary. This is a recent-window median
comparison, distinct from current-vs-7d change. p alone never enters the meaningful
changes report. UI shows very small values as p<0.0001, not p=0.0000.

Limitations: snapshots are observational and may be serially dependent; a ten-minute
dedupe is not decorrelation. Changed rapid refreshes still get stored. Unlike old
future design notes, Issue #7 explicitly uses snapshot windows, not daily aggregates.
MW assumes independent samples and tests distributions, not only medians unless
shapes are comparable. Small/tied samples make this normal approximation coarse.
No multiple-item testing correction is applied. Treat p as descriptive approximate
evidence with count/age guards, not calibrated certainty or causal manipulation proof.

## 13. Descriptive signals and reports

| Fact | Exact rule |
|---|---|
| CHEAP_VS_HISTORY | Mature 30d percentile <=20 |
| EXPENSIVE_VS_HISTORY | Mature 30d percentile >=80 |
| NORMAL_RANGE | Percentile strictly between 20 and 80 |
| RISING | Available robust 7d trend >+2%/day |
| FALLING | Available robust 7d trend <-2%/day |
| STABLE | Trend within inclusive [-2,+2]%/day |
| LOW_SUPPLY | Current/7d median quantity <=0.6 |
| HIGH_SUPPLY | Ratio >=1.6 |
| NORMAL_SUPPLY | Ratio strictly between 0.6 and 1.6 |
| Volatility LOW/NORMAL/HIGH | Own-return rules in section 11 |

Missing facts propagate UNKNOWN/INSUFFICIENT, never a fabricated NORMAL state.
The pure signal result includes a short descriptive enum summary. Report includes
configured items only: RISING sorted by descending trend, CHEAP historical
position, HIGH unusual returns, and combined meaningfulMove. Failed items are
omitted from those sections. Maturity summary includes all configured items.
These labels are observations, never BUY/SELL commands, profitability ranks or
sale price recommendations.

## 14. Remaining limits

Two or three daily scans are the intended cadence. Fast refreshes can overweight
short periods despite dedupe, while sparse days limit window coverage. Retention
can erase the age needed for 30d maturity under very heavy sampling. An insufficient
current-scan anomaly model is preserved; historical robustness cannot establish
that every underlying auction observation was clean. Realm/faction sharing,
full-result completeness and MP-05 client persistence remain beta checks.
Historical metrics are cached as of each item's last scan; UI age changes only on
UI/events, with no timer or OnUpdate. The optional 7d sparkline is deferred.
