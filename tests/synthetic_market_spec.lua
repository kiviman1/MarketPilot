-- Pure Lua 5.1 offline fixtures; no client, clock, live DB, or auction API globals.
local MP, DAY, NOW = {}, 86400, 100 * 86400
local pure = setmetatable({ type = type, math = math, table = table, string = string,
    ipairs = ipairs, pairs = pairs, next = next, rawget = rawget, setmetatable = setmetatable },
    { __index = function(_, key) error("Unexpected global in pure fixture pipeline: " .. key) end })
for _, name in ipairs({ "Statistics", "HistoryMath", "Database", "Significance", "HistoricalAnalytics",
    "MarketSignal", "Market", "Items" }) do
    setfenv(assert(loadfile("src/MarketPilot/" .. name .. ".lua")), pure)("MarketPilot", MP)
end
setfenv(assert(loadfile("tests/fixtures/SyntheticMarket.lua")), pure)("MarketPilot", MP)
local function near(a, b, epsilon) assert(a and math.abs(a - b) <= (epsilon or 1e-8), tostring(a) .. " vs " .. tostring(b)) end
local function clone(x) if type(x) ~= "table" then return x end; local copy = {}; for k, v in pairs(x) do copy[k] = clone(v) end; return copy end
local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local passed = 0
local function test(name, run) run(); passed = passed + 1; print("PASS " .. name) end
local synthetic, metadata = MP.SyntheticMarket.Create(NOW, MP.Items)
assert(synthetic and metadata.synthetic)

