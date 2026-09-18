local _, MP = ...
local DB, M = {}, MP.HistoryMath
DB.__index = DB
MP.Database = DB
local PRICES = { "rawMedian", "cleanMedian", "q1", "q3", "lowest" }
local COUNTS = { "totalQuantity", "levelCount", "suspicious", "extreme" }
local FIELDS = { "t", "rawMedian", "cleanMedian", "q1", "q3", "lowest", "totalQuantity",
    "levelCount", "suspicious", "extreme", "anomalySufficient" }
local DAY = 86400

function DB.Copy(snapshot)
    if type(snapshot) ~= "table" or not M.Integer(snapshot.t, 0) or type(snapshot.anomalySufficient) ~= "boolean" then
        return nil, "UNKNOWN: invalid snapshot header"
    end
    for _, key in ipairs(PRICES) do
        if snapshot[key] ~= nil and not M.Integer(snapshot[key], 1) then return nil, "UNKNOWN: invalid " .. key end
    end
    for _, key in ipairs(COUNTS) do
        if not M.Integer(snapshot[key], 0) then return nil, "UNKNOWN: invalid " .. key end
    end
    if snapshot.suspicious + snapshot.extreme > snapshot.levelCount then return nil, "UNKNOWN: invalid anomaly counts" end
    local copy = {}; for _, key in ipairs(FIELDS) do copy[key] = snapshot[key] end
    return copy
end

function DB.Snapshot(sample, analysis)
    if not sample or not analysis then return nil, "UNKNOWN: no completed analysis" end
    return DB.Copy({ t = sample.capturedAt, rawMedian = analysis.raw.weightedMedian,
        cleanMedian = analysis.clean.weightedMedian, q1 = analysis.clean.q1, q3 = analysis.clean.q3,
        lowest = analysis.raw.min, totalQuantity = analysis.raw.totalQuantity, levelCount = analysis.raw.levelCount,
        suspicious = analysis.anomaly.suspiciousCount, extreme = analysis.anomaly.extremeCount,
        anomalySufficient = analysis.anomaly.sufficient })
end

local function dense(list)
    if type(list) ~= "table" then return false end
    local n = 0
    for key in pairs(list) do if not M.Integer(key, 1) or key > #list then return false end; n = n + 1 end
    return n == #list
end

function DB.Open(root, key, now, preserveHistory)
    local self = setmetatable({ root = root, key = key, status = "UNKNOWN" }, DB)
    local function reject(reason) self.error = "UNKNOWN: history " .. reason; return self end
    if type(key) ~= "string" or key == "" then return reject("identity unavailable; persistence disabled") end
    if not M.Integer(now, 0) then return reject("clock unavailable") end
    if root == nil then root = { schema = 1, markets = {} }; self.root = root end
    if type(root) ~= "table" or root.schema ~= 1 or type(root.markets) ~= "table" then
        return reject("schema unsupported; existing data preserved, no automatic reset")
    end
    -- Validate the whole known schema before any retention mutation.
    for marketKey, market in pairs(root.markets) do
        if type(marketKey) ~= "string" or type(market) ~= "table" or type(market.items) ~= "table" then
            return reject("malformed market; existing data preserved")
        end
        for id, item in pairs(market.items) do
            if not M.Integer(id, 1) or type(item) ~= "table" or not dense(item.snapshots) then return reject("malformed item") end
            local previous = -1
            for _, snapshot in ipairs(item.snapshots) do
                if not DB.Copy(snapshot) or snapshot.t < previous then return reject("malformed/unsorted snapshots") end
                previous = snapshot.t
            end
        end
    end
    -- Identity revalidation only changes the binding; retention is not a migration.
    if not preserveHistory then
        for _, market in pairs(root.markets) do
            for _, item in pairs(market.items) do self:Prune(item.snapshots, now) end
        end
    end
    root.markets[key] = root.markets[key] or { items = {} }
    self.items, self.status = root.markets[key].items, "OK"
    return self
end

function DB:Prune(list, now)
    while #list > 0 and (#list > 200 or list[1].t < now - 60 * DAY) do table.remove(list, 1) end
end

function DB:History(itemID)
    local item = self.items and self.items[itemID]
    local result = {}
    for i, row in ipairs(item and item.snapshots or {}) do result[i] = DB.Copy(row) end
    return result
end

function DB:Append(itemID, snapshot)
    if self.status ~= "OK" then return nil, self.error end
    if not M.Integer(itemID, 1) then return nil, "UNKNOWN: invalid item ID" end
    local copy, err = DB.Copy(snapshot); if not copy then return nil, err end
    local item = self.items[itemID] or { snapshots = {} }
    local list, same = item.snapshots, true
    local last = list[#list]
    if last and copy.t < last.t then return nil, "UNKNOWN: clock moved backwards; history preserved" end
    if last then
        for _, field in ipairs(FIELDS) do if field ~= "t" and copy[field] ~= last[field] then same = false end end
        if same and copy.t - last.t < 600 then return false, "DEDUPED", DB.Copy(last) end
    end
    list[#list + 1] = copy
    self:Prune(list, copy.t)
    self.items[itemID] = item
    return true, "STORED", DB.Copy(copy)
end
