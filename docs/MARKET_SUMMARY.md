# Market Summary

Market Summary explains existing observations. It does not estimate a new price,
classify auctions again, predict a trade, or change what is saved. Current keeps
the technical current-scan table below **Market Summary**. History keeps its
technical table below **Historical Context**. Market Report is unchanged.

## Data and rendering contract

`MarketInsight.Build(data, context)` is a pure Lua reader. `data` is the existing
`Market:Get(selectedItemID)` result:

```text
current = compact recorded snapshot, or nil
analytics = existing HistoricalAnalytics result
signals = existing MarketSignal result
history = existing snapshot list
lastScan = optional session scan time
error = optional per-item update error
```

The caller supplies `{ itemID, scannerItemID, scannerState, now }` in `context`.
The result contains `itemID`, `current`, and `history`; the two latter
fields are ordered message lists. Each message has a `code` and named values.
Missing-metric lists contain enums. `UIViewModel.Insight` formats those messages
into `{ current = <text>, history = <text> }`, with English sentences and
copper-denominated display text. For example, `REFERENCE_BAND` carries `price`,
`q1`, and `q3`; `LOWEST_BELOW` carries `price` and unrounded `change`;
`ANOMALY_COUNTS` carries `suspicious` and `extreme`. The module never changes its
input, reads WoW state, starts scans, calls Auction House APIs, or writes history.

The snapshot has no item ID: UI fetches it using the selected item ID and binds
that selection to the context. A scanner working on another item cannot supply
this item's facts or failure state. Both AH and standalone modes use the same
input and formatter. An event/render refresh updates the text; there is no timer
or `OnUpdate` loop.

Age refers to `current.t`, the retained observation timestamp. A later deduped
scan's session-only `lastScan` does not make an older historical observation look
new. Descriptions are explicitly about recorded scans, including when AH is open.
Unknown/future timestamps do not become a zero-age claim.

## Sentence rules

The only new market arithmetic is:

```text
lowestVsReferencePct = 100 * (lowest / cleanMedian - 1)
```

Both inputs must be valid positive prices and the result finite. Keep precision
until display formatting. All historical change, percentile, trend and supply
values come from the existing analytics result. Existing signal thresholds below
are documented for consistency checks, not a new statistical model.

The first current paragraph describes the scan reference (`cleanMedian`), central
band (`q1` to `q3`), observed lowest price, and listed units (`totalQuantity`).
The central band is not all or most supply, and discrete weighted quartiles do
not guarantee exactly half the units lie inside it. Listed units are not sales,
traded volume, demand, sellers, or independent samples.

Quality notes say unusual levels were retained and extreme levels were excluded.
Zero exclusions does not establish a manipulation-free market. Equal raw and
clean medians do not establish clean data. A false or unavailable anomaly model
gets a limitation note; price-level count never creates a confidence score.

Historical statements qualify each metric separately. A ready maturity label
cannot authorize an unavailable metric. No historical price/supply statement is
inferred just from today's median, quantity, or an unrecognized signal. Unsupported
parts are named without discarding independently usable facts.

If a numeric historical result is valid but its signal label is absent or
contradictory, retain the numeric result and explicitly say its label is
unavailable. Do not manufacture a replacement direction or classification.

## Actual generated examples

The following plain-text examples were generated for 0.5.8. From 0.5.9, the same
sentences render native gold/silver/copper icons in place of currency letters;
these readable transcripts retain the letters. The band separator now has
spaces around the dash. Values, sentence rules and the pure insight contract
are unchanged. Historical half-copper medians also retain their fraction next
to the copper icon.

These are outputs of `UIViewModel.Insight(MarketInsight.Build(...))`, with
`current.t=4000000` and `context.now=4000120`, not sample prose assembled by hand.
The requested 27c reference, 20c–28c band, 18c lowest, 3,145 units, 21 levels,
four suspicious levels and zero extreme levels generate:

```text
The latest recorded scan's reference price is 27c, with a central price band of 20c-28c.
The lowest listed price is 18c, about 33.3% below that reference.
This scan covers 3,145 listed units.
4 unusual price levels were retained; no price levels were excluded.
More history is needed to judge whether this price and listed quantity are high or low for this market.
Latest recorded scan: 2 minutes ago.
```

With no current snapshot, the Current and History texts both contain:

```text
No scan recorded for this item.
```

