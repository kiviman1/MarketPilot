-- Deterministic explanation contract; deliberately no client or persistence APIs.
local MP, passed = {}, 0
local function loadModule(name, environment)
    local path = "src/MarketPilot/" .. name .. ".lua"
    local file = assert(io.open(path, "rb")); local source = file:read("*a"); file:close()
    local chunk = assert(loadstring(source, path))
    if environment then setfenv(chunk, environment) end
    chunk("MarketPilot", MP)
    return source
end
local pure = { math = math, table = table, type = type, ipairs = ipairs }
loadModule("HistoryMath", pure)
local source = loadModule("MarketInsight", pure)
loadModule("UIViewModel")
local function test(name, callback) callback(); passed = passed + 1; print("PASS " .. name) end
local function eq(a, b)
    assert(type(a) == type(b), "type mismatch: " .. tostring(a) .. " / " .. tostring(b))
    if type(a) ~= "table" then assert(a == b, tostring(a) .. " ~= " .. tostring(b)); return end
    for key, value in pairs(a) do eq(value, b[key]) end
    for key in pairs(b) do assert(a[key] ~= nil, "unexpected key " .. tostring(key)) end
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, entry in pairs(value) do result[key] = copy(entry) end; return result
end
-- Keep sentence-rule assertions readable independently of presentation markup.
-- Only the exact known native coin tags are normalized; malformed tags still fail.
-- Dedicated money/UI tests assert the actual unmodified markup.
local function plainMoney(text)
    for kind, suffix in pairs({ Gold = "g", Silver = "s", Copper = "c" }) do
        text = text:gsub("|TInterface\\MoneyFrame\\UI%-" .. kind .. "Icon:12:12:0:0|t", suffix)
    end
    return (text:gsub("(%d[gs]) (%d)", "%1%2"))
end
local function contains(text, expected) assert(plainMoney(text):find(expected, 1, true), expected .. " absent from:\n" .. text) end
local function absent(text, forbidden) assert(not plainMoney(text):find(forbidden, 1, true), forbidden .. " present in:\n" .. text) end
local function context() return { itemID = 2770, scannerItemID = 2770, scannerState = "DONE", now = 100120 } end
local function fixture()
    return { current = { t = 100000, rawMedian = 27, cleanMedian = 27, q1 = 20, q3 = 28, lowest = 18,
        totalQuantity = 3145, levelCount = 21, suspicious = 4, extreme = 0, anomalySufficient = true },
        analytics = { status = "INSUFFICIENT", maturity = "NEW", count = 1, windows = {
            [7] = { status = "INSUFFICIENT" }, [30] = { status = "INSUFFICIENT" } }, trend7d = { status = "INSUFFICIENT" } },
        signals = { price = "INSUFFICIENT", trend = "INSUFFICIENT", supply = "INSUFFICIENT" }, history = {}, lastScan = 100000 }
end
local function mature()
    local data = fixture()
    data.current.cleanMedian, data.current.rawMedian = 100, 100
    data.current.q1, data.current.q3, data.current.lowest, data.current.totalQuantity = 90, 110, 80, 1000
    data.analytics = { status = "OK", maturity = "30D READY", count = 61, windows = {
        [7] = { status = "OK", median = 125, change = -20, quantityMedian = 1000, supplyRatio = 1 },
        [30] = { status = "OK", median = 130, change = -23.076923 } },
        percentile30d = 10, trend7d = { status = "OK", pctPerDay = 3 } }
    data.signals = { price = "CHEAP_VS_HISTORY", trend = "RISING", supply = "NORMAL_SUPPLY" }
    return data
end
local function build(data, ctx)
    local insight = MP.MarketInsight.Build(data or fixture(), ctx or context())
    return MP.UIViewModel.Insight(insight), insight
end
local function message(insight, code, section)
    for _, row in ipairs(insight[section or "current"]) do if row.code == code then return row end end
