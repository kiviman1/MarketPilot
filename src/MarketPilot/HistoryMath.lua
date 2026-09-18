local _, MP = ...
local M = {}
MP.HistoryMath = M
function M.Finite(x) return type(x) == "number" and x == x and math.abs(x) < math.huge end
function M.Integer(x, minimum)
    return M.Finite(x) and x >= minimum and x <= 9007199254740991 and x % 1 == 0
end
function M.Median(values)
    if #values == 0 then return nil end
    local sorted = {}; for i, value in ipairs(values) do sorted[i] = value end
    table.sort(sorted)
    local middle = math.floor((#sorted + 1) / 2)
    if #sorted % 2 == 1 then return sorted[middle] end
    return sorted[middle] + (sorted[middle + 1] - sorted[middle]) / 2
end
function M.MAD(values)
    local center = M.Median(values); if not center then return nil end
    local deviations = {}; for i, x in ipairs(values) do deviations[i] = math.abs(x - center) end
    return M.Median(deviations)
end
function M.Change(current, baseline)
    if not M.Finite(current) or not M.Finite(baseline) or current <= 0 or baseline <= 0 then return nil end
    local value = (current / baseline - 1) * 100
    return M.Finite(value) and value or nil
end
