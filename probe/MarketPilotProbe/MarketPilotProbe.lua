local ADDON_NAME = ...

local Probe = {}
_G.MarketPilotProbe = Probe

local frame = CreateFrame("Frame")
local db
local ahOpen = false
local lastItemID
local registeredEvents = {}

local CANDIDATE_EVENTS = {
    "PLAYER_LOGIN",
    "AUCTION_HOUSE_SHOW",
    "AUCTION_HOUSE_CLOSED",
    "COMMODITY_SEARCH_RESULTS_UPDATED",
    "ITEM_SEARCH_RESULTS_UPDATED",
    "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED",
}

local CANDIDATE_FUNCTIONS = {
    "MakeItemKey",
    "SendSearchQuery",
    "GetNumCommoditySearchResults",
    "GetCommoditySearchResultInfo",
    "GetNumItemSearchResults",
    "GetItemSearchResultInfo",
    "IsThrottledMessageSystemReady",
}

local function now()
    if type(time) == "function" then
        return time()
    end
    return 0
end

local function appendLog(message)
    local line = tostring(message)
    print("|cff66ccffMarketPilotProbe:|r " .. line)

    if not db then
        return
    end

    db.logs = db.logs or {}
    db.logs[#db.logs + 1] = {
        t = now(),
        message = line,
    }

    while #db.logs > 200 do
        table.remove(db.logs, 1)
    end
end

