-- Pure Lua 5.1: only language/library operations are available to Pricing.
local MP = {}
local env = { type = type, ipairs = ipairs }
setfenv(assert(loadfile("src/MarketPilot/Pricing.lua")), env)("MarketPilot", MP)
local targets = MP.Pricing.Targets
local function analysis()
    return { anomaly = { sufficient = true, levels = {
        { unitPrice = 24, class = "NORMAL" }, { unitPrice = 20, class = "NORMAL" },
        { unitPrice = 28, class = "NORMAL" },
    } }, clean = { weightedMedian = 24, q3 = 28 } }
end
local passed = 0
local function test(name, run) run(); passed = passed + 1; print("PASS " .. name) end

test("sufficient Fast is lowest NORMAL without undercut or silver rounding", function()
    local a = analysis(); local result = targets(a)
    assert(result.fast.status == "OK" and result.fast.copper == 20)
    assert(a.anomaly.levels[1].unitPrice == 24 and #a.anomaly.levels == 3)
end)
test("suspicious low cannot be Fast", function()
    local a = analysis(); a.anomaly.levels[4] = { unitPrice = 2, class = "SUSPICIOUS" }
    assert(targets(a).fast.copper == 20)
end)
test("extreme low cannot be Fast", function()
    local a = analysis(); a.anomaly.levels[4] = { unitPrice = 1, class = "EXTREME" }
    assert(targets(a).fast.copper == 20)
end)
test("Normal uses clean weighted median and Patient uses clean Q3 exactly", function()
    local a = analysis(); a.raw = { weightedMedian = 1000000000, q3 = 1000000000 }
    local result = targets(a)
    assert(result.normal.copper == 24 and result.patient.copper == 28)
end)
test("insufficient/missing model never manufactures robust targets", function()
    local a = analysis()
    for _, value in ipairs({ false, 1, "true", {} }) do
        a.anomaly.sufficient = value
        local result = targets(a)
        for _, key in ipairs({ "fast", "normal", "patient" }) do
            assert(result[key].status == "INSUFFICIENT" and result[key].copper == nil)
        end
    end
    a.anomaly.sufficient = nil
    assert(targets(a).fast.status == "INSUFFICIENT")
    assert(targets(nil).normal.status == "INSUFFICIENT")
    assert(targets({}).patient.status == "INSUFFICIENT")
end)
test("invalid/fractional copper is UNKNOWN, never rounded or replaced with zero", function()
    for _, value in ipairs({ 0, -1, 20.5, math.huge, 0/0, "20", false, 9007199254740992 }) do
        local a = analysis(); a.clean.weightedMedian, a.clean.q3 = value, value
        local result = targets(a)
        assert(result.normal.status == "UNKNOWN" and result.patient.status == "UNKNOWN")
        assert(result.normal.copper == nil and result.patient.copper == nil)
        a.anomaly.levels[1].unitPrice = value
        assert(targets(a).fast.status == "UNKNOWN")
    end
end)
test("no NORMAL levels and missing clean fields remain UNKNOWN", function()
    local a = analysis()
    for _, row in ipairs(a.anomaly.levels) do row.class = "SUSPICIOUS" end
    a.clean = {}
    local result = targets(a)
    assert(result.fast.status == "UNKNOWN" and result.normal.status == "UNKNOWN" and result.patient.status == "UNKNOWN")
end)
test("exact integer upper boundary is preserved", function()
    local a = analysis(); local maximum = 9007199254740991
    a.anomaly.levels = { { class = "NORMAL", unitPrice = maximum } }
    a.clean.weightedMedian, a.clean.q3 = maximum, maximum
    local result = targets(a)
    assert(result.fast.copper == maximum and result.normal.copper == maximum and result.patient.copper == maximum)
end)
test("real Statistics absurd high outlier cannot tilt clean targets", function()
    setfenv(assert(loadfile("src/MarketPilot/Statistics.lua")), _G)("MarketPilot", MP)
    local sample = { priceLevels = {} }
    for price = 20, 28 do sample.priceLevels[#sample.priceLevels + 1] = { unitPrice = price, quantity = 20 } end
    sample.priceLevels[#sample.priceLevels + 1] = { unitPrice = 1000000000, quantity = 1000000 }
    local a = assert(MP.Statistics.Analyze(sample)); local result = targets(a)
    assert(a.anomaly.extremeCount == 1 and a.raw.weightedMedian == 1000000000)
    assert(result.fast.copper == 20 and result.normal.copper == 24 and result.patient.copper == 26)
end)
print("PASS " .. passed .. " pure Pricing offline tests (Lua 5.1)")
