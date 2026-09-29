local _, MP = ...
local Insight, M = {}, MP.HistoryMath
MP.MarketInsight = Insight

local function record(value) return type(value) == "table" and value or {} end
local function positive(value) return M.Finite(value) and value > 0 end
local function add(messages, code, values)
    local message = values or {}; message.code = code
    messages[#messages + 1] = message
end
local function sameDirection(a, b, change)
    return (a == b and change == 0) or (a < b and change < 0) or (a > b and change > 0)
end

-- Consistency guards for existing MarketSignal labels, not a second signal model.
-- Unknown/mismatched labels stay unavailable; no replacement label is inferred.
local function matches(label, value, low, high, lowerLabel, middleLabel, upperLabel)
    return (label == lowerLabel and value <= low) or (label == upperLabel and value >= high)
        or (label == middleLabel and value > low and value < high)
end

local function historyMessages(data, current, messages)
    local analytics, signal = record(data.analytics), record(data.signals)
    local windows = record(analytics.windows)
    local week, month, trend = record(windows[7]), record(windows[30]), record(analytics.trend7d)
    local missing, unavailable, supported = {}, {}, 0
    local function metric(name, status, valid, code, values)
        if status == "OK" and valid then add(messages, code, values); supported = supported + 1
        elseif status == "INSUFFICIENT" then missing[#missing + 1] = name
        else unavailable[#unavailable + 1] = name end
    end
    local hasPrice = current.cleanMedian ~= nil or current.rawMedian ~= nil or current.lowest ~= nil
        or current.q1 ~= nil or current.q3 ~= nil
    local contradictoryCount = current.levelCount == 0 and (current.totalQuantity ~= 0 or hasPrice)
        or current.totalQuantity == 0 and (M.Integer(current.levelCount, 1) or hasPrice)
    local reference = M.Integer(current.cleanMedian, 1) and not contradictoryCount
    metric("CHANGE", week.status, reference and positive(week.median) and M.Finite(week.change)
        and week.change > -100 and sameDirection(current.cleanMedian, week.median, week.change),
        "HISTORY_CHANGE", { change = week.change })
    local trendNumber = M.Finite(trend.pctPerDay) and trend.pctPerDay > -100
    local trendValid = trendNumber and ((signal.trend == "RISING" and trend.pctPerDay > 2)
            or (signal.trend == "FALLING" and trend.pctPerDay < -2)
            or (signal.trend == "STABLE" and trend.pctPerDay >= -2 and trend.pctPerDay <= 2))
    metric("TREND", trend.status, trendValid, "HISTORY_TREND", { label = signal.trend })
    if trend.status == "OK" and trendNumber and not trendValid then
        add(messages, "HISTORY_TREND_VALUE", { change = trend.pctPerDay })
    end
    local ratio = week.supplyRatio
    local supplyNumber = M.Integer(current.totalQuantity, 0) and not contradictoryCount and positive(week.quantityMedian)
        and M.Finite(ratio) and ratio >= 0
        and ((current.totalQuantity == 0 and ratio == 0) or (current.totalQuantity > 0 and ratio > 0))
        and ((current.totalQuantity == week.quantityMedian and ratio == 1)
            or (current.totalQuantity < week.quantityMedian and ratio < 1)
            or (current.totalQuantity > week.quantityMedian and ratio > 1))
    local supplyValid = supplyNumber and matches(signal.supply, ratio, 0.6, 1.6, "LOW_SUPPLY", "NORMAL_SUPPLY", "HIGH_SUPPLY")
    metric("SUPPLY", week.status, supplyValid, "HISTORY_SUPPLY", { label = signal.supply, ratio = ratio })
    if week.status == "OK" and supplyNumber and not supplyValid then add(messages, "HISTORY_SUPPLY_VALUE", { ratio = ratio }) end
    local percentile = analytics.percentile30d
    local positionNumber = reference and M.Finite(percentile) and percentile >= 0 and percentile <= 100
    local positionValid = positionNumber and matches(signal.price, percentile, 20, 80, "CHEAP_VS_HISTORY", "NORMAL_RANGE", "EXPENSIVE_VS_HISTORY")
    metric("POSITION", month.status, positionValid, "HISTORY_POSITION", { label = signal.price, percentile = percentile })
    if month.status == "OK" and positionNumber and not positionValid then add(messages, "HISTORY_POSITION_VALUE", { percentile = percentile }) end
    if #missing == 4 then add(messages, "MORE_HISTORY")
    elseif #missing > 0 then add(messages, "HISTORY_MISSING", { metrics = missing }) end
    if #unavailable > 0 then add(messages, "HISTORY_UNAVAILABLE", { metrics = unavailable }) end
    return supported, missing, unavailable
end

local function currentMessages(current, messages)
    local reference, lowest = M.Integer(current.cleanMedian, 1), M.Integer(current.lowest, 1)
    local band = M.Integer(current.q1, 1) and M.Integer(current.q3, 1) and current.q1 <= current.q3
        and (not reference or (current.q1 <= current.cleanMedian and current.cleanMedian <= current.q3))
    local conflictingLowest = lowest and M.Integer(current.q1, 1) and current.lowest > current.q1
    if conflictingLowest then band = false end
    local empty = current.levelCount == 0 and current.totalQuantity == 0 and current.cleanMedian == nil
        and current.rawMedian == nil and current.lowest == nil and current.q1 == nil and current.q3 == nil
        and current.suspicious == 0 and current.extreme == 0
    if empty then add(messages, "EMPTY_SCAN"); return end
    if reference then
        add(messages, band and "REFERENCE_BAND" or "REFERENCE", { price = current.cleanMedian, q1 = band and current.q1 or nil, q3 = band and current.q3 or nil })
    elseif band then add(messages, "BAND", { q1 = current.q1, q3 = current.q3 }) end
    if lowest then
        local change = reference and current.lowest <= current.cleanMedian and 100 * (current.lowest / current.cleanMedian - 1) or nil
        if M.Finite(change) then add(messages, change == 0 and "LOWEST_EQUAL" or "LOWEST_BELOW", { price = current.lowest, change = change })
        else add(messages, "LOWEST", { price = current.lowest }) end
    end
    if M.Integer(current.totalQuantity, 0) then add(messages, "QUANTITY", { count = current.totalQuantity }) end
    local missing = {}
    if not reference then missing[#missing + 1] = "REFERENCE" end
    if not band then missing[#missing + 1] = "BAND" end
    if not lowest then missing[#missing + 1] = "LOWEST" end
    if not M.Integer(current.totalQuantity, 0) then missing[#missing + 1] = "QUANTITY" end
    if #missing > 0 then add(messages, "CURRENT_UNAVAILABLE", { metrics = missing }) end
    if (lowest and reference and current.lowest > current.cleanMedian)
        or conflictingLowest
        or current.levelCount == 0 or current.totalQuantity == 0 then add(messages, "INCONSISTENT_RECORD") end

    local suspicious, extreme, levels = current.suspicious, current.extreme, current.levelCount
    local countsValid = M.Integer(suspicious, 0) and M.Integer(extreme, 0) and M.Integer(levels, 1)
        and suspicious <= levels and extreme <= levels - suspicious
    if countsValid and not (current.anomalySufficient == false and extreme > 0) then
        add(messages, "ANOMALY_COUNTS", { suspicious = suspicious, extreme = extreme })
    else add(messages, "ANOMALY_UNAVAILABLE") end
    if current.anomalySufficient == false then add(messages, "FILTER_INSUFFICIENT")
    elseif current.anomalySufficient ~= true then add(messages, "FILTER_UNAVAILABLE") end
end

-- data is Market:Get(context.itemID); it contains .current/.analytics/.signals.
-- Output owns its message tables: code + primitive parameters (or metric enum lists).
-- .current and .history are presentation sequences; inputs/history are never modified.
function Insight.Build(data, context)
    data, context = record(data), record(context)
    local result = { itemID = context.itemID, current = {}, history = {} }
    local hasRecord = type(data.current) == "table"
    local current = record(data.current)
    local failedScan = M.Integer(context.itemID, 1) and context.scannerItemID == context.itemID and context.scannerState == "ERROR"
    local failed = failedScan or (type(data.error) == "string" and data.error ~= "")
    if failed then
        local code = failedScan and (hasRecord and "SCAN_FAILED_STORED" or "SCAN_FAILED")
            or (hasRecord and "UPDATE_FAILED_STORED" or "UPDATE_FAILED")
        add(result.current, code); add(result.history, code)
    elseif data.error ~= nil then
        add(result.current, "UPDATE_STATUS_UNAVAILABLE"); add(result.history, "UPDATE_STATUS_UNAVAILABLE")
    end
    if not hasRecord then
        local code = data.current == nil and "NO_SCAN" or "INVALID_RECORD"
        add(result.current, code); add(result.history, code)
        return result
    end
    currentMessages(current, result.current)
    local supported, missing, unavailable = historyMessages(data, current, result.history)
    if #missing == 4 then add(result.current, "MORE_HISTORY")
    elseif #missing > 0 then add(result.current, "HISTORY_MISSING", { metrics = missing }) end
    if #unavailable > 0 then add(result.current, "HISTORY_UNAVAILABLE", { metrics = unavailable }) end
    if supported > 0 then add(result.current, "HISTORY_AVAILABLE") end
    -- Age refers to the retained snapshot, not a newer deduped session check.
    local code, values = "SCAN_TIME_UNAVAILABLE", nil
    if M.Integer(current.t, 0) then
        if M.Finite(context.now) and context.now >= current.t then code, values = "SCAN_AGE", { seconds = context.now - current.t }
        else code, values = "SCAN_CLOCK", { timestamp = current.t } end
    end
    add(result.current, code, values)
    add(result.history, code, values and { seconds = values.seconds, timestamp = values.timestamp } or nil)
    return result
end
