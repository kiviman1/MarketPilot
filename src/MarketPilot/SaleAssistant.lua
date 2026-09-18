local _, MP = ...
local Sale = {}
Sale.__index = Sale
MP.SaleAssistant = Sale

function Sale.New(inventory, scanner, api, pricing, report, clock)
    return setmetatable({ inventory = inventory, scanner = scanner, api = api, pricing = pricing,
        report = report, clock = clock, duration = 12 }, Sale)
end

function Sale:InvalidatePlan(reason)
    if self.plan then self.planNotice = "Prepared sale cancelled: " .. reason end
    self.plan, self.planContext = nil, nil
end

function Sale:OnScannerChanged()
    if self.plan and (self.scanner.state ~= "DONE" or self.scanner.sample ~= self.planContext.sample
        or self.scanner.analysis ~= self.planContext.analysis or not self.scanner.ahOpen) then
        self:InvalidatePlan("market scan changed")
    end
end

function Sale:RefreshInventory()
    self:InvalidatePlan("bag data changed/refreshed")
    self.inventory:Refresh()
    self.probeContext = nil
    self.probe = nil -- Never retain deposit/location observations across bag changes.
    local owned = self.inventory:Owned(self.itemID)
    if not owned or owned == 0 then
        self.itemID, self.quantity = nil, nil
    elseif not self.quantity or self.quantity > owned then self.quantity = owned end
    self.message = self.inventory.error
    if self.message and self.message ~= self.lastWarning then self.report(self.message) end
    self.lastWarning = self.message
end

function Sale:Select(itemID)
    if not self.scanner.ahOpen or self.scanner:IsActive() or self.scanner.blockedReason then return false end
    self:RefreshInventory()
    local owned = self.inventory:Owned(itemID)
    if not owned or owned < 1 then self.message = "UNKNOWN: item unavailable in bags"; return false end
    if self.itemID ~= itemID then self.quantity = owned end
    self.itemID, self.message = itemID, nil
    local sample = self.scanner.sample
    if not (self.scanner.state == "DONE" and sample and sample.itemID == itemID and self.scanner.analysis) then
        self.scanner:Start(itemID)
    end
    return true
end

function Sale:SetQuantity(quantity)
    local owned = self.inventory:Owned(self.itemID)
    if not owned or type(quantity) ~= "number" or quantity < 1 or quantity > owned or quantity % 1 ~= 0 then
        self.message = "Quantity must be a whole number from 1 to owned count."
        return false
    end
    if self.quantity ~= quantity then
        self:InvalidatePlan("quantity changed")
        self.probe, self.probeContext = nil, nil
    end
    self.quantity, self.message = quantity, nil
    return true
end

function Sale:SetDuration(hours)
    if hours ~= 12 and hours ~= 24 and hours ~= 48 then
        self.message = "Duration must be 12h, 24h or 48h."; return false
    end
    if self.duration ~= hours then
        self:InvalidatePlan("duration changed")
        self.probe, self.probeContext = nil, nil
    end
    self.duration, self.message = hours, nil
    return true
end

function Sale:SetTarget(kind)
    local keys = { FAST = "fast", NORMAL = "normal", PATIENT = "patient" }
    local target = keys[kind] and self.pricing.Targets(self:Analysis())[keys[kind]]
    if not target or target.status ~= "OK" then self.message = "INSUFFICIENT/UNKNOWN target"; return false end
    if self.targetKind ~= kind then self:InvalidatePlan("target changed") end
    self.targetKind, self.message = kind, nil
    return true
end

function Sale:PlanInput(targets)
    local evidence, observed = self.probeContext, {}
    for _, row in ipairs(self.probe and self.probe.capabilities or {}) do observed[row.name] = row end
    local valid, copper, present = observed.IsSellItemValid, observed.SupportsCopperValues, observed.PostCommodity
    local analysis = self:Analysis()
    return { ahOpen = self.scanner.ahOpen, active = self.scanner:IsActive(), scannerState = self.scanner.state,
        scanItemID = self.scanner.sample and self.scanner.sample.itemID, itemID = self.itemID,
        owned = self.inventory:Owned(self.itemID), quantity = self.quantity, durationHours = self.duration,
        targetKind = self.targetKind, targets = targets or self.pricing.Targets(analysis),
        sufficient = analysis and analysis.anomaly and analysis.anomaly.sufficient,
        evidenceFresh = evidence ~= nil and evidence.itemID == self.itemID and evidence.quantity == self.quantity
            and evidence.duration == self.duration and evidence.generation == self.inventory.generation,
        sellValid = valid and valid.status == "CANDIDATE_OBSERVED" and valid.value == true,
        copperSupported = copper and copper.status == "CANDIDATE_OBSERVED" and copper.value == true,
        postPresent = present and present.presence == "PRESENT" }
