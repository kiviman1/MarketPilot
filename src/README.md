# MarketPilot — MP-01 single-item vertical slice

Copy `src/MarketPilot/` into the beta client's `Interface/AddOns/` directory.
Enable MarketPilot and open AH after login (or close/reopen it after `/reload`).
The TOC retains the probe's provisional interface value `16001`; the actual build
and interface remain UNKNOWN. Compare `/dump GetBuildInfo()` before changing it,
or enable loading out-of-date addons if needed for this beta test.

Only these production files are part of MP-01, in TOC load order:

```text
MarketPilot.toc
Items.lua
AuctionAPI.lua
Scanner.lua
Core.lua
```

`Core` wires events and `/mp` commands to `Scanner`. `Items` configures only
Copper Ore (2770). `Scanner` calls `AuctionAPI`, the sole production compatibility
boundary, and owns a single in-memory sample:

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
summaries only. Samples are cleared on new scans and AH close; reload clears all
production state. There is no persistence, statistics model, pricing, UI, full
item list, paging, automatic buying/posting, timers or per-frame polling.

There is no automatic timeout/retry: if no result or ready event arrives, status
remains QUERYING/WAITING; close/reopen AH to cancel. Result completeness/paging and
request identity remain UNKNOWN. Do not query the same item concurrently through
the probe, default AH UI or another addon during validation: a late/concurrent
same-item event cannot be distinguished without a verified request identifier.
`auctionID` is not read or used. The first matching update completes the scan;
subsequent updates are ignored until another manual scan.

## Offline tests

Run from repository root with Lua 5.1:

```text
lua tests/marketpilot_spec.lua
lua probe/tests/probe_spec.lua
```

The production suite includes TOC and static boundary/scope checks. Fixtures do
not establish new beta facts. Reported probe `/reload` persistence is confirmed;
logout + character-switch persistence is deferred/unverified, not an MP-01 blocker.

## In-game checklist (not yet performed for production)

1. Open AH and run `/mp status`: expect IDLE and itemID 2770.
2. Run `/mp scan`: expect one query, or WAITING until the system-ready event.
3. Confirm DONE, the count of all currently available Copper Ore price levels,
   total quantity and minimum/maximum copper prices against the visible AH data.
   For a 2 silver/unit level the raw unitPrice is 200; no conversion is applied.
4. Run `/mp status` again. A scan already pending must not send another query.
5. Close AH: expect IDLE with no retained sample. Reopen and repeat one scan;
   the session query count should increase by exactly one.
6. Return debug output/errors and live build/interface. Production behavior remains
   unverified until this checklist is actually performed in the beta client.
