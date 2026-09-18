# MarketPilot

Private, lightweight WoW Forever market-intelligence terminal for Mining,
Herbalism and Skinning commodities.

## Current phase: MP-05

Starting from the validated MP-03 side panel:

```text
Open AH -> Scan Gathering Markets -> robust Statistics -> compact account-wide history
        -> trend / change / percentile / volatility / supply / significance
        -> market watch, selected-item detail and Market Report
```

This branch has no Sale Assistant, Inventory, Pricing or posting workflow.
No buying, selling, mail automation or whole-AH scan. MP-04/MP-04B are not its base.
The user remains the decision maker; signals are descriptive observations.

Install the complete `src/MarketPilot/` folder into the client's `Interface/AddOns/`.
See [production instructions and beta checklist](src/README.md),
[architecture/schema](docs/ARCHITECTURE.md), [exact model](docs/MARKET_MODEL.md),
and [confirmed versus unknown beta behavior](docs/API_FINDINGS.md).
MP-05 is tested offline; its new persistence, batch flow and dashboard still require
real Forever beta validation.

## Boundaries

- AH calls only in AuctionAPI; one event-driven Scanner query at a time.
- Statistics, HistoricalAnalytics, Significance and MarketSignal are pure Lua.
- Database writes compact versioned snapshots, never raw auction rows.
- UI consumes analysis; no per-frame processing or external framework.
- UNKNOWN/INSUFFICIENT is preserved. No automatic destructive schema reset.

Read `AGENTS.md` and the active GitHub issue before changing code. Completed
foundation: MP-00 isolated probe, MP-01 scanner, MP-02 robust statistics, MP-03
side panel. MP-05 is the new market-intelligence direction; live posting is not
part of it.

## Isolated probe

`probe/MarketPilotProbe` remains available for API diagnostics. Install separately;
commands: `/mpprobe status`, `/mpprobe scan 2770`, `/mpprobe dump`, `/mpprobe clear`.
Avoid concurrent same-item production/probe queries during validation.

## Tests

From repository root using Lua 5.1:

```text
lua tests/marketpilot_spec.lua
lua tests/statistics_spec.lua
lua tests/history_spec.lua
lua tests/ui_spec.lua
lua probe/tests/probe_spec.lua
```

Optimize for correctness, compact state, clear boundaries and easy beta iteration.
