local _, MP = ...
local UI = {}
UI.__index = UI
MP.UI = UI

local WIDTH, HEIGHT = 440, 650
local FIELDS = {
    { "Current lowest", "lowest" }, { "Raw median", "rawMedian" },
    { "Clean median", "cleanMedian" }, { "Clean Q1-Q3", "range" },
    { "Total quantity", "quantity" }, { "Price levels", "levels" },
    { "Suspicious", "suspicious" }, { "Extreme", "extreme" },
    { "Anomaly model", "sufficient" }, { "Scanner", "state" },
}
local HISTORY_FIELDS = {
    { "24h median", "median1" }, { "7d median", "median7" }, { "30d median", "median30" },
    { "7d / 30d change", "changes" }, { "Trend (7d window)", "trend" }, { "30d percentile", "percentile" },
    { "Return volatility", "volatility" }, { "Supply / 7d", "supply" }, { "Significance", "significance" },
    { "Last scan", "lastScan" }, { "Observations", "observations" },
}
local COLUMNS = { { "Now", "now", 123, 74 }, { "7d", "change", 200, 45 }, { "Trend", "trend", 247, 32 },
    { "30d %", "percentile", 282, 40 }, { "Supply", "supply", 326, 45 }, { "Maturity", "maturity", 374, 62 } }

function UI.New(scanner, items, report, market, batch, clock)
    return setmetatable({ scanner = scanner, items = items, report = report,
        market = market, batch = batch, clock = clock, historyValues = {},
        selectedItemID = scanner.itemID, collapsed = false, rows = {}, values = {} }, UI)
end

function UI:Warn(message)
    if self.lastWarning ~= message then self.report("panel UNKNOWN: " .. message) end
    self.lastWarning = message
end

function UI:Guard(callback, ...)
    local ok, err = pcall(callback, self, ...)
    if not ok then self:Close(); self:Warn(tostring(err)) end
    return ok
end

function UI:Toggle()
    self.collapsed = not self.collapsed
    self:Update()
end

function UI:IsReadOnly()
    return self.mode == "STANDALONE" or not self.scanner.ahOpen
end

function UI:ToggleWatch()
    if self.frame and self.frame:IsShown() then
        self.watchRequested = false
        self:Close()
    else
        self.watchRequested = true
        self:Open()
    end
end

function UI:OnHouseClosed()
    if self.watchRequested then self:Open() else self:Close() end
end

function UI:ClickItem(itemID)
    if not self.items.Contains(itemID) then return false end
    if self.mode == "STANDALONE" or self.batch.active then
        self.selectedItemID = itemID; self:Update(); return true
    end
    if not self.scanner.ahOpen or self.scanner:IsActive()
        or self.scanner.blockedReason then return false end
    self.selectedItemID = itemID
    self.scanner:Start(itemID)
    self:Update()
    return true
end

function UI:Scan()
    if self:IsReadOnly() or self.batch.active then return false end
    return self:ClickItem(self.selectedItemID)
end

function UI:StartBatch()
    if self:IsReadOnly() then return false end
    self.batch:Start(); self:Update()
end
function UI:CancelBatch()
    if self:IsReadOnly() then return false end
    self.batch:Cancel(); self:Update()
end
function UI:ToggleReport() self.reportMode = not self.reportMode; self:Update() end
function UI:Scroll(delta)
    self.scroll:SetVerticalScroll(math.max(0, math.min(self.scrollLimit, self.scroll:GetVerticalScroll() + delta)))
end

local function label(parent, text, x, y, width, font)
    local value = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    value:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    value:SetWidth(width)
    value:SetJustifyH("LEFT")
    value:SetText(text)
    return value
end

