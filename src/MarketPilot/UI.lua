local _, MP = ...
local UI = {}
UI.__index = UI
MP.UI = UI

local WIDTH, HEIGHT = 440, 650
local PAGE_SIZE = 6
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
local COLUMNS = { { "Now", "now", 155, 65 }, { "7d", "change", 220, 43 }, { "Trend", "trend", 265, 30 },
    { "30d %", "percentile", 296, 35 }, { "Supply", "supply", 333, 40 }, { "Maturity", "maturity", 375, 62 } }

function UI.New(scanner, items, report, market, batch, clock)
    return setmetatable({ scanner = scanner, items = items, report = report,
        market = market, batch = batch, clock = clock, historyValues = {},
        selectedItemID = scanner.itemID, collapsed = false, rows = {}, values = {},
        category = "All", page = 1, detailMode = "CURRENT" }, UI)
end

function UI:Warn(message)
    if self.lastWarning ~= message then self.report("Panel could not be shown: " .. message) end
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
    return self.demoInfo ~= nil or self.mode == "STANDALONE" or not self.scanner.ahOpen
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
    self.reportMode = false
    if self:IsReadOnly() or self.batch.active then
        self.selectedItemID = itemID; self:Update(); return true
    end
    if not self.scanner.ahOpen or self.scanner:IsActive()
        or self.scanner.blockedReason or self.scanner.uncertainQuery then return false end
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
    if self:IsReadOnly() or self.scanner.uncertainQuery or self.scanner.blockedReason then return false end
    self.batch:Start(); self:Update()
end
function UI:CancelBatch()
    if self:IsReadOnly() then return false end
    self.batch:Cancel(); self:Update()
end
function UI:ToggleReport()
    if not self.frame or not self.frame:IsShown() then
        self.watchRequested = true
        if not self:Open() then return false end
        self.reportMode = true
    else self.reportMode = not self.reportMode end
    self.collapsed = false
    if self.scroll then self.scroll:SetVerticalScroll(0) end
    self:Update()
end
function UI:SetCategory(category)
    if #self.items.List(category) == 0 then return false end
    self.category, self.page = category, 1
    self:Update()
