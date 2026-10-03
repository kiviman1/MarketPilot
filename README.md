# MarketPilot

Lightweight WoW Forever market-intelligence addon for Mining,
Herbalism and Skinning commodities.

## Market Watch (0.5.9)

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
per page, and use **Summary**, **History** or **Market Report** for detail.
With AH open, clicking a material refreshes its analysis and then opens its
normal name search in Blizzard's Browse Auctions list, using the same search
method and current filter/level settings as Blizzard's Search button. The two requests run in
sequence. Batch scans and the Refresh button do not navigate Blizzard's list.
**Market Summary** explains the recorded scan in Summary; **Historical Context**
explains supported comparisons in History. Both disclose missing data and scan
age above the metric cards. Prices use native gold/silver/copper
icons while preserving exact copper and fractional historical medians.
Away from AH, click the **minimap icon** or use `/mp watch` for stored history;
drag its title to move the read-only window. `/mp report` opens the stored report.
Right-click the minimap icon, click **Settings**, or use `/mp settings` for an
independent settings window. Adjust Watch size (80–120%), choose its start
category, lock window positions, toggle detailed scan logs, hide/show the icon,
or reset window positions. Scroll with the mouse wheel; redundant Up/Down buttons
have been removed. The named launcher supports the installed EllesmereUI icon
container and leaves its layout under that container's control.
Market Watch renders above normal action bars and unit frames, with Settings above
the watch. AH opens the usual attached scan panel; closing AH returns an explicitly opened
watch to its saved standalone position. No login/background scan starts automatically.

Runtime demo mode has been removed. Synthetic month-long market scenarios remain
offline regression fixtures only; the addon always displays real observations.

The redesigned terminal uses dark surfaces, gold active tabs, a selected-row
accent, category counts and a four-column metric grid. Market Report has four
separate cards and a maturity distribution bar. The **30d %** column remains a
price percentile, not a price-change percentage; its heading has an explanatory
tooltip. Long summaries, metric values and report entries expand vertically.
The viewport fits the available screen height; the mouse wheel reaches all content.

## Development testing

Private AHledger integration is available through the separate **MarketPilot
Sync** desktop companion and the addon's read-only **AHledger** tab. Select a
market explicitly, update, then `/reload` → `/mpdev external` in the dev addon.
Provider prices/history remain separate from local scans and SavedVariables.
See [setup, data contract and checks](docs/AHLEDGER_SYNC.md). Public release
packaging is not part of this development task.

Keep the CurseForge-managed `MarketPilot/` installation intact. Generate a
development copy from this same source with:

```powershell
python tools/package.py --dev-dir "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\MarketPilotDev"
```

This creates `MarketPilotDev.toc`, the **MarketPilot Dev** title, `/mpdev`
commands, a distinct named minimap button, dev asset paths and account-wide
`MarketPilotDevDB`. Release history/settings are never copied or migrated.
Dev initially has its own empty history. Enable only the dev addon while testing
AH scans to avoid overlapping panels or simultaneous requests. A newly installed
addon folder may require returning to character selection or restarting the client.
Use `/mpdev watch` and `/mpdev settings` for the independent windows.
The dev option creates no ZIP. Ordinary release packaging keeps the original
`MarketPilot` identity and excludes dev-only files. Build releases only when requested.

Missing values use plain labels: **No scan**, **No price**, **Needs history** and
**Failed**. A dash in a historical column means more observations are needed.
Missing prices never become zero. Technical state names remain in debug output.

Install the `MarketPilot/` folder from `MarketPilot-0.5.9.zip` into the client's
`Interface/AddOns/`. The archive contains only the addon runtime and its icon;
existing account history and settings are not bundled or replaced.
Build the upload archive from this checkout with `python tools/package.py`.
The resulting file is `dist/MarketPilot-0.5.9.zip`; see the
[release notes](docs/RELEASE_NOTES_0.5.9.md) for changes since 0.5.5 and the upload changelog.
The upload logo is [assets/MarketPilot-CurseForge.png](assets/MarketPilot-CurseForge.png),
a 512 x 512 PNG exported from the addon's own vector mark. Recreate it without an
addon build using `python tools/render_icon.py --png-only --size 512 <output.png>`.
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
also be run with Lua 5.1. GitHub Actions runs the same checks and validates the
source manifest with `python tools/package.py --check`; neither check creates a
build/package. No Python or external Lua library is bundled in the addon.
