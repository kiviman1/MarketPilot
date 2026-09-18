-- Deterministic pure Lua 5.1 fixtures; no client API or external library required.
local MP, DAY = {}, 86400
local pure = { type = type, math = math, table = table, string = string, ipairs = ipairs, pairs = pairs, setmetatable = setmetatable }
for _, name in ipairs({ "HistoryMath", "Database", "Significance", "HistoricalAnalytics", "MarketSignal" }) do
    setfenv(assert(loadfile("src/MarketPilot/" .. name .. ".lua")), pure)("MarketPilot", MP)
end
local DB, H, S, Signal = MP.Database, MP.HistoricalAnalytics, MP.Significance, MP.MarketSignal
local NOW = 70 * DAY
local function snapshot(t, price, quantity)
    return { t = t, rawMedian = price, cleanMedian = price, q1 = price, q3 = price, lowest = price,
        totalQuantity = quantity or 10, levelCount = 1, suspicious = 0, extreme = 0, anomalySufficient = false }
end
local function near(a, b, epsilon) assert(a and math.abs(a - b) <= (epsilon or 1e-8), tostring(a) .. " vs " .. tostring(b)) end
local passed = 0
local function test(name, run) run(); passed = passed + 1; print("PASS " .. name) end

test("database saves primitive whitelist only and returns detached history", function()
    local db = DB.Open(nil, "realm:faction", NOW)
    local s = snapshot(NOW, 20); s.priceLevels = { { unitPrice = 999 } }; s.raw = { junk = 1 }
    assert(db:Append(2770, s))
    local stored = db.root.markets[db.key].items[2770].snapshots[1]
    local n = 0; for _, value in pairs(stored) do assert(type(value) ~= "table"); n = n + 1 end
    assert(n == 11 and stored.priceLevels == nil and stored.raw == nil)
    s.cleanMedian = 999; db:History(2770)[1].cleanMedian = 555
    assert(stored.cleanMedian == 20 and stored.anomalySufficient == false)
end)
test("dedupe window is less than 600 seconds with every core field compared", function()
    local db = DB.Open(nil, "test", NOW); assert(db:Append(2770, snapshot(NOW, 20)))
    local added, state = db:Append(2770, snapshot(NOW + 599, 20))
    assert(added == false and state == "DEDUPED" and #db:History(2770) == 1)
    assert(db:Append(2770, snapshot(NOW + 600, 20)))
    for key, value in pairs({ cleanMedian = 21, totalQuantity = 11, suspicious = 1, anomalySufficient = true }) do
        local fresh = DB.Open(nil, "test", NOW); fresh:Append(2770, snapshot(NOW, 20))
        local s = snapshot(NOW + 1, 20); s[key] = value
        assert(fresh:Append(2770, s), key)
    end
end)
test("retention enforces both 200 observations and 60 days including reload", function()
    local db = DB.Open(nil, "test", 0)
    for i = 1, 205 do assert(db:Append(2770, snapshot(i * 600, i))) end
    local list = db:History(2770); assert(#list == 200 and list[1].cleanMedian == 6)
    local t = 60 * DAY + 600
    db:Append(2770, snapshot(t, 999))
    assert(db:History(2770)[1].t >= t - 60 * DAY)
    local reopened = DB.Open(db.root, "test", t + 60 * DAY)
    assert(#reopened:History(2770) == 1)
    reopened = DB.Open(db.root, "test", t + 60 * DAY + 1)
    assert(#reopened:History(2770) == 0)
end)
test("unsupported and corrupt schemas are preserved without silent resets", function()
    for _, root in ipairs({ { schema = 99, markets = { untouched = true } }, { schema = 0 },
        { schema = 1, markets = { x = { items = { [2770] = { snapshots = { { t = 1 } } } } } } } }) do
        local db = DB.Open(root, "test", NOW)
        assert(db.status == "UNKNOWN" and db.root == root and db:Append(2770, snapshot(NOW, 20)) == nil)
    end
    assert(DB.Open(nil, nil, NOW).root == nil)
end)
test("reload/account-wide fixture shares only the same conservative market key", function()
    local first = DB.Open(nil, "realmA:Alliance", NOW); first:Append(2770, snapshot(NOW, 20))
    local function clone(x) if type(x) ~= "table" then return x end; local y = {}; for k, v in pairs(x) do y[k] = clone(v) end; return y end
    local serialized = clone(first.root)
    assert(#DB.Open(serialized, "realmA:Alliance", NOW):History(2770) == 1)
    assert(#DB.Open(serialized, "realmA:Horde", NOW):History(2770) == 0)
    assert(#DB.Open(serialized, "realmB:Alliance", NOW):History(2770) == 0)
end)
test("empty snapshots retain insufficiency without inventing price and invalid numbers fail", function()
    local s = snapshot(NOW, nil, 0); s.levelCount = 0
    local db = DB.Open(nil, "test", NOW)
    assert(db:Append(2770, s) and db:History(2770)[1].cleanMedian == nil)
    for _, value in ipairs({ 0, -1, 1.5, math.huge, 0/0, "20" }) do
        s = snapshot(NOW + 1, value); assert(db:Append(2770, s) == nil)
    end
    assert(db:Append(2770, snapshot(NOW - 1, 20)) == nil)
end)
test("rolling medians exclude current and respect 24h/7d/30d boundaries", function()
    local history = {}
    for i, age in ipairs({ 30, 7, 2, 1, 0.5, 0.25 }) do
        history[i] = snapshot(NOW - age * DAY, ({ 70, 100, 110, 120, 130, 140 })[i])
    end
    local current = snapshot(NOW, 150, 20)
    local a = H.Analyze(history, current)
    assert(a.maturity == "30D READY" and a.count == 7)
    near(a.windows[1].median, 130); near(a.windows[7].median, 120); near(a.windows[30].median, 115)
    near(a.windows[7].change, 25); near(a.windows[30].change, (150 / 115 - 1) * 100)
    near(a.windows[7].supplyRatio, 2); near(a.windows[30].supplyRatio, 2)
    assert(a.percentile30d == 100 and history[1].cleanMedian == 70)
end)
test("percentile uses midrank ties and mature windows require prior observations", function()
    local history = { snapshot(NOW - 30 * DAY, 100), snapshot(NOW - 2 * DAY, 120),
        snapshot(NOW - DAY, 120), snapshot(NOW - DAY / 2, 140) }
    local a = H.Analyze(history, snapshot(NOW, 120))
    assert(a.percentile30d == 50 and a.windows[1].status == "INSUFFICIENT")
end)
test("maturity and window guards never invent full 7d/30d history", function()
    local current = snapshot(NOW, 100)
    assert(H.Analyze({}, current).maturity == "NEW")
    local a = H.Analyze({ snapshot(NOW - DAY, 90), snapshot(NOW - DAY / 2, 100) }, current)
    assert(a.maturity == "EARLY" and a.windows[7].median == nil and a.percentile30d == nil)
    a = H.Analyze({ snapshot(NOW - 7 * DAY, 90), snapshot(NOW - DAY, 100) }, current)
    assert(a.maturity == "7D READY" and a.windows[7].median == nil) -- Sparse coverage is not enough for a median.
end)
local function series(reverse, absurd)
    local rows, prices = {}, { 10000, 11000, 12100, 13310, 14641 }
    for i = 1, 5 do rows[i] = snapshot(NOW - (5 - i) * DAY, prices[reverse and 6 - i or i]) end
    if absurd then rows[3].cleanMedian = 1000000000 end
    return rows
end
test("Theil-Sen rising and falling log prices give correct percent/day", function()
    local rows = series(); near(H.Analyze(rows, rows[5]).trend7d.pctPerDay, 10)
    rows = series(true); near(H.Analyze(rows, rows[5]).trend7d.pctPerDay, (1 / 1.1 - 1) * 100)
end)
test("one absurd snapshot cannot dominate median pairwise slope", function()
    local rows = series(false, true); near(H.Analyze(rows, rows[5]).trend7d.pctPerDay, 10)
end)

test("30d trend requires mature history as well as five observations and 24h span", function()
    local rows = series()
    assert(H.Analyze(rows, rows[5]).trend30d.status == "INSUFFICIENT")
    table.insert(rows, 1, snapshot(NOW - 30 * DAY, 200))
    assert(H.Analyze(rows, rows[#rows]).trend30d.status == "OK")
end)
test("trend requires five distinct-time valid snapshots and at least 24h span", function()
    local rows = series(); table.remove(rows, 1)
    assert(H.Analyze(rows, rows[#rows]).trend7d.status == "INSUFFICIENT")
    rows = series(); for i, row in ipairs(rows) do row.t = NOW - (5 - i) * 100 end
    assert(H.Analyze(rows, rows[5]).trend7d.status == "INSUFFICIENT")
    rows = series(); rows[2].t = rows[1].t
    assert(H.Analyze(rows, rows[5]).count == 4)
end)
test("robust volatility is MAD of chronological log returns; latest shock is relative", function()
    local rows = series(); local a = H.Analyze(rows, rows[5])
    near(a.volatility.pct, 0); assert(a.volatility.class == "LOW")
    rows = {}; for i, price in ipairs({ 100, 100, 100, 100, 200 }) do rows[i] = snapshot(NOW - (5 - i) * DAY, price) end
    a = H.Analyze(rows, rows[5]); near(a.volatility.pct, 0); assert(a.volatility.class == "HIGH")
    rows = {}; for i, price in ipairs({ 100, 200, 100, 400, 100 }) do rows[i] = snapshot(NOW - (5 - i) * DAY, price) end
    a = H.Analyze(rows, rows[5])
    local r = { math.log(2), -math.log(2), math.log(4), -math.log(4) }
    near(a.volatility.pct, (math.exp(1.4826 * MP.HistoryMath.MAD(r)) - 1) * 100)
    rows = {}; for i, price in ipairs({ 100, 100, 200, 100, 400 }) do rows[i] = snapshot(NOW - (5 - i) * DAY, price) end
    a = H.Analyze(rows, rows[5]); assert(a.volatility.class == "NORMAL" and a.volatility.score > 1 and a.volatility.score <= 3)
end)
test("future/invalid prices are excluded, zero quantity denominator stays unavailable", function()
    local rows = { snapshot(NOW - 7 * DAY, 100, 0), snapshot(NOW - 2 * DAY, 100, 0),
        snapshot(NOW - DAY, 100, 0), snapshot(NOW + 1, 999), snapshot(NOW - 1, nil) }
    local a = H.Analyze(rows, snapshot(NOW, 100, 0))
    assert(a.count == 4 and a.windows[7].supplyRatio == nil)
    assert(H.Analyze(rows, snapshot(NOW, nil)).status == "UNKNOWN")
end)
test("Mann-Whitney guards and invalid samples preserve absence of p-values", function()
    local a = S.Compare({ 1, 2 }, { 1, 2, 3, 4, 5, 6, 7 }); assert(a.status == "INSUFFICIENT" and a.p == nil and a.significant == nil)
    assert(S.Compare({ 1, 2, 3 }, { 1, 2 }).p == nil)
    assert(S.Compare({ 0, 1, 2 }, { 1, 2, 3, 4, 5, 6, 7 }).status == "UNKNOWN")
end)
test("untied and tied p-values match independent normal-erfc references", function()
    local a = S.Compare({ 100, 101, 102 }, { 10, 20, 30, 40, 50, 60, 70 })
    near(a.p, 0.02265449408008937, 1.5e-7); assert(a.significant and a.practical and a.meaningfulMove)
    a = S.Compare({ 105, 105, 105 }, { 100, 100, 100, 100, 100, 100, 100 })
    near(a.p, 0.004274733960172568, 1.5e-7)
    assert(a.significant and not a.practical and not a.meaningfulMove)
end)
test("identical distributions do not shift; practical size alone is insufficient", function()
    local a = S.Compare({ 100, 100, 100 }, { 100, 100, 100, 100, 100, 100, 100 })
    assert(a.p == 1 and not a.meaningfulMove)
    a = S.Compare({ 80, 100, 150 }, { 50, 60, 70, 80, 90, 100, 200 })
    assert(a.practical and not a.significant and not a.meaningfulMove)
    a = S.Compare({ 90, 90, 90 }, { 100, 100, 100, 100, 100, 100, 100 })
    assert(a.practical and a.meaningfulMove) -- Inclusive negative 10% boundary.
end)
test("recent 24h and prior 7d significance windows are disjoint", function()
    local rows = {}
    for i = 2, 8 do rows[#rows + 1] = snapshot(NOW - i * DAY, 100) end
    rows[#rows + 1] = snapshot(NOW - DAY, 150); rows[#rows + 1] = snapshot(NOW - DAY / 2, 150)
    local a = H.Analyze(rows, snapshot(NOW, 150))
    assert(a.significance.recentCount == 3 and a.significance.baselineCount == 7 and a.significance.meaningfulMove)
end)
test("signal thresholds are descriptive and exact at all boundaries", function()
    local a = { status = "OK", windows = { [7] = { status = "OK", supplyRatio = 1 } },
        trend7d = { status = "OK", pctPerDay = 0 }, volatility = { status = "OK", class = "NORMAL" } }
    for _, pair in ipairs({ { 20, "CHEAP_VS_HISTORY" }, { 20.1, "NORMAL_RANGE" }, { 79.9, "NORMAL_RANGE" }, { 80, "EXPENSIVE_VS_HISTORY" } }) do
        a.percentile30d = pair[1]; assert(Signal.Describe(a).price == pair[2])
    end
    for _, pair in ipairs({ { 2, "STABLE" }, { -2, "STABLE" }, { 2.01, "RISING" }, { -2.01, "FALLING" } }) do
        a.trend7d.pctPerDay = pair[1]; assert(Signal.Describe(a).trend == pair[2])
    end
    for _, pair in ipairs({ { 0.6, "LOW_SUPPLY" }, { 1.6, "HIGH_SUPPLY" }, { 1, "NORMAL_SUPPLY" } }) do
        a.windows[7].supplyRatio = pair[1]; assert(Signal.Describe(a).supply == pair[2])
    end
    a.status = "UNKNOWN"; assert(Signal.Describe(a).price == "UNKNOWN")
    assert(Signal.Describe(H.Analyze({}, snapshot(NOW, 20))).price == "INSUFFICIENT")
end)
print("PASS " .. passed .. " database/history/significance/signal tests (Lua 5.1)")
