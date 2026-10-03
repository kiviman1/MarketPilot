-- Pure Lua 5.1: no client APIs, saved-data access or network access is available.
local MP, DAY = {}, 86400
local pure = { type = type, math = math, table = table, string = string, ipairs = ipairs,
    pairs = pairs, getmetatable = getmetatable }
local saved = { schema = 1, markets = { untouched = { items = { [2770] = { price = 123 } } } } }
MarketPilotDB = saved
setfenv(assert(loadfile("src/MarketPilot/ExternalData.lua")), pure)("MarketPilot", MP)
assert(MP.ExternalPayload == nil)
setfenv(assert(loadfile("src/MarketPilot/ExternalMarket.lua")), pure)("MarketPilot", MP)
local External, NOW = MP.ExternalMarket, 100 * DAY
local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, datum in pairs(value) do result[key] = clone(datum) end
    return result
end
local function fixture()
    return { schema = 1, source = "AHledger", url = "https://ahledger.com",
        market = "forever.normal.horde.us", marketLabel = "Normal Horde", region = "us", fetchedAt = NOW,
        itemIDs = { 2770 }, items = { [2770] = {
            latest = { t = NOW, median = 125.5, lowest = 100, quantity = 0, auctions = 0, median7d = 100.4, median30d = 251 },
            hourly = { { t = NOW - 3600, min = 90, median = 100.5, p25 = 99, p75 = 102, quantity = 30, auctions = 5 } },
            daily = { { t = NOW - 3 * DAY, median = 100 }, { t = NOW - DAY, median = 120 } },
        } } }
