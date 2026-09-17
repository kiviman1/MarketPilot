-- Offline Lua 5.1 fixtures only. These do NOT validate Forever client APIs.
-- Run from repository root: lua probe/tests/probe_spec.lua
local function fixture(saved, configure)
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.MarketPilotProbeDB = saved
    env.SlashCmdList = {}
    local f = { output = {}, timers = {}, sent = 0, reads = 0, ready = true, count = 2 }
    env.print = function(line) f.output[#f.output + 1] = line end
    env.time = function() return 123456 end
    env.GetBuildInfo = function() return "fixture-only", "123", "fixture-date", 99999 end
    local frame = { registered = {} }
    function frame:RegisterEvent(event) self.registered[event] = true end
    function frame:IsEventRegistered(event) return self.registered[event] == true end
    function frame:SetScript(_, handler) self.handler = handler end
    env.CreateFrame = function() return frame end
    env.C_Timer = { After = function(_, callback) f.timers[#f.timers + 1] = callback end }
    env.C_AuctionHouse = {
        IsThrottledMessageSystemReady = function() return f.ready end,
        MakeItemKey = function(id) return { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 } end,
        SendSearchQuery = function(key, sorts, flag)
            assert(type(key) == "table" and next(sorts) == nil and flag == true)
            f.sent = f.sent + 1
        end,
        GetNumCommoditySearchResults = function(id) assert(type(id) == "number"); return f.count end,
        GetNumItemSearchResults = function(key) assert(type(key) == "table"); return f.count end,
        GetCommoditySearchResultInfo = function(_, index)
            f.reads = f.reads + 1
            return { quantity = 10, unitPrice = index * 100, customFlag = false }
        end,
        GetItemSearchResultInfo = function(_, index)
            f.reads = f.reads + 1
            return { quantity = 3, buyoutAmount = 999, auctionID = 1000 + index }
        end,
    }
    f.env, f.frame = env, frame
    if configure then configure(f) end
    local namespace = {}
    for _, file in ipairs({ "ProbeSupport.lua", "MarketPilotProbe.lua" }) do
        local chunk = assert(loadfile("probe/MarketPilotProbe/" .. file))
        setfenv(chunk, env)("MarketPilotProbe", namespace)
    end
    function f:event(event, ...) frame.handler(frame, event, ...) end
    function f:command(command) env.SlashCmdList.MARKETPILOTPROBE(command) end
    function f:has(fragment)
        for _, line in ipairs(self.output) do if line:find(fragment, 1, true) then return true end end
        return false
    end
    function f:scan() self:event("AUCTION_HOUSE_SHOW"); self:command("scan 2770") end
    f:event("ADDON_LOADED", "MarketPilotProbe")
    f.db = namespace.db
    return f
end

local passed = 0
local function test(name, run)
    run()
    passed = passed + 1
    print("PASS " .. name)
end

test("build, function surface, registered versus fired, slash status", function()
    local f = fixture()
    f:command("status")
    assert(f.db.session.build.interface == 99999)
    assert(f.db.session.functions.SendSearchQuery == true)
    local observation = f.db.session.events.AUCTION_HOUSE_SHOW
    assert(observation.registered == true and observation.fired == 0)
    f:event("AUCTION_HOUSE_SHOW")
    assert(observation.fired == 1 and f:has("ready=true"))
end)

test("registration errors, explicit false, and silent rejection", function()
    local f = fixture(nil, function(f)
        function f.frame:RegisterEvent(event)
            if event == "ITEM_SEARCH_RESULTS_UPDATED" then error("fixture unknown event") end
            if event == "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT" then return false end
            if event ~= "COMMODITY_SEARCH_RESULTS_UPDATED" then self.registered[event] = true end
        end
    end)
    for _, event in ipairs({ "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT", "COMMODITY_SEARCH_RESULTS_UPDATED" }) do
        assert(f.db.session.events[event].registered == false)
    end
    assert(f:has("fixture unknown event"))
end)

test("missing APIs remain UNKNOWN without breaking commands", function()
    local f = fixture(nil, function(f) f.env.C_AuctionHouse = nil end)
    f:command("status"); f:scan(); f:command("dump")
    assert(f.db.session.functions.MakeItemKey == false)
    assert(f.db.session.throttle.state == "UNKNOWN" and f.sent == 0)
    assert(not f:has("command failed"))
end)

test("closed AH and invalid IDs never send", function()
    local f = fixture()
    f:command("scan 2770")
    f:event("AUCTION_HOUSE_SHOW")
    for _, id in ipairs({ "", "-1", "0", "1.5", "1e3", "nan", "2770 extra" }) do f:command("scan " .. id) end
    assert(f.sent == 0)
end)

test("throttle false blocks; ready event does not automatically query", function()
    local f = fixture()
    f.ready = false
    f:scan()
    assert(f.sent == 0 and f.db.session.throttle.state == false)
    f.ready = true
    f:event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    assert(f.sent == 0)
    f:command("scan 2770")
    assert(f.sent == 1)
end)

test("unknown readiness permits one explicitly requested diagnostic query", function()
    local f = fixture()
    f.ready = "unexpected"
    f:scan()
    f:command("scan 2771")
    assert(f.sent == 1 and f.db.session.throttle.state == "UNKNOWN")
end)

test("commodity correlation and bounded samples", function()
    local f = fixture()
    f.count = 100
    f:scan()
    f:event("COMMODITY_SEARCH_RESULTS_UPDATED", 999)
    f:event("COMMODITY_SEARCH_RESULTS_UPDATED", "2770")
    f:event("COMMODITY_SEARCH_RESULTS_UPDATED")
    assert(f.reads == 0 and f.db.lastSuccess == nil)
    f:event("COMMODITY_SEARCH_RESULTS_UPDATED", 2770)
    assert(f.reads == 5 and #f.db.lastSuccess.samples == 5)
    assert(f.db.lastSuccess.kind == "commodity" and f.db.lastSuccess.rowCount == 100)
    assert(f:has("quantity=10 unitPrice=100 auctionID=UNKNOWN"))
    f:event("COMMODITY_SEARCH_RESULTS_UPDATED", 2770)
    assert(f.reads == 5)
end)

test("item variant correlation and raw auction fields", function()
    local f = fixture()
    f:scan()
    local key = f.env.C_AuctionHouse.MakeItemKey(2770)
    key.itemLevel = 5
    f:event("ITEM_SEARCH_RESULTS_UPDATED", key)
    f:event("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 999 })
    f:event("ITEM_SEARCH_RESULTS_UPDATED")
    assert(f.reads == 0)
    key.itemLevel = 0
    f:event("ITEM_SEARCH_RESULTS_UPDATED", key)
    assert(f.db.lastSuccess.kind == "item")
    assert(f:has("quantity=3 unitPrice=UNKNOWN auctionID=1001"))
    assert(f.db.lastSuccess.samples[1]:find('"buyoutAmount"=999', 1, true))
end)

test("unexpected count types never become zero or overwrite success", function()
    local f = fixture()
    f:scan(); f:event("COMMODITY_SEARCH_RESULTS_UPDATED", 2770)
    local success = f.db.lastSuccess
    for _, count in ipairs({ "2", -1, 1.5, math.huge, 0/0, false }) do
        f.count = count
        f:command("scan 2770"); f:event("COMMODITY_SEARCH_RESULTS_UPDATED", 2770)
        assert(f.db.lastSuccess == success and f.db.lastQuery.status == "FAILED")
    end
    f.count = nil
    f:command("scan 2770"); f:event("COMMODITY_SEARCH_RESULTS_UPDATED", 2770)
    assert(f.db.lastSuccess == success)
end)

test("zero rows are a valid empty observation without invented prices", function()
    local f = fixture()
    f.count = 0
    f:scan(); f:event("COMMODITY_SEARCH_RESULTS_UPDATED", 2770)
    assert(f.db.lastSuccess.rowCount == 0 and #f.db.lastSuccess.samples == 0 and f.reads == 0)
end)

test("partial row failure preserves previous success and original error", function()
    local f = fixture()
    f:scan(); f:event("COMMODITY_SEARCH_RESULTS_UPDATED", 2770)
    local success = f.db.lastSuccess
    f.env.C_AuctionHouse.GetCommoditySearchResultInfo = function(_, index)
        if index == 2 then error("fixture row signature failure") end
        return { quantity = 1 }
    end
    f:command("scan 2770"); f:event("COMMODITY_SEARCH_RESULTS_UPDATED", 2770)
    assert(f.db.lastSuccess == success and f:has("fixture row signature failure"))
    f.env.C_AuctionHouse.GetCommoditySearchResultInfo = function() return nil end
    f:command("scan 2770"); f:event("COMMODITY_SEARCH_RESULTS_UPDATED", 2770)
    assert(f.db.lastSuccess == success)
end)

test("failed query is not retried and later events cannot create success", function()
    local f = fixture(nil, function(f)
        f.env.C_AuctionHouse.SendSearchQuery = function() f.sent = f.sent + 1; error("fixture original signature error") end
    end)
    f:scan(); f:event("COMMODITY_SEARCH_RESULTS_UPDATED", 2770)
    assert(f.sent == 1 and f.reads == 0 and f:has("fixture original signature error"))
    assert(f.db.lastSuccess == nil)
    f.env.C_AuctionHouse.SendSearchQuery = function() return false end
    f:command("scan 2770"); f:event("COMMODITY_SEARCH_RESULTS_UPDATED", 2770)
    assert(f.db.lastSuccess == nil)
end)

test("invalid key never triggers guessed fallback", function()
    local f = fixture(nil, function(f) f.env.C_AuctionHouse.MakeItemKey = function() return {} end end)
    f:scan()
    assert(f.sent == 0 and f:has("unusable key"))
end)

test("timeout and AH close cancel pending correlation", function()
    local f = fixture()
    f:scan(); f.timers[1]()
    f:event("COMMODITY_SEARCH_RESULTS_UPDATED", 2770)
    assert(f.reads == 0 and f:has("within 15s"))
    f:command("scan 2770")
    f:event("AUCTION_HOUSE_CLOSED"); f:event("COMMODITY_SEARCH_RESULTS_UPDATED", 2770)
    assert(f.reads == 0)
end)

test("primitive dump avoids cycles and metamethods, retains every field", function()
    local f = fixture()
    local row = setmetatable({ quantity = 0, unitPrice = 0, auctionID = 123, enabled = false }, {
        __tostring = function() error("must not stringify a table") end,
        __index = function() error("must not synthesize a field") end,
    })
    row.nested = row
    row[row] = "skip table key"
    for i = 1, 30 do row["custom" .. i] = i end
    f.env.C_AuctionHouse.GetCommoditySearchResultInfo = function() return row end
    f:scan(); f:event("COMMODITY_SEARCH_RESULTS_UPDATED", 2770)
    assert(f.db.lastSuccess.samples[1]:find('"custom30"=30', 1, true))
    assert(f:has("quantity=0 unitPrice=0 auctionID=123") and not f:has("handler failed"))
end)

test("schema-1 migration preserves old data but does not certify it", function()
    local legacy = { schema = 1, logs = {}, lastResult = { itemID = 2770 }, build = { build = "old" } }
    local f = fixture(legacy)
    f:command("dump")
    assert(f.db == legacy and legacy.schema == 2 and legacy.build.build == "old")
    assert(f.db.lastSuccess == nil and f:has("UNVERIFIED"))
end)

test("future schema preserved; explicit clear provides reset", function()
    local future = { schema = 99, sentinel = "retain" }
    local f = fixture(future)
    f:scan(); f:event("COMMODITY_SEARCH_RESULTS_UPDATED", 2770)
    assert(f.env.MarketPilotProbeDB == future and future.sentinel == "retain")
    f:command("clear")
    assert(f.env.MarketPilotProbeDB.schema == 2 and f.env.MarketPilotProbeDB.lastSuccess == nil)
end)

test("reload fixture retains success evidence, commands and bounded logs", function()
    local f = fixture()
    f:scan(); f:event("COMMODITY_SEARCH_RESULTS_UPDATED", 2770)
    local snapshot = f.db.lastSuccess.evidence
    f:event("AUCTION_HOUSE_SHOW")
    assert(snapshot.events.AUCTION_HOUSE_SHOW.fired == 1)
    local reloaded = fixture(f.db)
    reloaded:command("dump")
    assert(reloaded:has("saved lastSuccess") and reloaded:has("saved sample[1]"))
    assert(reloaded.db.lastSuccess.evidence == snapshot)
    assert(reloaded.db.session.events.AUCTION_HOUSE_SHOW.fired == 0)
    for _ = 1, 20 do reloaded:command("status") end
    assert(#reloaded.db.logs == 200 and not reloaded:has("command failed"))
end)

test("unchecked registration and unavailable build stay UNKNOWN", function()
    local f = fixture(nil, function(f)
        f.frame.IsEventRegistered = nil
        f.env.GetBuildInfo = function() error("fixture build failure") end
    end)
    f:command("status")
    assert(f.db.session.events.AUCTION_HOUSE_SHOW.registered == "UNKNOWN")
    assert(f.db.session.build.interface == nil and f:has("fixture build failure"))
    assert(not f:has("command failed"))
end)

test("missing readers and count exceptions cannot save success", function()
    local f = fixture()
    f.env.C_AuctionHouse.GetNumCommoditySearchResults = nil
    f:scan(); f:event("COMMODITY_SEARCH_RESULTS_UPDATED", 2770)
    assert(f.db.lastSuccess == nil and f:has("GetNumCommoditySearchResults unavailable"))
    f.env.C_AuctionHouse.GetNumCommoditySearchResults = function() error("fixture count failure") end
    f:command("scan 2770"); f:event("COMMODITY_SEARCH_RESULTS_UPDATED", 2770)
    assert(f.db.lastSuccess == nil and f:has("fixture count failure"))
    f.env.C_AuctionHouse.GetNumCommoditySearchResults = function() return 1 end
    f.env.C_AuctionHouse.GetCommoditySearchResultInfo = nil
    f:command("scan 2770"); f:event("COMMODITY_SEARCH_RESULTS_UPDATED", 2770)
    assert(f.db.lastSuccess == nil and f:has("GetCommoditySearchResultInfo unavailable"))
end)

test("old timer cannot cancel a new query; missing timer allows manual recovery", function()
    local f = fixture()
    f:scan(); f:event("COMMODITY_SEARCH_RESULTS_UPDATED", 2770)
    f:command("scan 2771")
    f.timers[1]()
    f:event("COMMODITY_SEARCH_RESULTS_UPDATED", 2771)
    assert(f.db.lastSuccess.itemID == 2771)
    f.env.C_Timer = nil
    f:command("scan 2770")
    assert(f:has("timeout timer unavailable"))
    f:event("AUCTION_HOUSE_CLOSED"); f:event("AUCTION_HOUSE_SHOW")
    f:command("scan 2771"); f:event("COMMODITY_SEARCH_RESULTS_UPDATED", 2771)
    assert(f.db.lastSuccess.itemID == 2771 and not f:has("command failed"))
end)

test("event arguments and large numeric primitive fields are preserved", function()
    local f = fixture()
    f:event("AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED", false, nil, { itemID = 2770 }, "extra")
    assert(f:has('arg1=false arg2=UNKNOWN arg3={"itemID"=2770} arg4="extra"'))
    f.env.C_AuctionHouse.GetItemSearchResultInfo = function() return { auctionID = 123456789012345 } end
    f:scan(); f:event("ITEM_SEARCH_RESULTS_UPDATED", f.env.C_AuctionHouse.MakeItemKey(2770))
    assert(f:has("auctionID=123456789012345"))
end)

print("PASS " .. passed .. " offline tests; no in-game validation performed")
