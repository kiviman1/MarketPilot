# MarketPilotProbe — MP-00 only

Copy `MarketPilotProbe/` into the Forever beta `Interface/AddOns/` folder.
The `.toc` interface value is unchanged and **unverified**. If the addon is
out of date, obtain the live value with `/dump GetBuildInfo()` before changing
it. There are no addon dependencies; the TOC loads the support helpers first.

## Manual client checks

1. Run `/mpprobe status`. Record build/interface, candidate function presence,
   event registration results, fired counts and current throttle readiness.
2. Open AH; confirm `AUCTION_HOUSE_SHOW`. Run `/mpprobe scan 2770`, or substitute
   a gathering item ID actually present in this beta. Wait for a matching result.
3. Run `/mpprobe dump`. Compare the first 2–3 logged rows against visible AH rows.
   Record what quantity and price mean; the probe never derives a unit price.
4. Manually query two or three different materials, waiting for results/ready
   events. Record throttle transitions. Explicit `ready=false` blocks the query;
   missing/non-boolean readiness stays UNKNOWN and permits the manual diagnostic
   call. No retries, query queue, paging, buying, selling or stress testing.
5. Close AH; confirm `AUCTION_HOUSE_CLOSED`. After a successful observation,
   run `/reload`, then `/mpprobe dump`. Log out normally, switch from the AH alt
   to the main character and dump again. Confirm the original item, timestamp,
   build and samples survive. Do not clear the data between these checks.
6. Return status/dump output and errors, plus visible AH rows for comparison.
   Only actual beta observations may be added to `docs/API_FINDINGS.md`.

## What the probe records

- Seven candidate function presence checks; presence does not confirm signature.
- Registration success checked separately from actual event counts. A successful
  registration call alone stays UNKNOWN if registration cannot be inspected.
- All arguments of observed candidate events, with top-level primitive fields
  on table arguments. Nested tables/functions/userdata are not traversed.
- One manually requested item at a time, up to five result rows, all primitive
  fields sorted for readability. Missing `quantity`, `unitPrice` and `auctionID`
  print UNKNOWN; no stack-price conversion or inferred fields.
- Commodity/item **result path** from the matching event. Zero rows record an
  empty observation, not proof of the item's tradability or market semantics.
- Readiness before/after queries and on throttle/result events. Pending queries
  expire after 15 seconds when the timer is available; otherwise close/reopen AH
  to cancel. Closing AH also cancels pending correlation.

The existing candidate calls are deliberately unchanged:
`MakeItemKey(itemID)`, `SendSearchQuery(itemKey, {}, true)`, commodity count/row
with `(itemID)` / `(itemID, index)`, item count/row with `(itemKey)` /
`(itemKey, index)`, and `IsThrottledMessageSystemReady()`.
Their Forever signatures remain **UNKNOWN**. Failures are logged with the
original error; there is no alternative-signature fallback.

Use only the probe to initiate searches while testing. Events have no proven
request identifier: a concurrent default-AH/other-addon search for the same
item, or a late response after a repeat query, cannot be reliably distinguished.
Unrelated/malformed events are logged but not used as results. The first matched
event with a valid count and readable sample tables is saved; result completeness,
paging and further updates remain UNKNOWN. A successful observation is not MP-00
acceptance and does not confirm price semantics or server-side query acceptance
beyond the evidence shown.

## SavedVariables

Account-wide `MarketPilotProbeDB` now uses schema 2: current session surface/build,
last query attempt, last successful result observation with frozen session evidence,
and a rolling maximum of 200 log entries. A failed/timeout query never overwrites
`lastSuccess`. `/mpprobe dump` includes saved samples and recent logs.

Schema 1 is upgraded additively. Its old `build`, `lastQuery`, `lastResult` and
logs are retained; `lastResult` is labelled UNVERIFIED rather than promoted to
success. Unknown schemas are preserved and use an in-memory session until an
explicit `/mpprobe clear` resets the data. That existing command now resets to
schema 2. Actual disk persistence still requires the client checks above.

## Offline checks

From the repository root, with a Lua 5.1 interpreter:

```text
lua probe/tests/probe_spec.lua
```

The fixtures mock build, AH calls, events, timers and SavedVariables reload.
They check error paths, correlation, unknown values, sample/log bounds and schema
preservation. They do not establish any Forever API facts and are not loaded by
the addon.
