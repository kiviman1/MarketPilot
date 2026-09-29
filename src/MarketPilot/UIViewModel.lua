local _, MP = ...
local View = {}
MP.UIViewModel = View

local function integer(value, minimum)
    return type(value) == "number" and value >= minimum
        and value <= 9007199254740991 and value % 1 == 0
end

function View.Money(value)
    if not integer(value, 1) then return "No price data" end
    local remainder = value % 10000
    local copper = remainder % 100
    return string.format("%.0fg %.0fs %.0fc", (value - remainder) / 10000, (remainder - copper) / 100, copper)
end

local function count(value)
    return integer(value, 0) and string.format("%.0f", value) or "Not available"
end

-- Presentation labels only: module status values remain unchanged for debugging.
function View.State(state)
    local labels = { IDLE = "Ready", WAITING = "Waiting for AH", QUERYING = "Scanning", COLLECTING = "Reading results",
        DONE = "Complete", ERROR = "Scan failed", RUNNING = "Scanning", CANCELLED = "Cancelled", BROWSING = "Opening AH search",
        ["AH CLOSED"] = "AH closed", ["READ ONLY"] = "Stored history" }
    return labels[state] or "Scan stopped"
end
function View.Maturity(state)
    local labels = { NEW = "New", EARLY = "Building", ["7D READY"] = "7d ready", ["30D READY"] = "30d ready" }
    return labels[state] or "Building"
end
function View.Anomaly(sufficient)
    if sufficient == true then return "Enough price levels" end
    return sufficient == false and "More price levels needed" or "Not assessed"
end
function View.Error(reason)
    local text = type(reason) == "string" and reason:lower() or ""
    if text:find("history", 1, true) then
        if text:find("identity", 1, true) then return "History unavailable: realm/faction not ready." end
        if text:find("clock", 1, true) then return "History paused: check the client clock. Saved data kept." end
        return "History unavailable: saved data kept. See /mp dbstatus."
    end
    if text:find("close/reopen", 1, true) or text:find("reopen ah", 1, true) then
        return "No reliable result. Close and reopen the Auction House to scan again."
    end
    if text:find("missing api", 1, true) or text:find("unavailable", 1, true) or text:find("required event", 1, true) then
        return "Scanning unavailable in this client. See /mp status."
    end
    if text:find("timed out", 1, true) or text:find("timeout", 1, true) then return "AH did not respond in time. Try again later." end
    if text:find("unitprice", 1, true) or text:find("quantity", 1, true) or text:find("row ", 1, true) then
        return "Scan failed: incomplete price data. Try Refresh."
    end
    return "Scan failed. Try Refresh; see /mp status for details."
end

local function unavailable(status)
    return status == "UNKNOWN" and "Not available" or "Needs history"
