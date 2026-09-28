# MarketPilot

Private, lightweight WoW Forever market-intelligence terminal for Mining,
Herbalism and Skinning commodities.

## MP-05 — gathering market watch (0.5.2)

Starting from the validated MP-03 side panel:

```text
Open AH -> Scan Gathering Markets -> robust Statistics -> compact account-wide history
        -> trend / change / percentile / volatility / supply / significance
        -> market watch, selected-item detail and Market Report
```

This branch has no Sale Assistant, Inventory, Pricing or posting workflow.
No buying, selling, mail automation or whole-AH scan. MP-04/MP-04B are not its base.
The user remains the decision maker; signals are descriptive observations.

Open AH and click **Scan Gathering Markets**. The catalogue covers 56 Classic
materials in Mining, Herbalism and Skinning. Filter by category, browse six rows
per page, and use **Current**, **History** or **Market Report** for detail.
Away from AH, `/mp watch` opens stored history read-only; `/mp report` opens the
stored report directly. No login/background scan starts automatically.

For a model preview, use **30d Demo** or `/mp demo on`. It generates 30 days of
simulated markets in memory and renders them through the same statistics,
history and report modules. The DEMO banner stays visible; scanning is disabled.
**Exit demo** or `/mp demo off` restores the real market. Reload also discards the
demo. Real saved history is never seeded or replaced. See [expected demo results](docs/DEMO.md).

Missing values use plain labels: **No scan**, **No price**, **Needs history** and
**Failed**. A dash in a historical column means more observations are needed.
Missing prices never become zero. Technical state names remain in debug output.

Install the complete `src/MarketPilot/` folder into the client's `Interface/AddOns/`,
or run `python tools/package.py` and extract the ZIP's `MarketPilot/` folder there.
See [production instructions and beta checklist](src/README.md),
[architecture/schema](docs/ARCHITECTURE.md), [exact model](docs/MARKET_MODEL.md),
and [confirmed versus unknown beta behavior](docs/API_FINDINGS.md).
The original five-item batch is live-validated. On 2026-09-28, the client also wrote
ten complete snapshots plus the diagnostic canary to disk, and the user's
post-reload check retained all ten snapshots and latest prices. The expanded catalogue,
new panel layout and timeout handling still need client checks; see the checklist.

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

From the repository root:

```text
python tools/test.py
```

The runner selects Lua 5.1 (or an installed `lupa.lua51`) and runs every production,
persistence and probe suite in a fresh runtime. Individual `*_spec.lua` files can
also be run with Lua 5.1. GitHub Actions runs the same checks and builds the clean
TOC-only addon package. No Python or external Lua library is bundled in the addon.
