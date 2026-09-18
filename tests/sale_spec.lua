-- Read-only bag/sell boundary fixtures; no client behavior is confirmed by these.
local ROOT = "src/MarketPilot/"
local function read(path)
    local file = assert(io.open(ROOT .. path, "rb")); local value = file:read("*a"); file:close(); return value
end
local function fixture()
    local f = { bags = { [0] = { { itemID = 2770, stackCount = 10 }, { itemID = 9999, stackCount = 1 } },
        [1] = { { itemID = 2770, stackCount = 27 }, { itemID = 2447, stackCount = 3 } } }, calls = {}, output = {} }
    local env = setmetatable({}, { __index = _G }); f.env = env
    env.NUM_BAG_SLOTS = 4
    env.C_Container = {
        GetContainerNumSlots = function(bag) return #(f.bags[bag] or {}) end,
        GetContainerItemInfo = function(bag, slot) return (f.bags[bag] or {})[slot] end,
    }
    env.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
    env.C_AuctionHouse = {
        IsSellItemValid = function(location, displayError)
            assert(location.bag == 0 and location.slot == 1 and displayError == false)
            f.calls.valid = (f.calls.valid or 0) + 1; return true
        end,
        CalculateCommodityDeposit = function(id, duration, quantity)
            f.calls.deposit = { id, duration, quantity }; return 20
        end,
        SupportsCopperValues = function() return true end,
        ShouldAutoPopulatePrice = function() return false end,
        PostCommodity = function() f.calls.post = true; error("MUST NEVER BE CALLED") end,
    }
    f.mp = {}
    for _, name in ipairs({ "Items", "AuctionAPI", "Pricing", "Inventory", "SaleAssistant" }) do
        setfenv(assert(loadfile(ROOT .. name .. ".lua")), env)("MarketPilot", f.mp)
    end
    f.inventory = f.mp.Inventory.New(f.mp.Items)
    f.inventory:Refresh()
    local scanner = { ahOpen = true, state = "IDLE", starts = 0 }
    function scanner:IsActive() return self.state == "QUERYING" end
    function scanner:Start(id) self.starts = self.starts + 1; self.itemID = id; self.state = "QUERYING" end
    f.scanner = scanner
    f.sale = f.mp.SaleAssistant.New(f.inventory, scanner, f.mp.AuctionAPI, f.mp.Pricing,
        function(message) f.output[#f.output + 1] = message end)
    return f
end
local passed = 0
local function test(name, run) run(); passed = passed + 1; print("PASS " .. name) end

test("only configured items aggregate across bags and slots", function()
    local f = fixture()
    assert(f.inventory.status == "OK" and f.inventory:Owned(2770) == 37 and f.inventory:Owned(2447) == 3)
    assert(f.inventory.items[9999] == nil and f.inventory:Owned(2318) == 0)
    assert(#f.inventory.items[2770].slots == 2)
end)
test("equipped reagent bag is included when client exposes total bag count", function()
    local f = fixture(); f.env.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5
    f.bags[5] = { { itemID = 2770, stackCount = 2 } }
    f.inventory:Refresh(); assert(f.inventory:Owned(2770) == 39)
    assert(f.bags[5][1].stackCount == 2) -- Read-only input.
end)
test("bag read failures discard partial/stale totals instead of inventing zero", function()
    for _, value in ipairs({ 0, -1, 1.5, math.huge, 0/0, "3", false }) do
        local f = fixture(); f.bags[1][1].stackCount = value
        assert(not f.inventory:Refresh() and f.inventory.status == "UNKNOWN")
        assert(f.inventory:Owned(2770) == nil and next(f.inventory.items) == nil)
    end
    local f = fixture(); f.env.C_Container.GetContainerItemInfo = function() error("fixture bag error") end
    assert(not f.inventory:Refresh() and f.inventory.error:find("fixture bag error", 1, true))
    f.env.C_Container = nil; assert(not f.inventory:Refresh())
end)
test("selection refuses parallel queries including a different item", function()
    local f = fixture()
    assert(f.sale:Select(2770)); assert(not f.sale:Select(2770)); assert(not f.sale:Select(2447))
    assert(f.scanner.starts == 1 and f.sale.itemID == 2770)
end)
test("quantity is integral and bounded by owned; duration is only 12/24/48", function()
    local f = fixture(); f.sale:Select(2770)
    for _, quantity in ipairs({ 0, -1, 38, 1.5, math.huge, 0/0, "3", false }) do
        assert(not f.sale:SetQuantity(quantity) and f.sale.quantity == 37)
    end
    assert(not f.sale:SetQuantity(nil)); assert(f.sale:SetQuantity(1)); assert(f.sale:SetQuantity(37))
    for _, hours in ipairs({ 12, 24, 48 }) do assert(f.sale:SetDuration(hours) and f.sale.duration == hours) end
    for _, hours in ipairs({ 0, 1, 2, 3, 72, "24", false }) do assert(not f.sale:SetDuration(hours) and f.sale.duration == 48) end
end)
test("slot refresh invalidates old generation and location lookup rejects silent slot replacement", function()
    local f = fixture(); f.sale:Select(2770)
    local old = f.inventory.items[2770].slots[1]
    assert(f.inventory:Location(2770).slot == 1)
    f.bags[0][1] = { itemID = 2318, stackCount = 4 }
    assert(f.inventory:Location(2770) == nil)
    f.sale:RefreshInventory()
    assert(f.inventory.generation ~= old.generation and f.sale.quantity == 27)
    assert(f.inventory:Location(2770).bag == 1)
    f.bags[1] = {}; f.sale:RefreshInventory()
    assert(f.sale.itemID == nil and f.sale.quantity == nil and f.inventory:Location(2770) == nil)
end)
test("candidate checks use only documented argument shapes and preserve false/zero", function()
    local f = fixture(); f.sale:Select(2770); f.sale:SetQuantity(10); f.sale:SetDuration(24)
    f.env.C_AuctionHouse.CalculateCommodityDeposit = function(id, duration, quantity)
        assert(id == 2770 and duration == 2 and quantity == 10); return 0
    end
    f.sale:CheckCapabilities()
    local result = f.sale.probe
    assert(result.deposit == 0 and result.capabilities[4].value == false)
    assert(result.capabilities[5].presence == "PRESENT" and result.capabilities[5].status == "UNKNOWN")
    assert(f.calls.valid == 1 and f.calls.post == nil)
end)
test("probe re-reads bags before validating; no stale counts or location is passed", function()
    local f = fixture(); f.sale:Select(2770); f.sale:CheckCapabilities()
    f.bags = {}; f.sale:CheckCapabilities()
    assert(f.calls.valid == 1 and f.sale.itemID == nil and f.sale.probe.deposit == nil)
    assert(f.calls.post == nil)
end)
test("every missing/throwing/malformed candidate stays UNKNOWN without alternative signatures", function()
    for _, name in ipairs({ "IsSellItemValid", "CalculateCommodityDeposit", "SupportsCopperValues", "ShouldAutoPopulatePrice" }) do
        for _, mode in ipairs({ "missing", "throw", "malformed", "nil" }) do
            local f = fixture(); local calls = 0
            f.env.C_AuctionHouse[name] = mode ~= "missing" and function()
                calls = calls + 1
                if mode == "throw" then error("fixture candidate error") end
                if mode == "nil" then return nil end
                return {}
            end or nil
            f.sale:Select(2770); f.sale:CheckCapabilities()
            for _, row in ipairs(f.sale.probe.capabilities) do
                if row.name == name then assert(row.status == "UNKNOWN" and row.value == nil) end
            end
            assert(calls == (mode == "missing" and 0 or 1) and f.calls.post == nil)
        end
    end
end)
test("presence-only checks invoke nothing, close blocks candidate calls", function()
    local f = fixture()
    for name in pairs(f.env.C_AuctionHouse) do f.env.C_AuctionHouse[name] = function() error("presence must not call") end end
    assert(#f.mp.AuctionAPI:SellCapabilities().capabilities == 5)
    f.scanner.ahOpen = false; assert(not f.sale:CheckCapabilities() and #f.output == 0)
end)
test("static boundaries exclude AH calls from presentation/pricing/inventory and all mutation APIs", function()
    for _, name in ipairs({ "UI.lua", "SaleUI.lua", "UIViewModel.lua", "Pricing.lua", "Inventory.lua", "SaleAssistant.lua" }) do
        local source = read(name)
        assert(not source:find("C_AuctionHouse", 1, true), name)
        for _, forbidden in ipairs({ "PickupContainerItem", "UseContainerItem", "DeleteCursorItem", "SendMail", "SecureActionButtonTemplate",
            "HookScript", "hooksecurefunc", "OnUpdate", "C_Timer", "SavedVariables" }) do
            assert(not source:find(forbidden, 1, true), name .. " " .. forbidden)
        end
    end
    local api = read("AuctionAPI.lua")
    assert(not api:match("PostCommodity%s*%(") and not api:match('call%("PostCommodity"'))
end)
print("PASS " .. passed .. " inventory/sale/API offline tests (Lua 5.1); beta compatibility UNKNOWN")
