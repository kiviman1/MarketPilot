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
    if not integer(itemID, 1) then return false, "UNKNOWN: invalid itemID" end
    local ok, itemKey = call("MakeItemKey", itemID)
    if not ok then return false, itemKey end
    if type(itemKey) ~= "table" or rawget(itemKey, "itemID") ~= itemID then
        return false, "UNKNOWN: MakeItemKey returned an invalid/mismatched key"
    end
    -- The MP-00 confirmed signature; no alternate calls or synthesized keys.
    local sent, result = call("SendSearchQuery", itemKey, {}, true)
    if not sent then return false, result end
    if result == false then return false, "UNKNOWN: SendSearchQuery returned false" end
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

local SELL_CANDIDATES = {
    "IsSellItemValid", "CalculateCommodityDeposit", "SupportsCopperValues",
    "ShouldAutoPopulatePrice", "PostCommodity",
}

function AuctionAPI:SellCapabilities()
    local result = { capabilities = {}, status = "NEEDS BETA CHECK" }
    for _, name in ipairs(SELL_CANDIDATES) do
        result.capabilities[#result.capabilities + 1] = { name = name,
            presence = type(C_AuctionHouse) == "table" and type(C_AuctionHouse[name]) == "function"
                and "PRESENT" or "ABSENT",
            status = "UNKNOWN", detail = "not called; Forever behavior unverified" }
    end
    return result
end

-- External Blizzard declarations only (linked in API_FINDINGS); no signature retries.
-- This explicit read-only probe cannot create auctions. Presence is not validation.
function AuctionAPI:ProbeSell(itemID, location, quantity, hours, locationError)
    local result = self:SellCapabilities()
    local function observe(index, expected, detail, ...)
        local row = result.capabilities[index]
        local ok, value = call(row.name, ...)
        row.detail = detail
        if not ok then row.detail = detail .. "; " .. tostring(value); return end
        if type(value) ~= expected or (expected == "number" and not integer(value, 0)) then
            row.detail = detail .. "; unexpected return type/value: " .. type(value)
            if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then
                row.detail = row.detail .. " " .. tostring(value)
            end
            return
        end
        row.status, row.value = "CANDIDATE_OBSERVED", value
    end
    observe(3, "boolean", "SupportsCopperValues()")
    observe(4, "boolean", "ShouldAutoPopulatePrice()")
    if location then
        observe(1, "boolean", "IsSellItemValid(ItemLocation, false)", location, false)
    else
        result.capabilities[1].detail = locationError or "UNKNOWN: select a bag item / ItemLocation unavailable"
    end
    -- External sell UI uses duration indices 1/2/3; hours mapping needs beta comparison.
    local duration = ({ [12] = 1, [24] = 2, [48] = 3 })[hours]
    if integer(itemID, 1) and integer(quantity, 1) and duration then
        observe(2, "number", "CalculateCommodityDeposit(" .. itemID .. ", " .. duration .. ", " .. quantity
            .. "); candidate duration index for " .. hours .. "h", itemID, duration, quantity)
        if result.capabilities[2].status == "CANDIDATE_OBSERVED" then result.deposit = result.capabilities[2].value end
    else
        result.capabilities[2].detail = "UNKNOWN: select a bag item and valid quantity/duration"
    end
    result.capabilities[5].detail = "presence only; NEVER CALLED; posting DISABLED; hardware/copper posting UNKNOWN"
    return result
end