end

test("CURRENT_REFERENCE_BELOW", function()
    local text, insight = build()
    contains(text.current, "reference price is 27c, with a central price band of 20c - 28c.")
    contains(text.current, "The lowest listed price is 18c, about 33.3% below that reference.")
    contains(text.current, "This scan covers 3,145 listed units.")
    contains(text.current, "4 unusual price levels were retained; no price levels were excluded.")
    contains(text.current, "More history is needed to judge whether this price and listed quantity are high or low for this market.")
    assert(math.abs(message(insight, "LOWEST_BELOW").change + 100 / 3) < 1e-12)
    contains(text.current, "Latest recorded scan: 2 minutes ago.")
end)
test("CURRENT_REFERENCE_EQUAL", function()
    local data = fixture(); data.current.lowest, data.current.q1 = 27, 27
    local text = build(data)
    contains(text.current, "27c, equal to that reference."); absent(text.current, "below that reference")
end)
test("CURRENT_REFERENCE_INVALID", function()
    for _, value in ipairs({ 0, -1, 1.5, "27", math.huge, 0/0, 9007199254740992 }) do
        local data = fixture(); data.current.cleanMedian = value
        local text = build(data)
        contains(text.current, "The lowest recorded listed price is 18c.")
        contains(text.current, "3,145 listed units"); contains(text.current, "Not assessable from this record: reference price.")
        absent(text.current, "below that reference"); absent(text.current, "reference price is 0")
    end
    local data = fixture(); data.current.cleanMedian = nil
    contains(build(data).current, "reference price.")
end)
test("CURRENT_LOWEST_INVALID", function()
    for _, value in ipairs({ 0, -1, 1.5, "18", math.huge, 0/0, false }) do
        local data = fixture(); data.current.lowest = value
        local text = build(data).current
        contains(text, "reference price is 27c"); contains(text, "3,145 listed units")
        contains(text, "Not assessable from this record: lowest listed price.")
        absent(text, "below that reference"); absent(text, "lowest listed price is")
    end
    local data = fixture(); data.current.lowest = nil
    contains(build(data).current, "Not assessable from this record: lowest listed price.")
end)
test("CURRENT_TINY_DIFFERENCE", function()
    local data = fixture(); data.current.cleanMedian, data.current.q1, data.current.q3, data.current.lowest = 100000, 99999, 100000, 99999
    local text, insight = build(data)
    assert(message(insight, "LOWEST_BELOW").change < 0)
    contains(text.current, "less than 0.1% below"); absent(text.current, "about 0.0%"); absent(text.current, "equal to")
end)
test("CURRENT_INVALID_BAND_PRESERVES_FACTS", function()
    local data = fixture(); data.current.q1, data.current.q3 = 30, 20
    local text = build(data); contains(text.current, "reference price is 27c.")
    contains(text.current, "18c, about 33.3%"); contains(text.current, "Not assessable from this record: central price band.")
    absent(text.current, "band of")
    data.current.q1, data.current.q3, data.current.lowest = 20, 28, 25
    text = build(data); absent(text.current, "band of"); contains(text.current, "fields are inconsistent")
end)
test("CURRENT_INCONSISTENT_LOWEST", function()
    local data = fixture(); data.current.lowest = 100
    local text = build(data)
    contains(text.current, "lowest recorded listed price is 1s0c"); contains(text.current, "fields are inconsistent")
    absent(text.current, "below that reference"); absent(text.current, "above that reference")
end)
test("CURRENT_INVALID_QUANTITY", function()
    local data = fixture(); data.current.totalQuantity = "3145"
    local text = build(data); contains(text.current, "reference price is 27c"); absent(text.current, "scan covers")
    contains(text.current, "Not assessable from this record: listed quantity.")
end)

