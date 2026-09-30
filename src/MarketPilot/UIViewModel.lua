local _, MP = ...
local View = {}
MP.UIViewModel = View

local function integer(value, minimum)
    return type(value) == "number" and value >= minimum
        and value <= 9007199254740991 and value % 1 == 0
end

local COINS = {
    gold = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:0:0|t",
    silver = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:0:0|t",
    copper = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:0:0|t",
}

-- Native inline textures keep this a pure presentation function. Omit only
-- leading zero denominations; lower zeros and every copper remain visible.
local function coinMoney(value)
    local remainder = value % 10000
    local copper = remainder % 100
    local gold, silver = (value - remainder) / 10000, (remainder - copper) / 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = string.format("%.0f", gold) .. COINS.gold end
    if gold > 0 or silver > 0 then parts[#parts + 1] = string.format("%.0f", silver) .. COINS.silver end
    -- Historical medians can contain half a copper. Do not turn them into an
    -- integer price or round to silver for display.
    parts[#parts + 1] = (copper % 1 == 0 and string.format("%.0f", copper) or tostring(copper)) .. COINS.copper
    return table.concat(parts, " ")
end

function View.Money(value)
    if not integer(value, 1) then return "No price data" end
    return coinMoney(value)
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
    if not MP.HistoryMath.Finite(value) or value <= 0 or value > 9007199254740991 then return "Needs history" end
    return coinMoney(value)
end
local function groupedCount(value)
    local text = string.format("%.0f", value)
    return text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end
local function magnitude(value)
    if value ~= 0 and math.abs(value) < 0.1 then return "less than 0.1%" end
    return string.format("%.1f%%", math.abs(value))
end
local function insightSentence(message)
    local c = message.code
    local fixed = {
        NO_SCAN = "No scan recorded for this item.",
        INVALID_RECORD = "The recorded scan cannot be read.",
        EMPTY_SCAN = "No price levels returned in the latest scan.",
        INCONSISTENT_RECORD = "Some recorded fields are inconsistent; their relationship cannot be assessed.",
        ANOMALY_UNAVAILABLE = "Retained and excluded price-level counts cannot be assessed from this record.",
        FILTER_INSUFFICIENT = "Not enough price variation/data for reliable outlier filtering.",
        FILTER_UNAVAILABLE = "Outlier-filtering sufficiency was not recorded.",
        MORE_HISTORY = "More history is needed to judge whether this price and listed quantity are high or low for this market.",
        HISTORY_AVAILABLE = "Supported historical comparisons are shown in History.",
        SCAN_FAILED_STORED = "The new scan failed; showing the previous recorded scan.",
        SCAN_FAILED = "The new scan failed.",
        UPDATE_FAILED_STORED = "The latest update reported an error; the available scan observation is shown below.",
        UPDATE_FAILED = "The latest update reported an error.",
        UPDATE_STATUS_UNAVAILABLE = "The latest update status cannot be assessed.",
        SCAN_TIME_UNAVAILABLE = "Recorded scan age is unavailable.",
    }
    if fixed[c] then return fixed[c] end
    if c == "REFERENCE_BAND" then return "The latest recorded scan's reference price is " .. View.Money(message.price)
        .. ", with a central price band of " .. View.Money(message.q1) .. " - " .. View.Money(message.q3) .. "." end
    if c == "REFERENCE" then return "The latest recorded scan's reference price is " .. View.Money(message.price) .. "." end
    if c == "BAND" then return "The latest recorded scan's central price band is " .. View.Money(message.q1) .. " - " .. View.Money(message.q3) .. "." end
    if c == "LOWEST_BELOW" then return "The lowest listed price is " .. View.Money(message.price)
        .. (math.abs(message.change) < 0.1 and ", " or ", about ") .. magnitude(message.change) .. " below that reference." end
    if c == "LOWEST_EQUAL" then return "The lowest listed price is " .. View.Money(message.price) .. ", equal to that reference." end
    if c == "LOWEST" then return "The lowest recorded listed price is " .. View.Money(message.price) .. "." end
    if c == "QUANTITY" then return "This scan covers " .. groupedCount(message.count) .. (message.count == 1 and " listed unit." or " listed units.") end
    if c == "ANOMALY_COUNTS" then
        local retained = message.suspicious == 0 and "No unusual price levels were retained" or (groupedCount(message.suspicious)
            .. (message.suspicious == 1 and " unusual price level was retained" or " unusual price levels were retained"))
        local excluded = message.extreme == 0 and "no price levels were excluded" or (groupedCount(message.extreme)
            .. (message.extreme == 1 and " extreme price level was excluded" or " extreme price levels were excluded"))
        return retained .. "; " .. excluded .. "."
    end
    if c == "HISTORY_CHANGE" then
        if message.change == 0 then return "The recorded reference price equals its 7-day median." end
        return "The recorded reference price is " .. magnitude(message.change) .. (message.change < 0 and " below" or " above") .. " its 7-day median."
    end
    if c == "HISTORY_TREND" then
        local directions = { RISING = "rising", STABLE = "stable", FALLING = "falling" }
        return "The available observations show a " .. directions[message.label] .. " price trend."
    end
    if c == "HISTORY_TREND_VALUE" then return "The recorded trend estimate is " .. View.Percent(message.change) .. "/day; its direction label is unavailable." end
    if c == "HISTORY_SUPPLY" then
        local positions = { LOW_SUPPLY = "below", NORMAL_SUPPLY = "near", HIGH_SUPPLY = "above" }
        return "Listed supply in this scan is " .. positions[message.label] .. " its recent usual level ("
            .. string.format("%.2fx", message.ratio) .. " its 7-day median)."
    end
    if c == "HISTORY_SUPPLY_VALUE" then return "The recorded listed-supply ratio is " .. string.format("%.2fx", message.ratio)
        .. " its 7-day median; its supply label is unavailable." end
    if c == "HISTORY_POSITION" then
        local positions = { CHEAP_VS_HISTORY = "low", NORMAL_RANGE = "in the middle range", EXPENSIVE_VS_HISTORY = "high" }
        return "The recorded reference is " .. positions[message.label] .. " among 30-day price observations (percentile "
            .. string.format("%.1f", message.percentile) .. ")."
    end
    if c == "HISTORY_POSITION_VALUE" then return "The recorded 30-day price percentile is " .. string.format("%.1f", message.percentile)
        .. "; its price-position label is unavailable." end
    if c == "CURRENT_UNAVAILABLE" or c == "HISTORY_MISSING" or c == "HISTORY_UNAVAILABLE" then
        local names = { REFERENCE = "reference price", BAND = "central price band", LOWEST = "lowest listed price", QUANTITY = "listed quantity",
            CHANGE = "7-day price comparison", TREND = "trend direction", SUPPLY = "historical supply comparison", POSITION = "30-day price position" }
        local parts = {}; for _, key in ipairs(message.metrics) do parts[#parts + 1] = names[key] end
        local prefix = c == "HISTORY_MISSING" and "More history is needed for: " or "Not assessable from this record: "
        return prefix .. table.concat(parts, ", ") .. "."
    end
    if c == "SCAN_AGE" then
        local seconds = message.seconds
        if seconds < 60 then return "Latest recorded scan: less than a minute ago." end
        local value, unit = math.floor(seconds / 60), "minute"
        if seconds >= 86400 then value, unit = math.floor(seconds / 86400), "day"
        elseif seconds >= 3600 then value, unit = math.floor(seconds / 3600), "hour" end
        return "Latest recorded scan: " .. groupedCount(value) .. " " .. unit .. (value == 1 and "" or "s") .. " ago."
    end
    if c == "SCAN_CLOCK" then return "Recorded timestamp: " .. string.format("%.0f", message.timestamp) .. "; age unavailable, check the client clock." end
    return "This part of the observation cannot be assessed."
end

function View.Insight(insight)
    local result = {}
    for _, section in ipairs({ "current", "history" }) do
        local lines = {}
        for _, message in ipairs(insight[section]) do lines[#lines + 1] = insightSentence(message) end
        result[section] = table.concat(lines, "\n")
    end
    return result
end
function View.Watch(data)
    local current, a, signal = data.current, data.analytics, data.signals
    local now = "No scan"
    if current then
        now = integer(current.cleanMedian, 1) and View.Money(current.cleanMedian) or "No price"
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
function View.ReportCards(report, items)
    local cards = {}
    local sections = { { "Rising markets", "rising" }, { "Below historical range", "cheap" },
        { "Unusual return volatility", "volatile" }, { "Meaningful changes", "significant" } }
    for _, section in ipairs(sections) do
        local lines = {}
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
        cards[#cards + 1] = { title = section[1], text = table.concat(lines, "\n") }
    end
    return cards
end
function View.Report(report, items)
    local lines = { "MARKET REPORT" }
    for _, card in ipairs(View.ReportCards(report, items)) do
        lines[#lines + 1] = "\n" .. card.title .. "\n" .. card.text
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
