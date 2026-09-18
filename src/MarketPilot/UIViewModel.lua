local _, MP = ...
local View = {}
MP.UIViewModel = View

local function integer(value, minimum)
    return type(value) == "number" and value >= minimum
        and value <= 9007199254740991 and value % 1 == 0
end

function View.Money(value)
    if not integer(value, 1) then return "UNKNOWN" end
    local remainder = value % 10000
    local copper = remainder % 100
    return string.format("%.0fg %.0fs %.0fc", (value - remainder) / 10000, (remainder - copper) / 100, copper)
end

local function count(value)
    return integer(value, 0) and string.format("%.0f", value) or "UNKNOWN"
end

function View.Percent(value)
    return MP.HistoryMath.Finite(value) and string.format("%+.1f%%", value) or "INSUFFICIENT"
end
function View.PValue(value)
    if not MP.HistoryMath.Finite(value) or value < 0 or value > 1 then return "INSUFFICIENT" end
    return value < 0.0001 and "p<0.0001" or string.format("p=%.4f", value)
end
function View.ReferenceMoney(value)
    if not MP.HistoryMath.Finite(value) or value <= 0 then return "INSUFFICIENT" end
    return value % 1 == 0 and View.Money(value) or string.format("%.1fc", value)
end
function View.Watch(data)
    local current, a, signal = data.current, data.analytics, data.signals
    local now = current and View.Money(current.cleanMedian):gsub("^0g ", ""):gsub("^0s ", ""):gsub(" ", "") or "?"
    local window = a.windows[7]
    local change = window and window.change
    local arrows = { RISING = "^", FALLING = "v", STABLE = "=" }
    local supplies = { LOW_SUPPLY = "Low", NORMAL_SUPPLY = "Normal", HIGH_SUPPLY = "High" }
    return { now = data.error and "ERROR" or now, change = change and string.format("%+.0f%%", change) or "?",
        trend = arrows[signal.trend] or "?", percentile = a.percentile30d and string.format("%.0f", a.percentile30d) or "?",
        supply = supplies[signal.supply] or "?", maturity = a.maturity }
end
function View.History(data, now)
    local a, values = data.analytics, {}
    for _, days in ipairs({ 1, 7, 30 }) do
        local window = a.windows[days]
        values["median" .. days] = View.ReferenceMoney(window and window.median)
        values["change" .. days] = View.Percent(window and window.change)
    end
    local window, significance = a.windows[7], a.significance
    values.trend = a.trend7d.status == "OK" and View.Percent(a.trend7d.pctPerDay) .. "/day" or a.trend7d.status
    values.percentile = a.percentile30d and string.format("%.1f / 100", a.percentile30d) or "INSUFFICIENT"
    values.volatility = a.volatility.status == "OK" and string.format("%.1f%% / %s", a.volatility.pct, a.volatility.class) or a.volatility.status
    values.supply = window and window.supplyRatio and string.format("%.2fx / %s", window.supplyRatio, data.signals.supply:gsub("_SUPPLY", "")) or "INSUFFICIENT"
    values.significance = significance.status == "OK" and string.format("%s / shift %s", View.PValue(significance.p),
        significance.meaningfulMove and "YES" or "NO") or significance.status
    values.lastScan = data.lastScan and now >= data.lastScan and string.format("%.0fm ago", math.floor((now - data.lastScan) / 60)) or "UNKNOWN"
    values.observations = count(a.count) .. " / " .. a.maturity
    values.signal = data.signals.summary or "UNKNOWN"
    return values
end
function View.Report(report, items)
    local lines = { "MARKET REPORT" }
    local sections = { { "Rising markets", "rising" }, { "Below historical range", "cheap" },
        { "Unusual return volatility", "volatile" }, { "Meaningful changes", "significant" } }
    for _, section in ipairs(sections) do
        lines[#lines + 1] = "\n" .. section[1]
        if #report[section[2]] == 0 then lines[#lines + 1] = "No supported observations" end
        for _, row in ipairs(report[section[2]]) do
            local a, value = row.data.analytics, "HIGH"
            if section[2] == "rising" then value = View.Percent(a.trend7d.pctPerDay) .. "/day"
            elseif section[2] == "cheap" then value = string.format("30d percentile %.0f", a.percentile30d)
            elseif section[2] == "significant" then value = View.PValue(a.significance.p) .. ", " .. View.Percent(a.significance.change) end
            lines[#lines + 1] = items.Metadata(row.itemID).name .. ": " .. value
        end
    end
    lines[#lines + 1] = "\nData maturity"
    for _, state in ipairs({ "NEW", "EARLY", "7D READY", "30D READY" }) do lines[#lines + 1] = state .. ": " .. report.maturity[state] end
    lines[#lines + 1] = "\nDescriptive observations; p-values are approximate."
    return table.concat(lines, "\n")
end

function View.Build(scanner, selectedItemID, metadata)
    local busy = scanner:IsActive()
    local current = scanner.state == "DONE" and scanner.sample and scanner.sample.itemID == selectedItemID
    local analysis = current and scanner.analysis
    local raw, clean, anomaly = analysis and analysis.raw, analysis and analysis.clean, analysis and analysis.anomaly
    local state = scanner.ahOpen and scanner.state or "AH CLOSED"
    local messages = {
        IDLE = "Choose an item to scan.", WAITING = "Waiting for throttle readiness...",
        QUERYING = "Waiting for commodity results...", COLLECTING = "Reading price levels...",
        DONE = "Current scan complete.", ERROR = "UNKNOWN: scan failed.",
        ["AH CLOSED"] = "Open the Auction House to browse.",
    }
    local sufficient = "UNKNOWN"
    if anomaly then sufficient = anomaly.sufficient and "SUFFICIENT" or "INSUFFICIENT" end
    local range = "UNKNOWN"
    if clean and integer(clean.q1, 1) and integer(clean.q3, 1) then
        range = View.Money(clean.q1) .. " - " .. View.Money(clean.q3)
    end
    local message = scanner.error or messages[state] or "UNKNOWN scanner state"
    if state == "DONE" and not analysis then message = "UNKNOWN: no analysis for the selected item." end
    if analysis and not anomaly.sufficient then
        message = anomaly.reason == "TOO_FEW_PRICE_LEVELS" and "INSUFFICIENT: fewer than 5 distinct prices."
            or "INSUFFICIENT: unusable anomaly scale."
    end
    return {
        itemID = selectedItemID, name = metadata.name, icon = metadata.icon, state = state,
        message = message, scanEnabled = scanner.ahOpen and not busy and not scanner.blockedReason,
        itemsEnabled = scanner.ahOpen and not busy and not scanner.blockedReason,
        buttonText = busy and "Scanning..." or (current and "Refresh" or "Scan"),
        lowest = View.Money(raw and raw.min), rawMedian = View.Money(raw and raw.weightedMedian),
        cleanMedian = View.Money(clean and clean.weightedMedian), range = range,
        quantity = count(raw and raw.totalQuantity), levels = count(raw and raw.levelCount),
        suspicious = count(anomaly and anomaly.suspiciousCount), extreme = count(anomaly and anomaly.extremeCount),
        sufficient = sufficient,
        exclusion = anomaly and ("Extreme outliers excluded: " .. count(anomaly.extremeCount) .. ". Suspicious retained.")
            or "Outlier classification: UNKNOWN",
    }
end
