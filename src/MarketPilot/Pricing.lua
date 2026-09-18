local _, MP = ...
local Pricing = {}
MP.Pricing = Pricing

local function target(value)
    if type(value) == "number" and value >= 1 and value <= 9007199254740991 and value % 1 == 0 then
        return { status = "OK", copper = value }
    end
    return { status = "UNKNOWN" }
end

-- MP-04-v1: interpret the existing analysis, never recalculate Statistics.
function Pricing.Targets(analysis)
    local anomaly = type(analysis) == "table" and analysis.anomaly
    if type(anomaly) ~= "table" or anomaly.sufficient ~= true then
        return { fast = { status = "INSUFFICIENT" }, normal = { status = "INSUFFICIENT" },
            patient = { status = "INSUFFICIENT" } }
    end
    local lowest
    for _, row in ipairs(anomaly.levels or {}) do
        if row.class == "NORMAL" then
            if target(row.unitPrice).status ~= "OK" then
                return { fast = target(nil), normal = target(nil), patient = target(nil) }
            end
            if not lowest or row.unitPrice < lowest then lowest = row.unitPrice end
        end
    end
    local clean = analysis.clean or {}
    return { fast = target(lowest), normal = target(clean.weightedMedian), patient = target(clean.q3) }
end
