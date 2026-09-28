local _, MP = ...
local Batch = {}
Batch.__index = Batch
MP.BatchScanner = Batch
function Batch.New(scanner, items)
    return setmetatable({ scanner = scanner, items = items, active = false, state = "IDLE", completed = 0, total = 0, results = {} }, Batch)
end
function Batch:Start()
    if self.active or self.scanner:IsActive() or not self.scanner.ahOpen or self.scanner.uncertainQuery then return false end
    self.queue, self.results = self.items.List(), {}
    self.total, self.completed, self.pending = #self.queue, 0, nil
    self.active, self.state = true, "RUNNING"
    self:Advance()
    return true
end
function Batch:Advance()
    if self.advancing then return end
    self.advancing = true
    while self.active do
        if not self.scanner.ahOpen then self:Cancel(); break end
        if self.pending then
            if self.scanner:IsActive() then break end
            self.results[self.pending] = { state = self.scanner.state, error = self.scanner.error }
            self.completed, self.pending = self.completed + 1, nil
            if self.scanner.uncertainQuery then self.active, self.state = false, "UNKNOWN: reopen AH"; break end
            if self.scanner.stopBatchReason then self.active, self.state = false, self.scanner.stopBatchReason; break end
        end
        if self.completed >= self.total then self.active, self.state = false, "DONE"; break end
        self.pending = self.queue[self.completed + 1]
        self.scanner:Start(self.pending)
    end
    self.advancing = false
end
function Batch:Cancel()
    self.active, self.state, self.pending = false, "CANCELLED", nil
    -- A dispatched query cannot be recalled. Drain its reply before another request.
    if self.scanner.state == "WAITING" then self.scanner:CancelWaiting() end
end