end

function Sale:Prepare()
    self:InvalidatePlan("new preparation")
    local input = self:PlanInput()
    local price, err = MP.SalePlan.Validate(input)
    if not price then self.message = err; return false end
    if not self.inventory:MatchesSnapshot() then
        self:RefreshInventory()
        self.message = "UNKNOWN: bags changed; select/check the item again."
        return false
    end
    -- Client reads can dispatch synchronous events; validate current evidence again.
    local plan, planError = MP.SalePlan.Create(self:PlanInput(), self.clock and self.clock())
    if not plan then self.message = planError; return false end
    self.plan = plan
    self.planContext = { sample = self.scanner.sample, analysis = self.scanner.analysis }
    self.message, self.planNotice = nil, nil
    return true
end

function Sale:Cancel()
    self:InvalidatePlan("user cancelled")
end

function Sale:Analysis()
    local scanner = self.scanner
    if scanner.ahOpen and scanner.state == "DONE" and scanner.sample
        and scanner.sample.itemID == self.itemID then return scanner.analysis end
end

function Sale:State()
    self:OnScannerChanged()
    local analysis = self:Analysis()
    local targets = self.pricing.Targets(analysis)
    local available, prepareReason = MP.SalePlan.Validate(self:PlanInput(targets))
    local message = self.message or self.planNotice
    if not message and self.itemID and not analysis then
        message = self.scanner.error or "No completed market analysis for this sale item. Select it or refresh its scan."
    end
    return { itemID = self.itemID, owned = self.itemID and self.inventory:Owned(self.itemID), quantity = self.quantity,
        duration = self.duration, inventory = self.inventory, message = message,
        scanState = self.scanner.ahOpen and self.scanner.state or "AH CLOSED",
        enabled = self.scanner.ahOpen and not self.scanner:IsActive() and not self.scanner.blockedReason,
        lowest = analysis and analysis.raw and analysis.raw.min,
        targets = targets, capabilities = self.probe or self.api:SellCapabilities(), targetKind = self.targetKind,
        plan = self.plan, prepareEnabled = available ~= nil, prepareReason = prepareReason }
end

function Sale:CheckCapabilities()
    self:InvalidatePlan("sell capability check requested")
    if not self.scanner.ahOpen then self.message = "UNKNOWN: open AH before sell checks"; return false end
    self:RefreshInventory() -- Re-read counts/slots even if a bag event was delayed.
    local context = { itemID = self.itemID, quantity = self.quantity, duration = self.duration,
        generation = self.inventory.generation }
    local location, locationError
    if context.itemID then location, locationError = self.inventory:Location(context.itemID) end
    self.probe = self.api:ProbeSell(context.itemID, location, context.quantity, context.duration, locationError)
    self.probeContext = context -- A synchronous bag event during a candidate call makes this stale.
    self.report("sell probe: candidate observations only; posting DISABLED; itemID=" .. tostring(context.itemID)
        .. " quantity=" .. tostring(context.quantity) .. " durationHours=" .. context.duration)
    for _, row in ipairs(self.probe.capabilities) do
        self.report(row.name .. " presence=" .. row.presence .. " status=" .. row.status
            .. " value=" .. (row.value == nil and "UNKNOWN" or tostring(row.value))
            .. " " .. row.detail)
    end
    return true
end

function Sale:Close()
    self:InvalidatePlan("AH closed")
    self.probeContext = nil
    self.itemID, self.quantity, self.probe, self.message = nil, nil, nil, nil
    self.inventory:Invalidate("UNKNOWN: AH closed")
end
