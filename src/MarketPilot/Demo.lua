local _, MP = ...
local Demo, DAY = {}, 86400
MP.Demo = Demo

-- A separate, disposable market: never accept a saved root or copy live history.
local profiles = {
    { kind = "RISING", label = "Rising market", description = "About +4% per day over 30 days." },
    { kind = "FALLING", label = "Falling market", description = "About -3.85% per day over 30 days." },
    { kind = "STABLE", label = "Stable market", description = "Unchanged price and supply; no meaningful shift." },
    { kind = "CHEAP_LOW_SUPPLY", label = "Cheaper / low supply", description = "Last 24h: price -40%, quantity -60%." },
    { kind = "EXPENSIVE_HIGH_SUPPLY", label = "Dearer / high supply", description = "Last 24h: price +60%, quantity doubled." },
    { kind = "UNUSUAL_RETURN", label = "Unusual latest move", description = "Small repeating moves, followed by one large jump." },
    { kind = "EXTREME_OUTLIER", label = "Extreme auction filtered", description = "One 100,000g price with dominant quantity; clean median stays 10s." },
}
local examples = { [2770] = 1, [2771] = 2, [2775] = 3, [2772] = 4, [2776] = 5, [3858] = 6, [2447] = 7 }

local function sample(kind, index, timestamp)
    local price, quantity = 1000, 20
    if kind == "RISING" then price = math.floor(1000 * 1.04 ^ (index / 3) + 0.5)
    elseif kind == "FALLING" then price = math.floor(1000 * 1.04 ^ ((90 - index) / 3) + 0.5)
    elseif kind == "CHEAP_LOW_SUPPLY" and index >= 87 then price, quantity = 600, 8
    elseif kind == "EXPENSIVE_HIGH_SUPPLY" and index >= 87 then price, quantity = 1600, 40
    elseif kind == "UNUSUAL_RETURN" then
        price = ({ 1000, 1100, 1050 })[index % 3 + 1]
        if index == 90 then price = 1800 end
    end
    local levels = {}
    -- Seven distinct levels keep the normal anomaly model well-defined; the
    -- central price is exactly the quantity-weighted median, with no rounding.
    for offset = -3, 3 do levels[#levels + 1] = { unitPrice = price + offset * 10, quantity = quantity } end
    if kind == "EXTREME_OUTLIER" and index == 90 then
        levels[#levels + 1] = { unitPrice = 1000000000, quantity = 10000 }
    end
    return { capturedAt = timestamp, priceLevels = levels }
end

function Demo.Create(now, items)
    if not MP.HistoryMath.Integer(now, 30 * DAY) then return nil, "Demo needs a valid current timestamp." end
    if type(items) ~= "table" or type(items.List) ~= "function" then return nil, "Demo needs configured items." end
    local ids, seen, count = items.List(), {}, 0
    if type(ids) ~= "table" then return nil, "Demo needs a list of configured items." end
    for key, id in pairs(ids) do
        if not MP.HistoryMath.Integer(key, 1) or key > #ids or not MP.HistoryMath.Integer(id, 1) or seen[id] then
            return nil, "Demo item list must contain unique valid IDs."
        end
        seen[id], count = true, count + 1
    end
    if count == 0 or count ~= #ids then return nil, "Demo needs a nonempty dense item list." end

    local database = MP.Database.Open(nil, "demo:30-days", now)
    if database.status ~= "OK" then return nil, database.error end
    local metadata = { synthetic = true, label = "Demo: 30 days of simulated markets", days = 30, count = 91, items = {} }
    for position, id in ipairs(ids) do
        local profile = profiles[examples[id] or ((position - 1) % #profiles + 1)]
        metadata.items[id] = { kind = profile.kind, label = profile.label, description = profile.description }
        for index = 0, 90 do
            local observation = sample(profile.kind, index, now - 30 * DAY + index * DAY / 3)
            local analysis, err = MP.Statistics.Analyze(observation)
            if not analysis then return nil, err end
            local snapshot; snapshot, err = MP.Database.Snapshot(observation, analysis)
            if not snapshot then return nil, err end
            local stored; stored, err = database:Append(id, snapshot)
            if not stored then return nil, err end
        end
    end
    return MP.Market.New(database, items), metadata
end
