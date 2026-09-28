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