end
local function signalSummary(signal)
    local labels = { RISING = "Rising", STABLE = "Stable", FALLING = "Falling", CHEAP_VS_HISTORY = "Below usual range",
        NORMAL_RANGE = "Usual range", EXPENSIVE_VS_HISTORY = "Above usual range", LOW_SUPPLY = "Low supply",
        NORMAL_SUPPLY = "Normal supply", HIGH_SUPPLY = "High supply" }
    local parts = {}
    for _, key in ipairs({ "trend", "price", "supply" }) do
        if labels[signal[key]] then parts[#parts + 1] = labels[signal[key]] end
    end
    return #parts > 0 and table.concat(parts, " / ") or "More scans needed to describe this market"
end

function View.Percent(value)
    return MP.HistoryMath.Finite(value) and string.format("%+.1f%%", value) or "Needs history"
end
function View.PValue(value)
    if not MP.HistoryMath.Finite(value) or value < 0 or value > 1 then return "Needs history" end
    return value < 0.0001 and "p<0.0001" or string.format("p=%.4f", value)
end
function View.ReferenceMoney(value)
    if not MP.HistoryMath.Finite(value) or value <= 0 then return "Needs history" end
    return value % 1 == 0 and View.Money(value) or string.format("%.1fc", value)
end
function View.Watch(data)
    local current, a, signal = data.current, data.analytics, data.signals
    local now = "No scan"
    if current then
        now = integer(current.cleanMedian, 1) and View.Money(current.cleanMedian):gsub("^0g ", ""):gsub("^0s ", ""):gsub(" ", "") or "No price"
    end
    local window = a.windows[7]
    local change = window and window.change
    local arrows = { RISING = "^", FALLING = "v", STABLE = "=" }
    local supplies = { LOW_SUPPLY = "Low", NORMAL_SUPPLY = "Normal", HIGH_SUPPLY = "High" }
    return { now = data.error and "Failed" or now, change = change and string.format("%+.0f%%", change) or "-",
        trend = arrows[signal.trend] or "-", percentile = a.percentile30d and string.format("%.0f", a.percentile30d) or "-",
        supply = supplies[signal.supply] or "-", maturity = View.Maturity(a.maturity) }
end
function View.History(data, now)
    local a, values = data.analytics, {}
    for _, days in ipairs({ 1, 7, 30 }) do
        local window = a.windows[days]
        values["median" .. days] = View.ReferenceMoney(window and window.median)
        values["change" .. days] = View.Percent(window and window.change)
    end
    local window, significance = a.windows[7], a.significance
    values.trend = a.trend7d.status == "OK" and View.Percent(a.trend7d.pctPerDay) .. "/day" or unavailable(a.trend7d.status)
    values.percentile = a.percentile30d and string.format("%.1f / 100", a.percentile30d) or "Needs history"
    local classes = { LOW = "Low", NORMAL = "Normal", HIGH = "High" }
    values.volatility = a.volatility.status == "OK" and string.format("%.1f%% / %s", a.volatility.pct, classes[a.volatility.class] or "Not available") or unavailable(a.volatility.status)
    local supplies = { LOW_SUPPLY = "Low", NORMAL_SUPPLY = "Normal", HIGH_SUPPLY = "High" }
    values.supply = window and window.supplyRatio and string.format("%.2fx / %s", window.supplyRatio, supplies[data.signals.supply] or "Not available") or "Needs history"
    values.significance = significance.status == "OK" and string.format("%s / shift %s", View.PValue(significance.p),
        significance.meaningfulMove and "Yes" or "No") or unavailable(significance.status)
    values.lastScan = data.lastScan and now >= data.lastScan and string.format("%.0fm ago", math.floor((now - data.lastScan) / 60))
        or (data.lastScan and "Check client clock" or "Not scanned")
    values.observations = count(a.count) .. " / " .. View.Maturity(a.maturity)
    values.signal = signalSummary(data.signals)
    return values
end
function View.Report(report, items)
    local lines = { "MARKET REPORT" }
    local sections = { { "Rising markets", "rising" }, { "Below historical range", "cheap" },
        { "Unusual return volatility", "volatile" }, { "Meaningful changes", "significant" } }
    for _, section in ipairs(sections) do
        lines[#lines + 1] = "\n" .. section[1]
        if #report[section[2]] == 0 then lines[#lines + 1] = "No supported observations" end
        for i, row in ipairs(report[section[2]]) do
            if i > 4 then break end
            local a, value = row.data.analytics, "HIGH"
            if section[2] == "rising" then value = View.Percent(a.trend7d.pctPerDay) .. "/day"
            elseif section[2] == "cheap" then value = string.format("30d percentile %.0f", a.percentile30d)
            elseif section[2] == "significant" then value = View.PValue(a.significance.p) .. ", " .. View.Percent(a.significance.change) end
            lines[#lines + 1] = items.Metadata(row.itemID).name .. ": " .. value
        end
        local remaining = #report[section[2]] - 4
        if remaining > 0 then lines[#lines + 1] = "+ " .. remaining .. " more; browse Market Watch" end
    end
    lines[#lines + 1] = "\nData maturity"
    for _, state in ipairs({ "NEW", "EARLY", "7D READY", "30D READY" }) do lines[#lines + 1] = View.Maturity(state) .. ": " .. report.maturity[state] end
    lines[#lines + 1] = "\nDescriptive observations; p-values are approximate."
    return table.concat(lines, "\n")
end

function View.Build(scanner, selectedItemID, metadata, readOnly)
    local busy = scanner:IsActive()
    local current = not readOnly and scanner.state == "DONE" and scanner.sample and scanner.sample.itemID == selectedItemID
    local analysis = current and scanner.analysis
    local raw, clean, anomaly = analysis and analysis.raw, analysis and analysis.clean, analysis and analysis.anomaly
    local state = readOnly and "READ ONLY" or (scanner.ahOpen and scanner.state or "AH CLOSED")
    local browsing = not readOnly and scanner.state == "DONE" and scanner.browse ~= nil
    if browsing then state = "BROWSING" end
    local messages = {
        IDLE = "Choose an item to scan.", WAITING = "Waiting for the Auction House to be ready...",
        QUERYING = "Waiting for commodity results...", COLLECTING = "Reading price levels...",
        DONE = "Current scan complete.", ERROR = "Scan failed. Try Refresh.",
        ["AH CLOSED"] = "Open the Auction House to browse.",
        ["READ ONLY"] = "No stored observation for this item; open AH to scan.",
    }
    local sufficient = View.Anomaly(nil)
    if anomaly then sufficient = View.Anomaly(anomaly.sufficient) end
    local range = "No price data"
    if clean and integer(clean.q1, 1) and integer(clean.q3, 1) then
        range = View.Money(clean.q1) .. " - " .. View.Money(clean.q3)
    end
    local message = (not readOnly and scanner.error and View.Error(scanner.error)) or messages[state] or "Scanner unavailable. See /mp status."
    if state == "DONE" and not analysis then message = "No completed scan for the selected item." end
    if analysis and not anomaly.sufficient then
        message = anomaly.reason == "TOO_FEW_PRICE_LEVELS" and "Outlier check needs more data: fewer than 5 distinct prices."
            or "Outlier check needs a wider spread of prices."
    end
    if raw and raw.levelCount == 0 then message = "No price levels returned. Prices unavailable for this scan." end
    if browsing then message = "Opening this item in Auction House search..."
    elseif not readOnly and scanner.state == "DONE" and scanner.browseError then
        message = message .. " AH search unavailable; use its Search box. See /mp status."
    end
    if not readOnly and scanner.uncertainQuery then
        message = scanner.browseError and "Scan data kept. Close and reopen the Auction House before scanning again."
            or "No reliable result. Close and reopen the Auction House before scanning again."
    end
    return {
        itemID = selectedItemID, name = metadata.name, icon = metadata.icon, state = state,
        message = message, scanEnabled = not readOnly and scanner.ahOpen and not busy and not scanner.blockedReason and not scanner.uncertainQuery,
        itemsEnabled = readOnly or (scanner.ahOpen and not busy and not scanner.blockedReason and not scanner.uncertainQuery),
        buttonText = readOnly and "Read only - open AH to scan" or (scanner.uncertainQuery and "Close and reopen AH"
            or (browsing and "Opening AH search..." or (busy and "Scanning..." or (current and "Refresh" or "Scan")))),
        lowest = View.Money(raw and raw.min), rawMedian = View.Money(raw and raw.weightedMedian),
        cleanMedian = View.Money(clean and clean.weightedMedian), range = range,
        quantity = count(raw and raw.totalQuantity), levels = count(raw and raw.levelCount),
        suspicious = count(anomaly and anomaly.suspiciousCount), extreme = count(anomaly and anomaly.extremeCount),
        sufficient = sufficient,
        exclusion = anomaly and ("Extreme outliers excluded: " .. count(anomaly.extremeCount) .. ". Suspicious retained.")
            or "Outlier check: scan this item first.",
    }
end