With that same snapshot, a supported 7d median of 40c, existing change of −32.5%,
existing rising trend, quantity median of 6,290 and supplied ratio of 0.5, but an
insufficient 30d window, the History text is:

```text
The recorded reference price is 32.5% below its 7-day median.
The available observations show a rising price trend.
Listed supply in this scan is below its recent usual level (0.50x its 7-day median).
More history is needed for: 30-day price position.
Latest recorded scan: 2 minutes ago.
```

If the selected item's new scan is in `ERROR`, the existing factual summary and
its original age remain, preceded by:

```text
The new scan failed; showing the previous recorded scan.
```

A generic `data.error` can instead mean a persistence/update failure, so it does
not assert that a new commodity scan failed or that the snapshot must be older.
Its text is: “The latest update reported an error; the available scan observation
is shown below.” Malformed error metadata produces “The latest update status
cannot be assessed.”

## Scenario matrix

Deterministic model and formatter scenarios live in
[`tests/market_insight_spec.lua`](../tests/market_insight_spec.lua). The test names
in the last column are stable scenario IDs.

### Current price and quantity

| Situation | Sentence rule | Test |
|---|---|---|
| Reference 27c, band 20c–28c, lowest 18c, 3,145 units | Explain the recorded reference/band, about 33.3% below reference, and 3,145 listed units; preserve the unrounded ratio internally. | `CURRENT_REFERENCE_BELOW` |
| Lowest equals reference | Say they match; do not claim a discount. | `CURRENT_REFERENCE_EQUAL` |
| Invalid reference, nonfinite or nonpositive input | Withhold the unsupported comparison and identify the unavailable part; preserve other valid facts. | `CURRENT_REFERENCE_INVALID` |
| Invalid/missing lowest price | Keep the valid reference and quantity without a lowest-price comparison. | `CURRENT_LOWEST_INVALID` |
| Lowest exceeds the reference | Preserve individual values but flag their inconsistent relationship; do not describe a discount or premium. | `CURRENT_INCONSISTENT_LOWEST` |
| Missing or unordered central band | Keep a valid reference/lowest/quantity; do not invent a range. | `CURRENT_INVALID_BAND_PRESERVES_FACTS` |
| Missing/invalid quantity | State quantity cannot be assessed; never replace it with zero. | `CURRENT_INVALID_QUANTITY` |
| Nonzero difference smaller than 0.1% | Say less than 0.1%; do not round into a zero discount or equality claim. | `CURRENT_TINY_DIFFERENCE` |

### Historical price position and change

| Situation | Sentence rule | Test |
|---|---|---|
| Available negative 7d change | State the supplied percent below its 7-day median; this is not a claim about a historical range. | `HISTORY_CHANGE_NEGATIVE` |
| Available zero 7d change | State equal to its 7-day median; no upward/downward move. | `HISTORY_CHANGE_ZERO` |
| Available positive 7d change | State the supplied percent above its 7-day median. | `HISTORY_CHANGE_POSITIVE` |
| Change contradicts reference/median direction or is invalid | Withhold the change statement; keep unrelated historical facts. | `HISTORY_CHANGE_INVALID` |
| Tiny nonzero 7d change | Say less than 0.1% above/below instead of a zero move. | `HISTORY_CHANGE_TINY_DIFFERENCE` |
| Available 30d window, percentile 0–20 and `CHEAP_VS_HISTORY` | Describe a low position among recorded 30-day prices, with the supplied percentile; no bargain or buying claim. | `PRICE_LOW` |
| Available 30d window, percentile strictly between 20 and 80 and `NORMAL_RANGE` | Describe the middle of recorded 30-day prices; no price-fairness claim. | `PRICE_NORMAL` |
| Available 30d window, percentile 80–100 and `EXPENSIVE_VS_HISTORY` | Describe a high position among recorded 30-day prices; no selling instruction. | `PRICE_HIGH` |
| Missing/insufficient/invalid 30d window or percentile | Name the unavailable price-position assessment; do not classify using maturity alone. | `PRICE_UNAVAILABLE` |
| Exact percentile boundaries 20 and 80, plus immediately interior values | Accept only the existing label that agrees with its supplied percentile. | `PRICE_BOUNDARIES` |
| Valid percentile but missing/contradictory label | Show the numeric percentile; say the price-position label is unavailable. | `HISTORY_LABEL_CONTRADICTIONS_PRESERVE_NUMBERS` |

### Trend