function UI:Create(anchor)
    local panel = CreateFrame("Frame", nil, anchor)
    self.frame = panel
    panel:Hide()
    panel:SetSize(WIDTH, HEIGHT)
    panel:EnableMouse(true)
    local background = panel:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(panel)
    background:SetColorTexture(0.035, 0.045, 0.06, 0.97)
    local accent = panel:CreateTexture(nil, "BORDER")
    accent:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    accent:SetSize(WIDTH, 2)
    accent:SetColorTexture(0.65, 0.52, 0.27, 1)
    label(panel, "MARKETPILOT - MARKET WATCH", 14, -13, WIDTH - 60, "GameFontNormal")
    self.toggle = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    self.toggle:SetSize(28, 24)
    self.toggle:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -9)
    self.toggle:SetScript("OnClick", function() self:Guard(self.Toggle) end)

    self.scroll = CreateFrame("ScrollFrame", nil, panel)
    self.scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -42)
    self.scroll:SetSize(WIDTH, HEIGHT - 74)
    self.scroll:EnableMouseWheel(true)
    self.scroll:SetScript("OnMouseWheel", function(_, delta) self:Guard(self.Scroll, -delta * 75) end)
    self.body = CreateFrame("Frame", nil, self.scroll)
    self.body:SetSize(WIDTH, HEIGHT)
    self.scroll:SetScrollChild(self.body)
    local function button(text, parent, x, y, width, action)
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y); b:SetSize(width, 24); b:SetText(text)
        b:SetScript("OnClick", function() self:Guard(action) end)
        return b
    end
    self.batchButton = button("Scan Gathering Markets", self.body, 14, -2, 218, self.StartBatch)
    self.cancelButton = button("Cancel", self.body, 237, -2, 76, self.CancelBatch)
    self.reportButton = button("Market Report", self.body, 318, -2, 110, self.ToggleReport)
    self.progress = label(self.body, "", 14, -30, WIDTH - 28)
    self.historyStatus = label(self.body, "", 14, -50, WIDTH - 28)
    label(self.body, "Item", 14, -72, 106)
    for _, col in ipairs(COLUMNS) do label(self.body, col[1], col[3], -72, col[4]) end
    local y = -94
    for _, category in ipairs(self.items.categories) do
        label(self.body, category.name, 14, y, WIDTH - 28, "GameFontNormalSmall")
        y = y - 18
        for _, id in ipairs(category.itemIDs) do
            local itemID = id
            local row = CreateFrame("Button", nil, self.body)
            row:SetSize(WIDTH - 28, 22)
            row:SetPoint("TOPLEFT", self.body, "TOPLEFT", 14, y)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(18, 18)
            row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
            row.text = label(row, "", 26, -4, 78)
            row.columns = {}
            for _, col in ipairs(COLUMNS) do row.columns[col[2]] = label(row, "?", col[3] - 14, -4, col[4]) end
            row.selection = row:CreateTexture(nil, "BACKGROUND")
            row.selection:SetAllPoints(row)
            row.selection:SetColorTexture(0.2, 0.35, 0.48, 0.65)
            row:SetScript("OnClick", function() self:Guard(self.ClickItem, itemID) end)
            self.rows[itemID] = row
            y = y - 23
        end
        y = y - 5
    end
    self.detail = CreateFrame("Frame", nil, self.body)
    self.detail:SetPoint("TOPLEFT", self.body, "TOPLEFT", 0, y)
    local detailTop = y
    self.detail:SetSize(WIDTH, 800)
    self.reportText = label(self.body, "", 14, y, WIDTH - 28)
    self.reportText:SetHeight(720); self.reportText:SetJustifyV("TOP"); self.reportText:Hide()
    y = -3
    self.name = label(self.detail, "", 14, y, WIDTH - 28, "GameFontNormal")
    self.name:SetHeight(30)
    y = y - 37
    for _, field in ipairs(FIELDS) do
        label(self.detail, field[1], 14, y, 135)
        self.values[field[2]] = label(self.detail, "UNKNOWN", 155, y, WIDTH - 169)
        self.values[field[2]]:SetJustifyH("RIGHT")
        self.values[field[2]]:SetHeight(26)
        y = y - 22
    end
    for _, field in ipairs(HISTORY_FIELDS) do
        label(self.detail, field[1], 14, y, 135)
        self.historyValues[field[2]] = label(self.detail, "INSUFFICIENT", 155, y, WIDTH - 169)
        y = y - 22
    end
    self.exclusion = label(self.detail, "", 14, y, WIDTH - 28)
    self.exclusion:SetHeight(28)
    self.message = label(self.detail, "", 14, y - 30, WIDTH - 28)
    self.message:SetHeight(36)
    self.scan = CreateFrame("Button", nil, self.detail, "UIPanelButtonTemplate")
    self.scan:SetPoint("TOPLEFT", self.detail, "TOPLEFT", 14, y - 70)
    self.scan:SetSize(WIDTH - 28, 26)
    self.scan:SetScript("OnClick", function() self:Guard(self.Scan) end)
    label(self.detail, "7d sparkline: deferred; numeric history above.", 14, y - 106, WIDTH - 28)
    self.expandedHeight = HEIGHT
    local contentHeight = -detailTop + math.max(740, -y + 135)
    self.body:SetHeight(contentHeight)
    self.scrollLimit = contentHeight - (HEIGHT - 74)
    self.footer = CreateFrame("Frame", nil, panel)
    self.footer:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0); self.footer:SetSize(WIDTH, 30)
    label(self.footer, "^ rising  v falling  = stable  ? insufficient", 14, -8, 328)
    button("Up", self.footer, 340, -3, 40, function(s) s:Scroll(-250) end)
    button("Down", self.footer, 384, -3, 42, function(s) s:Scroll(250) end)
end

