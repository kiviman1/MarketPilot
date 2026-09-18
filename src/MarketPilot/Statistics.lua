local _, MP = ...
local Statistics = {}
if MP then MP.Statistics = Statistics end

local MAX_INTEGER = 9007199254740991
local SCALE_EPSILON = 1e-12
local MODEL_VERSION = "MP-02-v1"

local function positiveInteger(value)
    return type(value) == "number" and value > 0
        and value <= MAX_INTEGER and value % 1 == 0
end

local function copyLevels(sample)
    if type(sample) ~= "table" or type(rawget(sample, "priceLevels")) ~= "table" then
        return nil, "UNKNOWN: priceLevels must be a dense array"
    end
    local source, count, last = rawget(sample, "priceLevels"), 0, 0
    for key in next, source do
        if not positiveInteger(key) then return nil, "UNKNOWN: invalid priceLevels index" end
        count, last = count + 1, math.max(last, key)
    end
    if count ~= last then return nil, "UNKNOWN: sparse priceLevels array" end
    local levels, total = {}, 0
    for index = 1, count do
        local row = rawget(source, index)
        if type(row) ~= "table" then return nil, "UNKNOWN: invalid price level " .. index end
        local price, quantity = rawget(row, "unitPrice"), rawget(row, "quantity")
        if not positiveInteger(price) then return nil, "UNKNOWN: invalid unitPrice at level " .. index end
        if not positiveInteger(quantity) then return nil, "UNKNOWN: invalid quantity at level " .. index end
        if quantity > MAX_INTEGER - total then return nil, "UNKNOWN: unsafe integer quantity sum" end
        total = total + quantity
        levels[index] = { unitPrice = price, quantity = quantity }
    end
    table.sort(levels, function(a, b)
        if a.unitPrice == b.unitPrice then return a.quantity < b.quantity end
        return a.unitPrice < b.unitPrice
    end)
    return levels
end

-- First cumulative quantity >= p * total. Compute ceil(total * numerator / 4)
-- without rounding the product near the exact-integer boundary.
local function weightedQuantile(levels, total, numerator)
    local rank = math.floor(total / 4) * numerator + math.ceil((total % 4) * numerator / 4)
    local cumulative = 0
    for _, level in ipairs(levels) do
        cumulative = cumulative + level.quantity
        if cumulative >= rank then return level.unitPrice end
    end
end

local function descriptors(levels)
    local result = { levelCount = #levels, totalQuantity = 0 }
    for _, level in ipairs(levels) do result.totalQuantity = result.totalQuantity + level.quantity end
    if #levels > 0 then
        result.min, result.max = levels[1].unitPrice, levels[#levels].unitPrice
        result.q1 = weightedQuantile(levels, result.totalQuantity, 1)
        result.weightedMedian = weightedQuantile(levels, result.totalQuantity, 2)
        result.q3 = weightedQuantile(levels, result.totalQuantity, 3)
    end
    return result
end

-- Unweighted type-7 quantile, used only for log prices and their deviations.
local function quantile(values, p)
    local h = 1 + (#values - 1) * p
    local lower = math.floor(h)
    local fraction = h - lower
    if fraction == 0 then return values[lower] end
    return values[lower] + fraction * (values[lower + 1] - values[lower])
end

function Statistics.Analyze(sample)
    local levels, err = copyLevels(sample)
    if not levels then return nil, err end
    -- One observation per distinct price, independent of quantity. Duplicate
    -- returned prices remain separate raw/clean rows but cannot inflate evidence.
    local logs, previous = {}, nil
    for _, level in ipairs(levels) do
        if level.unitPrice ~= previous then logs[#logs + 1] = math.log(level.unitPrice) end
        previous = level.unitPrice
    end
    local anomaly = {
        sufficient = false, observationCount = #logs, reason = "TOO_FEW_PRICE_LEVELS",
        suspiciousCount = 0, extremeCount = 0, levels = {},
        madUsable = false, iqrUsable = false,
    }
    if #logs > 0 then
        anomaly.logMedian = quantile(logs, 0.5)
        anomaly.logQ1, anomaly.logQ3 = quantile(logs, 0.25), quantile(logs, 0.75)
        anomaly.logIQR = anomaly.logQ3 - anomaly.logQ1
        local deviations = {}
        for i, value in ipairs(logs) do deviations[i] = math.abs(value - anomaly.logMedian) end
        table.sort(deviations)
        anomaly.logMAD = quantile(deviations, 0.5)
        anomaly.madUsable = anomaly.logMAD > SCALE_EPSILON
        anomaly.iqrUsable = anomaly.logIQR > SCALE_EPSILON
        if #logs >= 5 then
            anomaly.sufficient = anomaly.madUsable and anomaly.iqrUsable
            anomaly.reason = anomaly.sufficient and "CURRENT_SCAN_ONLY" or "DEGENERATE_SCALE"
        end
    end
    local clean = {}
    for _, level in ipairs(levels) do
        local x = math.log(level.unitPrice)
        local z
        if anomaly.madUsable then z = 0.6745 * (x - anomaly.logMedian) / anomaly.logMAD end
        local madSuspicious = z ~= nil and math.abs(z) > 3.5
        local madExtreme = z ~= nil and math.abs(z) > 6.0
        local iqrSuspicious = x < anomaly.logQ1 - 1.5 * anomaly.logIQR
            or x > anomaly.logQ3 + 1.5 * anomaly.logIQR
        local iqrExtreme = x < anomaly.logQ1 - 3.0 * anomaly.logIQR
            or x > anomaly.logQ3 + 3.0 * anomaly.logIQR
        local class = "NORMAL"
        if anomaly.sufficient and madExtreme and iqrExtreme then
            class = "EXTREME"
            anomaly.extremeCount = anomaly.extremeCount + 1
        elseif madSuspicious or iqrSuspicious then
            class = "SUSPICIOUS"
            anomaly.suspiciousCount = anomaly.suspiciousCount + 1
        end
        anomaly.levels[#anomaly.levels + 1] = {
            unitPrice = level.unitPrice, quantity = level.quantity, class = class,
            logPrice = x, modifiedZ = z,
            madSuspicious = madSuspicious, madExtreme = madExtreme,
            iqrSuspicious = iqrSuspicious, iqrExtreme = iqrExtreme,
        }
        if class ~= "EXTREME" then clean[#clean + 1] = level end
    end
    return {
        modelVersion = MODEL_VERSION, status = anomaly.sufficient and "OK" or "INSUFFICIENT",
        raw = descriptors(levels), clean = descriptors(clean), anomaly = anomaly,
    }
end

return Statistics
