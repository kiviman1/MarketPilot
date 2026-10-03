local _, MP = ...
local VERSION = "0.5.9"
local debugEnabled = false

local function debug(message)
    print("|cff66ccffMarketPilot:|r " .. message:gsub("|", "||"))
end

local panel, market, batch, advance
local lastBrowseError
local function computedMarketKey()
    local realmOK, realm = false, nil
    local factionOK, faction = false, nil
    if type(GetRealmName) == "function" then realmOK, realm = pcall(GetRealmName) end
    if type(UnitFactionGroup) == "function" then factionOK, faction = pcall(UnitFactionGroup, "player") end
    if realmOK and factionOK and type(realm) == "string" and realm ~= "" and type(faction) == "string" and faction ~= "" then
        return "forever-beta:v1:" .. #realm .. ":" .. realm .. ":" .. #faction .. ":" .. faction
    end
end

-- Diagnostics retain detached text only, once per startup phase. No saved log or
-- raw AH rows; rawget/next avoid invoking callbacks on a malformed global.
local startupObservations, observedPhases = {}, {}
local function primitive(value)
    local kind = type(value)
    if kind == "string" then return (value:gsub("[\r\n]", " ")) end
    if kind == "number" or kind == "boolean" or kind == "nil" then return tostring(value) end
    return "<" .. kind .. ">"
end
local function field(value, key)
    if type(value) == "table" then return rawget(value, key) end
end
local function marketCounts(value)
    local items = field(value, "items")
    if type(items) ~= "table" then return "UNKNOWN", "UNKNOWN" end
    local itemCount, snapshotCount, complete = 0, 0, true
    for _, item in next, items do
        itemCount = itemCount + 1
        local snapshots = field(item, "snapshots")
        if type(snapshots) == "table" then
            for _ in next, snapshots do snapshotCount = snapshotCount + 1 end
        else complete = false end
    end
    return itemCount, complete and snapshotCount or "UNKNOWN"
