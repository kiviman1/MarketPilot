local _, MP = ...
local AuctionAPI = {}
MP.AuctionAPI = AuctionAPI

local REQUIRED = {
    "MakeItemKey", "SendSearchQuery", "IsThrottledMessageSystemReady",
    "GetNumCommoditySearchResults", "GetCommoditySearchResultInfo",
}
local MAX_INTEGER = 9007199254740991 -- Exact integer range of Lua 5.1 numbers.

local function integer(value, minimum)
    return type(value) == "number" and value >= minimum
        and value <= MAX_INTEGER and value % 1 == 0
end

local function call(name, ...)
    if type(C_AuctionHouse) ~= "table" or type(C_AuctionHouse[name]) ~= "function" then
        return false, "UNKNOWN: missing API " .. name
    end
    local ok, value = pcall(C_AuctionHouse[name], ...)
    if not ok then
        return false, "UNKNOWN: " .. name .. " failed: " .. tostring(value)
    end
    return true, value
end

function AuctionAPI:IsAvailable()
    for _, name in ipairs(REQUIRED) do
        if type(C_AuctionHouse) ~= "table" or type(C_AuctionHouse[name]) ~= "function" then
            return false, "UNKNOWN: missing API " .. name
        end
    end
    return true
end

function AuctionAPI:IsReady()
    local ok, value = call("IsThrottledMessageSystemReady")
    if not ok then return nil, value end
    if type(value) ~= "boolean" then
        return nil, "UNKNOWN: readiness must be boolean, got " .. type(value)
    end
    return value
end

function AuctionAPI:QueryCommodity(itemID)
    if not integer(itemID, 1) then return false, "UNKNOWN: invalid itemID", false end
    local ok, itemKey = call("MakeItemKey", itemID)
    if not ok then return false, itemKey, false end
    if type(itemKey) ~= "table" or rawget(itemKey, "itemID") ~= itemID then
        return false, "UNKNOWN: MakeItemKey returned an invalid/mismatched key", false
    end
    -- The MP-00 confirmed signature; no alternate calls or synthesized keys.
    local sent, result = call("SendSearchQuery", itemKey, {}, true)
    -- The third return distinguishes a safe pre-dispatch failure from a send
    -- whose server-side outcome is unknown. Never retry an ambiguous dispatch.
    if not sent then return false, result, true end
    if result == false then return false, "UNKNOWN: SendSearchQuery returned false", true end
    -- A successful call is not completion; Scanner must wait for a matching event.
    return true
end

local function browseUI()
    local frame = AuctionHouseFrame
    if (type(frame) ~= "table" and type(frame) ~= "userdata") or type(frame.IsShown) ~= "function" then
        return nil, "UNKNOWN: Blizzard Auction House is unavailable"
    end
    local shownOK, shown = pcall(frame.IsShown, frame)
    if not shownOK or not shown then return nil, "UNKNOWN: Blizzard Auction House is closed" end
    for _, name in ipairs({ "GetCategoriesList", "SetDisplayMode", "SetSearchText", "SendBrowseQuery" }) do
        if type(frame[name]) ~= "function" then return nil, "UNKNOWN: missing Blizzard " .. name end
    end
    for _, name in ipairs({ "SendBrowseQuery", "HasFullBrowseResults" }) do
        if type(C_AuctionHouse) ~= "table" or type(C_AuctionHouse[name]) ~= "function" then
            return nil, "UNKNOWN: missing API " .. name
        end
    end
    if type(g_auctionHouseSortsBySearchContext) ~= "table" then
        return nil, "UNKNOWN: Blizzard browse sorting is not loaded"
    end
    local mode = type(AuctionHouseFrameDisplayMode) == "table" and AuctionHouseFrameDisplayMode.Buy
    if type(mode) ~= "table" then
        return nil, "UNKNOWN: Blizzard browse mode is unavailable"
    end
    local searchBar = frame.SearchBar
    if (type(searchBar) ~= "table" and type(searchBar) ~= "userdata") or type(searchBar.StartSearch) ~= "function" then
        return nil, "UNKNOWN: Blizzard Search button path is unavailable"
    end
    local ok, categories = pcall(frame.GetCategoriesList, frame)
    if not ok or (type(categories) ~= "table" and type(categories) ~= "userdata")
        or type(categories.SetSelectedCategory) ~= "function" then
        return nil, "UNKNOWN: Blizzard browse categories are unavailable"
    end
    return { frame = frame, categories = categories, mode = mode, searchBar = searchBar }
