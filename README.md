# MarketPilot

Private, lightweight World of Warcraft Forever market-analysis addon for personal use.

## Goal

MarketPilot will scan only gathering-related Auction House markets (Mining, Herbalism/Cultivation, and Skinning), build a small local price history, reject obvious price anomalies, and show a robust reference price for selling gathered materials.

The project intentionally does **not** try to become a full Auction House suite.

## Current phase: MP-00

Before building the real addon, verify the live WoW Forever beta Auction House API inside the client.

The repository currently contains a small `MarketPilotProbe` addon. It is intentionally isolated from the future production addon so that API assumptions do not leak into the architecture.

### Probe install

Copy the `probe/MarketPilotProbe` folder into the WoW Forever beta AddOns directory, enable the addon, enter the game, and open an Auction House.

Useful commands:

```text
/mpprobe status
/mpprobe scan 2770
/mpprobe dump
/mpprobe clear
```

`2770` is used only as the initial Copper Ore test item. If that item is unavailable or changed in Forever, use another known gathering item ID.

## Planned architecture

```text
Core
 ├─ Scanner ──> AuctionAPI
 │    │
 │    └─> Statistics ──> Database
 │
 └─> Pricing ──> UI
```

Rules:

- WoW Auction House calls live only behind `AuctionAPI`.
- `Statistics` is pure Lua and does not call WoW APIs.
- `Database` stores data; it does not calculate prices.
- `UI` presents state; it does not send Auction House queries.
- No framework dependency unless a concrete need is proven.
- No automatic buying or selling.
- No whole-AH scan unless later testing proves it is necessary and safe.

See `AGENTS.md` and `docs/` before making code changes.

## Roadmap

1. **MP-00** — beta Auction House API probe.
2. **MP-01** — narrow gathering-item scanner.
3. **MP-02** — robust statistics: median, MAD, IQR, anomaly classification.
4. **MP-03** — account-wide SavedVariables and snapshot history.
5. **MP-04** — pricing/reference layer.
6. **MP-05** — small Auction House panel and `/mp` viewer.
7. **MP-06** — confidence and historical significance analysis after enough data exists.

## Scope

Private personal project. Optimize for correctness, low memory/CPU use, clear boundaries, and easy beta iteration rather than distribution or feature count.
