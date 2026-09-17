# Beta Test Plan — MP-00

Purpose: verify the actual WoW Forever beta Auction House surface before production code is written.

## Test 0 — addon loads

1. Copy `probe/MarketPilotProbe` into the Forever beta AddOns folder.
2. Enable it on the character screen.
3. Log in.
4. Run:

```text
/mpprobe status
```

Record the reported client version/build/interface and API availability.

If the client marks the addon out of date, first compare the live interface value printed by `GetBuildInfo()` with the `.toc`. Update the `.toc` only after confirming the live value.

## Test 1 — AH event surface

1. Log onto the parked AH character.
2. Open the Auction House.
3. Confirm the probe logs `AUCTION_HOUSE_SHOW`.
4. Close it and confirm `AUCTION_HOUSE_CLOSED`.
5. Note which throttle/result events the probe was able to register.

Pass condition: AH open/close is observable and at least one result path can be identified.

## Test 2 — one-item query

With the Auction House open:

```text
/mpprobe scan 2770
```

The initial test item is Copper Ore only because it is a familiar gathering item. If Forever changed/removed the ID or the market has no data, repeat with a known gathering item ID visible in the beta client.

Record:

- whether `MakeItemKey` exists/works;
- whether `SendSearchQuery` exists/works;
- which result event fires;
- whether the result is treated as a commodity or normal item;
- returned row count;
- primitive fields present on the first few result rows;
- any Lua error or throttle error.

Do not "fix" mismatched signatures by guessing. Capture the failure first.

## Test 3 — price/quantity semantics

Compare 2–3 visible AH rows with the probe output.

We need to establish whether returned values mean:

- integer copper per unit;
- total stack price;
- aggregated quantity at a price level;
- one auction per result;
- another Forever-specific structure.

Pass condition: at least one visible market row can be reconciled with API output.

## Test 4 — throttle behavior

Run two or three different gathering-item queries manually, waiting for result/ready events between them.

Record:

- whether queries can be sent back-to-back;
- whether a throttle-ready event fires;
- whether `IsThrottledMessageSystemReady` exists and changes state;
- whether the client rejects or queues premature queries.

No stress test. We only need enough information to build an event-driven queue.

## Test 5 — SavedVariables across characters

1. On the AH alt, run at least one probe query.
2. Log out normally.
3. Log onto the main character.
4. Run:

```text
/mpprobe dump
```

Pass condition: the saved probe/build/query summary is visible on the second character.

This confirms account-wide persistence for the planned AH-alt workflow.

## Test 6 — reload persistence

After a successful query:

```text
/reload
/mpprobe dump
```

Pass condition: saved summary survives reload.

## Evidence to return

Copy the chat output from:

```text
/mpprobe status
/mpprobe dump
```

plus any Lua error text. Screenshots of the queried AH item are useful when price semantics are unclear.

Update `docs/API_FINDINGS.md` only with behavior actually observed in-client.

## Exit criteria for MP-00

Do not start the production scanner until these are known:

- live client interface/build;
- usable query function/signature;
- result event(s);
- result-read function/signature;
- price and quantity semantics;
- throttle/ready behavior;
- account-wide SavedVariables behavior.