end
local function near(a, b) assert(a and math.abs(a - b) < 1e-9, tostring(a) .. " vs " .. tostring(b)) end
local passed = 0
local function test(name, run) run(); passed = passed + 1; print("PASS " .. name) end
local function invalid(payload, configured)
    if configured == nil then configured = { 2770, 2771 } end
    local market = External.New(payload, configured)
    assert(market.status == "INVALID" and type(market.reason) == "string")
    assert(market.market == nil and market.fetchedAt == nil)
    local row = market:Get(2770)
    assert(row.status == "INVALID" and row.latest == nil and #row.hourly == 0 and #row.daily == 0)
    assert(row.change7d == nil and row.change30d == nil and row.market == nil)
end

test("placeholder and missing payload return no data", function()
    local market = External.New(MP.ExternalPayload, { 2770 })
    assert(market.status == "NO_DATA" and market:Get(2770).status == "NO_DATA")
    assert(market:Get(2770).latest == nil and market:Get(2770).hourlyCount == 0)
end)
test("provider fields fractional prices and explicit market identity are preserved", function()
    local market = External.New(fixture(), { 2770, 2771 })
    assert(market.status == "OK" and market.reason == nil)
    assert(market.source == "AHledger" and market.url == "https://ahledger.com")
    assert(market.market == "forever.normal.horde.us" and market.marketLabel == "Normal Horde")
    assert(market.region == "us" and market.fetchedAt == NOW)
    local row = market:Get(2770)
    assert(row.status == "OK" and row.latest.median == 125.5 and row.latest.quantity == 0 and row.latest.auctions == 0)
    near(row.change7d, 25); near(row.change30d, -50)
    assert(row.hourlyCount == 1 and row.dailyCount == 2 and row.dailySpanSeconds == 2 * DAY)
    assert(row.hourlySpanSeconds == 0 and row.dailyFirstAt == NOW - 3 * DAY and row.dailyLastAt == NOW - DAY)
    assert(row.maturity == nil and row.analytics == nil and row.signals == nil)
    assert(row.latest.cleanMedian == nil and row.latest.levelCount == nil and row.percentile30d == nil)
end)
test("explicit Forever markets accept every ruleset faction and changed provider labels", function()
    for _, ruleset in ipairs({ "normal", "pvp", "rp" }) do
        for _, faction in ipairs({ "horde", "alliance" }) do
            local payload = fixture()
            payload.market = "forever." .. ruleset .. "." .. faction .. ".us"
            payload.marketLabel = "Provider renamed " .. ruleset .. " / " .. faction
            local market = External.New(payload, { 2770 })
            assert(market.status == "OK" and market.market == payload.market and market.marketLabel == payload.marketLabel)
            assert(market:Get(2770).marketLabel == payload.marketLabel)
        end
    end
    local payload = fixture(); payload.market, payload.region, payload.marketLabel = "forever.future_ruleset.faction-2.eu", "eu", "Updated label (EU)"
    assert(External.New(payload, { 2770 }).status == "OK")
    payload.marketLabel = "Normal – Horde / Royaume français"
    local market = External.New(payload, { 2770 })
    assert(market.status == "OK" and market:Get(2770).marketLabel == payload.marketLabel)
    for _, market in ipairs({ "normal.horde.us", "forever.normal.horde", "forever.normal.horde.us.extra",
        "forever.normal.horde.us/", "forever..horde.us", "forever.normal.horde. us" }) do
        payload = fixture(); payload.market = market; invalid(payload)
    end
    for _, text in ipairs({ "", "   ", "Label\nMore", "Label\tMore", "Label" .. string.char(0), "Label" .. string.char(127),
        "|cFFFFFFFFLabel", string.rep("x", 129), string.rep("é", 65) }) do
        payload = fixture(); payload.marketLabel = text; invalid(payload)
    end
end)
test("missing items and nullable latest remain individually unavailable", function()
    local payload = fixture(); payload.items[2770].latest = nil
    local market = External.New(payload, { 2770, 2771 })
    local row = market:Get(2770)
    assert(market.status == "OK" and row.status == "OK" and row.latest == nil and row.change7d == nil)
    row = market:Get(2771)
    assert(row.status == "NO_DATA" and row.latest == nil and row.dailyCount == 0 and row.dailySpanSeconds == nil)
    assert(row.marketLabel == "Normal Horde")
    assert(market:Get(9999).status == "NO_DATA")
    payload.items[2770] = {}; market = External.New(payload, { 2770 })
    assert(market.status == "NO_DATA" and market:Get(2770).status == "NO_DATA")
    payload.items = {}; assert(External.New(payload, { 2770 }).status == "NO_DATA")
end)
test("omitted metrics retain nil and never infer prices from history", function()
    local payload = fixture(); payload.items[2770].latest = { t = NOW, auctions = 5 }
    local row = External.New(payload, { 2770 }):Get(2770)
    assert(row.latest.median == nil and row.latest.lowest == nil and row.latest.quantity == nil)
    assert(row.latest.median7d == nil and row.latest.median30d == nil and row.change7d == nil and row.change30d == nil)
    payload.items[2770].latest = { t = NOW, median7d = 100, median30d = 100 }
    row = External.New(payload, { 2770 }):Get(2770)
    assert(row.latest.median == nil and row.change7d == nil and row.change30d == nil)
end)
test("histories sort timestamps in copies and report actual short coverage", function()
    local payload = fixture()
    payload.items[2770].daily = { { t = NOW - DAY, median = 120 }, { t = NOW - 3 * DAY, median = 100 } }
    payload.items[2770].hourly = { { t = NOW - 60, median = 120 }, { t = NOW - 3600, median = 100 } }
    local row = External.New(payload, { 2770 }):Get(2770)
    assert(row.daily[1].t == NOW - 3 * DAY and row.hourly[1].t == NOW - 3600)
    assert(row.dailySpanSeconds == 2 * DAY and row.hourlySpanSeconds == 3540 and row.maturity == nil)
    assert(payload.items[2770].daily[1].t == NOW - DAY and payload.items[2770].hourly[1].t == NOW - 60)
end)
test("input and returned records cannot mutate later reads or local saved data", function()
    local payload = fixture(); local market = External.New(payload, { 2770 })
    payload.items[2770].latest.median = 999; payload.items[2770].daily[1].median = 999
    payload.marketLabel = "Other"; payload.itemIDs[1] = 999
    local row = market:Get(2770)
    assert(row.latest.median == 125.5 and row.daily[1].median == 100 and row.marketLabel == "Normal Horde")
    row.latest.median = 333; row.hourly[1].median = 333; row.daily[1].median = 333; row.marketLabel = "Other"
    row = market:Get(2770)
    assert(row.latest.median == 125.5 and row.hourly[1].median == 100.5 and row.daily[1].median == 100)
    assert(row.marketLabel == "Normal Horde" and MarketPilotDB == saved and saved.markets.untouched.items[2770].price == 123)
    assert(MP.Database == nil and MP.Scanner == nil and MP.AuctionAPI == nil)
end)
test("malformed identity schema timestamps and unknown fields invalidate whole export", function()
    for key, value in pairs({ schema = 2, source = "Other", url = "http://ahledger.com", market = "forever.normal.alliance",
        marketLabel = "", region = "eu", fetchedAt = -1 }) do
        local payload = fixture(); payload[key] = value; invalid(payload)
    end
    for _, key in ipairs({ "schema", "source", "url", "market", "marketLabel", "region", "fetchedAt", "itemIDs", "items" }) do
        local payload = fixture(); payload[key] = nil; invalid(payload)
    end
    local payload = fixture(); payload.extra = true; invalid(payload)
    payload = fixture(); payload.items[2770].extra = true; invalid(payload)
    payload = fixture(); payload.items[2770].latest.rawMedian = 100; invalid(payload)
    invalid(false); invalid("invalid"); invalid(setmetatable(fixture(), {}))
    for _, value in ipairs({ 0.5, math.huge, 0/0, "100", 9007199254740992 }) do
        payload = fixture(); payload.fetchedAt = value; invalid(payload)
        payload = fixture(); payload.items[2770].latest.t = value; invalid(payload)
    end
    payload = fixture(); payload.items[2770].latest.t = nil; invalid(payload)
end)
test("history observation limits accept the boundary and reject oversized arrays", function()
    local function rows(count)
        local result = {}; for index = 1, count do result[index] = { t = NOW - index * 3600, median = 100 } end
        return result
    end
    local payload = fixture(); payload.items[2770].hourly = rows(200); payload.items[2770].daily = rows(40)
    local row = External.New(payload, { 2770 }):Get(2770)
    assert(row.status == "OK" and row.hourlyCount == 200 and row.dailyCount == 40)
    payload = fixture(); payload.items[2770].hourly = rows(201); invalid(payload)
    payload = fixture(); payload.items[2770].daily = rows(41); invalid(payload)
end)
test("contradictory descriptors within one observation invalidate the payload", function()
    local payload = fixture(); payload.items[2770].latest.lowest = 126; invalid(payload)
    for _, seriesName in ipairs({ "hourly", "daily" }) do
        for _, prices in ipairs({ { min = 101, median = 100 }, { p25 = 120, p75 = 110 },
            { p25 = 120, median = 110 }, { median = 120, p75 = 110 }, { min = 101, p25 = 100 }, { min = 101, p75 = 100 } }) do
            payload = fixture(); local row = { t = NOW - 100 }
            for key, value in pairs(prices) do row[key] = value end
            payload.items[2770][seriesName] = { row }; invalid(payload)
        end
    end
    payload = fixture(); payload.items[2770].hourly = { { t = NOW - 10, min = 100.5, p25 = 100.5, median = 100.5, p75 = 100.5 } }
    assert(External.New(payload, { 2770 }).status == "OK")
    payload = fixture(); payload.items[2770].latest.median7d = 10
    payload.items[2770].daily[1].median = 200
    assert(External.New(payload, { 2770 }).status == "OK") -- Different timestamps and provider baselines are independent.
end)
test("invalid prices or counts invalidate all records instead of trusting partial data", function()
    for _, value in ipairs({ 0, -1, math.huge, -math.huge, 0/0, "100", false, 9007199254740992 }) do
        for _, key in ipairs({ "median", "lowest", "median7d", "median30d" }) do
            local payload = fixture(); payload.items[2770].latest[key] = value; invalid(payload)
        end
        for _, key in ipairs({ "min", "median", "p25", "p75" }) do
            local payload = fixture(); payload.items[2770].hourly[1][key] = value; invalid(payload)
        end
    end
    for _, value in ipairs({ -1, 0.5, math.huge, 0/0, "3", false, 9007199254740992 }) do
        for _, key in ipairs({ "quantity", "auctions" }) do
            local payload = fixture(); payload.items[2770].latest[key] = value; invalid(payload)
            payload = fixture(); payload.items[2770].daily[1][key] = value; invalid(payload)
        end
    end
    local payload = fixture(); payload.items[2770].latest = false; invalid(payload)
    payload = fixture(); payload.items[2770].daily[2] = false; invalid(payload)
end)
test("IDs and dense arrays reject hidden data duplicates and arbitrary items", function()
    for _, array in ipairs({ false, { [1] = 2770, [3] = 2771 }, { 2770, 2770 }, { 2770, hidden = 2771 } }) do
        local payload = fixture(); payload.itemIDs = clone(array); invalid(payload)
        invalid(fixture(), clone(array))
    end
    local payload = fixture(); payload.itemIDs = { 2770, 9999 }; invalid(payload)
    payload = fixture(); payload.items["2770"] = payload.items[2770]; invalid(payload)
    payload = fixture(); payload.items[2771] = {}; invalid(payload)
    for _, array in ipairs({ false, { [1] = { t = NOW }, [3] = { t = NOW - DAY } }, { { t = NOW }, hidden = {} },
        { { t = NOW }, { t = NOW } } }) do
        payload = fixture(); payload.items[2770].daily = clone(array); invalid(payload)
    end
    payload = fixture(); payload.items[2770].hourly[1] = setmetatable({ t = NOW }, {}); invalid(payload)
end)
test("finite price boundaries and comparison overflow preserve absence of fake changes", function()
    local payload = fixture(); local latest = payload.items[2770].latest
    latest.median, latest.median7d, latest.median30d = 9007199254740991, 1e-300, 9007199254740991
    latest.quantity, latest.auctions = 9007199254740991, 9007199254740991
    local row = External.New(payload, { 2770 }):Get(2770)
    assert(row.status == "OK" and row.latest.median == 9007199254740991 and row.change7d == nil)
    near(row.change30d, 0)
end)
print(string.format("PASS: %d external data tests", passed))