end
function UI:Page(delta)
    local pages = math.max(1, math.ceil(#self.items.List(self.category) / PAGE_SIZE))
    self.page = math.max(1, math.min(pages, self.page + delta))
    self:Update()
end
function UI:Detail(mode)
    self.detailMode = mode; self:Update()
end
function UI:Scroll(delta)
    self.scroll:SetVerticalScroll(math.max(0, math.min(self.scrollLimit, self.scroll:GetVerticalScroll() + delta)))
end

local function label(parent, text, x, y, width, font)
    local value = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    value:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    value:SetWidth(width)
    if value.SetWordWrap then value:SetWordWrap(false) end
    value:SetJustifyH("LEFT")
    value:SetText(text)
    return value
end

function UI:Create(anchor)
    local panel = CreateFrame("Frame", nil, anchor)
    self.frame = panel
    panel:Hide()
    panel:SetSize(WIDTH, HEIGHT)
    if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
    panel:EnableMouse(true)
    local background = panel:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(panel)
    background:SetColorTexture(0.035, 0.045, 0.06, 0.97)
    local accent = panel:CreateTexture(nil, "BORDER")
    accent:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    accent:SetSize(WIDTH, 2)
    accent:SetColorTexture(0.65, 0.52, 0.27, 1)
    label(panel, "MARKETPILOT - MARKET WATCH", 14, -13, WIDTH - 100, "GameFontNormal")
    self.toggle = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    self.toggle:SetSize(28, 24)
    self.toggle:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -44, -9)
    self.toggle:SetScript("OnClick", function() self:Guard(self.Toggle) end)
    self.closeButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    self.closeButton:SetSize(28, 24)
    self.closeButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -9)
    self.closeButton:SetText("x")
    self.closeButton:SetScript("OnClick", function() self:Guard(self.ToggleWatch) end)

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
    self.historyStatus:SetWidth(326)
    self.demoButton = button("30d Demo", self.body, 346, -45, 80, function(s)
        if s.onDemo then s.onDemo() end
    end)
    self.catalogue = CreateFrame("Frame", nil, self.body)
    self.catalogue:SetPoint("TOPLEFT", self.body, "TOPLEFT", 0, -72)
    self.catalogue:SetSize(WIDTH, 218)
    self.categoryButtons = {}
    for index, name in ipairs({ "All", "Mining", "Herbalism", "Skinning" }) do
        local category = name
        self.categoryButtons[name] = button(name, self.catalogue, 14 + (index - 1) * 104, 0, 100,
            function(s) s:SetCategory(category) end)
    end
    label(self.catalogue, "Item", 14, -31, 138)
    for _, col in ipairs(COLUMNS) do label(self.catalogue, col[1], col[3], -31, col[4]) end
    local y = -51
    for _, category in ipairs(self.items.categories) do
        for _, id in ipairs(category.itemIDs) do
            local itemID = id
            local row = CreateFrame("Button", nil, self.catalogue)
            row:SetSize(WIDTH - 28, 22)
            row:SetPoint("TOPLEFT", self.catalogue, "TOPLEFT", 14, y)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(18, 18)
            row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
            row.text = label(row, "", 26, -4, 113)
            row.columns = {}
            for _, col in ipairs(COLUMNS) do row.columns[col[2]] = label(row, "-", col[3] - 14, -4, col[4]) end
            row.selection = row:CreateTexture(nil, "BACKGROUND")
            row.selection:SetAllPoints(row)
            row.selection:SetColorTexture(0.2, 0.35, 0.48, 0.65)
            row:SetScript("OnClick", function() self:Guard(self.ClickItem, itemID) end)
            self.rows[itemID] = row
        end
    end
    self.previous = button("<", self.catalogue, 14, -193, 36, function(s) s:Page(-1) end)
    self.pageLabel = label(self.catalogue, "", 60, -199, 320)
    self.next = button(">", self.catalogue, WIDTH - 50, -193, 36, function(s) s:Page(1) end)
    y = -302
    self.detail = CreateFrame("Frame", nil, self.body)
    self.detail:SetPoint("TOPLEFT", self.body, "TOPLEFT", 0, y)
    local detailTop = y
    self.detail:SetSize(WIDTH, 800)
    self.reportText = label(self.body, "", 14, -82, WIDTH - 28)
    if self.reportText.SetWordWrap then self.reportText:SetWordWrap(true) end
    self.reportText:SetHeight(720); self.reportText:SetJustifyV("TOP"); self.reportText:Hide()
    y = -3
    self.name = label(self.detail, "", 14, y, WIDTH - 28, "GameFontNormal")
    self.name:SetHeight(30)
    self.currentButton = button("Current", self.detail, 14, -37, 96, function(s) s:Detail("CURRENT") end)
    self.historyButton = button("History", self.detail, 114, -37, 96, function(s) s:Detail("HISTORY") end)
    self.scan = button("Scan", self.detail, 216, -37, 210, self.Scan)
    self.currentDetails = CreateFrame("Frame", nil, self.detail)
    self.currentDetails:SetPoint("TOPLEFT", self.detail, "TOPLEFT", 0, -72)
    self.currentDetails:SetSize(WIDTH, 300)
    self.historicalDetails = CreateFrame("Frame", nil, self.detail)
    self.historicalDetails:SetPoint("TOPLEFT", self.detail, "TOPLEFT", 0, -72)
    self.historicalDetails:SetSize(WIDTH, 300)
    y = 0
    for _, field in ipairs(FIELDS) do
        label(self.currentDetails, field[1], 14, y, 135)
        self.values[field[2]] = label(self.currentDetails, "Not scanned", 155, y, WIDTH - 169)
        self.values[field[2]]:SetJustifyH("RIGHT")
        self.values[field[2]]:SetHeight(20)
        y = y - 20
    end
    y = 0
    for _, field in ipairs(HISTORY_FIELDS) do
        label(self.historicalDetails, field[1], 14, y, 135)
        self.historyValues[field[2]] = label(self.historicalDetails, "Needs history", 155, y, WIDTH - 169)
        y = y - 20
    end
    self.exclusion = label(self.currentDetails, "", 14, -205, WIDTH - 28)
    self.exclusion:SetHeight(28)
    if self.exclusion.SetWordWrap then self.exclusion:SetWordWrap(true) end
    self.message = label(self.currentDetails, "", 14, -237, WIDTH - 28)
    self.message:SetHeight(54)
    if self.message.SetWordWrap then self.message:SetWordWrap(true) end
    self.expandedHeight = HEIGHT
    local contentHeight = -detailTop + 378
    self.watchContentHeight, self.reportContentHeight = contentHeight, 816
    self.body:SetHeight(contentHeight)
    self.scrollLimit = contentHeight - (HEIGHT - 74)
    self.footer = CreateFrame("Frame", nil, panel)
    self.footer:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0); self.footer:SetSize(WIDTH, 30)
    label(self.footer, "^ rising  v falling  = stable  - needs history", 14, -8, 328)
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
    local readOnly = self.demoInfo ~= nil or self.mode == "STANDALONE"
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
        view.sufficient = MP.UIViewModel.Anomaly(s.anomalySufficient)
        view.exclusion = "Extreme outliers excluded: " .. s.extreme .. ". Suspicious retained."
        view.message = s.levelCount == 0 and "No price levels in stored observation; see History for scan age."
            or "Stored observation; see History for last scan age."
    end
    if data.error and not self.scanner.uncertainQuery then view.message = MP.UIViewModel.Error(data.error) end
    if self.demoInfo then
        local scenario = self.demoInfo.items[self.selectedItemID]
        view.message = scenario and ("Demo: " .. scenario.label .. ". " .. scenario.description) or "Simulated market data."
        view.buttonText, view.scanEnabled = "Demo - scans disabled", false
    end
    if self.reportMode then self.detail:Hide(); self.catalogue:Hide(); self.reportText:Show()
        self.reportText:SetText(MP.UIViewModel.Report(self.market:Report(), self.items))
    else self.reportText:Hide(); self.detail:Show(); self.catalogue:Show() end
    local contentHeight = self.reportMode and self.reportContentHeight or self.watchContentHeight
    self.body:SetHeight(contentHeight)
    self.scrollLimit = math.max(0, contentHeight - (HEIGHT - 74))
    self.scroll:SetVerticalScroll(math.min(self.scroll:GetVerticalScroll(), self.scrollLimit))
    self.reportButton:SetText(self.reportMode and "Market Watch" or "Market Report")
    if self.detailMode == "HISTORY" then self.historicalDetails:Show(); self.currentDetails:Hide()
    else self.historicalDetails:Hide(); self.currentDetails:Show() end
    if self.detailMode == "HISTORY" then self.historyButton:Disable(); self.currentButton:Enable()
    else self.currentButton:Disable(); self.historyButton:Enable() end
    local history = MP.UIViewModel.History(data, self.clock())
    history.changes = history.change7 .. " / " .. history.change30
    for key, widget in pairs(self.historyValues) do widget:SetText(history[key]) end
    self.progress:SetText(self.demoInfo and "DEMO ONLY | 30 simulated days | No live scans"
        or (readOnly and "READ ONLY | Stored history | Open AH to scan"
        or (self.batch.state == "IDLE" and self.scanner.state == "IDLE" and "Ready | " .. #self.items.List() .. " materials"
        or MP.UIViewModel.State(self.batch.state) .. "  " .. self.batch.completed .. " / " .. self.batch.total
            .. "  |  " .. MP.UIViewModel.State(self.scanner.state))))
    self.historyStatus:SetText(self.demoInfo and "Synthetic examples - real history untouched"
        or (self.market.db.status == "OK" and "History: account-wide / realm + faction" or MP.UIViewModel.Error(self.market.db.error)))
    self.demoButton:SetText(self.demoInfo and "Exit demo" or "30d Demo")
    if self:IsReadOnly() or self.batch.active or self.scanner:IsActive() or self.scanner.uncertainQuery
        or self.scanner.blockedReason then self.batchButton:Disable() else self.batchButton:Enable() end
    if not self:IsReadOnly() and self.batch.active then self.cancelButton:Enable() else self.cancelButton:Disable() end
    self.name:SetText(view.name)
    for _, field in ipairs(FIELDS) do
        self.values[field[2]]:SetText(field[2] == "state" and MP.UIViewModel.State(view.state) or view[field[2]])
    end
    self.message:SetText(view.message)
    self.exclusion:SetText(view.exclusion)
    self.scan:SetText(view.buttonText)
    if view.scanEnabled and not self.batch.active then self.scan:Enable() else self.scan:Disable() end
    local list, visible = self.items.List(self.category), {}
    local pages = math.max(1, math.ceil(#list / PAGE_SIZE))
    self.page = math.max(1, math.min(pages, self.page))
    for i = 1, PAGE_SIZE do
        local id = list[(self.page - 1) * PAGE_SIZE + i]
        if id then visible[id] = i end
    end
    self.pageLabel:SetText(string.format("%s | %d items | %d / %d", self.category, #list, self.page, pages))
    if self.page == 1 then self.previous:Disable() else self.previous:Enable() end
    if self.page == pages then self.next:Disable() else self.next:Enable() end
    for name, widget in pairs(self.categoryButtons) do
        if name == self.category then widget:Disable() else widget:Enable() end
    end
    for itemID, row in pairs(self.rows) do
        local info = self.items.Metadata(itemID)
        row.text:SetText(info.name)
        row.icon:SetTexture(info.icon)
        local watch = MP.UIViewModel.Watch(self.market:Get(itemID))
        for key, widget in pairs(row.columns) do widget:SetText(watch[key]) end
        if itemID == view.itemID then row.selection:Show() else row.selection:Hide() end
        if view.itemsEnabled or self.batch.active then row:Enable() else row:Disable() end
        if visible[itemID] then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.catalogue, "TOPLEFT", 14, -51 - (visible[itemID] - 1) * 23)
            row:Show()
        else row:Hide() end
    end
end

function UI:MetadataReceived(itemID, success)
    if success == true and self.items.Contains(itemID) and self.items.InvalidateMetadata(itemID) then
        self:Update()
    end
end
