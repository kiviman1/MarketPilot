local _, MP = ...
local H, M = {}, MP.HistoryMath
MP.HistoricalAnalytics = H
local DAY = 86400

local function trend(rows)
    if #rows < 5 or rows[#rows].t - rows[1].t < DAY then return { status = "INSUFFICIENT" } end
    local slopes = {}
    for i = 1, #rows - 1 do
        for j = i + 1, #rows do
            slopes[#slopes + 1] = (math.log(rows[j].cleanMedian) - math.log(rows[i].cleanMedian))
                / ((rows[j].t - rows[i].t) / DAY)
        end
    end
    local slope = M.Median(slopes)
    local pct = (math.exp(slope) - 1) * 100
    if not M.Finite(pct) then return { status = "UNKNOWN" } end
    return { status = "OK", slope = slope, pctPerDay = pct }
end

local function volatility(rows)
    if #rows < 5 or rows[#rows].t - rows[1].t < DAY then return { status = "INSUFFICIENT" } end
    local returns = {}
    for i = 2, #rows do returns[#returns + 1] = math.log(rows[i].cleanMedian) - math.log(rows[i - 1].cleanMedian) end
    local sigma = 1.4826 * M.MAD(returns)
    -- Relative unusual-return score against this item's preceding returns.
    local prior = {}; for i = 1, #returns - 1 do prior[i] = returns[i] end
    local center, scale = M.Median(prior), 1.4826 * M.MAD(prior)
    local deviation = math.abs(returns[#returns] - center)
    local score = scale > 1e-12 and deviation / scale or nil
    local class = scale <= 1e-12 and (deviation <= 1e-12 and "LOW" or "HIGH")
        or (score <= 1 and "LOW" or (score > 3 and "HIGH" or "NORMAL"))
    return { status = "OK", pct = (math.exp(sigma) - 1) * 100, class = class, score = score }
end

function H.Analyze(history, current)
    local result = { status = "INSUFFICIENT", maturity = "NEW", count = 0, windows = {},
        trend7d = { status = "INSUFFICIENT" }, trend30d = { status = "INSUFFICIENT" },
        volatility = { status = "INSUFFICIENT" }, significance = { status = "INSUFFICIENT" } }
    if type(history) ~= "table" or type(current) ~= "table" or not M.Integer(current.t, 0) then
        result.status = "UNKNOWN"; return result
    end
    local now, byTime = current.t, {}
    -- One observation per timestamp; later input wins. Current is not its own baseline.
    for _, row in ipairs(history) do
        if type(row) == "table" and M.Integer(row.t, 0) and row.t <= now and row.t >= now - 60 * DAY
            and M.Integer(row.cleanMedian, 1) then byTime[row.t] = row end
    end
    byTime[now] = M.Integer(current.cleanMedian, 1) and current or nil
    local rows = {}; for _, row in pairs(byTime) do rows[#rows + 1] = row end
    table.sort(rows, function(a, b) return a.t < b.t end)
    result.count = #rows
    local span = #rows > 0 and now - rows[1].t or 0
    if #rows >= 3 then result.maturity = span >= 30 * DAY and "30D READY" or (span >= 7 * DAY and "7D READY" or "EARLY") end
    local sets = {}
    for _, days in ipairs({ 1, 7, 30 }) do
        local prices, quantities, inWindow = {}, {}, {}
        for _, row in ipairs(rows) do
            if row.t >= now - days * DAY then
                inWindow[#inWindow + 1] = row
                if row.t < now then
                    prices[#prices + 1] = row.cleanMedian
                    if M.Integer(row.totalQuantity, 0) then quantities[#quantities + 1] = row.totalQuantity end
                end
            end
        end
        local window = { status = "INSUFFICIENT", count = #prices }
        if span >= days * DAY and #prices >= 3 then
            window.status, window.median = "OK", M.Median(prices)
            window.change = M.Change(current.cleanMedian, window.median)
            window.quantityMedian = M.Median(quantities)
            if window.quantityMedian and window.quantityMedian > 0 and M.Integer(current.totalQuantity, 0) then
                window.supplyRatio = current.totalQuantity / window.quantityMedian
            end
        end
        result.windows[days], sets[days] = window, inWindow
    end
    if result.windows[30].status == "OK" and M.Integer(current.cleanMedian, 1) then
        local less, equal, count = 0, 0, 0
        for _, row in ipairs(sets[30]) do
            if row.t < now then
                count = count + 1
                if row.cleanMedian < current.cleanMedian then less = less + 1
                elseif row.cleanMedian == current.cleanMedian then equal = equal + 1 end
            end
        end
        result.percentile30d = 100 * (less + equal / 2) / count
    end
    result.trend7d = trend(sets[7])
    if span >= 30 * DAY then result.trend30d = trend(sets[30]) end
    result.volatility = volatility(sets[7])
    local recent, baseline = {}, {}
    for _, row in ipairs(rows) do
        if row.t >= now - DAY then recent[#recent + 1] = row.cleanMedian
        elseif row.t >= now - 8 * DAY then baseline[#baseline + 1] = row.cleanMedian end
    end
    result.significance = MP.Significance.Compare(recent, baseline)
    result.status = M.Integer(current.cleanMedian, 1) and "OK" or "UNKNOWN"
    return result
end
