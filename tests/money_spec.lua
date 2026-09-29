-- Currency presentation only; native texture rendering requires the client.
local MP, passed = {}, 0
local pure = { type = type, tostring = tostring, math = math, string = string, table = table, ipairs = ipairs }
for _, name in ipairs({ "HistoryMath", "MarketInsight", "UIViewModel" }) do
    setfenv(assert(loadfile("src/MarketPilot/" .. name .. ".lua")), pure)("MarketPilot", MP)
end
local V = MP.UIViewModel
local gold = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:0:0|t"
local silver = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:0:0|t"
local copper = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:0:0|t"
local function test(name, run) run(); passed = passed + 1; print("PASS " .. name) end
local function eq(actual, expected) assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected)) end

test("native coins preserve the user's prices and denomination zeros", function()
    for _, case in ipairs({
        { 1, "1" .. copper }, { 20, "20" .. copper }, { 99, "99" .. copper },
        { 100, "1" .. silver .. " 0" .. copper },
        { 199, "1" .. silver .. " 99" .. copper },
        { 9000, "90" .. silver .. " 0" .. copper },
        { 10000, "1" .. gold .. " 0" .. silver .. " 0" .. copper },
        { 10001, "1" .. gold .. " 0" .. silver .. " 1" .. copper },
        { 10400, "1" .. gold .. " 4" .. silver .. " 0" .. copper },
        { 10500, "1" .. gold .. " 5" .. silver .. " 0" .. copper },
        { 28700, "2" .. gold .. " 87" .. silver .. " 0" .. copper },
        { 123456, "12" .. gold .. " 34" .. silver .. " 56" .. copper },
    }) do eq(V.Money(case[1]), case[2]); eq(V.ReferenceMoney(case[1]), case[2]) end
end)

test("very large exact prices are neither abbreviated nor converted to scientific notation", function()
    eq(V.Money(1000000000), "100000" .. gold .. " 0" .. silver .. " 0" .. copper)
    eq(V.Money(9007199254740991), "900719925474" .. gold .. " 9" .. silver .. " 91" .. copper)
end)

test("fractional historical copper stays fractional through denomination boundaries", function()
    eq(V.ReferenceMoney(0.5), "0.5" .. copper)
    eq(V.ReferenceMoney(99.5), "99.5" .. copper)
    eq(V.ReferenceMoney(199.5), "1" .. silver .. " 99.5" .. copper)
    eq(V.ReferenceMoney(9999.5), "99" .. silver .. " 99.5" .. copper)
    eq(V.ReferenceMoney(10000.5), "1" .. gold .. " 0" .. silver .. " 0.5" .. copper)
    eq(V.Money(199.5), "No price data") -- An actual unit price must still be integer copper.
end)

test("invalid prices retain missing-data labels without zero coins", function()
    for _, value in ipairs({ false, {}, "20", 0, -1, 0/0, math.huge, -math.huge, 9007199254740992 }) do
        eq(V.Money(value), "No price data"); eq(V.ReferenceMoney(value), "Needs history")
    end
    eq(V.Money(nil), "No price data"); eq(V.ReferenceMoney(nil), "Needs history")
end)

test("watch uses the shared complete coin string and leaves failures and missing facts readable", function()
    local data = { current = { cleanMedian = 10400 }, analytics = { windows = {} }, signals = {} }
    eq(V.Watch(data).now, "1" .. gold .. " 4" .. silver .. " 0" .. copper)
    data.error = "failure"; eq(V.Watch(data).now, "Failed")
    data.error, data.current.cleanMedian = nil, nil; eq(V.Watch(data).now, "No price")
    data.current = nil; eq(V.Watch(data).now, "No scan")
end)

test("all historical references render coins while keeping half-copper medians", function()
    local data = { analytics = {
        windows = { [1] = { median = 27 }, [7] = { median = 199.5 }, [30] = { median = 10400 } },
        trend7d = { status = "INSUFFICIENT" }, volatility = { status = "INSUFFICIENT" },
        significance = { status = "INSUFFICIENT" },
    }, signals = {} }
    local view = V.History(data, 1000)
    eq(view.median1, "27" .. copper)
    eq(view.median7, "1" .. silver .. " 99.5" .. copper)
    eq(view.median30, "1" .. gold .. " 4" .. silver .. " 0" .. copper)
end)

test("summary references lowest and both range endpoints all render native coins", function()
    local data = { current = { t = 1000, rawMedian = 27, cleanMedian = 27, q1 = 20, q3 = 28,
        lowest = 18, totalQuantity = 3145, levelCount = 21, suspicious = 4, extreme = 0, anomalySufficient = true },
        analytics = { windows = { [7] = { status = "INSUFFICIENT" }, [30] = { status = "INSUFFICIENT" } },
            trend7d = { status = "INSUFFICIENT" } }, signals = {} }
    local insight = MP.MarketInsight.Build(data, { itemID = 2770, now = 1120 })
    local text = V.Insight(insight).current
    assert(text:find("reference price is 27" .. copper, 1, true))
    assert(text:find("20" .. copper .. " - 28" .. copper, 1, true))
    assert(text:find("18" .. copper .. ", about 33.3% below", 1, true))
    assert(text:find("3,145 listed units", 1, true))
    assert(not text:find("27c", 1, true))
    eq(V.Insight(insight).current, text)
    eq(data.current.cleanMedian, 27); eq(data.current.q1, 20); eq(data.current.q3, 28)
end)

print("PASS " .. passed .. " native coin presentation tests (Lua 5.1)")
