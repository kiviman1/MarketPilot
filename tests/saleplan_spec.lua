-- Pure Lua 5.1 validation/snapshot tests; no client APIs in this environment.
local MP = {}
local env = { type = type, math = math, ipairs = ipairs, setmetatable = setmetatable, error = error }
setfenv(assert(loadfile("src/MarketPilot/SalePlan.lua")), env)("MarketPilot", MP)
local Plan = MP.SalePlan
local function context()
    return { ahOpen = true, active = false, scannerState = "DONE", scanItemID = 2770, itemID = 2770,
        owned = 2, quantity = 2, durationHours = 12, targetKind = "FAST", sufficient = true,
        targets = { fast = { status = "OK", copper = 20 }, normal = { status = "OK", copper = 24 },
            patient = { status = "OK", copper = 28 } }, evidenceFresh = true,
        sellValid = true, copperSupported = true, postPresent = true }
end
local passed = 0
local function test(name, run) run(); passed = passed + 1; print("PASS " .. name) end

test("prepare creates exactly six primitive immutable snapshot fields", function()
    local input = context(); local plan = assert(Plan.Create(input, 123456))
    local copy = Plan.Copy(plan); local count = 0
    for key, value in pairs(copy) do
        assert(type(value) == "number" or type(value) == "string")
        assert(not pcall(function() plan[key] = value end))
        count = count + 1
    end
    assert(count == 6 and plan.itemID == 2770 and plan.createdAt == 123456)
    assert(not pcall(function() plan.extra = {} end) and getmetatable(plan) == false)
    input.quantity, input.targets.fast.copper, copy.quantity = 1, 300, 900
    assert(plan.quantity == 2 and plan.unitPrice == 20)
end)
test("all three targets use supplied Pricing output without arithmetic or recomputation", function()
    for kind, price in pairs({ FAST = 20, NORMAL = 24, PATIENT = 28 }) do
        local input = context(); input.targetKind = kind
        local plan = assert(Plan.Create(input, 1))
        assert(plan.unitPrice == price and plan.targetKind == kind and Plan.Total(plan.quantity, price) == price * 2)
    end
end)
test("insufficient/missing target never arms a plan", function()
    local input = context(); input.sufficient = false
    assert(Plan.Create(input, 1) == nil)
    input.sufficient = true; input.targets.fast.status = "INSUFFICIENT"
    assert(Plan.Create(input, 1) == nil)
    input.targets = nil; assert(Plan.Create(input, 1) == nil)
    input = context(); input.targetKind = "CUSTOM"; assert(Plan.Create(input, 1) == nil)
    input.targetKind = nil; assert(Plan.Create(input, 1) == nil)
end)
test("quantity and exact integer copper bounds reject invalid input", function()
    for _, value in ipairs({ 0, -1, 1.5, math.huge, 0/0, "20", false, 9007199254740992 }) do
        local input = context(); input.targets.fast.copper = value
        assert(Plan.Create(input, 1) == nil)
        input = context(); input.quantity = value
        assert(Plan.Create(input, 1) == nil)
    end
    local input = context(); input.quantity = 3; assert(Plan.Create(input, 1) == nil)
    input.quantity, input.owned = 1, 0; assert(Plan.Create(input, 1) == nil)
    input.owned = nil; assert(Plan.Create(input, 1) == nil)
end)
test("duration accepts only 12/24/48 hours", function()
    for _, hours in ipairs({ 12, 24, 48 }) do
        local input = context(); input.durationHours = hours; assert(Plan.Create(input, 1))
    end
    for _, hours in ipairs({ 1, 2, 3, 0, 72, 12.5, "12", false }) do
        local input = context(); input.durationHours = hours; assert(Plan.Create(input, 1) == nil)
    end
end)
test("AH, same-item DONE, idle scanner and fresh positive capabilities are mandatory", function()
    for _, key in ipairs({ "ahOpen", "evidenceFresh", "sellValid", "copperSupported", "postPresent", "sufficient" }) do
        for _, value in ipairs({ false, 1, "true" }) do
            local input = context(); input[key] = value; assert(Plan.Create(input, 1) == nil, key)
        end
        local input = context(); input[key] = nil; assert(Plan.Create(input, 1) == nil, key)
    end
    for _, state in ipairs({ "IDLE", "WAITING", "QUERYING", "COLLECTING", "ERROR" }) do
        local input = context(); input.scannerState = state; assert(Plan.Create(input, 1) == nil)
    end
    local input = context(); input.active = true; assert(Plan.Create(input, 1) == nil)
    input = context(); input.scanItemID = 2447; assert(Plan.Create(input, 1) == nil)
end)
test("total listed value rejects overflow at the exact integer boundary", function()
    local maximum = 9007199254740991
    assert(Plan.Total(1, maximum) == maximum)
    assert(Plan.Total(2, 4503599627370495) == 9007199254740990)
    assert(Plan.Total(3, 3002399751580330) == 9007199254740990)
    assert(Plan.Total(2, 4503599627370496) == nil)
    assert(Plan.Total(3, 3002399751580331) == nil)
    local input = context(); input.targets.fast.copper = maximum
    local plan, err = Plan.Create(input, 1)
    assert(plan == nil and err:find("exact integer", 1, true))
end)
test("unknown timestamp cannot create a misleading plan", function()
    assert(Plan.Create(context(), nil) == nil)
    assert(Plan.Create(context(), math.huge) == nil)
end)
print("PASS " .. passed .. " pure sale plan offline tests (Lua 5.1)")
