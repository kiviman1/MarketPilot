# MarketPilot — MP-02 current-scan statistics

Copy `src/MarketPilot/` into the beta client's `Interface/AddOns/` directory.
Enable MarketPilot and open AH after login (or close/reopen it after `/reload`).
Interface `16001` was confirmed on Forever beta 1.60.1 build 69893. If testing a
newer build, compare `/dump GetBuildInfo()` before changing the TOC.

Production files in TOC load order:

```text
MarketPilot.toc
Items.lua
AuctionAPI.lua
Statistics.lua
Scanner.lua
Core.lua
```

`Core` wires events and `/mp` commands to `Scanner`. `Items` configures only
Copper Ore (2770). `Scanner` calls `AuctionAPI`, the sole production compatibility
boundary, and owns a single in-memory sample plus a separate pure Statistics result:

```text
{ itemID = 2770, capturedAt = <timestamp>, priceLevels = {
    { unitPrice = <integer copper>, quantity = <integer quantity> }, ...
} }
```

## Behavior and boundaries

`IDLE -> WAITING -> QUERYING -> COLLECTING -> DONE`; errors enter `ERROR`,
and AH close cancels/resets to `IDLE`. `/mp scan` starts one manual request.
`WAITING` advances only when readiness is true, checking it on the initial command
and the confirmed system-ready event. Extra scan commands/ready events cannot send
a second in-flight query. Missing/non-boolean readiness is ERROR/UNKNOWN.

Only matching commodity events while QUERYING can complete a scan. All currently
returned rows are read, in API order, with separate owned tables even when prices
repeat. No five-row cap, regrouping, conversion or rounding. Positive, finite,
exact integers are required for unitPrice/quantity; missing, zero, negative,
fractional, string or out-of-range values reject the entire sample as ERROR/UNKNOWN.
No partial sample is presented as complete. Zero result rows are a valid empty
sample with total quantity 0 and UNKNOWN lowest/highest prices.

`/mp status` and completion output show state, itemID, session query count, level
count, summed quantity and lowest/highest copper prices. These are debugging
summaries only. Samples/analysis are cleared on new scans and AH close; reload clears
all production state. There is no persistence, pricing, UI, full
item list, paging, automatic buying/posting, timers or per-frame polling.

There is no automatic timeout/retry: if no result or ready event arrives, status
remains QUERYING/WAITING; close/reopen AH to cancel. Result completeness/paging and
request identity remain UNKNOWN. Do not query the same item concurrently through
the probe, default AH UI or another addon during validation: a late/concurrent
same-item event cannot be distinguished without a verified request identifier.
`auctionID` is not read or used. The first matching update completes the scan;
subsequent updates are ignored until another manual scan.

## MP-02 analysis

On successful result collection, Scanner calls `Statistics.Analyze(sample)` once.
Raw rows remain intact. `scanner.analysis` retains raw and clean level count,
quantity, min/max and discrete quantity-weighted Q1/median/Q3, along with log-price
MAD/IQR metrics and annotated NORMAL/SUSPICIOUS/EXTREME rows. Output is deterministic
and has model version `MP-02-v1`; details and exact thresholds are in
`docs/MARKET_MODEL.md`.

The debug summary adds only `rawMedian`, `cleanMedian`, `suspicious`, `extreme` and
`anomalySufficient=yes/no`. Fewer than five distinct prices, or unusable MAD/IQR,
means INSUFFICIENT; raw/clean descriptors are still available and no EXTREME level
is removed. With sufficient data EXTREME requires both |modified Z| > 6 and a
3*IQR fence violation. SUSPICIOUS uses |Z| > 3.5 or a 1.5*IQR violation and stays
in all clean calculations. These are current-scan descriptions, not trade advice
or calibrated confidence. There is no history, p-value or pricing recommendation.

## Offline tests

Run from repository root with Lua 5.1:

```text
lua tests/marketpilot_spec.lua
lua tests/statistics_spec.lua
lua probe/tests/probe_spec.lua
```

The production suite includes TOC and static boundary/scope checks. Fixtures do
not establish new beta facts. Probe persistence and the MP-01 production query flow
were validated in-client; see `docs/API_FINDINGS.md`. MP-02 adds no persistence.

## In-game checklist (MP-02 integration not yet performed)

1. Open AH and run `/mp status`: expect IDLE and itemID 2770.
2. Run `/mp scan`: expect one query, or WAITING until the system-ready event.
3. Confirm DONE, the count of all currently available Copper Ore price levels,
   total quantity and minimum/maximum copper prices against the visible AH data.
   For a 2 silver/unit level the raw unitPrice is 200; no conversion is applied.
4. Check `rawMedian`, `cleanMedian`, `suspicious`, `extreme`, `anomalySufficient`.
   If the market still has two levels (such as the validated 199/200 copper snapshot),
   expect `anomalySufficient=no`, `extreme=0` and equal raw/clean medians. The median
   is either 199 or 200 according to cumulative quantities; the old total 472 alone
   does not determine it. Repeat `/mp status` without rescanning: analysis must stay
   unchanged. A scan already pending must not send another query.
5. Close AH: expect IDLE with no retained sample. Reopen and repeat one scan;
   the session query count should increase by exactly one.
6. If at least five distinct price levels naturally exist, record anomaly output
   and compare integer raw/clean prices with visible data. The absurd-price cases
   are offline fixtures; no test listing is needed. Return debug output/errors.
