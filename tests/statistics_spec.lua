-- Run from repository root with Lua 5.1: lua tests/statistics_spec.lua
local path = "src/MarketPilot/Statistics.lua"
local file = assert(io.open(path, "rb"))
local source = file:read("*a")
file:close()
local chunk = assert(loadstring(source, path))
-- Deliberately no client globals, clock, filesystem, persistence or random source.
setfenv(chunk, { math = math, table = table, type = type, rawget = rawget, next = next, ipairs = ipairs })
local Statistics = chunk()

local function sample(prices, quantities)
    local rows = {}
    for i, price in ipairs(prices) do rows[i] = { unitPrice = price, quantity = quantities and quantities[i] or 1 } end
    return { priceLevels = rows }
end
local function analyze(value)
    local analysis, err = Statistics.Analyze(value)
    assert(analysis, err)
    return analysis
end
local function near(a, b)
    assert(math.abs(a - b) < 1e-12, tostring(a) .. " ~= " .. tostring(b))
end
local function equal(a, b)
    assert(type(a) == type(b), "type mismatch")
    if type(a) ~= "table" then assert(a == b, tostring(a) .. " ~= " .. tostring(b)); return end
    for key, value in pairs(a) do equal(value, b[key]) end
    for key in pairs(b) do assert(a[key] ~= nil, "unexpected key " .. tostring(key)) end
end
local function rowAt(analysis, price)
    for _, row in ipairs(analysis.anomaly.levels) do if row.unitPrice == price then return row end end
    error("missing price " .. price)