end
local function savedVariablesSnapshot(phase)
    local root, db = MarketPilotDB, market and market.db
    local markets, rows = field(root, "markets"), {}
    if type(markets) == "table" then
        for key, value in next, markets do
            local items, snapshots = marketCounts(value)
            rows[#rows + 1] = { key = primitive(key), items = items, snapshots = snapshots }
        end
    end
    table.sort(rows, function(a, b) return a.key < b.key end)
    local canary = field(root, "_svCanary")
    local prefix = "svdebug " .. phase
    local lines = { prefix .. " globalType=" .. type(root) .. " schema=" .. primitive(field(root, "schema"))
        .. " marketKeys=" .. (type(markets) == "table" and #rows or "UNKNOWN")
        .. " computedKey=" .. (computedMarketKey() or "UNKNOWN")
        .. " activeKey=" .. (db and db.status == "OK" and db.key or "UNKNOWN")
        .. " globalSameRoot=" .. (db and tostring(root == db.root) or "NO_DB")
        .. " canary=" .. (canary ~= nil and "PRESENT" or "ABSENT") .. " value=" .. primitive(canary)
        .. " version=" .. VERSION }
    for _, row in ipairs(rows) do
        lines[#lines + 1] = prefix .. " marketKey=" .. row.key .. " items=" .. row.items .. " snapshots=" .. row.snapshots
    end
    return lines
end
local function observeStartup(phase)
    if observedPhases[phase] then return end
    startupObservations[#startupObservations + 1] = savedVariablesSnapshot(phase)
    observedPhases[phase] = true
end
observeStartup("CORE_FILE_LOAD") -- Before constructing Market or calling DB.Open.

local function savedVariablesDebug()
    for _, lines in ipairs(startupObservations) do
        for _, line in ipairs(lines) do debug(line) end
    end
    for _, line in ipairs(savedVariablesSnapshot("CURRENT")) do debug(line) end
end
local function markSavedVariables()
    if type(MarketPilotDB) ~= "table" then debug("svmark: global is not a table; no canary written"); return end
    local ok, timestamp = pcall(time)
    if not ok or not MP.HistoryMath.Integer(timestamp, 0) then debug("svmark: clock UNKNOWN; no canary written"); return end
    rawset(MarketPilotDB, "_svCanary", timestamp)
    debug("svmark: _svCanary=" .. string.format("%.0f", timestamp) .. "; reload then /mp svdebug")
end

local function notify(message)
    if debugEnabled or (MP.scanner and MP.scanner.state == "ERROR") then debug(message) end
    local browseError = MP.scanner and MP.scanner.browseError
    if browseError and browseError ~= lastBrowseError then debug("AH browse: " .. browseError) end
    lastBrowseError = browseError
    if market then market:Record(MP.scanner) end
    if panel then panel:Guard(panel.Update) end
end
-- Optional one-shot deadline, never a polling loop or a request retry.
local schedule
if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    schedule = function(seconds, callback)
        C_Timer.After(seconds, function()
            local ok, err = pcall(function() callback(); if advance then advance() end end)
            if not ok then MP.scanner:Fail("UNKNOWN: scan deadline failed: " .. tostring(err)) end
        end)
    end
end
local scanner = MP.Scanner.New(MP.AuctionAPI, MP.Items.testItemID, notify, time, schedule)
MP.scanner = scanner
batch = MP.BatchScanner.New(scanner, MP.Items)
market = MP.Market.New(MP.Database.Open(nil), MP.Items)
MP.batch, MP.market = batch, market
panel = MP.UI.New(scanner, MP.Items, debug, market, batch, time)
MP.panel = panel
-- Imported provider data stays session-only, separate from local scan history.
MP.external = MP.ExternalMarket.New(MP.ExternalPayload, MP.Items.List())
panel.external = MP.external
MP.ExternalPayload = nil
local preferences = MP.Preferences.New(nil)
local settings, minimap
panel.preferences = preferences
local function applyPreference(key)
    if not key or key == "debugLogging" then debugEnabled = preferences:Get("debugLogging") end
    if not key or key == "watchScale" or key == "defaultCategory" or key == "lockWindows" then
        panel:Guard(panel.ApplyPreferences)
    end
    if key == "minimapShown" then minimap:Refresh() end
end
settings = MP.Settings.New(preferences, {
    onChanged = applyPreference,
    onResetPositions = function() panel:Guard(panel.ResetPosition) end,
}, debug)
minimap = MP.Minimap.New(preferences, {
    watch = function() panel:Guard(panel.ToggleWatch) end,
    settings = function() settings:Toggle() end,
}, debug)
panel.onSettings = function() settings:Toggle() end
MP.preferences, MP.settings, MP.minimap = preferences, settings, minimap
local frame = CreateFrame("Frame")
local startupError

local function initializePreferences()
    -- Bind without seeding or replacing the saved root. Explicit UI changes are
    -- the only preference writes; market history remains owned by Database.
    local ok, err = pcall(function()
        preferences:Bind(MarketPilotDB)
        applyPreference()
        settings:Refresh()
        minimap:Refresh()
    end)
    if not ok then debug("Window settings unavailable: " .. tostring(err)) end
end

local function initializeHistory()
    local key = computedMarketKey()
    -- An early valid identity is provisional: only the same key/root may reuse
    -- the binding. Rebinding must not prune or replace existing history.
    local sameRoot = market.db.root == MarketPilotDB
    if market.db.status == "OK" and market.db.key == key and sameRoot then return end
    local db = MP.Database.Open(MarketPilotDB, key, time(), sameRoot)
    if db.status == "OK" then MarketPilotDB = db.root else debug(db.error) end
    market.db, market.cache = db, {}
    market.latest, market.errors, market.scanTimes = {}, {}, {}
    -- Keep lastSample: an old completed scan must not be recorded into a new key.
end

local function databaseStatus()
    local db = market.db
    local function number(value)
        return MP.HistoryMath.Integer(value, 0) and string.format("%.0f", value) or "UNKNOWN"
    end
    debug("db status=" .. db.status .. " activeKey=" .. (db.status == "OK" and db.key or "UNKNOWN")
        .. " globalSameRoot=" .. tostring(MarketPilotDB == db.root)
        .. (db.error and " error=" .. db.error or ""))
    for _, itemID in ipairs(MP.Items.List()) do
        local history = db:History(itemID)
        local latest = history[#history]
        debug("itemID=" .. itemID .. " snapshots=" .. (db.status == "OK" and #history or "UNKNOWN")
            .. " latestTimestamp=" .. number(latest and latest.t)
            .. " latestCleanMedian=" .. number(latest and latest.cleanMedian) .. " (copper)")
    end
end

advance = function()
    local wasActive = batch.active
    batch:Advance()
    if wasActive and not batch.active then
        local failed = 0
        for _, result in pairs(batch.results) do if result.state == "ERROR" then failed = failed + 1 end end
        debug("batch " .. batch.state .. ": " .. batch.completed .. "/" .. batch.total
            .. " finished; " .. failed .. " failed. Open Market Watch for results.")
    end
    panel:Guard(panel.Update)
end

local function onEvent(event, itemID, success)
    if event == "GET_ITEM_INFO_RECEIVED" then panel:Guard(panel.MetadataReceived, itemID, success); return end
    -- Revalidate even a successful early binding against stable player identity.
    -- Watch/dbstatus themselves never initialize or write history.
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        observeStartup(event .. " pre-bind")
        initializeHistory()
        observeStartup(event .. " post-bind")
        initializePreferences()
        if panel.anchor then panel:Guard(panel.Update) end
        return
    end
    if event == "ADDON_LOADED" then
        if itemID == "MarketPilot" then
            observeStartup("ADDON_LOADED pre-bind")
            initializeHistory()
            observeStartup("ADDON_LOADED post-bind")
            initializePreferences()
        end
        if scanner.ahOpen and (not panel.anchor or panel.mode ~= "AH") then panel:Open() end
        return
    end
    if startupError then return end
    if event == "AUCTION_HOUSE_SHOW" then
        initializeHistory(); initializePreferences(); scanner:OnHouseOpened(); panel:Open()
    elseif event == "AUCTION_HOUSE_CLOSED" then batch:Cancel(); scanner:OnHouseClosed(); panel:OnHouseClosed()
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then scanner:OnReady()
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then scanner:OnCommodityResults(itemID)
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then scanner:OnBrowseResults()
    elseif event == "AUCTION_HOUSE_BROWSE_FAILURE" then scanner:OnBrowseFailure() end
    advance()
end

frame:SetScript("OnEvent", function(_, event, ...)
    local ok, err = pcall(onEvent, event, ...)
    if not ok then scanner:Fail("UNKNOWN: event handler failed: " .. tostring(err)) end
end)

for _, event in ipairs({
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
    "COMMODITY_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
}) do
    local ok, err = pcall(frame.RegisterEvent, frame, event)
    if not ok or err == false then
        startupError = "UNKNOWN: cannot register " .. event .. ": " .. tostring(err)
        scanner.blockedReason = startupError
        scanner:Fail(startupError)
    end
end

-- Browse navigation is optional. An unsupported event must not disable the
-- already validated commodity scanner or read-only history.
do
    local event = "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED"
    local ok, err = pcall(frame.RegisterEvent, frame, event)
    if not ok or err == false then
        scanner.browseBlockedReason = "UNKNOWN: cannot register " .. event .. ": " .. tostring(err)
        debug(scanner.browseBlockedReason)
    end
    local failureOK, failureError = pcall(frame.RegisterEvent, frame, "AUCTION_HOUSE_BROWSE_FAILURE")
    if not failureOK or failureError == false then
        debug("optional AH browse failure event unavailable; deadline remains active: " .. tostring(failureError))
    end
end

for _, event in ipairs({ "GET_ITEM_INFO_RECEIVED", "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD" }) do
    local ok, err = pcall(frame.RegisterEvent, frame, event)
    if not ok or err == false then debug("optional panel event unavailable: " .. event .. " " .. tostring(err)) end
end

SLASH_MARKETPILOT1 = "/mp"
SlashCmdList.MARKETPILOT = function(input)
    local ok, err = pcall(function()
        local command = (input or ""):match("^%s*(.-)%s*$"):lower()
        if (panel.mode == "STANDALONE" or panel.externalMode) and (command == "scan" or command == "batch" or command == "cancel") then
            debug("read-only view; select Market Watch with AH open to scan"); return
        end
        if command == "scan" then
            if startupError then debug(startupError); return end
            if batch.active then debug("batch active; cancel before a manual scan"); return end
            scanner:Start(panel.selectedItemID)
        elseif command == "batch" then batch:Start(); advance()
        elseif command == "cancel" then batch:Cancel(); panel:Guard(panel.Update)
        elseif command == "report" then panel:Guard(panel.ToggleReport)
        elseif command == "watch" then panel:Guard(panel.ToggleWatch)
        elseif command == "external" then panel:Guard(panel.ToggleExternal)
        elseif command == "syncstatus" then
            debug("AHledger status=" .. MP.external.status .. " market=" .. (MP.external.market or "not selected")
                .. " fetchedAt=" .. tostring(MP.external.fetchedAt or "not updated")
                .. (MP.external.reason and " reason=" .. MP.external.reason or ""))
        elseif command == "settings" then settings:Toggle()
        elseif command == "dbstatus" then databaseStatus()
        elseif command == "svdebug" then savedVariablesDebug()
        elseif command == "svmark" then markSavedVariables()
        elseif command == "debug on" or command == "debug off" then
            preferences:Set("debugLogging", command == "debug on")
            applyPreference("debugLogging")
            settings:Refresh()
            debug("scan trace " .. (debugEnabled and "ON" or "OFF"))
        elseif command == "status" or command == "" then debug(scanner:Summary())
        else debug("commands: /mp scan | /mp status | /mp dbstatus | /mp svdebug | /mp svmark | /mp batch | /mp cancel | /mp report | /mp watch | /mp external | /mp syncstatus | /mp settings | /mp debug on/off") end
    end)
    if not ok then scanner:Fail("UNKNOWN: command failed: " .. tostring(err)) end
end

debug("v" .. VERSION .. " loaded; minimap: watch / settings. /mp watch for history; /mp settings for options.")
