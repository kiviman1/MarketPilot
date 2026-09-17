# Production addon placeholder

Do not implement the production addon until MP-00 has confirmed the live Forever beta Auction House API and result semantics.

Planned files:

```text
MarketPilot.toc
Core.lua
AuctionAPI.lua
Items.lua
Scanner.lua
Statistics.lua
Database.lua
Pricing.lua
UI.lua
```

The first production commit after MP-00 should establish only the smallest working vertical slice:

```text
AH open
-> one configured item query
-> normalized result
-> compact in-memory statistics
-> debug output
```

Persistence, full item lists, pricing, and UI should follow in separate tasks.
