local _, MP = ...
local External = {}
MP.ExternalMarket = External

local MAX_INTEGER = 9007199254740991
local METADATA = { "source", "url", "market", "marketLabel", "region", "fetchedAt" }
local ROOT_FIELDS = { schema = true, source = true, url = true, market = true,
    marketLabel = true, region = true, fetchedAt = true, itemIDs = true, items = true }
local ITEM_FIELDS = { latest = true, hourly = true, daily = true }
local LATEST_FIELDS = { t = "time", median = "price", lowest = "price", quantity = "count",
    auctions = "count", median7d = "price", median30d = "price" }
local HISTORY_FIELDS = { t = "time", min = "price", median = "price", p25 = "price",
    p75 = "price", quantity = "count", auctions = "count" }

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function integer(value, minimum)
    return finite(value) and value >= minimum and value <= MAX_INTEGER and value % 1 == 0
end
local function price(value)
    -- Provider medians may include fractions of one copper; preserve them.
    return finite(value) and value > 0 and value <= MAX_INTEGER
end
local function marketRegion(value)
    if type(value) ~= "string" or #value > 128 then return nil end
    return value:match("^forever%.[a-z0-9][a-z0-9_-]*%.[a-z0-9][a-z0-9_-]*%.([a-z0-9][a-z0-9_-]*)$")
end
local function label(value)
    -- Provider text is rendered in WoW font strings. Reject control bytes and
    -- the pipe introducer used by color, link and texture markup.
    return type(value) == "string" and #value > 0 and #value <= 128
        and not value:find("[%z\1-\31\127]") and not value:find("|", 1, true)
        and value:find("[^ ]") ~= nil
end
local function plain(value)
    return type(value) == "table" and getmetatable(value) == nil
end
local function fields(value, allowed, path)
    if not plain(value) then return nil, path .. " must be a plain table" end
    for key in pairs(value) do
        if not allowed[key] then return nil, path .. " contains an unsupported field" end
    end
    return true
end
local function arrayCount(value, path)
    if not plain(value) then return nil, path .. " must be a dense array" end
    local count, maximum = 0, 0
    for key in pairs(value) do
        if not integer(key, 1) then return nil, path .. " must be a dense array" end
        count = count + 1
        if key > maximum then maximum = key end
    end
    if maximum ~= count then return nil, path .. " must be a dense array" end
    return count
end
local function ids(value, path, allowed)
    local count, reason = arrayCount(value, path)
    if not count then return nil, reason end
    local result = {}
    for index = 1, count do
        local id = value[index]
        if not integer(id, 1) or result[id] or (allowed and not allowed[id]) then
            return nil, path .. " contains an invalid, duplicate or unconfigured item ID"
        end
        result[id] = true
    end
    return result
end
local function observation(value, allowed, path)
    local valid, reason = fields(value, allowed, path)
    if not valid then return nil, reason end
    if not integer(value.t, 0) then return nil, path .. ".t must be an epoch integer" end
    local result = {}
    for key, kind in pairs(allowed) do
        local datum = value[key]
        if datum ~= nil then
            if (kind == "price" and not price(datum))
                or (kind ~= "price" and not integer(datum, 0)) then
                return nil, path .. "." .. key .. " is invalid"
            end
            result[key] = datum
        end
    end
    if allowed == LATEST_FIELDS then
        if result.lowest and result.median and result.lowest > result.median then
            return nil, path .. ": lowest exceeds median"
        end
    else
        local previous
        for _, key in ipairs({ "min", "p25", "median", "p75" }) do
            local datum = result[key]
            if datum then
                if previous and datum < previous then return nil, path .. ": price descriptors are inconsistent" end
                previous = datum
            end
        end
    end
    return result
end
local function series(value, path, maximum)
    if value == nil then return {} end
    local count, reason = arrayCount(value, path)
    if not count then return nil, reason end
    if count > maximum then return nil, path .. " exceeds the observation limit" end
    local result = {}
    for index = 1, count do
        local row, errorText = observation(value[index], HISTORY_FIELDS, path .. "[" .. index .. "]")
        if not row then return nil, errorText end
        result[index] = row
    end
    table.sort(result, function(a, b) return a.t < b.t end)
    for index = 2, count do
        if result[index - 1].t == result[index].t then return nil, path .. " contains duplicate timestamps" end
    end
    return result
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, datum in pairs(value) do result[key] = copy(datum) end
    return result