local function describeTable(value)
    if type(value) ~= "table" then
        return tostring(value)
    end

    local parts = {}
    local count = 0

    for key, fieldValue in pairs(value) do
        local fieldType = type(fieldValue)
        if fieldType == "string" or fieldType == "number" or fieldType == "boolean" or fieldValue == nil then
            count = count + 1
            parts[#parts + 1] = tostring(key) .. "=" .. tostring(fieldValue)
            if count >= 20 then
                parts[#parts + 1] = "..."
                break
            end
        end
    end

    return "{" .. table.concat(parts, ", ") .. "}"
end

local function getBuildSnapshot()
    local version, build, buildDate, interface = GetBuildInfo()
    return {
        version = version,
        build = build,
        buildDate = buildDate,
        interface = interface,
        capturedAt = now(),
    }
end

local function saveBuildSnapshot()
    if not db then
        return
    end
    db.build = getBuildSnapshot()
end

local function safeRegisterEvent(eventName)
    local ok, err = pcall(frame.RegisterEvent, frame, eventName)
    registeredEvents[eventName] = ok and true or false
    if not ok then
        appendLog("event unavailable: " .. eventName .. " -> " .. tostring(err))
    end
end

local function functionExists(name)
    return type(C_AuctionHouse) == "table" and type(C_AuctionHouse[name]) == "function"
end

local function printStatus()
    saveBuildSnapshot()
    local build = db and db.build or getBuildSnapshot()

    appendLog("client version=" .. tostring(build.version)
        .. " build=" .. tostring(build.build)
        .. " date=" .. tostring(build.buildDate)
        .. " interface=" .. tostring(build.interface))

    appendLog("C_AuctionHouse=" .. tostring(type(C_AuctionHouse) == "table") .. " AH-open=" .. tostring(ahOpen))

    for _, name in ipairs(CANDIDATE_FUNCTIONS) do
        appendLog("API " .. name .. "=" .. tostring(functionExists(name)))
    end

    for _, eventName in ipairs(CANDIDATE_EVENTS) do
        appendLog("event registered " .. eventName .. "=" .. tostring(registeredEvents[eventName] == true))
    end

    if functionExists("IsThrottledMessageSystemReady") then
        local ok, ready = pcall(C_AuctionHouse.IsThrottledMessageSystemReady)
        appendLog("throttle ready call ok=" .. tostring(ok) .. " value=" .. tostring(ready))
    end
end

local function readCommodityResults(itemID)
    if not functionExists("GetNumCommoditySearchResults") or not functionExists("GetCommoditySearchResultInfo") then
        appendLog("commodity result API incomplete")
        return
    end

    local okCount, count = pcall(C_AuctionHouse.GetNumCommoditySearchResults, itemID)
    if not okCount then
        appendLog("GetNumCommoditySearchResults failed: " .. tostring(count))
        return
    end

    count = tonumber(count) or 0
    appendLog("commodity results itemID=" .. tostring(itemID) .. " rows=" .. tostring(count))

    local samples = {}
    local maxRows = math.min(count, 5)
    for index = 1, maxRows do
        local okInfo, info = pcall(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, index)
        if okInfo then
            local description = describeTable(info)
            samples[#samples + 1] = description
            appendLog("commodity[" .. index .. "] " .. description)
        else
            appendLog("commodity[" .. index .. "] failed: " .. tostring(info))
        end
    end

    if db then
        db.lastResult = {
            kind = "commodity",
            itemID = itemID,
            rowCount = count,
            samples = samples,
            capturedAt = now(),
        }
    end
end

local function makeItemKey(itemID)
    if not functionExists("MakeItemKey") then
        return false, "MakeItemKey unavailable"
    end

    local ok, itemKey = pcall(C_AuctionHouse.MakeItemKey, itemID)
    if not ok then
        return false, itemKey
    end

    return true, itemKey
end

local function readItemResults(itemID, eventItemKey)
    if not functionExists("GetNumItemSearchResults") or not functionExists("GetItemSearchResultInfo") then
        appendLog("item result API incomplete")
        return
    end

    local itemKey = eventItemKey
    if type(itemKey) ~= "table" then
        local okKey, keyOrError = makeItemKey(itemID)
        if not okKey then
            appendLog("cannot build item key for item result: " .. tostring(keyOrError))
            return
        end
        itemKey = keyOrError
    end

    local okCount, count = pcall(C_AuctionHouse.GetNumItemSearchResults, itemKey)
    if not okCount then
        appendLog("GetNumItemSearchResults failed: " .. tostring(count))
        return
    end

    count = tonumber(count) or 0
    appendLog("item results itemID=" .. tostring(itemID) .. " rows=" .. tostring(count))

    local samples = {}
    local maxRows = math.min(count, 5)
    for index = 1, maxRows do
        local okInfo, info = pcall(C_AuctionHouse.GetItemSearchResultInfo, itemKey, index)
        if okInfo then
            local description = describeTable(info)
            samples[#samples + 1] = description
            appendLog("item[" .. index .. "] " .. description)
        else
            appendLog("item[" .. index .. "] failed: " .. tostring(info))
        end
    end

    if db then
        db.lastResult = {
            kind = "item",
            itemID = itemID,
            rowCount = count,
            samples = samples,
            capturedAt = now(),
        }
    end
end

local function queryItem(itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then
        appendLog("usage: /mpprobe scan <itemID>")
        return
    end

    if not ahOpen then
        appendLog("open the Auction House before scanning")
        return
    end

    if not functionExists("SendSearchQuery") then
        appendLog("SendSearchQuery unavailable")
        return
    end

    local okKey, itemKey = makeItemKey(itemID)
    if not okKey then
        appendLog("MakeItemKey failed: " .. tostring(itemKey))
        return
    end

    lastItemID = itemID
    if db then
        db.lastQuery = {
            itemID = itemID,
            attemptedAt = now(),
        }
    end

    local ok, err = pcall(C_AuctionHouse.SendSearchQuery, itemKey, {}, true)
    if ok then
        appendLog("query sent for itemID=" .. tostring(itemID))
    else
        appendLog("SendSearchQuery failed: " .. tostring(err))
    end
end

local function dumpSaved()
    if not db then
        appendLog("database not initialized")
        return
    end

    local build = db.build
    if build then
        appendLog("saved build version=" .. tostring(build.version)
            .. " build=" .. tostring(build.build)
            .. " interface=" .. tostring(build.interface))
    else
        appendLog("no saved build snapshot")
    end

    if db.lastQuery then
        appendLog("saved lastQuery itemID=" .. tostring(db.lastQuery.itemID)
            .. " attemptedAt=" .. tostring(db.lastQuery.attemptedAt))
    else
        appendLog("no saved query")
    end

    if db.lastResult then
        appendLog("saved lastResult kind=" .. tostring(db.lastResult.kind)
            .. " itemID=" .. tostring(db.lastResult.itemID)
            .. " rows=" .. tostring(db.lastResult.rowCount)
            .. " capturedAt=" .. tostring(db.lastResult.capturedAt))
        for index, description in ipairs(db.lastResult.samples or {}) do
            appendLog("saved sample[" .. index .. "] " .. tostring(description))
        end
    else
        appendLog("no saved result")
    end
end

local function clearSaved()
    MarketPilotProbeDB = {
        schema = 1,
        logs = {},
    }
    db = MarketPilotProbeDB
    saveBuildSnapshot()
    appendLog("saved probe data cleared")
end

SLASH_MARKETPILOTPROBE1 = "/mpprobe"
SlashCmdList.MARKETPILOTPROBE = function(input)
    input = input or ""
    local command, argument = input:match("^(%S*)%s*(.-)$")
    command = string.lower(command or "")

    if command == "scan" then
        queryItem(argument)
    elseif command == "dump" then
        dumpSaved()
    elseif command == "clear" then
        clearSaved()
    elseif command == "status" or command == "" then
        printStatus()
    else
        appendLog("commands: status | scan <itemID> | dump | clear")
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedName = ...
        if loadedName ~= ADDON_NAME then
            return
        end

        MarketPilotProbeDB = MarketPilotProbeDB or {
            schema = 1,
            logs = {},
        }
        db = MarketPilotProbeDB
        saveBuildSnapshot()

        for _, eventName in ipairs(CANDIDATE_EVENTS) do
            safeRegisterEvent(eventName)
        end

        appendLog("loaded; run /mpprobe status")
        return
    end

    if event == "PLAYER_LOGIN" then
        saveBuildSnapshot()
        appendLog("PLAYER_LOGIN")
    elseif event == "AUCTION_HOUSE_SHOW" then
        ahOpen = true
        appendLog("AUCTION_HOUSE_SHOW")
    elseif event == "AUCTION_HOUSE_CLOSED" then
        ahOpen = false
        appendLog("AUCTION_HOUSE_CLOSED")
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        local eventItemID = ...
        local itemID = tonumber(eventItemID) or lastItemID
        appendLog("COMMODITY_SEARCH_RESULTS_UPDATED arg1=" .. tostring(eventItemID))
        if itemID then
            readCommodityResults(itemID)
        end
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        local eventItemKey = ...
        appendLog("ITEM_SEARCH_RESULTS_UPDATED arg1=" .. describeTable(eventItemKey))
        if lastItemID then
            readItemResults(lastItemID, eventItemKey)
        end
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        appendLog("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED" then
        appendLog("AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED " .. describeTable({...}))
    else
        appendLog("event=" .. tostring(event))
    end
end)

frame:RegisterEvent("ADDON_LOADED")