function UI:Open()
    if not self.scanner.ahOpen and not self.watchRequested then return false end
    local mode = self.scanner.ahOpen and "AH" or "STANDALONE"
    -- Top-level parents only; switching mode never queries or changes history.
    local anchor, anchorName
    if mode == "AH" then anchor, anchorName = AuctionHouseFrame, "AuctionHouseFrame"
    else anchor, anchorName = UIParent, "UIParent" end
    if (type(anchor) ~= "table" and type(anchor) ~= "userdata") or type(anchor.GetObjectType) ~= "function" then
        self:Close()
        self:Warn(anchorName .. " unavailable; panel hidden. Debug commands remain available.")
        return false
    end
    local ok, err = pcall(function()
        if not self.frame then self:Create(anchor) end
        self.frame:Hide()
        self.frame:SetParent(anchor)
        self.frame:ClearAllPoints()
        if mode == "AH" then self.frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
        else self.frame:SetPoint("CENTER", anchor, "CENTER", 0, 0) end
        self.anchor, self.mode = anchor, mode
        self.items.InvalidateMetadata()
        self:Update()
        self.frame:Show()
    end)
    if not ok then
        if self.frame then self.frame:Hide() end
        if not self.anchor then self.frame, self.rows, self.values, self.historyValues = nil, {}, {}, {} end
        self:Warn(tostring(err))
        return false
    end
    self.lastWarning = nil
    return true
end

function UI:Close()
    if self.frame then self.frame:Hide() end
end

function UI:Update()
    local readOnly = self.mode == "STANDALONE"
    self.view = MP.UIViewModel.Build(self.scanner, self.selectedItemID, self.items.Metadata(self.selectedItemID), readOnly)
    if not self.frame or not self.anchor then return end
    if not self.scanner.ahOpen and not readOnly then self:Close(); return end
    local view = self.view
    self.frame:SetHeight(self.collapsed and 42 or self.expandedHeight)
    self.toggle:SetText(self.collapsed and "+" or "-")
    if self.collapsed then self.body:Hide(); self.scroll:Hide(); self.footer:Hide()
    else self.body:Show(); self.scroll:Show(); self.footer:Show() end
    local data = self.market:Get(self.selectedItemID)
    -- A completed historical observation remains visible after reopening AH.
    if data.current and (readOnly or self.scanner.state == "IDLE" or self.scanner.itemID ~= self.selectedItemID) then
        local s = data.current
        view.lowest, view.rawMedian, view.cleanMedian = MP.UIViewModel.Money(s.lowest), MP.UIViewModel.Money(s.rawMedian), MP.UIViewModel.Money(s.cleanMedian)
        view.range = MP.UIViewModel.Money(s.q1) .. " - " .. MP.UIViewModel.Money(s.q3)
        view.quantity, view.levels = tostring(s.totalQuantity), tostring(s.levelCount)
        view.suspicious, view.extreme = tostring(s.suspicious), tostring(s.extreme)
        view.sufficient = s.anomalySufficient and "SUFFICIENT" or "INSUFFICIENT"
        view.exclusion = "Extreme outliers excluded: " .. s.extreme .. ". Suspicious retained."
        view.message = "Stored observation; see last scan age."
    end
    if data.error then view.message = data.error end
    if self.reportMode then self.detail:Hide(); self.reportText:Show()
        self.reportText:SetText(MP.UIViewModel.Report(self.market:Report(), self.items))
    else self.reportText:Hide(); self.detail:Show() end
    local history = MP.UIViewModel.History(data, self.clock())
    history.changes = history.change7 .. " / " .. history.change30
    for key, widget in pairs(self.historyValues) do widget:SetText(history[key]) end
    self.progress:SetText(readOnly and "READ ONLY | Stored history | Open AH to scan"
        or self.batch.state .. "  " .. self.batch.completed .. " / " .. self.batch.total .. "  |  " .. self.scanner.state)
    self.historyStatus:SetText(self.market.db.status == "OK" and "History: account-wide / realm + faction" or self.market.db.error)
    if self:IsReadOnly() or self.batch.active or self.scanner:IsActive() or self.scanner.uncertainQuery then self.batchButton:Disable() else self.batchButton:Enable() end
    if not self:IsReadOnly() and self.batch.active then self.cancelButton:Enable() else self.cancelButton:Disable() end
    self.name:SetText(view.name)
    for _, field in ipairs(FIELDS) do self.values[field[2]]:SetText(view[field[2]]) end
    self.message:SetText(view.message)
    self.exclusion:SetText(view.exclusion)
    self.scan:SetText(view.buttonText)
    if view.scanEnabled and not self.batch.active then self.scan:Enable() else self.scan:Disable() end
    for itemID, row in pairs(self.rows) do
        local info = self.items.Metadata(itemID)
        row.text:SetText(info.name)
        row.icon:SetTexture(info.icon)
        local watch = MP.UIViewModel.Watch(self.market:Get(itemID))
        for key, widget in pairs(row.columns) do widget:SetText(watch[key]) end
        if itemID == view.itemID then row.selection:Show() else row.selection:Hide() end
        if view.itemsEnabled or self.batch.active then row:Enable() else row:Disable() end
    end
end

function UI:MetadataReceived(itemID, success)
    if success == true and self.items.Contains(itemID) and self.items.InvalidateMetadata(itemID) then
        self:Update()
    end
end