end

function AuctionAPI:PrepareBrowse(itemID)
    if not integer(itemID, 1) or not MP.Items.Contains(itemID) then
        return nil, "UNKNOWN: invalid browse item"
    end
    local ui, reason = browseUI()
    if not ui then return nil, reason end
    local ok, metadata = pcall(MP.Items.Metadata, itemID)
    if not ok or type(metadata) ~= "table" or metadata.known ~= true
        or type(metadata.name) ~= "string" or not metadata.name:find("%S") then
        return nil, "UNKNOWN: item name is not loaded for Blizzard browse"
    end
    return { name = metadata.name }
end

function AuctionAPI:QueryBrowse(name)
    if type(name) ~= "string" or not name:find("%S") then
        return false, "UNKNOWN: invalid browse name", false
    end
    local ui, reason = browseUI()
    if not ui then return false, reason, false end
    local ready, readyReason = self:IsReady()
    if ready ~= true then return false, readyReason or "Blizzard browse is not ready", false end
    -- Source-backed Forever 1.60.1 (70009), wow-ui-source bd2470a:
    -- SearchBar:StartSearch is the native Search button's own entry point.
    -- Buy must be shown before setting text: SearchBar:OnShow clears its text.
    -- Leave filter/level construction to Blizzard, just as a manual search does.
    -- The previous forced exact-name query differed from the working live button.
    local prepared, preparationError = pcall(function()
        ui.categories:SetSelectedCategory(nil)
        ui.frame:SetDisplayMode(ui.mode)
        if ui.frame:SetSearchText(name) ~= true then error("Blizzard rejected browse search text") end
    end)
    if not prepared then return false, "UNKNOWN: browse preparation failed: " .. tostring(preparationError), false end
    -- One native search; do not try alternative parameters or retry empty results.
    local sent, result = pcall(ui.searchBar.StartSearch, ui.searchBar)
    if not sent then return false, "UNKNOWN: Blizzard browse failed: " .. tostring(result), true end
    if result == false then return false, "UNKNOWN: Blizzard browse returned false", true end
    -- Like commodity search, successful dispatch is not a completed result.
    return true
end

function AuctionAPI:AreBrowseResultsReady()
    local ready, reason = self:IsReady()
    if ready ~= true then return ready, reason end
    -- Forever source bd2470a: BrowseResultsFrame.lua uses this predicate;
    -- AuctionHouseDocumentation.lua:706-712 specifies a boolean with no args.
    -- Browse update events also follow commodity queries, so an event alone
    -- cannot prove completion. This predicate is not a request correlation ID.
    local ok, complete = call("HasFullBrowseResults")
    if not ok then return nil, complete end
    if type(complete) ~= "boolean" then
        return nil, "UNKNOWN: browse completeness must be boolean, got " .. type(complete)
    end
    return complete
end

function AuctionAPI:ReadCommodityResults(itemID)
    if not integer(itemID, 1) then return nil, "UNKNOWN: invalid itemID" end
    local ok, count = call("GetNumCommoditySearchResults", itemID)
    if not ok then return nil, count end
    if not integer(count, 0) then return nil, "UNKNOWN: invalid commodity result count" end
    local levels = {}
    for index = 1, count do
        local rowOK, row = call("GetCommoditySearchResultInfo", itemID, index)
        if not rowOK then return nil, row end
        if type(row) ~= "table" then
            return nil, "UNKNOWN: row " .. index .. " is not a table"
        end
        local price, quantity = rawget(row, "unitPrice"), rawget(row, "quantity")
        if not integer(price, 1) then
            return nil, "UNKNOWN: row " .. index .. " has invalid/missing unitPrice"
        end
        if not integer(quantity, 1) then
            return nil, "UNKNOWN: row " .. index .. " has invalid/missing quantity"
        end
        -- Own primitive data only; preserve every row and its copper value as-is.
        levels[#levels + 1] = { unitPrice = price, quantity = quantity }
    end
    return levels
end