| Situation | Sentence rule | Test |
|---|---|---|
| Available 7d trend, `RISING`, greater than +2%/day | Available observations show a rising trend; no prediction that prices will rise next. | `TREND_RISING` |
| Available 7d trend, `STABLE`, inclusive −2% to +2%/day | Available observations show a stable trend; this does not promise a fixed price. | `TREND_STABLE` |
| Available 7d trend, `FALLING`, less than −2%/day | Available observations show a falling trend. | `TREND_FALLING` |
| Missing/insufficient/invalid trend | Trend cannot yet be assessed; keep any usable price/supply statement. | `TREND_UNAVAILABLE` |
| Exact −2 and +2%/day boundaries | Both remain stable under the existing signal rule. | `TREND_BOUNDARIES` |
| Valid numeric trend but missing/contradictory label | Show the supplied numeric estimate; say the direction label is unavailable. | `HISTORY_LABEL_CONTRADICTIONS_PRESERVE_NUMBERS` |

The 7d trend describes available observations in that window; it can be available
during `EARLY`. Do not require a full week merely because the window is seven days.

### Listed supply

| Situation | Sentence rule | Test |
|---|---|---|
| Available 7d quantity comparison, `LOW_SUPPLY`, ratio ≤0.6 | Listed supply is below its recent usual level, with the supplied ratio. | `SUPPLY_LOW` |
| Available comparison, `NORMAL_SUPPLY`, ratio strictly between 0.6 and 1.6 | Listed supply is near its recent usual level. | `SUPPLY_NORMAL` |
| Available comparison, `HIGH_SUPPLY`, ratio ≥1.6 | Listed supply is above its recent usual level. | `SUPPLY_HIGH` |
| Missing/insufficient comparison or invalid denominator/ratio | Supply relative to history cannot be assessed; a valid listed-unit count remains factual. | `SUPPLY_UNAVAILABLE` |
| Exact ratios 0.6 and 1.6, plus immediately interior values | Accept only labels agreeing with the existing inclusive low/high boundaries. | `SUPPLY_BOUNDARIES` |
| Valid supply ratio but missing/contradictory label | Show the supplied ratio; say the supply label is unavailable. | `HISTORY_LABEL_CONTRADICTIONS_PRESERVE_NUMBERS` |

Supply is listed quantity relative to the existing 7d median quantity. It never
establishes sold volume, liquidity, scarcity caused by demand, or future prices.

### Anomalies and data sufficiency

| Situation | Sentence rule | Test |
|---|---|---|
| Sufficient model, zero suspicious/extreme | Say no unusual levels were retained and no price levels were excluded; no proof of clean data. | `ANOMALY_ZERO` |
| Valid suspicious count >0 | Explain those unusual price levels were retained; use singular/plural correctly. | `ANOMALY_RETAINED` |
| Valid extreme count >0 | Explain those price levels were excluded from the reference calculation. | `ANOMALY_EXCLUDED` |
| `anomalySufficient=false`, including few distinct prices or unusable spread | Show valid observed descriptors and state reliable outlier filtering is unavailable. Do not invent a reason absent from the snapshot. | `ANOMALY_INSUFFICIENT` |
| Missing/nonboolean sufficiency, invalid counts, or internally inconsistent anomaly facts | Mark the anomaly interpretation unavailable; preserve independent price and quantity facts. | `ANOMALY_INVALID` |
| No usable historical metrics | Explain more history is needed to judge historical price and listed quantity; do not promise readiness after N scans. | `CURRENT_REFERENCE_BELOW`, `HISTORY_METRIC_STATUS_BEATS_MATURITY` |
| A metric is ready but another is not | Show the ready result and name only the unavailable part; maturity never replaces metric status. | `MIXED_7D_WITHOUT_30D` |
| Maturity and metric status disagree | Use each metric's status, never maturity as a substitute. | `HISTORY_METRIC_STATUS_BEATS_MATURITY` |
| Missing quantity but usable price/trend/percentile | Keep the independent historical facts and withhold the supply comparison. | `INDEPENDENT_HISTORY_FIELDS` |

### Required mixed cases

These are simultaneous facts, not mutually exclusive labels.

