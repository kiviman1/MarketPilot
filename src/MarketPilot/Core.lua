local _, MP = ...

local function debug(message)
    print("|cff66ccffMarketPilot:|r " .. message:gsub("|", "||"))
end

local panel, market, batch
local function notify(message)
    debug(message)
    if market then market:Record(MP.scanner) end
    if panel then panel:Guard(panel.Update) end
end
local scanner = MP.Scanner.New(MP.AuctionAPI, MP.Items.testItemID, notify, time)
MP.scanner = scanner
batch = MP.BatchScanner.New(scanner, MP.Items)
market = MP.Market.New(MP.Database.Open(nil), MP.Items)
MP.batch, MP.market = batch, market
panel = MP.UI.New(scanner, MP.Items, debug, market, batch, time)
MP.panel = panel
local frame = CreateFrame("Frame")
local startupError

local function initializeHistory()
    local realmOK, realm = false, nil
    local factionOK, faction = false, nil
    if type(GetRealmName) == "function" then realmOK, realm = pcall(GetRealmName) end
    if type(UnitFactionGroup) == "function" then factionOK, faction = pcall(UnitFactionGroup, "player") end
    local key
    if realmOK and factionOK and type(realm) == "string" and realm ~= "" and type(faction) == "string" and faction ~= "" then
        key = "forever-beta:v1:" .. #realm .. ":" .. realm .. ":" .. #faction .. ":" .. faction
    end
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
        .. (db.error and " error=" .. db.error or ""))
    for _, itemID in ipairs(MP.Items.List()) do
        local history = db:History(itemID)
        local latest = history[#history]
        debug("itemID=" .. itemID .. " snapshots=" .. (db.status == "OK" and #history or "UNKNOWN")
            .. " latestTimestamp=" .. number(latest and latest.t)
            .. " latestCleanMedian=" .. number(latest and latest.cleanMedian) .. " (copper)")
    end
end

local function advance()
    batch:Advance()
    panel:Guard(panel.Update)
end

local function onEvent(event, itemID, success)
    if event == "GET_ITEM_INFO_RECEIVED" then panel:Guard(panel.MetadataReceived, itemID, success); return end
    -- Revalidate even a successful early binding against stable player identity.
    -- Watch/dbstatus themselves never initialize or write history.
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        initializeHistory()
        if panel.anchor then panel:Guard(panel.Update) end
        return
    end
    if event == "ADDON_LOADED" then
        if itemID == "MarketPilot" then initializeHistory() end
        if scanner.ahOpen and (not panel.anchor or panel.mode ~= "AH") then panel:Open() end
        return
    end
    if startupError then return end
    if event == "AUCTION_HOUSE_SHOW" then initializeHistory(); scanner:OnHouseOpened(); panel:Open()
    elseif event == "AUCTION_HOUSE_CLOSED" then batch:Cancel(); scanner:OnHouseClosed(); panel:OnHouseClosed()
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then scanner:OnReady()
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then scanner:OnCommodityResults(itemID) end
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

for _, event in ipairs({ "GET_ITEM_INFO_RECEIVED", "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD" }) do
    local ok, err = pcall(frame.RegisterEvent, frame, event)
    if not ok or err == false then debug("optional panel event unavailable: " .. event .. " " .. tostring(err)) end
end

SLASH_MARKETPILOT1 = "/mp"
SlashCmdList.MARKETPILOT = function(input)
    local ok, err = pcall(function()
        local command = (input or ""):match("^%s*(.-)%s*$"):lower()
        if panel.mode == "STANDALONE" and (command == "scan" or command == "batch" or command == "cancel") then
            debug("read-only watch; open AH to scan"); return
        end
        if command == "scan" then
            if startupError then debug(startupError); return end
            if batch.active then debug("batch active; cancel before a manual scan"); return end
            scanner:Start(panel.selectedItemID)
        elseif command == "batch" then batch:Start(); advance()
        elseif command == "cancel" then batch:Cancel(); panel:Guard(panel.Update)
        elseif command == "report" then panel:Guard(panel.ToggleReport)
        elseif command == "watch" then panel:Guard(panel.ToggleWatch)
        elseif command == "dbstatus" then databaseStatus()
        elseif command == "status" or command == "" then debug(scanner:Summary())
        else debug("commands: /mp scan | /mp status | /mp dbstatus | /mp batch | /mp cancel | /mp report | /mp watch") end
    end)
    if not ok then scanner:Fail("UNKNOWN: command failed: " .. tostring(err)) end
end

debug("loaded; open AH to scan, or /mp watch to browse stored history. /mp status for debugging")
