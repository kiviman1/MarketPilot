local _, MP = ...
local Scanner = {}
Scanner.__index = Scanner
MP.Scanner = Scanner
Scanner.TIMEOUT_SECONDS = 30

local MAX_INTEGER = 9007199254740991
local ACTIVE = { WAITING = true, QUERYING = true, COLLECTING = true }

function Scanner.New(api, itemID, notify, clock, schedule)
    return setmetatable({
        api = api, itemID = itemID, notify = notify, clock = clock, schedule = schedule,
        state = "IDLE", ahOpen = false, queryCount = 0,
    }, Scanner)
end

function Scanner:Summary()
    local summary = self.summary
    local analysis = self.analysis
    local function number(value)
        return value ~= nil and string.format("%.0f", value) or "UNKNOWN"
    end
    return "state=" .. self.state .. " AH-open=" .. tostring(self.ahOpen)
        .. " itemID=" .. self.itemID .. " queriesSent=" .. self.queryCount
        .. " levels=" .. number(summary and summary.levelCount)
        .. " totalQuantity=" .. number(summary and summary.totalQuantity)
        .. " lowestUnitPrice=" .. number(summary and summary.lowest)
        .. " highestUnitPrice=" .. number(summary and summary.highest)
        .. " rawMedian=" .. number(analysis and analysis.raw.weightedMedian)
        .. " cleanMedian=" .. number(analysis and analysis.clean.weightedMedian)
        .. " suspicious=" .. number(analysis and analysis.anomaly.suspiciousCount)
        .. " extreme=" .. number(analysis and analysis.anomaly.extremeCount)
        .. " anomalySufficient=" .. (analysis and (analysis.anomaly.sufficient and "yes" or "no") or "UNKNOWN")
        .. " deadline=" .. (self.schedule and (Scanner.TIMEOUT_SECONDS .. "s") or "UNAVAILABLE")
        .. " (copper/unit)" .. (self.error and " error=" .. self.error or "")
end

function Scanner:Fail(reason)
    self.requestToken = nil
    self.analysis = nil
    self.state, self.sample, self.summary = "ERROR", nil, nil
    self.error = reason
    self.notify(self:Summary())
end

function Scanner:OnHouseOpened()
    self.ahOpen = true
    self.notify(self:Summary())
end

function Scanner:OnHouseClosed()
    self.requestToken = nil
    self.stopBatchReason = nil
    self.uncertainQuery = nil
    self.analysis = nil
    self.ahOpen = false
    self.state, self.sample, self.summary, self.error = "IDLE", nil, nil, nil
    self.notify("AH closed; scan cancelled/reset. " .. self:Summary())
end

function Scanner:IsActive()
    return ACTIVE[self.state] == true
end

function Scanner:CancelWaiting()
    if self.state == "WAITING" then
        self.requestToken = nil
        self.state, self.error = "IDLE", nil
        self.notify("pending scan cancelled before dispatch. " .. self:Summary())
    end
end

function Scanner:Start(itemID)
    if self.uncertainQuery then self:Fail("UNKNOWN: prior dispatch uncertain; close/reopen AH"); return end
    if ACTIVE[self.state] then
        self.notify("scan already pending; no additional query. " .. self:Summary())
        return
    end
    self.stopBatchReason = nil
    if itemID ~= nil then
        if not MP.Items.Contains(itemID) then self:Fail("UNKNOWN: item is not configured"); return end
        self.itemID = itemID
    end
    if self.blockedReason then
        self.stopBatchReason = "UNKNOWN: required events unavailable"
        self:Fail(self.blockedReason)
        return
    end
    self.sample, self.summary, self.error = nil, nil, nil
    self.analysis = nil
    if not self.ahOpen then self:Fail("AH is closed; open it before /mp scan"); return end
    local available, err = self.api:IsAvailable()
    if not available then
        self.stopBatchReason = "UNKNOWN: Auction API unavailable"
        self:Fail(err)
        return
    end
    self.state = "WAITING"
    if self.schedule then
        local token = {}
        self.requestToken = token
        -- One deadline per player-requested scan; no polling, retry or timer
        -- renewal on throttle events. Superseded callbacks cannot affect a scan.
        local scheduled, scheduleError = pcall(self.schedule, Scanner.TIMEOUT_SECONDS, function()
            if self.requestToken ~= token or not self:IsActive() then return end
            local dispatched = self.state ~= "WAITING"
            self.uncertainQuery = dispatched
            self.stopBatchReason = dispatched and "UNKNOWN: reopen AH" or "TIMEOUT: throttle not ready"
            self:Fail(dispatched and "UNKNOWN: result timeout; close/reopen AH before scanning again"
                or "UNKNOWN: throttle wait timed out before dispatch")
        end)
        if not scheduled then
            self.stopBatchReason = "UNKNOWN: scan deadline unavailable"
            self:Fail("UNKNOWN: scan deadline unavailable: " .. tostring(scheduleError))
            return
        end
    end
    self:TryQuery()
end

function Scanner:TryQuery()
    if not self.ahOpen or self.state ~= "WAITING" then return end
    local ready, err = self.api:IsReady()
    if ready == nil then
        self.stopBatchReason = "UNKNOWN: throttle readiness unavailable"
        self:Fail(err)
        return
    end
    if not ready then
        self.notify("throttle not ready; waiting for system-ready event. " .. self:Summary())
        return
    end
    self.state = "QUERYING"
    local ok, queryError, uncertain = self.api:QueryCommodity(self.itemID)
    if not ok then
        self.uncertainQuery = uncertain ~= false
        self:Fail(queryError)
        return
    end
    self.queryCount = self.queryCount + 1
    self.notify("one query sent; waiting for matching commodity result. " .. self:Summary())
end

function Scanner:OnReady()
    self:TryQuery()
end

function Scanner:OnCommodityResults(itemID)
    if not self.ahOpen or self.state ~= "QUERYING" then return end
    if itemID ~= self.itemID then
        self.notify("ignored mismatched commodity result; expected itemID=" .. self.itemID)
        return
    end
    self.state = "COLLECTING"
    self.notify("collecting commodity results. " .. self:Summary())
    local levels, err = self.api:ReadCommodityResults(self.itemID)
    if not levels then self:Fail(err); return end
    local summary = { levelCount = #levels, totalQuantity = 0 }
    for _, level in ipairs(levels) do
        if level.quantity > MAX_INTEGER - summary.totalQuantity then
            self:Fail("UNKNOWN: total quantity exceeds exact integer range")
            return
        end
        summary.totalQuantity = summary.totalQuantity + level.quantity
        summary.lowest = summary.lowest and math.min(summary.lowest, level.unitPrice) or level.unitPrice
        summary.highest = summary.highest and math.max(summary.highest, level.unitPrice) or level.unitPrice
    end
    self.sample = { itemID = self.itemID, capturedAt = self.clock(), priceLevels = levels }
    local analysis, analysisError = MP.Statistics.Analyze(self.sample)
    if not analysis then self:Fail(analysisError); return end
    self.analysis = analysis
    self.requestToken = nil
    self.summary, self.error, self.state = summary, nil, "DONE"
    self.notify(self:Summary())
end