test("synthetic seeds all 56 configured items with 91 compact observations spanning 30 days", function()
    assert(metadata.days == 30 and metadata.count == 91 and #MP.Items.List() == 56)
    local fields = { t = true, rawMedian = true, cleanMedian = true, q1 = true, q3 = true, lowest = true,
        totalQuantity = true, levelCount = true, suspicious = true, extreme = true, anomalySufficient = true }
    for _, id in ipairs(MP.Items.List()) do
        local history = synthetic.db:History(id)
        assert(#history == 91 and #history <= 200)
        assert(history[1].t == NOW - 30 * DAY and history[91].t == NOW)
        assert(metadata.items[id].kind and metadata.items[id].description)
        for i, row in ipairs(history) do
            if i > 1 then assert(row.t - history[i - 1].t == DAY / 3) end
            for key, value in pairs(row) do assert(fields[key] and type(value) ~= "table") end
            assert(row.cleanMedian > 0 and row.cleanMedian % 1 == 0)
        end
        assert(synthetic:Get(id).analytics.maturity == "30D READY")
    end
end)

test("synthetic uses the real Statistics, Snapshot, Database and Market pipeline", function()
    local analyze, snapshot, open, new = MP.Statistics.Analyze, MP.Database.Snapshot, MP.Database.Open, MP.Market.New
    local counts = { analyze = 0, snapshot = 0, open = 0, market = 0 }
    MP.Statistics.Analyze = function(sample) counts.analyze = counts.analyze + 1; return analyze(sample) end
    MP.Database.Snapshot = function(sample, analysis) counts.snapshot = counts.snapshot + 1; return snapshot(sample, analysis) end
    MP.Database.Open = function(root, key, now)
        assert(root == nil and key == "fixture:30-days"); counts.open = counts.open + 1; return open(root, key, now)
    end
    MP.Market.New = function(db, items) counts.market = counts.market + 1; return new(db, items) end
    local result = MP.SyntheticMarket.Create(NOW, { List = function() return { 2770 } end })
    MP.Statistics.Analyze, MP.Database.Snapshot, MP.Database.Open, MP.Market.New = analyze, snapshot, open, new
    assert(result and counts.analyze == 91 and counts.snapshot == 91 and counts.open == 1 and counts.market == 1)
    assert(result:Get(2770).analytics.trend7d.status == "OK")
end)

test("rising synthetic rolling medians and changes match independently calculated prices", function()
    local data = synthetic:Get(2770)
    -- Independent Python statistics.median references for rounded 1000*1.04^(i/3), i=0..90.
    assert(data.current.cleanMedian == 3243)
    for _, pair in ipairs({ { 1, 3160, 3 }, { 7, 2809, 21 }, { 30, 1789.5, 90 } }) do
        local window = data.analytics.windows[pair[1]]
        assert(window.status == "OK" and window.count == pair[3])
        near(window.median, pair[2]); near(window.change, (3243 / pair[2] - 1) * 100)
    end
    assert(data.analytics.percentile30d == 100)
    assert(data.signals.price == "EXPENSIVE_VS_HISTORY" and data.signals.trend == "RISING")
end)

test("synthetic Theil-Sen trends match independent median pairwise slope references", function()
    -- Independent Python statistics.median over all pairwise log-price slopes.
    near(synthetic:Get(2770).analytics.trend7d.pctPerDay, 4.000251302683845)
    near(synthetic:Get(2770).analytics.trend30d.pctPerDay, 3.9995495998352726)
    local down = synthetic:Get(2771)
    assert(down.current.cleanMedian == 1000 and down.signals.trend == "FALLING")
    near(down.analytics.windows[1].median, 1026)
    near(down.analytics.windows[7].median, 1155)
    near(down.analytics.windows[30].median, 1813)
    assert(down.analytics.percentile30d == 0 and down.signals.price == "CHEAP_VS_HISTORY")
end)

test("stable synthetic ties give midrank percentile, zero volatility and no significant move", function()
    local data = synthetic:Get(2775)
    for _, window in pairs(data.analytics.windows) do
        assert(window.median == 1000 and window.change == 0 and window.supplyRatio == 1)
    end
    assert(data.analytics.percentile30d == 50 and data.analytics.significance.p == 1)
    assert(not data.analytics.significance.meaningfulMove)
    near(data.analytics.trend7d.pctPerDay, 0); near(data.analytics.volatility.pct, 0)
    assert(data.signals.trend == "STABLE" and data.signals.price == "NORMAL_RANGE")
    assert(data.signals.supply == "NORMAL_SUPPLY" and data.signals.volatility == "LOW")
end)

test("last-day price and supply shifts retain separate percentile and significance facts", function()
    local low, high = synthetic:Get(2772), synthetic:Get(2776)
    assert(low.current.cleanMedian == 600 and high.current.cleanMedian == 1600)
    near(low.analytics.windows[7].change, -40); near(high.analytics.windows[7].change, 60)
    near(low.analytics.windows[7].supplyRatio, 0.4); near(high.analytics.windows[7].supplyRatio, 2)
    -- Three earlier observations tie the current price; the current point is excluded.
    near(low.analytics.percentile30d, 100 * 1.5 / 90)
    near(high.analytics.percentile30d, 100 * 88.5 / 90)
    assert(low.signals.price == "CHEAP_VS_HISTORY" and low.signals.supply == "LOW_SUPPLY")
    assert(high.signals.price == "EXPENSIVE_VS_HISTORY" and high.signals.supply == "HIGH_SUPPLY")
    for _, data in ipairs({ low, high }) do
        local s = data.analytics.significance
        assert(s.recentCount == 4 and s.baselineCount == 21 and s.meaningfulMove)
        -- Independent erfc(z/sqrt(2)); U=0 or84, tie-corrected variance=73.5, continuity=.5.
        near(s.p, 0.0000012940972209345354, 1.5e-7)
        assert(data.signals.trend == "STABLE") -- Four recent points do not dominate a robust 7d trend.
    end
end)

test("latest unusual return has independently calculated MAD dispersion and own-return score", function()
    local data = synthetic:Get(3858)
    assert(data.current.cleanMedian == 1800)
    -- Independent Python median/MAD on the 21 returns from repeating1000/1100/1050, final1800.
    near(data.analytics.volatility.pct, 0.3371392620212227)
    near(data.analytics.volatility.score, 173.9645991450578, 1e-6)
    assert(data.signals.volatility == "HIGH")
end)

test("100000g dominant-quantity auction cannot corrupt clean median or historical references", function()
    local data = synthetic:Get(2447)
    assert(metadata.items[2447].kind == "EXTREME_OUTLIER")
    assert(data.current.rawMedian == 1000000000 and data.current.cleanMedian == 1000)
    assert(data.current.q1 == 980 and data.current.q3 == 1020 and data.current.lowest == 970)
    assert(data.current.levelCount == 8 and data.current.extreme == 1 and data.current.suspicious == 0)
    assert(data.current.anomalySufficient and data.current.totalQuantity == 10140)
    assert(data.analytics.windows[30].median == 1000 and data.analytics.windows[30].change == 0)
    assert(data.analytics.percentile30d == 50 and data.analytics.significance.p == 1)
    near(data.analytics.windows[7].supplyRatio, 10140 / 140) -- Supply is deliberately the raw factual count.
end)

test("real reports consume synthetic market analytics without separate report math", function()
    local report = synthetic:Report()
    assert(report.maturity["30D READY"] == 56 and report.maturity.NEW == 0)
    local function contains(rows, id) for _, row in ipairs(rows) do if row.itemID == id then return true end end; return false end
    assert(contains(report.rising, 2770) and not contains(report.rising, 2771))
    assert(contains(report.cheap, 2772) and contains(report.volatile, 3858))
    assert(contains(report.significant, 2772) and contains(report.significant, 2776))
    assert(not contains(report.significant, 2775) and not contains(report.significant, 2447))
end)

test("synthetic root, metadata and history are detached from real data and subsequent synthetic sessions", function()
    local live = MP.Database.Open(nil, "real:realm:faction", NOW)
    live:Append(2770, clone(synthetic.db:History(2770)[1]))
    live.root._svCanary = 12345
    local before = clone(live.root)
    local again, labels = MP.SyntheticMarket.Create(NOW, MP.Items)
    assert(again.db.root ~= synthetic.db.root and again.db.root ~= live.root and same(live.root, before))
    assert(same(again.db.root, synthetic.db.root) and same(labels, metadata))
    again.db.items[2770].snapshots[1].cleanMedian = 123
    labels.items[2770].label = "changed"
    assert(synthetic.db:History(2770)[1].cleanMedian == 1000 and metadata.items[2770].label == "Rising market")
    assert(same(live.root, before) and synthetic.latest[2770] == nil)
end)

test("synthetic construction validates clock and configured IDs without creating a partial market", function()
    for _, clock in ipairs({ -1, 0, 30 * DAY - 1, 1.5, math.huge, 0/0, "today" }) do
        local result, err = MP.SyntheticMarket.Create(clock, MP.Items); assert(result == nil and type(err) == "string")
    end
    assert(MP.SyntheticMarket.Create(NOW, nil) == nil)
    for _, ids in ipairs({ {}, { 2770, 2770 }, { [1] = 2770, [3] = 2771 }, { 2770, hidden = 2771 }, { 0 }, { 1.5 } }) do
        local before = clone(ids)
        assert(MP.SyntheticMarket.Create(NOW, { List = function() return ids end }) == nil)
        assert(same(ids, before))
    end
    assert(MP.SyntheticMarket.Create(NOW, { List = function() return false end }) == nil)
end)

test("insufficient history still has no fabricated model values when tested beside mature synthetic", function()
    local history = synthetic.db:History(2770)
    local current = history[#history]
    local sparse = { history[#history - 1], current }
    local a = MP.HistoricalAnalytics.Analyze(sparse, current)
    assert(a.maturity == "NEW" and a.windows[7].median == nil and a.percentile30d == nil)
    assert(a.trend7d.status == "INSUFFICIENT" and a.volatility.status == "INSUFFICIENT")
    assert(a.significance.status == "INSUFFICIENT" and a.significance.p == nil)
    assert(MP.MarketSignal.Describe(a).price == "INSUFFICIENT")
end)

print("PASS " .. passed .. " synthetic market/model tests (Lua 5.1)")