| Situation | Combined sentence rule | Test |
|---|---|---|
| Low historical price + rising trend | Show both low 30d position and rising observed trend; do not cancel either or predict a rebound. | `MIXED_LOW_RISING` |
| Low supply + falling trend | Show both low listed supply and falling observed trend; do not infer demand or a future rise. | `MIXED_LOW_SUPPLY_FALLING` |
| 7d ready + 30d insufficient | Keep supported 7d change, trend and supply; explain the missing 30d position. | `MIXED_7D_WITHOUT_30D` |
| Extreme excluded + unchanged raw/clean median | Report exclusions even though the displayed medians match; do not say filtering was unnecessary or data was clean. | `MIXED_EXCLUSION_UNCHANGED_MEDIAN` |
| New scan failed + old saved record | Explicitly identify the previous recorded observation, retain its original age/facts, and disclose the unsuccessful update. | `MIXED_FAILED_NEW_STORED` |

### Missing, stale and inconsistent records

No snapshot produces **“No scan recorded for this item.”** A valid empty snapshot
produces **“No price levels returned in the latest scan.”** An empty response is
not proof that the entire market has no items. Invalid fields never turn into
zero-price facts. Unknown or contradictory historical labels never yield an
invented explanation. A retained record remains a retained record while another
scan is running, after a failed update, and outside the AH.

| Situation | Sentence rule | Test |
|---|---|---|
| No snapshot, with or without a failed first scan | State no scan is recorded; disclose failure separately when supported. | `NO_RECORD` |
| Valid empty snapshot | State that this scan returned no price levels; never substitute the previous price. | `EMPTY_SCAN` |
| Unreadable/malformed snapshot | Say the record or individual fields cannot be assessed; do not call it an empty successful scan. | `INVALID_RECORD` |
| Zero levels/units contradict positive recorded prices | Disclose inconsistent fields and suppress affected comparisons; preserve an independently available trend. | `INCONSISTENT_EMPTY_RECORD` |
| Generic update error with a valid observation | Disclose the update error without assuming an older observation or a failed commodity scan. | `FAILED_UPDATE_IS_NOT_ALWAYS_OLD_SCAN` |
| Malformed error metadata | Mark update status unassessable; do not invent a failure. | `INVALID_ERROR_METADATA` |
| Scanner error belongs to another item | Ignore that error for the selected item's explanation. | `OTHER_ITEM_ERROR_DOES_NOT_LEAK` |
| Missing/future time or normal minute/hour/day age | Show the supported age or explicitly unavailable clock information. | `TIMESTAMP_AND_FUTURE_CLOCK` |
| Newer session-only deduped scan time | Keep the retained snapshot's age. | `DEDUPE_TIME_STAYS_RECORDED_TIME` |
| Repeated generation | Return identical detached messages without changing any input or calling client/persistence APIs. | `PURE_DETERMINISTIC_AND_INPUTS_UNCHANGED` |

Additional regression coverage checks selection isolation, matching AH/standalone
text, immutable repeated rendering, stored-history preservation, no standalone
queries, and wrapped text/scroll reachability at the existing supported scales.

These checks are in [`tests/ui_spec.lua`](../tests/ui_spec.lua):

| Integration rule | Deterministic test name |
|---|---|
| Default Current summary and technical tables remain visible; History uses its own title/text; Report stays separate | `summary is visible by default and preserves raw statistics` |
| Switching selection never leaks the previous item's description or queries outside AH | `summary selection uses only the selected item and never starts a standalone query` |
| Mode alone cannot change a stored observation's explanation | `stored summary is identical in standalone and AH modes` |
| Repeated renders/reload preserve data and reuse existing analytics | `summary survives reload and repeated rendering without writes or analytics reruns` |
| Failed refresh keeps old facts explicitly dated; another selected item does not inherit the error | `failed refresh keeps previous summary explicitly dated` |
| Measured wrapped height keeps tables below text, with full mouse-wheel access at 80–120% scale | `wrapped summaries stay above raw tables at all supported scales` |
| A successful empty result replaces the old nonempty description | `summary switches to empty observation after successful empty refresh` |

## Validation and client checks

```text
python tools/test.py
python tools/package.py --check
```

In client, inspect Current and History for a known item, switch items, scroll to
the raw tables, and repeat at 80% and 120% scale. Open `/mp watch` outside the AH
and confirm it explains the same saved observation without scanning. Test an
unscanned item and an empty result when available. After a failed scan, confirm
the previous record is identified clearly. Actual font wrapping and the new
summary's client behavior require this visual check; offline tests do not claim
they were observed in game.

SavedVariables schema, retained records, dedupe, retention, gathering catalogue,
statistical thresholds, historical algorithms, and scanner behavior are unchanged.
