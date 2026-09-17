local ADDON_NAME, Probe = ...
_G.MarketPilotProbe = Probe

local frame = CreateFrame("Frame")
local ahOpen = false
local pending
local log, text, describe = Probe.Log, Probe.Text, Probe.Describe

local CANDIDATE_EVENTS = {
    "PLAYER_LOGIN",
    "AUCTION_HOUSE_SHOW",
    "AUCTION_HOUSE_CLOSED",
    "COMMODITY_SEARCH_RESULTS_UPDATED",
    "ITEM_SEARCH_RESULTS_UPDATED",
    "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
    "AUCTION_HOUSE_THROTTLED_SPECIFIC_SEARCH_READY",
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

local function recordSurface()
    for _, name in ipairs(CANDIDATE_FUNCTIONS) do
        Probe.session.functions[name] = Probe.Exists(name)
    end
end

local function registerEvents()
    for _, event in ipairs(CANDIDATE_EVENTS) do
        local ok, result = pcall(frame.RegisterEvent, frame, event)
        local registered = "UNKNOWN"
        if not ok or result == false then
            registered = false
        elseif type(frame.IsEventRegistered) == "function" then
            local checked, value = pcall(frame.IsEventRegistered, frame, event)
            if checked and type(value) == "boolean" then registered = value end
        end
        Probe.session.events[event] = { registered = registered, fired = 0 }
        log("event " .. event .. " registerCallOK=" .. text(ok)
            .. " registered=" .. text(registered) .. " return=" .. text(result))
    end
end

local function printSession(session, label)
    log(label .. " build " .. describe(session.build))
    for _, name in ipairs(CANDIDATE_FUNCTIONS) do
        log(label .. " API " .. name .. "=" .. text(session.functions[name]))
    end
    for _, event in ipairs(CANDIDATE_EVENTS) do
        log(label .. " event " .. event .. " " .. describe(session.events[event]))
    end
    log(label .. " throttle " .. describe(session.throttle))
end

local function status()
    recordSurface()
    Probe.Ready("status")
    log("AH-open=" .. text(ahOpen) .. " pendingItemID=" .. text(pending and pending.itemID))
    printSession(Probe.session, "current")
    log("API signatures/price/quantity semantics=UNKNOWN until beta client evidence is reviewed")
end

local function finishFailure(reason)
    log(reason .. "; last successful observation preserved")
    if pending then pending.status = "FAILED" end
    pending = nil
end

-- Existing probe signatures are explicit candidates, not confirmed Forever APIs.
-- Never retry a failure with a different signature or synthesize an item key.
local function readResults(kind, key, event)
    local query = pending
    local countName = kind == "commodity" and "GetNumCommoditySearchResults" or "GetNumItemSearchResults"
    local rowName = kind == "commodity" and "GetCommoditySearchResultInfo" or "GetItemSearchResultInfo"
    log("candidate " .. countName .. "(" .. describe(key) .. ")")
    local ok, count = Probe.Call(countName, key)
    if not ok or not Probe.IsCount(count) then
        finishFailure("result count=UNKNOWN; raw=" .. text(count))
        return
    end
    log("result path=" .. kind .. " itemID=" .. query.itemID .. " rows=" .. count)
    local samples = {}
    for index = 1, math.min(count, 5) do
        log("candidate " .. rowName .. "(key, " .. index .. ")")
        local rowOK, row = Probe.Call(rowName, key, index)
        if not rowOK or type(row) ~= "table" then
            finishFailure("row[" .. index .. "]=UNKNOWN; raw=" .. text(row))
            return
        end
        local description = describe(row)
        samples[#samples + 1] = description
        log(kind .. "[" .. index .. "] " .. description)
        log("fields quantity=" .. text(rawget(row, "quantity"))
            .. " unitPrice=" .. text(rawget(row, "unitPrice"))
            .. " auctionID=" .. text(rawget(row, "auctionID")) .. "; semantics=UNKNOWN")
    end
    Probe.Ready("result")
    query.status = "OBSERVED"
    Probe.db.lastSuccess = {
        kind = kind, itemID = query.itemID, rowCount = count,
        samples = samples, capturedAt = Probe.Now(), event = event,
        query = Probe.Copy(query), evidence = Probe.Copy(Probe.session),
    }
    pending = nil
    log("saved successful result observation (up to 5 rows); completeness/semantics=UNKNOWN")
end

local function matchingResult(event, value)
    if not pending then
        log("result ignored: no pending probe query")
        return
    end
    if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        if type(value) ~= "number" or value ~= pending.itemID then
            log("result ignored: itemID missing/mismatched; correlation=UNKNOWN")
            return
        end
        readResults("commodity", value, event)
    else
        if type(value) ~= "table" or rawget(value, "itemID") ~= pending.itemID then
            log("result ignored: item key missing/mismatched; correlation=UNKNOWN")
            return
        end
        -- Check every field supplied by MakeItemKey, including variant fields.
        for key, field in next, pending.itemKey do
            if rawget(value, key) ~= field then
                log("result ignored: item key differs; correlation=UNKNOWN")
                return
            end
        end
        readResults("item", value, event)
    end
end

local function queryItem(argument)
    local itemID = tonumber(argument)
    if not argument:match("^%d+$") or not Probe.IsCount(itemID) or itemID == 0 then
        log("usage: /mpprobe scan <positive integer itemID>")
        return
    end
    if not ahOpen then log("open the Auction House before scanning"); return end
    if pending then log("query still pending; wait or close/reopen AH to cancel"); return end
    if not Probe.Exists("SendSearchQuery") then log("SendSearchQuery unavailable; signature=UNKNOWN"); return end
    local ready = Probe.Ready("before query")
    if ready == false then log("not ready; no query sent. Retry manually after a ready event"); return end
    log("candidate MakeItemKey(itemID); Forever signature=UNKNOWN")
    local okKey, itemKey = Probe.Call("MakeItemKey", itemID)
    if not okKey or type(itemKey) ~= "table" or rawget(itemKey, "itemID") ~= itemID then
        log("MakeItemKey returned unusable key: " .. describe(itemKey) .. "; query not sent")
        return
    end
    -- Keep correlation keys primitive and detached from mutable API-owned data.
    local savedKey = {}
    for key, value in next, itemKey do
        local kind = type(value)
        if (type(key) ~= "string" and type(key) ~= "number")
            or (kind ~= "string" and kind ~= "number" and kind ~= "boolean") then
            log("item key contains non-primitive fields; signature=UNKNOWN; query not sent")
            return
        end
        savedKey[key] = value
    end
    recordSurface()
    local query = { itemID = itemID, itemKey = savedKey, attemptedAt = Probe.Now(), status = "PENDING" }
    pending = query
    Probe.db.lastQuery = query
    log("candidate SendSearchQuery(itemKey, {}, true) key=" .. describe(itemKey) .. "; Forever signature=UNKNOWN")
    local ok, result = Probe.Call("SendSearchQuery", itemKey, {}, true)
    log("SendSearchQuery callOK=" .. text(ok) .. " return=" .. describe(result) .. "; server acceptance=UNKNOWN until result event")
    if not ok or result == false then
        finishFailure("query failed/rejected")
        return
    end
    Probe.Ready("after query")
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(15, function()
            if pending == query then finishFailure("no matching result within 15s; outcome=UNKNOWN") end
        end)
    else
        log("timeout timer unavailable; close/reopen AH if query remains pending")
    end
end

local function dumpSaved()
    local db = Probe.db
    -- Snapshot before printing: dump output must not evict original evidence.
    local logs = Probe.Copy(db.logs)
    log("saved schema=" .. text(db.schema) .. " lastQuery=" .. describe(db.lastQuery))
    if db.lastSuccess then
        local saved = db.lastSuccess
        log("saved lastSuccess " .. describe(saved))
        log("saved query " .. describe(saved.query))
        for index, sample in ipairs(saved.samples) do log("saved sample[" .. index .. "] " .. sample) end
        printSession(saved.evidence, "saved success")
    else
        log("no saved successful observation")
    end
    if db.lastResult then log("legacy schema-1 lastResult (UNVERIFIED) " .. describe(db.lastResult)) end
    print("|cff66ccffMarketPilotProbe:|r recent evidence (max 200 entries):")
    for _, entry in ipairs(logs) do
        print((("[" .. text(entry.t) .. "] " .. entry.message):gsub("|", "||")))
    end
end

local function clearSaved()
    pending = nil
    MarketPilotProbeDB = { schema = 2, logs = {} }
    Probe.db = MarketPilotProbeDB
    Probe.db.session = Probe.session
    log("saved probe data cleared; current session counters retained")
end

local function onEvent(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON_NAME then return end
        Probe.InitDB()
        Probe.session = { build = Probe.Build(), functions = {}, events = {} }
        Probe.db.session = Probe.session
        recordSurface()
        registerEvents()
        log("loaded; run /mpprobe status. Candidate signatures remain UNKNOWN in Forever")
        return
    end
    if not Probe.session then return end
    local observation = Probe.session.events[event]
    if observation then
        observation.fired = observation.fired + 1
        observation.lastFiredAt = Probe.Now()
    end
    local arguments = {}
    for index = 1, select("#", ...) do
        arguments[#arguments + 1] = "arg" .. index .. "=" .. describe(select(index, ...))
    end
    log("event fired " .. event .. " " .. table.concat(arguments, " "))
    if event == "AUCTION_HOUSE_SHOW" then
        ahOpen = true
        recordSurface()
        Probe.Ready(event)
    elseif event == "AUCTION_HOUSE_CLOSED" then
        ahOpen = false
        if pending then finishFailure("AH closed; query cancelled") end
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_UPDATED" then
        matchingResult(event, ...)
    elseif event:find("THROTTLED", 1, true) then
        Probe.Ready(event)
    end
end

frame:SetScript("OnEvent", function(...)
    local ok, err = pcall(onEvent, ...)
    if not ok then finishFailure("event handler failed (original error): " .. text(err)) end
end)

SLASH_MARKETPILOTPROBE1 = "/mpprobe"
SlashCmdList.MARKETPILOTPROBE = function(input)
    local ok, err = pcall(function()
        if not Probe.db then log("database not initialized; check addon load errors"); return end
        local command, argument = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
        command = string.lower(command or "")
        if command == "scan" then queryItem(argument)
        elseif command == "dump" then dumpSaved()
        elseif command == "clear" then clearSaved()
        elseif command == "status" or command == "" then status()
        else log("commands: status | scan <itemID> | dump | clear") end
    end)
    if not ok then finishFailure("command failed (original error): " .. text(err)) end
end

local loadedOK, loadedError = pcall(frame.RegisterEvent, frame, "ADDON_LOADED")
if not loadedOK or loadedError == false then log("cannot register ADDON_LOADED: " .. text(loadedError)) end