for _, case in ipairs({ { "NEGATIVE", -20, 125, "20.0% below" }, { "ZERO", 0, 100, "equals its 7-day median" },
    { "POSITIVE", 25, 80, "25.0% above" } }) do
    test("HISTORY_CHANGE_" .. case[1], function()
        local data = mature(); data.analytics.windows[7].change, data.analytics.windows[7].median = case[2], case[3]
        contains(build(data).history, case[4])
    end)
end
test("HISTORY_CHANGE_INVALID", function()
    local data = mature(); data.analytics.windows[7].change = 20 -- positive with a lower reference
    local text = build(data).history; absent(text, "above its 7-day"); contains(text, "Not assessable from this record: 7-day price comparison")
    data.analytics.windows[7].change = math.huge
    absent(build(data).history, "inf")
end)
test("HISTORY_CHANGE_TINY_DIFFERENCE", function()
    local data = mature(); data.analytics.windows[7].median, data.analytics.windows[7].change = 100.0001, -0.0000999999
    contains(build(data).history, "less than 0.1% below its 7-day median")
end)
for _, case in ipairs({ { "LOW", 0, "CHEAP_VS_HISTORY", "low" }, { "NORMAL", 50, "NORMAL_RANGE", "in the middle range" },
    { "HIGH", 100, "EXPENSIVE_VS_HISTORY", "high" } }) do
    test("PRICE_" .. case[1], function()
        local data = mature(); data.analytics.percentile30d, data.signals.price = case[2], case[3]
        contains(build(data).history, "reference is " .. case[4] .. " among 30-day price observations")
    end)
end
test("PRICE_BOUNDARIES", function()
    for _, case in ipairs({ {20, "CHEAP_VS_HISTORY"}, {20.001, "NORMAL_RANGE"}, {79.999, "NORMAL_RANGE"}, {80, "EXPENSIVE_VS_HISTORY"} }) do
        local data = mature(); data.analytics.percentile30d, data.signals.price = case[1], case[2]
        local _, insight = build(data); assert(message(insight, "HISTORY_POSITION", "history"))
    end
end)
test("PRICE_UNAVAILABLE", function()
    local data = mature(); data.analytics.percentile30d = 101
    local text = build(data).history; absent(text, "among 30-day"); contains(text, "30-day price position")
    data.analytics.percentile30d, data.analytics.windows[30].status = 10, "INSUFFICIENT"
    text = build(data).history; absent(text, "among 30-day"); contains(text, "More history is needed for: 30-day price position.")
end)
for _, case in ipairs({ { "RISING", 3, "rising" }, { "STABLE", 0, "stable" }, { "FALLING", -3, "falling" } }) do
    test("TREND_" .. case[1], function()
        local data = mature(); data.analytics.trend7d.pctPerDay, data.signals.trend = case[2], case[1]
        contains(build(data).history, "show a " .. case[3] .. " price trend")
    end)
end
test("TREND_BOUNDARIES", function()
    for _, value in ipairs({ -2, 2 }) do
        local data = mature(); data.analytics.trend7d.pctPerDay, data.signals.trend = value, "STABLE"
        contains(build(data).history, "stable price trend")
    end
end)
test("TREND_UNAVAILABLE", function()
    for _, value in ipairs({ math.huge, 0/0, -100, "3" }) do
        local data = mature(); data.analytics.trend7d.pctPerDay = value
        local text = build(data).history; absent(text, "show a rising"); contains(text, "trend direction")
    end
end)
for _, case in ipairs({ { "LOW", 0.5, "LOW_SUPPLY", 2000, "below" }, { "NORMAL", 1, "NORMAL_SUPPLY", 1000, "near" },
    { "HIGH", 2, "HIGH_SUPPLY", 500, "above" } }) do
    test("SUPPLY_" .. case[1], function()
        local data = mature(); data.analytics.windows[7].supplyRatio, data.signals.supply, data.analytics.windows[7].quantityMedian = case[2], case[3], case[4]
        contains(build(data).history, "supply in this scan is " .. case[5] .. " its recent usual level")
    end)
