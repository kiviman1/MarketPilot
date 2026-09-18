local _, MP = ...

local function debug(message)
    print("|cff66ccffMarketPilot:|r " .. message:gsub("|", "||"))
end

local panel, sale
local function notify(message)
    debug(message)
    if sale then sale:OnScannerChanged() end
    if panel then panel:Guard(panel.Update) end
end
local scanner = MP.Scanner.New(MP.AuctionAPI, MP.Items.testItemID, notify, time)
MP.scanner = scanner
local inventory = MP.Inventory.New(MP.Items)
sale = MP.SaleAssistant.New(inventory, scanner, MP.AuctionAPI, MP.Pricing, debug, time)
MP.inventory, MP.sale = inventory, sale
panel = MP.UI.New(scanner, MP.Items, debug, sale)
MP.panel = panel
local frame = CreateFrame("Frame")
local startupError

local function onEvent(event, itemID, success)
    if event == "BAG_UPDATE_DELAYED" then
        if scanner.ahOpen then sale:RefreshInventory(); panel:Guard(panel.Update) end
        return
    end
    if event == "GET_ITEM_INFO_RECEIVED" then panel:Guard(panel.MetadataReceived, itemID, success); return end
    if event == "ADDON_LOADED" then
        if scanner.ahOpen and not panel.anchor then panel:Open() end
        return
    end
    if startupError then return end
    if event == "AUCTION_HOUSE_SHOW" then sale:RefreshInventory(); scanner:OnHouseOpened(); panel:Open()
    elseif event == "AUCTION_HOUSE_CLOSED" then sale:Close(); scanner:OnHouseClosed(); panel:Close()
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then scanner:OnReady()
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then scanner:OnCommodityResults(itemID) end
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

for _, event in ipairs({ "GET_ITEM_INFO_RECEIVED", "ADDON_LOADED" }) do
    local ok, err = pcall(frame.RegisterEvent, frame, event)
    if not ok or err == false then debug("optional panel event unavailable: " .. event .. " " .. tostring(err)) end
end

do
    local ok, err = pcall(frame.RegisterEvent, frame, "BAG_UPDATE_DELAYED")
    if not ok or err == false then
        inventory.blockedReason = "UNKNOWN: BAG_UPDATE_DELAYED unavailable: " .. tostring(err)
        debug(inventory.blockedReason) -- Disable sale inventory, keep market browsing available.
    end
end

SLASH_MARKETPILOT1 = "/mp"
SlashCmdList.MARKETPILOT = function(input)
    local ok, err = pcall(function()
        local command = (input or ""):match("^%s*(.-)%s*$"):lower()
        if command == "scan" then
            if startupError then debug(startupError); return end
            scanner:Start()
        elseif command == "status" or command == "" then debug(scanner:Summary())
        elseif command == "sellstatus" then sale:CheckCapabilities(); panel:Guard(panel.Update)
        else debug("commands: /mp scan | /mp status | /mp sellstatus (selected itemID=" .. scanner.itemID .. ")") end
    end)
    if not ok then scanner:Fail("UNKNOWN: command failed: " .. tostring(err)) end
end

debug("loaded; open AH and click a MarketPilot item. /mp status remains available for debugging")
