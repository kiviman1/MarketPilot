-- Source-backed native browse adapter fixtures; live Forever validation is separate.
local function fixture()
    local f = { calls = {}, sent = 0, readyCalls = 0, completeCalls = 0, ready = true,
        complete = true, shown = true, known = true }
    local env = setmetatable({}, { __index = _G })
    env._G = env
    local mp = { Items = {
        Contains = function(id) return id == 4625 end,
        Metadata = function(id)
            assert(id == 4625)
            return { known = f.known, name = f.name or "Feuerblüte" }
        end,
    } }
    local buy = { "BrowseResultsFrame", "SearchBar" }
    env.AuctionHouseFrameDisplayMode = { Buy = buy }
    env.Enum = { AuctionHouseFilter = { ExactMatch = 5 } }
    env.g_auctionHouseSortsBySearchContext = { BrowseAll = { { sortOrder = 0, reverseSort = false } } }
    env.g_auctionHouseFilters = { minLevel = 40, maxLevel = 50, filters = { [2] = true } }
    local categories = { selected = "Weapons" }
    function categories:SetSelectedCategory(index)
        f.calls[#f.calls + 1] = "category"
        self.selected = index
    end
    local frame = { mode = "Sell", text = "Old search" }
    function frame:IsShown() return f.shown end
    function frame:GetCategoriesList() return categories end
    function frame:SetDisplayMode(mode)
        f.calls[#f.calls + 1] = "mode"
        assert(mode == buy and categories.selected == nil)
        self.mode = mode
        self.text = "" -- Native SearchBar OnShow clears text.
    end
    function frame:SetSearchText(name)
        f.calls[#f.calls + 1] = "text"
        if self.mode ~= buy then return false end
        self.text = name
        return true
    end
    function frame:SendBrowseQuery(name, minLevel, maxLevel, filters)
        f.calls[#f.calls + 1] = "browse"
        assert(self.mode == buy and self.text == name and categories.selected == nil)
        assert(minLevel == nil and maxLevel == nil)
        assert(#filters == 1 and filters[1] == env.Enum.AuctionHouseFilter.ExactMatch)
        env.C_AuctionHouse.SendBrowseQuery({ searchString = name, filters = filters })
    end
    env.C_AuctionHouse = {
        IsThrottledMessageSystemReady = function()
            f.readyCalls = f.readyCalls + 1
            return f.ready
        end,
        SendBrowseQuery = function(query)
            f.sent = f.sent + 1
            f.query = query
        end,
        HasFullBrowseResults = function(...)
            assert(select("#", ...) == 0)
            f.completeCalls = f.completeCalls + 1
            return f.complete
        end,
    }
    env.AuctionHouseFrame = frame
    setfenv(assert(loadfile("src/MarketPilot/AuctionAPI.lua")), env)("MarketPilot", mp)
    f.env, f.mp, f.frame, f.categories, f.api = env, mp, frame, categories, mp.AuctionAPI
    return f
end

local count = 0
local function test(name, run)
    run()
    count = count + 1
    print("PASS " .. name)
end

test("prepare resolves localized configured name without UI changes or query", function()
    local f = fixture()
    local request = assert(f.api:PrepareBrowse(4625))
    assert(request.name == "Feuerblüte")
    assert(f.frame.text == "Old search" and f.frame.mode == "Sell")
    assert(f.categories.selected == "Weapons" and #f.calls == 0)
    assert(f.sent == 0 and f.readyCalls == 0)
end)

test("one exact native browse switches category then mode then text before dispatch", function()
    local f = fixture()
    assert(f.api:QueryBrowse(assert(f.api:PrepareBrowse(4625)).name))
    assert(table.concat(f.calls, ",") == "category,mode,text,browse")
    assert(f.sent == 1 and f.readyCalls == 1 and f.query.searchString == "Feuerblüte")
    -- Requested query ignores old filters but never overwrites player preferences.
    local filters = f.env.g_auctionHouseFilters
    assert(filters.minLevel == 40 and filters.maxLevel == 50 and filters.filters[2] == true)
end)

test("unknown or unconfigured item never invents a browse name", function()
    local f = fixture()
    for _, id in ipairs({ 1, 0, -1, 4625.1, "4625", false }) do
        assert(f.api:PrepareBrowse(id) == nil)
    end
    f.known = false
    local request, reason = f.api:PrepareBrowse(4625)
    assert(request == nil and reason:find("not loaded", 1, true))
    f.known, f.name = true, "   "
    assert(f.api:PrepareBrowse(4625) == nil)
    assert(f.sent == 0 and #f.calls == 0)
end)

test("closed or absent AH rejects before touching UI", function()
    local f = fixture()
    f.shown = false
    assert(f.api:PrepareBrowse(4625) == nil)
    local ok, _, uncertain = f.api:QueryBrowse("Firebloom")
    assert(not ok and uncertain == false)
    f.env.AuctionHouseFrame = nil
    assert(f.api:PrepareBrowse(4625) == nil)
    assert(f.sent == 0 and #f.calls == 0)
end)

test("missing native methods fail explicitly without a fallback query", function()
    for _, method in ipairs({ "IsShown", "GetCategoriesList", "SetDisplayMode", "SetSearchText", "SendBrowseQuery" }) do
        local f = fixture()
        f.frame[method] = nil
        local request, reason = f.api:PrepareBrowse(4625)
        assert(request == nil and type(reason) == "string", method)
        local ok, _, uncertain = f.api:QueryBrowse("Firebloom")
        assert(not ok and uncertain == false and f.sent == 0 and #f.calls == 0, method)
    end
end)

test("missing categories or category method has no deep-child workaround", function()
    local f = fixture()
    f.categories.SetSelectedCategory = nil
    assert(f.api:PrepareBrowse(4625) == nil)
    f.frame.GetCategoriesList = function() error("category not ready") end
    assert(f.api:PrepareBrowse(4625) == nil)
    assert(f.sent == 0 and #f.calls == 0)
end)

test("malformed native frame or category return cannot escape the API boundary", function()
    for _, bad in ipairs({ true, 12, "categories" }) do
        local f = fixture()
        f.frame.GetCategoriesList = function() return bad end
        local ok, reason, uncertain = f.api:QueryBrowse("Firebloom")
        assert(not ok and uncertain == false and type(reason) == "string")
        f.env.AuctionHouseFrame = bad
        assert(f.api:PrepareBrowse(4625) == nil)
        assert(f.sent == 0 and #f.calls == 0)
    end
end)

test("requires runtime exact-match symbol and buy mode without numeric fallback", function()
    local f = fixture()
    f.env.Enum.AuctionHouseFilter.ExactMatch = nil
    assert(f.api:PrepareBrowse(4625) == nil)
    f.env.Enum.AuctionHouseFilter.ExactMatch = "5"
    assert(f.api:PrepareBrowse(4625) == nil)
    f.env.Enum.AuctionHouseFilter.ExactMatch = 8
    f.env.AuctionHouseFrameDisplayMode.Buy = nil
    assert(f.api:PrepareBrowse(4625) == nil)
    f.env.AuctionHouseFrameDisplayMode.Buy = { "BrowseResultsFrame" }
    assert(f.api:PrepareBrowse(4625))
    assert(f.sent == 0)
end)

test("missing native API or not-yet-loaded sorts cannot report dispatch", function()
    local f = fixture()
    f.env.C_AuctionHouse.SendBrowseQuery = nil
    assert(f.api:PrepareBrowse(4625) == nil)
    f = fixture()
    f.env.g_auctionHouseSortsBySearchContext = nil
    local ok, reason, uncertain = f.api:QueryBrowse("Firebloom")
    assert(not ok and uncertain == false and reason:find("sorting", 1, true))
    assert(f.sent == 0 and #f.calls == 0)
end)

test("browse preparation requires the native completeness predicate", function()
    local f = fixture()
    f.env.C_AuctionHouse.HasFullBrowseResults = nil
    local request, reason = f.api:PrepareBrowse(4625)
    assert(request == nil and reason:find("HasFullBrowseResults", 1, true))
    local ok, _, uncertain = f.api:QueryBrowse("Firebloom")
    assert(not ok and uncertain == false and f.sent == 0 and #f.calls == 0)
end)

test("browse completeness requires both throttle readiness and full native results", function()
    local f = fixture()
    f.ready = false
    assert(f.api:AreBrowseResultsReady() == false and f.completeCalls == 0)
    f.ready, f.complete = true, false
    assert(f.api:AreBrowseResultsReady() == false and f.completeCalls == 1)
    f.complete = true
    assert(f.api:AreBrowseResultsReady() == true and f.completeCalls == 2)
    assert(f.sent == 0 and #f.calls == 0)
end)

test("browse completeness missing, throwing, and nonboolean APIs preserve unknown", function()
    local f = fixture()
    f.env.C_AuctionHouse.HasFullBrowseResults = nil
    local ready, reason = f.api:AreBrowseResultsReady()
    assert(ready == nil and reason:find("missing API", 1, true))
    f.env.C_AuctionHouse.HasFullBrowseResults = function() error("native completeness unavailable") end
    ready, reason = f.api:AreBrowseResultsReady()
    assert(ready == nil and reason:find("native completeness unavailable", 1, true))
    for _, value in ipairs({ "true", 0, 1, {} }) do
        f.env.C_AuctionHouse.HasFullBrowseResults = function() return value end
        ready, reason = f.api:AreBrowseResultsReady()
        assert(ready == nil and reason:find("must be boolean", 1, true))
    end
    f.env.C_AuctionHouse.HasFullBrowseResults = function() return nil end
    ready, reason = f.api:AreBrowseResultsReady()
    assert(ready == nil and reason:find("must be boolean", 1, true))
    assert(f.sent == 0 and #f.calls == 0)
end)

test("unknown readiness never checks completeness or completes browsing", function()
    local f = fixture()
    f.ready = "true"
    local ready, reason = f.api:AreBrowseResultsReady()
    assert(ready == nil and reason:find("boolean", 1, true) and f.completeCalls == 0)
    f.env.C_AuctionHouse.IsThrottledMessageSystemReady = function() error("not ready to inspect") end
    ready, reason = f.api:AreBrowseResultsReady()
    assert(ready == nil and reason:find("not ready to inspect", 1, true) and f.completeCalls == 0)
end)

test("dispatch revalidates AH and capability after preparation", function()
    local f = fixture()
    local request = assert(f.api:PrepareBrowse(4625))
    f.shown = false
    assert(not f.api:QueryBrowse(request.name))
    f.shown = true
    f.frame.SendBrowseQuery = nil
    assert(not f.api:QueryBrowse(request.name))
    assert(f.sent == 0 and #f.calls == 0)
end)

test("throttle rejection has no UI mutation and no retry", function()
    local f = fixture()
    f.ready = false
    local ok, reason, uncertain = f.api:QueryBrowse("Firebloom")
    assert(not ok and uncertain == false and reason:find("not ready", 1, true))
    assert(f.sent == 0 and #f.calls == 0 and f.readyCalls == 1)
end)

test("invalid readiness is not treated as ready", function()
    local f = fixture()
    f.ready = "true"
    local ok, reason, uncertain = f.api:QueryBrowse("Firebloom")
    assert(not ok and uncertain == false and reason:find("boolean", 1, true))
    assert(f.sent == 0 and #f.calls == 0)
end)

test("readiness and visibility exceptions remain non-dispatch errors", function()
    local f = fixture()
    f.env.C_AuctionHouse.IsThrottledMessageSystemReady = function() error("readiness unavailable") end
    local ok, reason, uncertain = f.api:QueryBrowse("Firebloom")
    assert(not ok and uncertain == false and reason:find("readiness unavailable", 1, true))
    f.frame.IsShown = function() error("visibility unavailable") end
    assert(f.api:PrepareBrowse(4625) == nil)
    assert(f.sent == 0 and #f.calls == 0)
end)

test("invalid name cannot clear the current Blizzard search", function()
    local f = fixture()
    for _, name in ipairs({ "", " \t", 4625, false }) do
        local ok, _, uncertain = f.api:QueryBrowse(name)
        assert(not ok and uncertain == false)
    end
    assert(f.sent == 0 and #f.calls == 0)
end)

test("preparation error and rejected text remain safe pre-dispatch failures", function()
    local f = fixture()
    f.frame.SetDisplayMode = function() error("native mode failed") end
    local ok, reason, uncertain = f.api:QueryBrowse("Firebloom")
    assert(not ok and uncertain == false and reason:find("preparation", 1, true))
    assert(f.sent == 0)
    f = fixture()
    f.frame.SetSearchText = function() return false end
    ok, reason, uncertain = f.api:QueryBrowse("Firebloom")
    assert(not ok and uncertain == false and f.sent == 0)
end)

test("native send failure is ambiguous and never automatically retried", function()
    local f = fixture()
    f.env.C_AuctionHouse.SendBrowseQuery = function()
        f.sent = f.sent + 1
        error("failure after possible dispatch")
    end
    local ok, reason, uncertain = f.api:QueryBrowse("Firebloom")
    assert(not ok and uncertain == true and reason:find("failed", 1, true))
    assert(f.sent == 1)
end)

test("explicit false native send is ambiguous", function()
    local f = fixture()
    f.frame.SendBrowseQuery = function() f.sent = f.sent + 1; return false end
    local ok, reason, uncertain = f.api:QueryBrowse("Firebloom")
    assert(not ok and uncertain == true and reason:find("returned false", 1, true))
    assert(f.sent == 1)
end)

test("browse adapter has no click proxy, deep frame access, or purchase action", function()
    local file = assert(io.open("src/MarketPilot/AuctionAPI.lua", "rb"))
    local source = file:read("*a")
    file:close()
    for _, forbidden in ipairs({ "SearchBox", "FilterButton", ":Click(", "SelectBrowseResult",
        "StartCommoditiesPurchase", "StartItemPurchase", "hooksecurefunc", "OnUpdate" }) do
        assert(not source:find(forbidden, 1, true), forbidden)
    end
end)

print("PASS " .. count .. " AuctionAPI browse tests (Lua 5.1)")
