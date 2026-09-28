-- Executable Lua saved-data fixtures. This verifies our data contract, not the
-- Forever client's serializer or whether its installed TOC registers the root.
local MP, DAY = {}, 86400
local pure = { type = type, math = math, table = table, string = string,
    ipairs = ipairs, pairs = pairs, setmetatable = setmetatable }
for _, name in ipairs({ "HistoryMath", "Database", "Significance", "HistoricalAnalytics", "MarketSignal", "Market" }) do
    setfenv(assert(loadfile("src/MarketPilot/" .. name .. ".lua")), pure)("MarketPilot", MP)
end
local NOW, DB = 100 * DAY, MP.Database
local function snapshot(t, price, quantity)
    return { t = t, rawMedian = price, cleanMedian = price, q1 = price, q3 = price, lowest = price,
        totalQuantity = quantity or 10, levelCount = price and 1 or 0,
        suspicious = 0, extreme = 0, anomalySufficient = false }
end

-- Test-only serializer with deterministic ordering. Re-executing the text creates
-- entirely new tables and preserves exact integers, nil fields and quoted keys.
local function literal(value)
    if type(value) == "number" then
        assert(value == value and math.abs(value) < math.huge)
        return string.format("%.17g", value)
    end
    if type(value) == "string" then return string.format("%q", value) end
    if type(value) == "boolean" or value == nil then return tostring(value) end
    assert(type(value) == "table", "Saved fixture must contain only primitive data")
    local entries = {}
    for key, child in pairs(value) do entries[#entries + 1] = "[" .. literal(key) .. "]=" .. literal(child) end
    table.sort(entries)
    return "{" .. table.concat(entries, ",") .. "}"
end
local function reload(root)
    local env = {}
    setfenv(assert(loadstring("MarketPilotDB=" .. literal(root))), env)()
    return env.MarketPilotDB
end
local passed = 0
local function test(name, run) run(); passed = passed + 1; print("PASS " .. name) end

test("executable saved-data round-trip preserves all partitions, canary and unknown prices", function()
    local key = 'forever-beta:v1:18:Classic Beta PvE 2:5:Horde'
    local otherKey = 'other realm:quote " and slash \\ : Alliance'
    local db = DB.Open(nil, key, NOW)
    assert(db:Append(2770, snapshot(NOW, 29, 472)))
    assert(db:Append(2775, snapshot(NOW, nil, 0)))
    assert(DB.Open(db.root, otherKey, NOW):Append(2447, snapshot(NOW, 15)))
    db.root._svCanary = NOW
    local before, root = literal(db.root), reload(db.root)
    assert(root ~= db.root and root.markets ~= db.root.markets and literal(root) == before)
    local reopened = DB.Open(root, key, NOW + 1)
    assert(reopened.status == "OK" and reopened.root == root)
    assert(reopened:History(2770)[1].cleanMedian == 29 and root._svCanary == NOW)
    local empty = reopened:History(2775)[1]
    assert(empty.cleanMedian == nil and empty.totalQuantity == 0 and empty.anomalySufficient == false)
    assert(DB.Open(root, otherKey, NOW + 1):History(2447)[1].cleanMedian == 15)
    assert(literal(root) == before)
end)

test("fresh Market hydrates current and report after text reload without a scan or mutation", function()
    local db = DB.Open(nil, "same-realm:same-faction", NOW)
    for i, price in ipairs({ 10000, 11000, 12100, 13310, 14641 }) do
        assert(db:Append(2770, snapshot(NOW - (5 - i) * DAY, price)))
    end
    assert(db:Append(2775, snapshot(NOW, nil, 0)))
    local root = reload(db.root)
    local reopened = DB.Open(root, db.key, NOW)
    local before = literal(root)
    local items = { List = function() return { 2770, 2775 } end }
    local market = MP.Market.New(reopened, items)
    local current = market:Get(2770)
    assert(current.current.cleanMedian == 14641 and current.lastScan == NOW)
    assert(current.analytics.count == 5 and #current.history == 5)
    assert(market:Get(2775).current.cleanMedian == nil)
    local report = market:Report()
    assert(#report.rising == 1 and report.rising[1].itemID == 2770)
    assert(report.maturity.EARLY == 1 and report.maturity.NEW == 1)
    assert(literal(root) == before and next(market.latest) == nil and market.lastSample == nil)
end)

test("different characters with the same key share serialized history without a character field", function()
    local key = "realm:faction"
    local bank = DB.Open(nil, key, NOW)
    assert(bank:Append(2770, snapshot(NOW, 20)))
    local root = reload(bank.root)
    local main = DB.Open(root, key, NOW + 1)
    assert(main.root == root and main.items == root.markets[key].items)
    assert(main:History(2770)[1].cleanMedian == 20)
    assert(DB.Open(root, "realm:other-faction", NOW + 1):History(2770)[1] == nil)
    assert(main:History(2770)[1].cleanMedian == 20)
end)

test("schema validation is atomic before retention and never rewrites damaged history", function()
    local root = { schema = 1, _svCanary = 7, markets = {
        old = { items = { [2770] = { snapshots = { snapshot(0, 20) } } } },
        bad = { items = { [2775] = { snapshots = { { t = NOW, cleanMedian = 99 } } } } },
    } }
    local before = literal(root)
    local db = DB.Open(root, "new-partition", NOW)
    assert(db.status == "UNKNOWN" and db.root == root and db.items == nil)
    assert(literal(root) == before and root.markets["new-partition"] == nil)
    assert(db:Append(2770, snapshot(NOW, 21)) == nil and literal(root) == before)
end)

test("rejected append and identity rebind preserve exact serialized history", function()
    local db = DB.Open(nil, "early-key", NOW)
    assert(db:Append(2770, snapshot(NOW, 20)))
    local stable = DB.Open(db.root, "stable-key", NOW)
    assert(stable:Append(2447, snapshot(NOW, 30)))
    db.root._svCanary = NOW
    local before = literal(db.root)
    assert(stable:Append(2447, snapshot(NOW - 1, 40)) == nil)
    local malformed = snapshot(NOW + 1, 0)
    assert(stable:Append(2447, malformed) == nil)
    local rebound = DB.Open(db.root, "stable-key", NOW + 61 * DAY, true)
    assert(rebound.status == "OK" and rebound:History(2447)[1].cleanMedian == 30)
    assert(literal(db.root) == before)
end)

test("largest accepted exact integers survive text reload and compact whitelist", function()
    local db = DB.Open(nil, "exact-integers", NOW)
    local row = snapshot(NOW, 9007199254740991, 9007199254740991)
    row.auctions, row.unrelated = { { forbidden = true } }, "discard"
    assert(db:Append(2770, row))
    local restored = DB.Open(reload(db.root), db.key, NOW):History(2770)[1]
    assert(restored.cleanMedian == 9007199254740991 and restored.totalQuantity == 9007199254740991)
    assert(restored.auctions == nil and restored.unrelated == nil and restored.anomalySufficient == false)
end)

test("September 28 client-written Copper and Tin observations hydrate from the real spaced realm key", function()
    -- Public item/market observations only; no account or character identifiers.
    -- Copied from the client-written compact fields, not from an AH row fixture.
    local key = "forever-beta:v1:18:Classic Beta PvE 2:5:Horde"
    local root = { schema = 1, _svCanary = 1790634087, markets = { [key] = { items = {
        [2770] = { snapshots = {
            { t = 1790633907, rawMedian = 124, cleanMedian = 124, q1 = 121, q3 = 129,
                lowest = 109, totalQuantity = 2368, levelCount = 33, suspicious = 4, extreme = 0, anomalySufficient = true },
            { t = 1790634112, rawMedian = 124, cleanMedian = 124, q1 = 121, q3 = 129,
                lowest = 109, totalQuantity = 2390, levelCount = 33, suspicious = 4, extreme = 0, anomalySufficient = true },
        } },
        [2771] = { snapshots = {
            { t = 1790633908, rawMedian = 389, cleanMedian = 388, q1 = 385, q3 = 418,
                lowest = 384, totalQuantity = 1128, levelCount = 29, suspicious = 0, extreme = 1, anomalySufficient = true },
            { t = 1790634113, rawMedian = 388, cleanMedian = 385, q1 = 385, q3 = 400,
                lowest = 384, totalQuantity = 1154, levelCount = 29, suspicious = 0, extreme = 1, anomalySufficient = true },
        } },
    } } } }
    local restored = reload(root)
    local db = DB.Open(restored, key, 1790634209)
    local market = MP.Market.New(db, { List = function() return { 2770, 2771 } end })
    assert(db.status == "OK" and db.root == restored)
    assert(market:Get(2770).current.cleanMedian == 124 and market:Get(2770).current.totalQuantity == 2390)
    assert(market:Get(2771).current.cleanMedian == 385 and market:Get(2771).current.extreme == 1)
    assert(#market:Get(2770).history == 2 and #market:Get(2771).history == 2)
    assert(restored._svCanary == 1790634087 and literal(restored) == literal(root))
end)

print("PASS " .. passed .. " persistence round-trip tests (Lua 5.1)")
