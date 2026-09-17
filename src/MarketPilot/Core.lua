local _, MP = ...

local function debug(message)
    print("|cff66ccffMarketPilot:|r " .. message:gsub("|", "||"))
end

local scanner = MP.Scanner.New(MP.AuctionAPI, MP.Items.testItemID, debug, time)
MP.scanner = scanner
local frame = CreateFrame("Frame")
local startupError

local function onEvent(event, itemID)
    if startupError then return end
    if event == "AUCTION_HOUSE_SHOW" then scanner:OnHouseOpened()
    elseif event == "AUCTION_HOUSE_CLOSED" then scanner:OnHouseClosed()
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
        scanner:Fail(startupError)
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
        else debug("commands: /mp scan | /mp status (configured itemID=" .. MP.Items.testItemID .. ")") end
    end)
    if not ok then scanner:Fail("UNKNOWN: command failed: " .. tostring(err)) end
end

debug("loaded; open AH, then /mp scan. /mp status shows current in-memory state")