end
local function withTail(price, quantity)
    local value = sample({ 8000, 8500, 9000, 9500, 10000, 10500, 11000, 11500, 12000 })
    for _, row in ipairs(value.priceLevels) do row.quantity = 20 end
    value.priceLevels[#value.priceLevels + 1] = { unitPrice = price, quantity = quantity or 1 }
    return value
end
local passed = 0
local function test(name, run)
    run(); passed = passed + 1; print("PASS " .. name)
end

test("pure module has no external or nondeterministic references", function()
    for _, name in ipairs({ "C_AuctionHouse", "CreateFrame", "SavedVariables", "GetBuildInfo",
        "_G", "time", "date", "print", "random", "require", "auctionID" }) do
        assert(not source:find("%f[%w_]" .. name .. "%f[^%w_]"), name)
    end
    assert(not source:find("os%.") and not source:find("io%."))
    assert(type(Statistics.Analyze) == "function")
end)

test("discrete weighted quartiles with unequal quantities", function()
    local a = analyze(sample({ 100, 200, 300 }, { 1, 3, 6 }))
    equal(a.raw, { levelCount = 3, totalQuantity = 10, min = 100, max = 300,
        q1 = 200, weightedMedian = 300, q3 = 300 })
    assert(a.modelVersion == "MP-02-v1")
    local ties = analyze(sample({ 100, 200, 300, 400 }))
    assert(ties.raw.q1 == 100 and ties.raw.weightedMedian == 200 and ties.raw.q3 == 300)
    assert(analyze(sample({ 100, 200 })).raw.weightedMedian == 100)
end)

test("exact weighted rank at maximum safe quantity", function()
    -- 0.75 * W rounds down here; direct floating multiplication is not enough.
    local a = analyze(sample({ 100, 200, 300, 400 }, {
        2251799813685247, 2251799813685248, 2251799813685248, 2251799813685248,
    }))
    assert(a.raw.totalQuantity == 9007199254740991)
    assert(a.raw.q1 == 200 and a.raw.weightedMedian == 300 and a.raw.q3 == 400)
    local b = analyze(sample({ 9007199254740990, 9007199254740991 }))
    assert(b.raw.min == 9007199254740990 and b.raw.max == 9007199254740991)
    assert(b.raw.weightedMedian == 9007199254740990)
end)

test("sorted and unsorted results identical; inputs untouched", function()
    local first = sample({ 300, 100, 200, 100, 1000000000 }, { 4, 2, 3, 1, 9 })
    local before = sample({ 300, 100, 200, 100, 1000000000 }, { 4, 2, 3, 1, 9 })
    local second = sample({ 100, 100, 200, 300, 1000000000 }, { 1, 2, 3, 4, 9 })
    equal(analyze(first), analyze(second)); equal(first, before)
    local result = analyze(first)
    result.anomaly.levels[1].unitPrice = 999
    equal(first, before)
end)

test("100000g outlier with dominant quantity cannot corrupt clean median", function()
    local input = withTail(1000000000, 1000000) -- 100000 * 10000 copper.
    local a = analyze(input)
    assert(a.status == "OK" and a.anomaly.sufficient and a.anomaly.extremeCount == 1)
    assert(rowAt(a, 1000000000).class == "EXTREME")
    assert(a.raw.weightedMedian == 1000000000 and a.raw.totalQuantity == 1000180)
    equal(a.clean, { levelCount = 9, totalQuantity = 180, min = 8000, max = 12000,
        weightedMedian = 10000, q1 = 9000, q3 = 11000 })
    assert(#input.priceLevels == 10 and input.priceLevels[10].unitPrice == 1000000000)
end)

test("absurd low price excluded symmetrically", function()
    local a = analyze(withTail(1, 1000000))
    assert(rowAt(a, 1).class == "EXTREME" and a.anomaly.extremeCount == 1)
    assert(a.raw.weightedMedian == 1 and a.clean.weightedMedian == 10000)
    assert(a.clean.min == 8000 and a.clean.totalQuantity == 180)
end)

test("four levels insufficient; five distinct levels can support exclusion", function()
    local small = analyze(sample({ 10000, 10100, 10200, 1000000000 }, { 1, 1, 1, 9999 }))
    assert(small.status == "INSUFFICIENT" and not small.anomaly.sufficient)
    assert(small.anomaly.extremeCount == 0 and small.anomaly.reason == "TOO_FEW_PRICE_LEVELS")
    assert(rowAt(small, 1000000000).class == "SUSPICIOUS")
    equal(small.raw, small.clean)
    local enough = analyze(sample({ 9900, 10000, 10100, 10200, 1000000000 }))
    assert(enough.anomaly.sufficient and rowAt(enough, 1000000000).class == "EXTREME")
end)

test("quantity cannot influence detector center or classification", function()
    local a = analyze(withTail(1000000000, 1))
    local b = analyze(withTail(1000000000, 1000000000))
    for _, key in ipairs({ "logMedian", "logMAD", "logQ1", "logQ3", "logIQR", "observationCount" }) do
        assert(a.anomaly[key] == b.anomaly[key])
    end
    for i, row in ipairs(a.anomaly.levels) do
        assert(row.class == b.anomaly.levels[i].class and row.modifiedZ == b.anomaly.levels[i].modifiedZ)
    end
end)

test("duplicate prices preserve descriptors but cannot inflate anomaly sample size", function()
    local a = analyze(sample({ 100, 100, 100, 100, 100, 1000000000 }))
    assert(a.raw.levelCount == 6 and a.raw.totalQuantity == 6 and #a.anomaly.levels == 6)
    assert(a.anomaly.observationCount == 2 and not a.anomaly.sufficient and a.anomaly.extremeCount == 0)
end)

test("IQR-only suspicion stays in all clean descriptors", function()
    local a = analyze(withTail(16000, 10000))
    local row = rowAt(a, 16000)
    assert(row.class == "SUSPICIOUS" and row.iqrSuspicious and not row.madSuspicious)
    assert(a.anomaly.suspiciousCount == 1 and a.anomaly.extremeCount == 0)
    equal(a.raw, a.clean)
    assert(a.clean.weightedMedian == 16000 and a.clean.max == 16000)
end)

test("neither strong IQR nor strong MAD alone is enough for EXTREME", function()
    local iqrOnly = rowAt(analyze(withTail(24000)), 24000)
    assert(iqrOnly.iqrExtreme and not iqrOnly.madExtreme and iqrOnly.class == "SUSPICIOUS")
    local a = analyze(sample({ 3438, 4738, 12561, 12838, 13654 }))
    local madOnly = rowAt(a, 3438)
    assert(madOnly.madExtreme and not madOnly.iqrExtreme and madOnly.class == "SUSPICIOUS")
    assert(a.clean.min == 3438) -- Suspicious low rows stay in clean min as well.
end)

test("strict 3.5/6 MAD and 1.5/3 IQR thresholds at adjacent copper prices", function()
    local ref = analyze(withTail(1000000000)).anomaly
    local boundaries = {
        { "madSuspicious", ref.logMedian + 3.5 * ref.logMAD / 0.6745 },
        { "madExtreme", ref.logMedian + 6.0 * ref.logMAD / 0.6745 },
        { "iqrSuspicious", ref.logQ3 + 1.5 * ref.logIQR },
        { "iqrExtreme", ref.logQ3 + 3.0 * ref.logIQR },
    }
    for _, boundary in ipairs(boundaries) do
        local price = math.exp(boundary[2])
        local below, above = math.floor(price), math.ceil(price)
        assert(above == below + 1)
        local lower, upper = analyze(withTail(below)), analyze(withTail(above))
        near(lower.anomaly.logMAD, ref.logMAD); near(upper.anomaly.logMAD, ref.logMAD)
        assert(rowAt(lower, below)[boundary[1]] == false, boundary[1])
        assert(rowAt(upper, above)[boundary[1]] == true, boundary[1])
    end
end)

test("log median, type-7 quartiles, MAD and signed modified Z", function()
    local prices = { 100, 200, 400, 800, 1600 }
    local a = analyze(sample(prices)).anomaly
    near(a.logMedian, math.log(400)); near(a.logQ1, math.log(200)); near(a.logQ3, math.log(800))
    near(a.logMAD, math.log(2)); near(a.logIQR, math.log(4))
    near(a.levels[1].modifiedZ, -1.349); near(a.levels[5].modifiedZ, 1.349)
    local even = analyze(sample({ 100, 200, 400, 800 })).anomaly
    near(even.logMedian, (math.log(200) + math.log(400)) / 2)
    near(even.logQ1, math.log(100) + 0.75 * (math.log(200) - math.log(100)))
end)

test("flat, empty and nearly flat markets avoid zero division/false precision", function()
    local flat = analyze(sample({ 200, 200, 200, 200, 200 }))
    assert(flat.anomaly.logMAD == 0 and flat.anomaly.logIQR == 0 and flat.anomaly.extremeCount == 0)
    for _, row in ipairs(flat.anomaly.levels) do assert(row.modifiedZ == nil and row.class == "NORMAL") end
    local empty = analyze(sample({}))
    equal(empty.raw, { levelCount = 0, totalQuantity = 0 }); equal(empty.raw, empty.clean)
    assert(empty.status == "INSUFFICIENT" and empty.anomaly.logMedian == nil)
    local almost = analyze(sample({ 9007199254740987, 9007199254740988, 9007199254740989,
        9007199254740990, 9007199254740991 }))
    assert(almost.anomaly.observationCount == 5 and almost.anomaly.reason == "DEGENERATE_SCALE")
    assert(not almost.anomaly.sufficient and almost.anomaly.extremeCount == 0)
end)

test("scale epsilon exercised on both sides", function()
    local function scale(base)
        return analyze(sample({ base, base+1, base+2, base+3, base+4 })).anomaly
    end
    local usable, tiny = scale(100000000000), scale(10000000000000)
    assert(usable.logMAD > 1e-12 and usable.sufficient)
    assert(tiny.logMAD <= 1e-12 and not tiny.sufficient)
end)

test("invalid numeric fields, missing fields and malformed arrays reject safely", function()
    for _, field in ipairs({ "unitPrice", "quantity" }) do
        for _, value in ipairs({ 0, -1, 1.5, "200", false, {}, math.huge, -math.huge, 0/0, 9007199254740992 }) do
            local input = sample({ 100, 200 })
            input.priceLevels[2][field] = value
            local result, err = Statistics.Analyze(input)
            assert(result == nil and err:find("invalid " .. field, 1, true))
        end
        local input = sample({ 100 }); input.priceLevels[1][field] = nil
        assert(Statistics.Analyze(input) == nil)
    end
    for _, input in ipairs({ false, {}, { priceLevels = false }, { priceLevels = { false } },
        { priceLevels = { [2] = { unitPrice = 100, quantity = 1 } } },
        { priceLevels = { ["1"] = { unitPrice = 100, quantity = 1 } } } }) do
        local result, err = Statistics.Analyze(input)
        assert(result == nil and type(err) == "string")
    end
    assert(Statistics.Analyze(nil) == nil)
end)

test("unsafe integer sum rejects without rounding or partial results", function()
    local result, err = Statistics.Analyze(sample({ 100, 200 }, { 9007199254740991, 1 }))
    assert(result == nil and err:find("unsafe integer quantity sum", 1, true))
end)

print("PASS " .. passed .. " statistics offline tests (Lua 5.1)")