end
test("SUPPLY_BOUNDARIES", function()
    for _, case in ipairs({ {600, 0.6, "LOW_SUPPLY"}, {601, 0.601, "NORMAL_SUPPLY"}, {1599, 1.599, "NORMAL_SUPPLY"}, {1600, 1.6, "HIGH_SUPPLY"} }) do
        local data = mature(); data.current.totalQuantity, data.analytics.windows[7].supplyRatio, data.signals.supply = case[1], case[2], case[3]
        local _, insight = build(data); assert(message(insight, "HISTORY_SUPPLY", "history"))
    end
end)
test("SUPPLY_UNAVAILABLE", function()
    local data = mature(); data.analytics.windows[7].quantityMedian = 0
    local text = build(data).history; absent(text, "supply in this scan is"); contains(text, "historical supply comparison")
    data = mature(); data.analytics.windows[7].supplyRatio = -1
    absent(build(data).history, "supply in this scan is")
end)
test("HISTORY_LABEL_CONTRADICTIONS_PRESERVE_NUMBERS", function()
    local data = mature(); data.signals.price, data.signals.trend, data.signals.supply = "EXPENSIVE_VS_HISTORY", "FALLING", "LOW_SUPPLY"
    local text = build(data).history
    absent(text, "show a falling"); absent(text, "reference is high"); absent(text, "supply in this scan is below")
    contains(text, "+3.0%/day; its direction label is unavailable")
    contains(text, "ratio is 1.00x"); contains(text, "percentile is 10.0")
    data.signals = {}; text = build(data).history
    contains(text, "+3.0%/day"); contains(text, "ratio is 1.00x"); contains(text, "percentile is 10.0")
end)
test("HISTORY_METRIC_STATUS_BEATS_MATURITY", function()
    local data = fixture(); data.analytics.maturity = "30D READY"
    data.signals = { price = "CHEAP_VS_HISTORY", trend = "RISING", supply = "HIGH_SUPPLY" }
    local text = build(data).history
    contains(text, "More history is needed"); absent(text, "rising price trend"); absent(text, "above its recent")
    data = mature(); data.analytics.maturity = "NEW"
    contains(build(data).history, "20.0% below its 7-day")
end)

test("ANOMALY_ZERO", function()
    local data = fixture(); data.current.suspicious = 0
    local text = build(data).current
    contains(text, "No unusual price levels were retained; no price levels were excluded.")
    for _, forbidden in ipairs({ "manipulat", "strong sample", "high confidence", "clean data" }) do absent(text, forbidden) end
end)
test("ANOMALY_RETAINED", function()
    local data = fixture(); data.current.suspicious = 1
    local text = build(data).current
    contains(text, "1 unusual price level was retained")
    data.current.suspicious = 2; contains(build(data).current, "2 unusual price levels were retained")
    data.current.totalQuantity, data.current.levelCount, data.current.suspicious, data.current.anomalySufficient = 1, 1, 0, false
    data.current.lowest, data.current.q1, data.current.q3 = 27, 27, 27
    contains(build(data).current, "1 listed unit.")
end)
test("ANOMALY_EXCLUDED", function()
    local data = fixture(); data.current.extreme = 1
    contains(build(data).current, "1 extreme price level was excluded")
    data.current.extreme = 2; contains(build(data).current, "2 extreme price levels were excluded")
end)
test("ANOMALY_INSUFFICIENT", function()
    for _, levels in ipairs({ 4, 21 }) do
        local data = fixture(); data.current.levelCount, data.current.anomalySufficient = levels, false
        local text = build(data).current
        contains(text, "reference price is 27c"); contains(text, "Not enough price variation/data for reliable outlier filtering.")
        absent(text, "fewer than 5"); absent(text, "wider spread")
    end
end)
test("ANOMALY_INVALID", function()
    local data = fixture(); data.current.suspicious = 22
    local text = build(data).current; contains(text, "counts cannot be assessed"); absent(text, "22 unusual")
    data = fixture(); data.current.extreme, data.current.anomalySufficient = 1, false
    text = build(data).current; absent(text, "1 extreme price level was excluded"); contains(text, "reliable outlier filtering")
    data = fixture(); data.current.anomalySufficient = nil
    contains(build(data).current, "sufficiency was not recorded")
    for _, value in ipairs({ "true", 1 }) do
        data.current.anomalySufficient = value
        contains(build(data).current, "sufficiency was not recorded")
    end
    for _, value in ipairs({ -1, "4", math.huge, 0/0 }) do
        data = fixture(); data.current.suspicious = value
        contains(build(data).current, "counts cannot be assessed")
    end
    data = fixture(); data.current.extreme = nil
    contains(build(data).current, "counts cannot be assessed")
end)

