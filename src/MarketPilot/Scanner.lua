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
        .. " browse=" .. (self.browse and self.browse.phase or "NONE")
        .. (self.browseError and " browseError=" .. self.browseError or "")
        .. " deadline=" .. (self.schedule and (Scanner.TIMEOUT_SECONDS .. "s") or "UNAVAILABLE")
        .. " (copper/unit)" .. (self.error and " error=" .. self.error or "")
end

function Scanner:Fail(reason)
    self.requestToken = nil
    self.browse = nil
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
    self.browse, self.browseError = nil, nil
    self.stopBatchReason = nil
    self.uncertainQuery = nil
    self.analysis = nil
    self.ahOpen = false
    self.state, self.sample, self.summary, self.error = "IDLE", nil, nil, nil
    self.notify("AH closed; scan cancelled/reset. " .. self:Summary())
end

function Scanner:IsActive()
    return ACTIVE[self.state] == true or self.browse ~= nil
end

function Scanner:CancelWaiting()
    if self.state == "WAITING" then
        self.requestToken = nil
        self.browse = nil
        self.state, self.error = "IDLE", nil
        self.notify("pending scan cancelled before dispatch. " .. self:Summary())
    end
end

function Scanner:Start(itemID, openBrowse)
    if self.uncertainQuery then
        if self.state == "DONE" and self.browseError then
            self.notify("AH browse outcome uncertain; close/reopen AH. " .. self:Summary())
        else self:Fail("UNKNOWN: prior dispatch uncertain; close/reopen AH") end
        return
    end
    if self:IsActive() then
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
    self.browse, self.browseError = nil, nil
    self.analysis = nil
    if not self.ahOpen then self:Fail("AH is closed; open it before /mp scan"); return end
    local available, err = self.api:IsAvailable()
    if not available then
        self.stopBatchReason = "UNKNOWN: Auction API unavailable"
        self:Fail(err)
        return
    end
    if openBrowse then
        if self.browseBlockedReason then self.browseError = self.browseBlockedReason
        elseif not self.schedule then self.browseError = "UNKNOWN: AH browse deadline unavailable"
        else
            local request, reason = self.api:PrepareBrowse(self.itemID)
            if request then self.browse = { name = request.name, phase = "QUEUED" }
            else self.browseError = reason end
        end
    end
    self.state = "WAITING"
    if self.schedule then
        local token = {}
        self.requestToken = token
        -- One deadline per player-requested scan; no polling, retry or timer
        -- renewal on throttle events. Superseded callbacks cannot affect a scan.
        local scheduled, scheduleError = pcall(self.schedule, Scanner.TIMEOUT_SECONDS, function()
            if self.requestToken ~= token or not self:IsActive() then return end
            if self.state == "DONE" and self.browse then
                local dispatched = self.browse.phase == "QUERYING"
                self:FinishBrowse(dispatched and "UNKNOWN: AH browse timed out; close/reopen AH"
                    or "UNKNOWN: AH browse throttle wait timed out", dispatched)
                return
            end
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
    if self.state == "DONE" and self.browse then self:TryBrowse(); self:CheckBrowseCompletion()
    else self:TryQuery() end
end

-- Navigation is a second, serialized query requested only by an explicit row
-- click. Keep the completed commodity sample; browse rows are never persisted.
function Scanner:FinishBrowse(reason, uncertain)
    self.requestToken, self.browse = nil, nil
    self.browseError = reason
    if uncertain then self.uncertainQuery = true end
    self.notify(self:Summary())
end

function Scanner:TryBrowse()
    if not self.ahOpen or self.state ~= "DONE" or not self.browse or self.browse.phase ~= "WAITING" then return end
    local ready, reason = self.api:IsReady()
    if ready == nil then self:FinishBrowse(reason, false); return end
    if not ready then return end
    self.browse.phase = "QUERYING"
    local ok, err, uncertain = self.api:QueryBrowse(self.browse.name)
    if not ok then self:FinishBrowse(err, uncertain ~= false); return end
    self.notify(self:Summary())
end

function Scanner:OnBrowseResults()
    if self.ahOpen and self.state == "DONE" and self.browse and self.browse.phase == "QUERYING" then
        self.browse.resultSeen = true
        self:CheckBrowseCompletion()
    end
end

function Scanner:CheckBrowseCompletion()
    if not self.ahOpen or not self.browse or self.browse.phase ~= "QUERYING" or not self.browse.resultSeen then return end
    -- The browse event has no request ID and can also accompany commodity
    -- results. An event alone must not unlock another query while AH is busy
    -- or its browse cache is incomplete. Check on events only, never poll.
    local ready, reason = self.api:AreBrowseResultsReady()
    if ready == nil then self:FinishBrowse(reason, true)
    elseif ready then self:FinishBrowse() end
end

function Scanner:OnBrowseFailure()
    if self.ahOpen and self.state == "DONE" and self.browse and self.browse.phase == "QUERYING" then
        self:FinishBrowse("UNKNOWN: Blizzard AH browse failed; close/reopen AH", true)
    end
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
    if self.browse then self.browse.phase = "WAITING" else self.requestToken = nil end
    self.summary, self.error, self.state = summary, nil, "DONE"
    self.notify(self:Summary())
    self:TryBrowse()
end
