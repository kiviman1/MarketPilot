local _, MP = ...
local Market = {}
Market.__index = Market
MP.Market = Market
function Market.New(database, items)
    return setmetatable({ db = database, items = items, cache = {}, latest = {}, errors = {}, scanTimes = {} }, Market)
end
function Market:Record(scanner)
    if scanner.state == "ERROR" then self.errors[scanner.itemID] = scanner.error; self.cache[scanner.itemID] = nil end
    if scanner.state ~= "DONE" or self.lastSample == scanner.sample then return end
    self.lastSample = scanner.sample
    local snapshot, err = MP.Database.Snapshot(scanner.sample, scanner.analysis)
    if not snapshot then self.errors[scanner.itemID] = err; self.cache[scanner.itemID] = nil; return end
    local _, status, representative = self.db:Append(scanner.itemID, snapshot)
    self.latest[scanner.itemID] = representative or snapshot
    self.scanTimes[scanner.itemID] = snapshot.t
    self.errors[scanner.itemID] = status ~= "STORED" and status ~= "DEDUPED" and status or nil
    self.cache[scanner.itemID] = nil
end
function Market:Get(itemID)
    if self.cache[itemID] then return self.cache[itemID] end
    local history = self.db:History(itemID)
    local current = self.latest[itemID] or history[#history]
    local analytics = MP.HistoricalAnalytics.Analyze(history, current)
    local result = { current = current, analytics = analytics, signals = MP.MarketSignal.Describe(analytics),
        history = history, lastScan = self.scanTimes[itemID] or (current and current.t), error = self.errors[itemID] }
    self.cache[itemID] = result
    return result
end
function Market:Report()
    local report = { rising = {}, cheap = {}, volatile = {}, significant = {}, maturity = { NEW = 0, EARLY = 0, ["7D READY"] = 0, ["30D READY"] = 0 } }
    for _, id in ipairs(self.items.List()) do
        local item = self:Get(id)
        report.maturity[item.analytics.maturity] = report.maturity[item.analytics.maturity] + 1
        if not item.error and item.analytics.status == "OK" then
            local row = { itemID = id, data = item }
            if item.signals.trend == "RISING" then report.rising[#report.rising + 1] = row end
            if item.signals.price == "CHEAP_VS_HISTORY" then report.cheap[#report.cheap + 1] = row end
            if item.signals.volatility == "HIGH" then report.volatile[#report.volatile + 1] = row end
            if item.analytics.significance.meaningfulMove then report.significant[#report.significant + 1] = row end
        end
    end
    table.sort(report.rising, function(a, b)
        local x, y = a.data.analytics.trend7d.pctPerDay, b.data.analytics.trend7d.pctPerDay
        return x == y and a.itemID < b.itemID or x > y
    end)
    return report
end