end
local function metadata(target, source)
    for _, key in ipairs(METADATA) do target[key] = source and source[key] or nil end
end
local function coverage(target, rows, prefix)
    target[prefix .. "Count"] = #rows
    if #rows > 0 then
        target[prefix .. "FirstAt"] = rows[1].t
        target[prefix .. "LastAt"] = rows[#rows].t
        target[prefix .. "SpanSeconds"] = rows[#rows].t - rows[1].t
    end
end
local function change(current, baseline)
    if not current or not baseline then return nil end
    local result = (current / baseline - 1) * 100
    return finite(result) and result or nil
end
local function instance(status, reason, source, records, configured)
    local result = { status = status, reason = reason }
    metadata(result, source)
    -- Private validated snapshots and detached results prevent callers from
    -- changing the payload or the next read. There is no database reference.
    function result:Get(itemID)
        local row = records and configured[itemID] and records[itemID]
        local output = row and copy(row) or { hourly = {}, daily = {} }
        output.itemID = itemID
        output.status = status == "INVALID" and "INVALID" or (row and "OK" or "NO_DATA")
        output.reason = output.status == "INVALID" and reason
            or (output.status == "NO_DATA" and "No exported data for this item" or nil)
        metadata(output, source)
        coverage(output, output.hourly, "hourly")
        coverage(output, output.daily, "daily")
        if output.latest then
            output.change7d = change(output.latest.median, output.latest.median7d)
            output.change30d = change(output.latest.median, output.latest.median30d)
        end
        return output
    end
    return result
end

function External.New(payload, configuredIDs)
    if payload == nil then return instance("NO_DATA", "No AHledger export loaded") end
    local configured, reason = ids(configuredIDs, "configuredIDs")
    if not configured then return instance("INVALID", reason) end
    local valid
    valid, reason = fields(payload, ROOT_FIELDS, "payload")
    if not valid then return instance("INVALID", reason) end
    if payload.schema ~= 1 then return instance("INVALID", "Unsupported AHledger payload schema") end
    local region = marketRegion(payload.market)
    if payload.source ~= "AHledger" or payload.url ~= "https://ahledger.com"
        or not region or payload.region ~= region or not label(payload.marketLabel) then
        return instance("INVALID", "AHledger export market/source identity is invalid")
    end
    if not integer(payload.fetchedAt, 0) then return instance("INVALID", "fetchedAt must be an epoch integer") end
    local declared
    declared, reason = ids(payload.itemIDs, "itemIDs", configured)
    if not declared then return instance("INVALID", reason) end
    if not plain(payload.items) then return instance("INVALID", "items must be a plain table") end
    local records, hasData = {}, false
    for id, value in pairs(payload.items) do
        if not integer(id, 1) or not declared[id] then return instance("INVALID", "items contains an undeclared item ID") end
        valid, reason = fields(value, ITEM_FIELDS, "item " .. id)
        if not valid then return instance("INVALID", reason) end
        local row = {}
        if value.latest ~= nil then
            row.latest, reason = observation(value.latest, LATEST_FIELDS, "item " .. id .. ".latest")
            if not row.latest then return instance("INVALID", reason) end
        end
        row.hourly, reason = series(value.hourly, "item " .. id .. ".hourly", 200)
        if not row.hourly then return instance("INVALID", reason) end
        row.daily, reason = series(value.daily, "item " .. id .. ".daily", 40)
        if not row.daily then return instance("INVALID", reason) end
        if row.latest or #row.hourly > 0 or #row.daily > 0 then
            records[id], hasData = row, true
        end
    end
    -- Copy metadata only after the complete payload has passed validation.
    local source = {}
    metadata(source, payload)
    local emptyReason
    if not hasData then emptyReason = "Export contains no item observations" end
    return instance(hasData and "OK" or "NO_DATA", emptyReason, source, records, configured)
end
