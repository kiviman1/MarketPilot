# AGENTS.md

Instructions for Codex and any automated coding agent working in this repository.

## Project intent

MarketPilot is a private, lightweight WoW Forever Auction House analysis addon. It should help us understand gathering-material markets without turning into a large Auction House framework.

## Non-negotiable engineering rules

1. **Small tasks only.** Make the minimum change required for the active task. Do not combine bug fixes, refactors, UI work, and new features unless the task explicitly requires it.
2. **No speculative API assumptions.** WoW Forever beta behavior must be verified in-client. If an API/event/field is not confirmed, keep it behind the probe or `AuctionAPI` boundary and document it as unknown.
3. **Preserve UNKNOWN.** Do not silently infer missing Auction House data or fabricate a price from incomplete results.
4. **Single responsibility.** Scanner scans, Statistics calculates, Database stores, Pricing interprets, UI renders.
5. **No direct AH calls outside `AuctionAPI`.** This is the compatibility seam for Forever beta changes.
6. **No framework dependency by default.** Do not add Ace3 or third-party libraries unless specifically requested and justified.
7. **No automation of protected gameplay actions.** No automatic buying, selling, posting, mailing, movement, or other actions requiring player input.
8. **No busy polling.** Prefer events and throttle-ready signals. Avoid per-frame Auction House logic.
9. **Keep SavedVariables compact.** Do not persist raw full-market scans unless a task explicitly requires it. Persist compact snapshots.
10. **No destructive migrations.** SavedVariables schema changes require a schema version and an explicit migration or safe reset path.
11. **No broad cleanup.** Do not rename/reformat unrelated code while implementing a scoped task.
12. **Tests where practical.** Pure statistical/price logic should be testable outside WoW with deterministic Lua fixtures.

## Development deployments and CurseForge releases

The user installs the public addon through CurseForge. Preserve that installation.

- Future in-game development copies must use a separate `MarketPilotDev/` folder
  and an unmistakable `MarketPilot Dev` addon title; never overwrite the
  CurseForge-managed `MarketPilot/` folder during development.
- Before the next development deployment, implement and verify the dev identity:
  matching TOC name, addon/asset paths, isolated SavedVariables (such as
  `MarketPilotDevDB`), slash commands (such as `/mpdev`), and named global frames.
  Renaming the directory alone is not sufficient. This workflow rule does not
  mean that a dev packaging mode already exists.
- Keep dev data separate from release history/settings. Do not copy, migrate,
  reset or delete the user's release data without an explicit request.
- Avoid simultaneous AH scans from the dev and release addons during testing.
- CurseForge release ZIPs retain the normal `MarketPilot/` folder, title,
  commands, asset paths and `MarketPilotDB` identity. Exclude dev-only artifacts.
- Generate development/release variants from the same source; do not maintain
  a second manually edited addon tree. Build a release only when requested.

## Current task gate

The production addon must not be implemented past the documented scaffold until MP-00 confirms the actual Forever beta Auction House behavior.

The first milestone is the isolated `probe/MarketPilotProbe` addon. It should answer:

- Which candidate `C_AuctionHouse` functions exist?
- Which Auction House events can be registered and which actually fire?
- Can a gathering item be queried while the AH is open?
- What result structure is returned for commodity and/or item searches?
- Is a throttle-ready signal exposed and required between queries?
- Does account-wide SavedVariables data survive logout/character switch?
- What are the live build and interface values?

## Planned production modules

```text
MarketPilot/
  Core.lua
  AuctionAPI.lua
  Items.lua
  Scanner.lua
  Statistics.lua
  Database.lua
  Pricing.lua
  UI.lua
```

Dependencies should flow in one direction. Avoid cyclic module references.

## Statistics rules

Read `docs/MARKET_MODEL.md` before implementing any price calculation. In particular:

- Use unit prices, never raw stack prices.
- Do not use arithmetic mean as the primary market reference.
- Detect anomalies on log prices using robust methods.
- Treat statistical significance and practical price movement as separate requirements.
- Low sample counts must lower confidence rather than produce false precision.

## Required completion note for each task

When finishing a Codex task, report:

- files changed;
- behavior added/changed;
- assumptions still unverified;
- tests/static checks run;
- in-game checks still required;
- any SavedVariables schema impact.

Do not claim an in-game behavior was validated unless it was actually observed in the client.
