-- Deterministic offline Lua 5.1 tests, not a substitute for beta client testing.
-- Run from repository root: lua tests/marketpilot_spec.lua
local ROOT = "src/MarketPilot/"
local function read(path)
    local file = assert(io.open(path, "rb"))
    local contents = file:read("*a")
    file:close()
    return contents
end

local files = {}
local toc = read(ROOT .. "MarketPilot.toc")
for line in toc:gmatch("[^\r\n]+") do
    if line:sub(1, 1) ~= "#" then files[#files + 1] = line end
end

local function fixture(configure)
    local env = setmetatable({}, { __index = _G })
    env._G, env.SlashCmdList = env, {}
    local f = { env = env, ready = true, sent = 0, reads = {}, readinessCalls = 0, output = {}, rows = {
        { unitPrice = 200, quantity = 285, auctionID = 25442, totalNumberOfOwners = 20 },
        { unitPrice = 300, quantity = 10 },
    } }
    env.time = function() return 123456 end
    env.print = function(message) f.output[#f.output + 1] = message end
    local frame = { registered = {} }
    function frame:RegisterEvent(event) self.registered[event] = true end
    function frame:SetScript(kind, callback)
        assert(kind == "OnEvent", "no per-frame scripts")
        self.handler = callback
    end
    env.CreateFrame = function() return frame end
    env.C_AuctionHouse = {
        IsThrottledMessageSystemReady = function()
            f.readinessCalls = f.readinessCalls + 1
            return f.ready
        end,
        MakeItemKey = function(id)
            assert(id == 2770)
            return { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
        end,
        SendSearchQuery = function(key, sorts, flag)
            assert(key.itemID == 2770 and next(sorts) == nil and flag == true)
            f.sent = f.sent + 1
        end,
        GetNumCommoditySearchResults = function(id)
            assert(id == 2770)
            if f.count ~= nil then return f.count end
            return #f.rows
        end,
        GetCommoditySearchResultInfo = function(id, index)
            assert(id == 2770 and f.mp.scanner.state == "COLLECTING")
            f.reads[#f.reads + 1] = index
            return f.rows[index]
        end,
    }
    f.frame = frame
    if configure then configure(f) end
    f.mp = {}
    for _, name in ipairs(files) do
        local chunk = assert(loadfile(ROOT .. name))
        setfenv(chunk, env)("MarketPilot", f.mp)
    end
    f.scanner = f.mp.scanner
    function f:event(event, ...) self.frame.handler(self.frame, event, ...) end
    function f:command(command) self.env.SlashCmdList.MARKETPILOT(command) end
    function f:has(fragment)
        for _, line in ipairs(self.output) do if line:find(fragment, 1, true) then return true end end
        return false
    end
    function f:start() self:event("AUCTION_HOUSE_SHOW"); self:command("scan") end
    function f:complete() self:event("COMMODITY_SEARCH_RESULTS_UPDATED", 2770) end
    return f
end

local passed = 0
local function test(name, run)
    run()
    passed = passed + 1
    print("PASS " .. name)
end

test("TOC order and static production boundaries", function()
    assert(table.concat(files, ",") == "Items.lua,AuctionAPI.lua,Statistics.lua,Scanner.lua,Core.lua")
    assert(not toc:find("SavedVariables", 1, true))
    for _, name in ipairs(files) do
        local source = read(ROOT .. name)
        assert(not source:find("auctionID", 1, true), name)
        assert(not source:find("OnUpdate", 1, true), name)
        assert(not source:find("C_Timer", 1, true), name)
        assert(not source:find("MarketPilotDB", 1, true), name)
        assert(not source:find("SPECIFIC_SEARCH_READY", 1, true), name)
        if name ~= "AuctionAPI.lua" then assert(not source:find("C_AuctionHouse", 1, true), name) end
    end
end)

test("initial IDLE, closed-AH rejection, strict configured command", function()
    local f = fixture()
    assert(f.scanner.state == "IDLE" and f.scanner.sample == nil)
    f:command("status")
    assert(f:has("state=IDLE") and f:has("itemID=2770"))
    f:command("scan")
    assert(f.sent == 0 and f.scanner.state == "ERROR")
    f:event("AUCTION_HOUSE_SHOW")
    assert(f.sent == 0) -- Opening AH is never an automatic scan.
    f:command("scan 1234")
    assert(f.sent == 0 and f:has("commands: /mp scan"))
    f:command("  SCAN  ")
    assert(f.sent == 1 and f.scanner.state == "QUERYING")
end)

test("throttle queues one intent and ready advances exactly one query", function()
    local f = fixture()
    f.ready = false
    f:start()
    assert(f.sent == 0 and f.scanner.state == "WAITING")
    f:command("scan"); f:command("status")
    assert(f.readinessCalls == 1) -- No polling from duplicate scan/status.
    f:event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    assert(f.sent == 0 and f.scanner.state == "WAITING")
    f.ready = true
    f:event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    f:event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    f:command("scan")
    assert(f.sent == 1 and f.readinessCalls == 3 and f.scanner.state == "QUERYING")
end)

test("ready event without pending scan does not query", function()
    local f = fixture()
    f:event("AUCTION_HOUSE_SHOW"); f:event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    assert(f.sent == 0 and f.readinessCalls == 0 and f.scanner.state == "IDLE")
end)

test("unexpected and mismatched results do not complete", function()
    local f = fixture()
    f:complete()
    f.ready = false
    f:start(); f:complete()
    assert(f.scanner.state == "WAITING" and #f.reads == 0)
    f.ready = true
    f:event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    for _, value in ipairs({ 999, "2770", {}, false }) do f:event("COMMODITY_SEARCH_RESULTS_UPDATED", value) end
    f:event("COMMODITY_SEARCH_RESULTS_UPDATED")
    assert(f.scanner.state == "QUERYING" and f.scanner.sample == nil and #f.reads == 0)
    f:complete()
    assert(f.scanner.state == "DONE")
end)

test("all levels normalized independently in order with exact copper", function()
    local f = fixture()
    f.rows = {
        { unitPrice = 300, quantity = 1 }, { unitPrice = 200, quantity = 285 },
        { unitPrice = 200, quantity = 2 }, { unitPrice = 999, quantity = 3 },
        { unitPrice = 150, quantity = 4 }, { unitPrice = 500, quantity = 5 },
        { unitPrice = 123456789012345, quantity = 6 },
    }
    f:start(); f:complete()
    local sample, summary = f.scanner.sample, f.scanner.summary
    assert(f.scanner.state == "DONE" and #f.reads == 7 and #sample.priceLevels == 7)
    assert(sample.itemID == 2770 and sample.capturedAt == 123456)
    assert(summary.totalQuantity == 306 and summary.lowest == 150 and summary.highest == 123456789012345)
    for index, row in ipairs(f.rows) do
        local level, keys = sample.priceLevels[index], 0
        assert(level ~= row and level.unitPrice == row.unitPrice and level.quantity == row.quantity)
        for key in pairs(level) do assert(key == "unitPrice" or key == "quantity"); keys = keys + 1 end
        assert(keys == 2 and f.reads[index] == index)
    end
    f.rows[1].unitPrice = 9999
    assert(sample.priceLevels[1].unitPrice == 300)
    assert(f:has("levels=7 totalQuantity=306 lowestUnitPrice=150 highestUnitPrice=123456789012345"))
end)

test("missing or invalid row fields reject whole sample without fabrication", function()
    local invalid = { false, "200", 0, -1, 1.5, math.huge, 0/0, 9007199254740992, {} }
    for _, field in ipairs({ "unitPrice", "quantity" }) do
        for index = 0, #invalid do
            local f = fixture()
            f.rows[2][field] = index == 0 and nil or invalid[index]
            f:start(); f:complete()
            assert(f.scanner.state == "ERROR" and f.scanner.sample == nil and f.scanner.summary == nil)
            assert(f:has("invalid/missing " .. field) and f:has("levels=UNKNOWN totalQuantity=UNKNOWN"))
        end
    end
end)

test("invalid counts and non-table rows remain UNKNOWN", function()
    for _, count in ipairs({ "2", false, -1, 0.5, math.huge, 0/0 }) do
        local f = fixture()
        f.count = count
        f:start(); f:complete()
        assert(f.scanner.state == "ERROR" and f:has("invalid commodity result count") and #f.reads == 0)
    end
    for _, row in ipairs({ false, 200, "row" }) do
        local f = fixture()
        f.rows[2] = row
        f:start(); f:complete()
        assert(f.scanner.sample == nil and f:has("row 2 is not a table"))
    end
    local f = fixture()
    f.count = 3 -- The third row is nil, not a valid empty result.
    f:start(); f:complete()
    assert(f.scanner.state == "ERROR" and f:has("row 3 is not a table"))
end)

test("empty result does not invent a lowest/highest price", function()
    local f = fixture()
    f.rows = {}
    f:start(); f:complete()
    assert(f.scanner.state == "DONE" and #f.scanner.sample.priceLevels == 0)
    assert(f:has("levels=0 totalQuantity=0 lowestUnitPrice=UNKNOWN highestUnitPrice=UNKNOWN"))
end)

test("AH close cancels both waiting and active scans; reopen requires command", function()
    for _, ready in ipairs({ false, true }) do
        local f = fixture()
        f.ready = ready
        f:start()
        local sent = f.sent
        f:event("AUCTION_HOUSE_CLOSED")
        assert(f.scanner.state == "IDLE" and f.scanner.sample == nil and not f.scanner.ahOpen)
        f.ready = true
        f:event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY"); f:complete()
        f:event("AUCTION_HOUSE_SHOW"); f:complete()
        assert(f.sent == sent and f.scanner.state == "IDLE")
        f:command("scan"); f:complete()
        assert(f.sent == sent + 1 and f.scanner.state == "DONE")
    end
end)

test("duplicate results cannot complete twice; next manual scan replaces sample", function()
    local f = fixture()
    f:start(); f:complete()
    local sample, printed = f.scanner.sample, #f.output
    f:complete(); f:event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    assert(f.scanner.sample == sample and #f.output == printed and #f.reads == 2 and f.sent == 1)
    f:command("scan")
    assert(f.scanner.sample == nil and f.sent == 2)
    f:complete()
    assert(f.scanner.sample ~= sample and f.scanner.state == "DONE")
    f:event("AUCTION_HOUSE_CLOSED")
    assert(f.scanner.sample == nil and f.scanner.summary == nil)
end)

test("missing APIs fail explicitly with no query", function()
    for _, name in ipairs({ "MakeItemKey", "SendSearchQuery", "IsThrottledMessageSystemReady",
        "GetNumCommoditySearchResults", "GetCommoditySearchResultInfo" }) do
        local f = fixture(function(f) f.env.C_AuctionHouse[name] = nil end)
        f:start()
        assert(f.scanner.state == "ERROR" and f.sent == 0 and f:has("UNKNOWN: missing API " .. name))
    end
end)

test("unknown readiness never sends a query", function()
    for _, value in ipairs({ "true", 1, {} }) do
        local f = fixture()
        f.ready = value
        f:start()
        assert(f.scanner.state == "ERROR" and f.sent == 0 and f:has("readiness must be boolean"))
    end
    local f = fixture()
    f.ready = nil
    f:start()
    assert(f.scanner.state == "ERROR" and f.sent == 0)
end)

test("API exceptions preserve original errors without alternative calls", function()
    for _, name in ipairs({ "MakeItemKey", "SendSearchQuery", "IsThrottledMessageSystemReady",
        "GetNumCommoditySearchResults", "GetCommoditySearchResultInfo" }) do
        local calls = 0
        local f = fixture(function(f)
            f.env.C_AuctionHouse[name] = function() calls = calls + 1; error("original fixture " .. name) end
        end)
        f:start(); f:complete(); f:complete()
        assert(f.scanner.state == "ERROR" and f.scanner.sample == nil and calls == 1)
        assert(f:has("original fixture " .. name))
    end
end)

test("bad item key and explicit send rejection do not await results", function()
    for _, key in ipairs({ false, {}, { itemID = 999 }, "key" }) do
        local f = fixture(function(f) f.env.C_AuctionHouse.MakeItemKey = function() return key end end)
        f:start(); f:complete()
        assert(f.scanner.state == "ERROR" and f.sent == 0 and f:has("invalid/mismatched key"))
    end
    local f = fixture(function(f) f.env.C_AuctionHouse.SendSearchQuery = function() return false end end)
    f:start(); f:complete()
    assert(f.scanner.state == "ERROR" and #f.reads == 0 and f:has("SendSearchQuery returned false"))
end)

test("exact integer boundary and summed-quantity overflow", function()
    local f = fixture()
    f.rows = { { unitPrice = 9007199254740991, quantity = 9007199254740991 } }
    f:start(); f:complete()
    assert(f.scanner.state == "DONE" and f.scanner.sample.priceLevels[1].unitPrice == 9007199254740991)
    assert(f:has("highestUnitPrice=9007199254740991"))
    f.rows[2] = { unitPrice = 1, quantity = 1 }
    f:command("scan"); f:complete()
    assert(f.scanner.state == "ERROR" and f.scanner.sample == nil and f:has("exceeds exact integer range"))
end)

test("event registration failure blocks scanning with visible error", function()
    local f = fixture(function(f)
        function f.frame:RegisterEvent(event)
            if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then error("fixture unavailable event") end
            self.registered[event] = true
        end
    end)
    f:start(); f:command("status")
    assert(f.scanner.state == "ERROR" and f.sent == 0 and f:has("fixture unavailable event"))
end)

test("statistics runs once per completion and status retains compact analysis", function()
    local f = fixture()
    local calls, analyze = 0, f.mp.Statistics.Analyze
    f.mp.Statistics.Analyze = function(value) calls = calls + 1; return analyze(value) end
    f:start()
    assert(f.scanner.analysis == nil)
    f:complete(); f:complete(); f:command("status")
    assert(calls == 1 and f.scanner.analysis.status == "INSUFFICIENT")
    assert(f:has("rawMedian=200 cleanMedian=200 suspicious=0 extreme=0 anomalySufficient=no"))
    assert(#f.scanner.sample.priceLevels == 2)
    f:command("scan")
    assert(f.scanner.analysis == nil)
    f:complete()
    assert(calls == 2)
    f:event("AUCTION_HOUSE_CLOSED")
    assert(f.scanner.analysis == nil)
end)

test("scanner retains raw absurd level while clean statistics exclude it", function()
    local f = fixture()
    f.rows = {}
    for price = 8000, 12000, 500 do f.rows[#f.rows + 1] = { unitPrice = price, quantity = 20 } end
    f.rows[#f.rows + 1] = { unitPrice = 1000000000, quantity = 1000000 }
    f:start(); f:complete()
    assert(f.scanner.state == "DONE" and #f.scanner.sample.priceLevels == 10)
    assert(f.scanner.analysis.raw.weightedMedian == 1000000000)
    assert(f.scanner.analysis.clean.weightedMedian == 10000)
    assert(f:has("rawMedian=1000000000 cleanMedian=10000 suspicious=0 extreme=1 anomalySufficient=yes"))
    f.rows[1].quantity = 0
    f:command("scan"); f:complete()
    assert(f.scanner.state == "ERROR" and f.scanner.analysis == nil)
end)

print("PASS " .. passed .. " production offline tests (Lua 5.1); beta validation still required")
