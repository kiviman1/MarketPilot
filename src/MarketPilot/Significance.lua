local _, MP = ...
local S, M = {}, MP.HistoryMath
MP.Significance = S

-- Two-sided normal tail approximation; absolute p error < 1.5e-7.
local function twoSided(z)
    if z == 0 then return 1 end
    local t = 1 / (1 + 0.2316419 * z)
    local tail = 0.3989422804014327 * math.exp(-z * z / 2) * t
        * (0.319381530 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))))
    return math.max(0, math.min(1, 2 * tail))
end

local function sampleCount(list)
    if type(list) ~= "table" then return nil end
    local count, last = 0, 0
    for index, value in pairs(list) do
        if not M.Integer(index, 1) or not M.Finite(value) or value <= 0 then return nil end
        count, last = count + 1, math.max(last, index)
    end
    if count ~= last then return nil end
    return count
end

function S.Compare(recent, baseline)
    local n, m = sampleCount(recent), sampleCount(baseline)
    local result = { status = "UNKNOWN", recentCount = n, baselineCount = m }
    if not n or not m then return result end
    result.status = "INSUFFICIENT"
    local rows = {}
    for group, list in ipairs({ recent, baseline }) do
        for _, value in ipairs(list) do
            rows[#rows + 1] = { value = value, recent = group == 1 }
        end
    end
    local N = #rows
    if n < 3 or m < 7 then return result end
    table.sort(rows, function(a, b) return a.value < b.value end)
    local rankSum, tieSum, i = 0, 0, 1
    while i <= N do
        local j = i; while j < N and rows[j + 1].value == rows[i].value do j = j + 1 end
        local rank, size = (i + j) / 2, j - i + 1
        for k = i, j do if rows[k].recent then rankSum = rankSum + rank end end
        tieSum = tieSum + size ^ 3 - size
        i = j + 1
    end
    local u = rankSum - n * (n + 1) / 2
    local variance = n * m / 12 * (N + 1 - tieSum / (N * (N - 1)))
    local z = variance > 0 and math.max(0, math.abs(u - n * m / 2) - 0.5) / math.sqrt(variance) or 0
    result.status, result.method, result.u, result.p = "OK", "MW_NORMAL_TIE_CONTINUITY", u, twoSided(z)
    local recentMedian, baselineMedian = M.Median(recent), M.Median(baseline)
    result.change = M.Change(recentMedian, baselineMedian)
    result.significant = result.p < 0.05
    result.practical = math.abs(recentMedian - baselineMedian) >= baselineMedian / 10
    result.meaningfulMove = result.significant and result.practical
    return result
end
