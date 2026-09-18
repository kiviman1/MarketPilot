local _, MP = ...
local Sale = {}
Sale.__index = Sale
MP.SaleAssistant = Sale

function Sale.New(inventory, scanner, api, pricing, report)
    return setmetatable({ inventory = inventory, scanner = scanner, api = api, pricing = pricing,
        report = report, duration = 12 }, Sale)
end

function Sale:RefreshInventory()
    self.inventory:Refresh()
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
    self.quantity, self.probe, self.message = quantity, nil, nil
    return true
end

function Sale:SetDuration(hours)
    if hours ~= 12 and hours ~= 24 and hours ~= 48 then
        self.message = "Duration must be 12h, 24h or 48h."; return false
    end
    self.duration, self.probe, self.message = hours, nil, nil
    return true
end

function Sale:Analysis()
    local scanner = self.scanner
    if scanner.ahOpen and scanner.state == "DONE" and scanner.sample
        and scanner.sample.itemID == self.itemID then return scanner.analysis end
end

function Sale:State()
    local analysis = self:Analysis()
    local message = self.message
    if not message and self.itemID and not analysis then
        message = self.scanner.error or "No completed market analysis for this sale item. Select it or refresh its scan."
    end
    return { itemID = self.itemID, owned = self.itemID and self.inventory:Owned(self.itemID), quantity = self.quantity,
        duration = self.duration, inventory = self.inventory, message = message,
        scanState = self.scanner.ahOpen and self.scanner.state or "AH CLOSED",
        enabled = self.scanner.ahOpen and not self.scanner:IsActive() and not self.scanner.blockedReason,
        lowest = analysis and analysis.raw and analysis.raw.min,
        targets = self.pricing.Targets(analysis), capabilities = self.probe or self.api:SellCapabilities() }
end

function Sale:CheckCapabilities()
    if not self.scanner.ahOpen then self.message = "UNKNOWN: open AH before sell checks"; return false end
    self:RefreshInventory() -- Re-read counts/slots even if a bag event was delayed.
    local location, locationError
    if self.itemID then location, locationError = self.inventory:Location(self.itemID) end
    self.probe = self.api:ProbeSell(self.itemID, location, self.quantity, self.duration, locationError)
    self.report("sell probe: candidate observations only; posting DISABLED; itemID=" .. tostring(self.itemID)
        .. " quantity=" .. tostring(self.quantity) .. " durationHours=" .. self.duration)
    for _, row in ipairs(self.probe.capabilities) do
        self.report(row.name .. " presence=" .. row.presence .. " status=" .. row.status
            .. " value=" .. (row.value == nil and "UNKNOWN" or tostring(row.value))
            .. " " .. row.detail)
    end
    return true
end

function Sale:Close()
    self.itemID, self.quantity, self.probe, self.message = nil, nil, nil, nil
    self.inventory:Invalidate("UNKNOWN: AH closed")
end