test("MIXED_LOW_RISING", function()
    local text = build(mature()).history
    contains(text, "reference is low among 30-day"); contains(text, "rising price trend")
end)
test("MIXED_LOW_SUPPLY_FALLING", function()
    local data = mature(); data.analytics.windows[7].quantityMedian, data.analytics.windows[7].supplyRatio, data.signals.supply = 2000, 0.5, "LOW_SUPPLY"
    data.analytics.trend7d.pctPerDay, data.signals.trend = -3, "FALLING"
    local text = build(data).history; contains(text, "below its recent usual level"); contains(text, "falling price trend")
end)
test("MIXED_7D_WITHOUT_30D", function()
    local data = mature(); data.analytics.maturity = "7D READY"
    data.analytics.windows[30], data.analytics.percentile30d, data.signals.price = { status = "INSUFFICIENT" }, nil, "INSUFFICIENT"
    local text = build(data).history
    contains(text, "20.0% below its 7-day"); contains(text, "rising price trend"); contains(text, "near its recent usual level")
    contains(text, "More history is needed for: 30-day price position."); absent(text, "reference is low among")
end)
test("MIXED_EXCLUSION_UNCHANGED_MEDIAN", function()
    local data = fixture(); data.current.extreme = 1
    assert(data.current.rawMedian == data.current.cleanMedian)
    local text = build(data).current; contains(text, "reference price is 27c"); contains(text, "1 extreme price level was excluded")
    absent(text, "clean data"); absent(text, "no price levels were excluded")
end)
test("MIXED_FAILED_NEW_STORED", function()
    local data, ctx = mature(), context(); data.error, ctx.scannerState = "UNKNOWN: timed out", "ERROR"
    local text = build(data, ctx)
    contains(text.current, "The new scan failed; showing the previous recorded scan.")
    contains(text.current, "reference price is 1s0c"); contains(text.history, "previous recorded scan")
    contains(text.history, "20.0% below its 7-day")
end)
test("FAILED_UPDATE_IS_NOT_ALWAYS_OLD_SCAN", function()
    local data = fixture(); data.error = "UNKNOWN: history clock"
    local text = build(data).current
    contains(text, "latest update reported an error"); absent(text, "new scan failed"); absent(text, "previous recorded")
end)
test("INVALID_ERROR_METADATA", function()
    for _, value in ipairs({ false, 0, "", {} }) do
        local data = fixture(); data.error = value
        local text = build(data).current
        contains(text, "update status cannot be assessed"); absent(text, "update reported an error"); absent(text, "new scan failed")
    end
end)
test("OTHER_ITEM_ERROR_DOES_NOT_LEAK", function()
    local ctx = context(); ctx.scannerItemID, ctx.scannerState = 2447, "ERROR"
    local text = build(fixture(), ctx).current; absent(text, "failed"); contains(text, "reference price is 27c")
end)
test("NO_RECORD", function()
    local text = build({})
    eq(text.current, "No scan recorded for this item."); eq(text.current, text.history)
    local ctx = context(); ctx.scannerState = "ERROR"
    text = build({}, ctx); contains(text.current, "The new scan failed."); contains(text.current, "No scan recorded")
end)
test("EMPTY_SCAN", function()
    local data = fixture(); data.current = { t = 100000, levelCount = 0, totalQuantity = 0, suspicious = 0, extreme = 0, anomalySufficient = false }
    local text = build(data).current
    contains(text, "No price levels returned in the latest scan."); absent(text, "reference price is"); absent(text, "market is empty")
end)
test("INVALID_RECORD", function()
    local data = fixture(); data.current = "bad"
    eq(build(data).current, "The recorded scan cannot be read.")
    data.current = {}; local text = build(data).current
    contains(text, "Not assessable from this record:"); absent(text, "No scan recorded"); absent(text, "No price levels returned")
end)
test("INCONSISTENT_EMPTY_RECORD", function()
    local data = mature(); data.current.levelCount, data.current.totalQuantity = 0, 0
    local text = build(data)
    absent(text.current, "No price levels returned"); contains(text.current, "fields are inconsistent")
    absent(text.history, "reference is low"); absent(text.history, "below its 7-day"); absent(text.history, "supply in this scan is")
    contains(text.history, "rising price trend")
    data.current.cleanMedian, data.current.rawMedian, data.current.q1, data.current.q3 = nil, nil, nil, nil
    data.analytics.windows[7].supplyRatio, data.signals.supply = 0, "LOW_SUPPLY"
    -- A leftover lowest price also contradicts an otherwise zero-count record.
    absent(build(data).history, "supply in this scan is")
    data.current.lowest, data.current.levelCount = nil, 2
    -- A positive price-level count cannot explain zero listed units.
    absent(build(data).history, "supply in this scan is")
end)
test("INDEPENDENT_HISTORY_FIELDS", function()
    local data = mature(); data.current.totalQuantity = nil
    local text = build(data).history
    contains(text, "20.0% below its 7-day"); contains(text, "reference is low"); contains(text, "rising price trend")
    absent(text, "supply in this scan is"); contains(text, "historical supply comparison")
end)
test("TIMESTAMP_AND_FUTURE_CLOCK", function()
    local data, ctx = fixture(), context(); data.current.t = nil
    contains(build(data, ctx).current, "Recorded scan age is unavailable.")
    data.current.t = 100500; contains(build(data, ctx).current, "Recorded timestamp: 100500; age unavailable, check the client clock.")
    data.current.t = 100120; contains(build(data, ctx).current, "less than a minute ago")
    data.current.t = 96520; contains(build(data, ctx).current, "1 hour ago")
    data.current.t = 13720; contains(build(data, ctx).current, "1 day ago")
end)
test("DEDUPE_TIME_STAYS_RECORDED_TIME", function()
    local data = fixture(); data.lastScan = 100120
    contains(build(data).current, "2 minutes ago")
end)
test("PURE_DETERMINISTIC_AND_INPUTS_UNCHANGED", function()
    for _, forbidden in ipairs({ "C_AuctionHouse", "CreateFrame", "SavedVariables", "MarketPilotDB", "_G", "OnUpdate", "random", "require" }) do
        assert(not source:find(forbidden, 1, true), forbidden)
    end
    assert(not source:find("os%.") and not source:find("io%.") and not source:find("Statistics%."))
    local data, ctx = mature(), context(); data.history = { copy(data.current) }
    local before, beforeContext = copy(data), copy(ctx)
    local text, insight = build(data, ctx)
    for _ = 1, 5 do local nextText, nextInsight = build(data, ctx); eq(nextText, text); eq(nextInsight, insight) end
    eq(data, before); eq(ctx, beforeContext)
    insight.current[1].price = 99999; eq(data, before)
end)

print("PASS: " .. passed .. " MarketInsight tests")
