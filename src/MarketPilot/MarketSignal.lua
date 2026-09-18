local _, MP = ...
local Signal, M = {}, MP.HistoryMath
MP.MarketSignal = Signal
function Signal.Describe(analytics)
    local missing = analytics.status == "UNKNOWN" and "UNKNOWN" or "INSUFFICIENT"
    local result = { price = missing, trend = missing, supply = missing, volatility = missing }
    if analytics.status == "UNKNOWN" then return result end
    local percentile = analytics.percentile30d
    if M.Finite(percentile) then
        result.price = percentile <= 20 and "CHEAP_VS_HISTORY" or (percentile >= 80 and "EXPENSIVE_VS_HISTORY" or "NORMAL_RANGE")
    end
    local trend = analytics.trend7d
    if trend.status == "OK" then
        result.trend = trend.pctPerDay > 2 and "RISING" or (trend.pctPerDay < -2 and "FALLING" or "STABLE")
    elseif trend.status == "UNKNOWN" then result.trend = "UNKNOWN" end
    local window = analytics.windows[7]
    if window and window.status == "OK" and M.Finite(window.supplyRatio) then
        result.supply = window.supplyRatio <= 0.6 and "LOW_SUPPLY" or (window.supplyRatio >= 1.6 and "HIGH_SUPPLY" or "NORMAL_SUPPLY")
    end
    if analytics.volatility.status == "OK" then result.volatility = analytics.volatility.class end
    result.summary = result.trend .. " / " .. result.price .. " / " .. result.supply
    return result
end
