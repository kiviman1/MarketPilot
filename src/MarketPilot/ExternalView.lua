local _, MP = ...
local View = {}
MP.ExternalView = View

local function money(value)
    return MP.HistoryMath.Finite(value) and value > 0 and value <= 9007199254740991
        and MP.UIViewModel.ReferenceMoney(value) or "Not available"
end
local function count(value)
    return MP.HistoryMath.Integer(value, 0) and string.format("%.0f", value) or "Not available"
end
local function percent(value)
    return MP.HistoryMath.Finite(value) and MP.UIViewModel.Percent(value) or "Not available"
end
local function text(value)
    return type(value) == "string" and value ~= "" and value or "Not available"
end
local function timestamp(value)
    if not MP.HistoryMath.Integer(value, 0) then return "Not available" end
    if type(date) == "function" then
        local ok, formatted = pcall(date, "%Y-%m-%d %H:%M", value)
        if ok and type(formatted) == "string" then return formatted end
    end
    return string.format("%.0f", value)
end
local function age(value, now)
    if not MP.HistoryMath.Integer(value, 0) or not MP.HistoryMath.Finite(now) then return "Age unavailable" end
    if now < value then return "Age unavailable; check client clock" end
    local seconds = now - value
    if seconds < 60 then return "less than a minute ago" end
    local amount, unit = math.floor(seconds / 60), "minute"
    if seconds >= 86400 then amount, unit = math.floor(seconds / 86400), "day"
    elseif seconds >= 3600 then amount, unit = math.floor(seconds / 3600), "hour" end
    return string.format("%.0f", amount) .. " " .. unit .. (amount == 1 and "" or "s") .. " ago"
end
local function span(seconds)
    if not MP.HistoryMath.Integer(seconds, 0) then return "Not available" end
    return string.format("%.1f days", seconds / 86400)
end

function View.Watch(data)
    local latest = data.status == "OK" and data.latest or nil
    return { now = latest and money(latest.median) or "No data",
        change = data.status == "OK" and MP.HistoryMath.Finite(data.change7d) and percent(data.change7d) or "-",
        trend = "-", percentile = "-", supply = "-", maturity = data.status == "OK" and "External" or "No data" }
end

function View.Build(data, metadata, now)
    local latest = data.status == "OK" and data.latest or nil
    latest = latest or {}
    local result = { name = metadata.name, icon = metadata.icon, maturity = data.status == "OK" and "External" or "No data",
        median = money(latest.median), lowest = money(latest.lowest), quantity = count(latest.quantity),
        auctions = count(latest.auctions), median7d = money(latest.median7d), median30d = money(latest.median30d),
        change7d = percent(data.status == "OK" and data.change7d or nil),
        change30d = percent(data.status == "OK" and data.change30d or nil),
        hourlyCount = count(data.status == "OK" and data.hourlyCount or nil),
        dailyCount = count(data.status == "OK" and data.dailyCount or nil),
        latestAt = timestamp(latest.t) .. " | " .. age(latest.t, now),
        fetchedAt = timestamp(data.fetchedAt) .. " | " .. age(data.fetchedAt, now),
        span30d = span(data.dailySpanSeconds) }
    local identity = "Selected market: " .. text(data.marketLabel) .. " | Region: " .. text(data.region)
        .. " | Market ID: " .. text(data.market)
    local source = "Source: " .. text(data.source) .. " | https://ahledger.com"
    local status = data.status == "OK" and "Read only. Provider medians and auction counts; prices are per unit."
        or "AHledger data unavailable: " .. text(data.reason)
    result.description = identity .. "\n" .. source .. "\n" .. status
        .. "\nLatest observation: " .. result.latestAt .. "\nFetched: " .. result.fetchedAt
        .. "\nDaily series actual span: " .. result.span30d
    local daily = data.status == "OK" and data.daily or {}
    local bucket = daily and daily[#daily]
    if bucket and money(bucket.p25) ~= "Not available" and money(bucket.p75) ~= "Not available" then
        result.band = "Latest daily bucket P25-P75: " .. money(bucket.p25) .. " - " .. money(bucket.p75)
            .. " | " .. timestamp(bucket.t)
    end
    return result
end

function View.History(data, mode)
    local hourly = mode == "HOURLY"
    local series = data.status == "OK" and (hourly and data.hourly or data.daily) or {}
    series = series or {}
    local lines = { (hourly and "Hourly" or "Daily") .. " provider buckets (latest 12 available):" }
    if #series == 0 then lines[#lines + 1] = "No bucket data available." end
    for i = math.max(1, #series - 11), #series do
        local bucket = series[i]
        lines[#lines + 1] = timestamp(bucket.t) .. " | median " .. money(bucket.median)
            .. " | min " .. money(bucket.min) .. " | quantity " .. count(bucket.quantity)
            .. " | auctions " .. count(bucket.auctions)
    end
    return table.concat(lines, "\n")
end
