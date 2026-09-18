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
