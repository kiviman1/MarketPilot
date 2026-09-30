local _, MP = ...
local UI = {}
UI.__index = UI
MP.UI = UI

local WIDTH, HEIGHT = 660, 760
local PAGE_SIZE = 6
local WINDOW_LEVEL = 100 -- Normal dialog layer; Settings uses a separate level above this tree.
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
local COLUMNS = { { "NOW", "now", 190, 120 }, { "7D", "change", 314, 46 },
    { "TREND", "trend", 364, 40 }, { "30D %", "percentile", 408, 46 },
    { "SUPPLY", "supply", 458, 66 }, { "MATURITY", "maturity", 530, 100 } }
local DETAIL_TOP, ROW_TOP, ROW_HEIGHT = 498, 76, 36
local Theme = MP.UITheme


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

function UI:ApplyWindowLayer()
    if self.frame.SetFixedFrameLevel then self.frame:SetFixedFrameLevel(false) end
    self.frame:SetFrameStrata("DIALOG")
    self.frame:SetFrameLevel(WINDOW_LEVEL)
    if self.frame.SetFixedFrameLevel then self.frame:SetFixedFrameLevel(true) end
end

function UI:IsReadOnly()
    return self.mode == "STANDALONE" or not self.scanner.ahOpen
end

function UI:StartDrag()
    if self.mode ~= "STANDALONE" or self.scanner.ahOpen or not self.frame or not self.frame:IsShown() then return false end
    if self.preferences and self.preferences:Get("lockWindows") then return false end
    self.frame:StartMoving()
    self.dragging = true
    return true
end

function UI:StopDrag()
    if not self.dragging then return end
    self.dragging = false
    self.frame:StopMovingOrSizing()
    if self.mode == "STANDALONE" and self.preferences then
        local position = MP.Preferences.CapturePosition(self.frame, UIParent)
        if position then self.preferences:Set("watchPosition", position) end
    end
end

function UI:ResetPosition()
    self:StopDrag()
    if self.preferences then self.preferences:Set("watchPosition", nil) end
    if self.frame and self.mode == "STANDALONE" then
        MP.Preferences.ApplyPosition(self.frame, UIParent, nil)
    end
end

function UI:ApplyPreferences()
    if not self.preferences then return end
    local category = self.preferences:Get("defaultCategory")
    if category ~= self.appliedDefaultCategory then
        self.category, self.page, self.appliedDefaultCategory = category, 1, category
    end
    if self.frame then
        self:StopDrag()
        self.frame:SetScale(self.preferences:Get("watchScale"))
        self:FitViewport()
        self.frame:SetMovable(self.mode == "STANDALONE" and not self.preferences:Get("lockWindows"))
        if self.mode == "STANDALONE" then
            MP.Preferences.ApplyPosition(self.frame, UIParent, self.preferences:Get("watchPosition"))
        end
        self:Update()
    end
end

function UI:FitViewport()
    -- Bound the viewport, not its content. Wheel scrolling still reaches every
    -- card when the game UI scale leaves less vertical screen space.
    local height, scale = UIParent:GetHeight(), UIParent:GetEffectiveScale() / self.frame:GetEffectiveScale()
    self.expandedHeight = HEIGHT
    if type(height) == "number" and height > 0 and scale > 0 then
        self.expandedHeight = math.max(160, math.min(HEIGHT, math.floor(height * scale - 20)))
    end
    self.scroll:SetHeight(self.expandedHeight - 84)
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
    self.scanner:Start(itemID, true)
    self:Update()
    return true
end

function UI:Scan()
    if self:IsReadOnly() or self.batch.active then return false end
    if self.scanner:IsActive() or self.scanner.blockedReason or self.scanner.uncertainQuery then return false end
    self.scanner:Start(self.selectedItemID)
    self:Update()
    return true
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
    Theme.Color(value, "text")
    return value
end

function UI:Create(anchor)
    local panel = CreateFrame("Frame", nil, anchor)
    self.frame = panel
    panel:Hide(); self:ApplyWindowLayer(); panel:SetSize(WIDTH, HEIGHT)
    panel:SetClampedToScreen(true); panel:EnableMouse(true)
    panel:SetScript("OnHide", function() self:Guard(self.StopDrag) end)
    Theme.Surface(panel, "canvas")
    local header = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -1); header:SetSize(WIDTH - 2, 50)
    header:SetColorTexture(unpack(Theme.colors.card))
    self.titleBar = CreateFrame("Frame", nil, panel)
    self.titleBar:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -1)
    self.titleBar:SetSize(WIDTH - 98, 50)
    Theme.Surface(self.titleBar)
    self.titleBar:EnableMouse(true); self.titleBar:RegisterForDrag("LeftButton")
    self.titleBar:SetScript("OnDragStart", function() self:Guard(self.StartDrag) end)
    self.titleBar:SetScript("OnDragStop", function() self:Guard(self.StopDrag) end)
    local icon = self.titleBar:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24); icon:SetPoint("TOPLEFT", self.titleBar, "TOPLEFT", 16, -13)
    icon:SetTexture("Interface\\AddOns\\MarketPilot\\Media\\Icon.tga")
    label(self.titleBar, "MarketPilot", 50, -17, WIDTH - 160, "GameFontHighlight")
    local function button(text, parent, x, y, width, action, height)
        local b = Theme.Button(parent, text, width, height or 30, function() self:Guard(action) end)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        return b
    end
    self.toggle = button("-", panel, WIDTH - 88, -10, 32, self.Toggle)
    self.closeButton = button("x", panel, WIDTH - 46, -10, 32, self.ToggleWatch)
    self.scroll = CreateFrame("ScrollFrame", nil, panel)
    self.scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -52)
    self.scroll:SetSize(WIDTH, HEIGHT - 84); self.scroll:EnableMouseWheel(true)
    self.scroll:SetScript("OnMouseWheel", function(_, delta) self:Guard(self.Scroll, -delta * 75) end)
    self.body = CreateFrame("Frame", nil, self.scroll)
    self.body:SetSize(WIDTH, HEIGHT); self.scroll:SetScrollChild(self.body)
    self.batchButton = button("Scan Gathering Markets", self.body, 16, -12, 226, self.StartBatch)
    self.cancelButton = button("Cancel", self.body, 250, -12, 66, self.CancelBatch)
    self.settingsButton = button("Settings", self.body, WIDTH - 102, -12, 86, function(s)
        if s.onSettings then s.onSettings() end
    end)
    self.progress = label(self.body, "", 16, -55, WIDTH - 32)
    Theme.Color(self.progress, "gold")
    self.historyStatus = label(self.body, "", 16, -77, WIDTH - 32)
    Theme.Color(self.historyStatus, "muted")
    self.watchButton = button("Market Watch", self.body, 16, -105, 145, function(s)
        s.reportMode = false; s.scroll:SetVerticalScroll(0); s:Update()
    end, 34)
    self.reportButton = button("Market Report", self.body, 169, -105, 145, self.ToggleReport, 34)
    self.catalogue = CreateFrame("Frame", nil, self.body)
    self.catalogue:SetPoint("TOPLEFT", self.body, "TOPLEFT", 0, -154)
    self.catalogue:SetSize(WIDTH, 326)
    self.categoryButtons = {}
    local categoryWidth = (WIDTH - 56) / 4
    for index, name in ipairs({ "All", "Mining", "Herbalism", "Skinning" }) do
        local category = name
        self.categoryButtons[name] = button(name .. "  " .. #self.items.List(name), self.catalogue,
            16 + (index - 1) * (categoryWidth + 8), 0, categoryWidth,
            function(s) s:SetCategory(category) end)
    end
    local tableHeader = CreateFrame("Frame", nil, self.catalogue)
    tableHeader:SetPoint("TOPLEFT", self.catalogue, "TOPLEFT", 16, -46)
    tableHeader:SetSize(WIDTH - 32, 30); Theme.Surface(tableHeader)
    Theme.Color(label(tableHeader, "ITEM", 12, -10, 155), "muted")
    for _, col in ipairs(COLUMNS) do Theme.Color(label(tableHeader, col[1], col[3] - 16, -10, col[4]), "muted") end
    local percentileHeader = CreateFrame("Frame", nil, self.catalogue)
    percentileHeader:SetPoint("TOPLEFT", self.catalogue, "TOPLEFT", 408, -46)
    percentileHeader:SetSize(46, 30); percentileHeader:EnableMouse(true)
    percentileHeader:SetScript("OnEnter", function()
        if GameTooltip then
            GameTooltip:SetOwner(percentileHeader, "ANCHOR_TOP")
            GameTooltip:SetText("30-day price percentile")
            GameTooltip:AddLine("Position in recorded prices; not a price-change percentage.", 0.7, 0.8, 0.9, true)
            GameTooltip:Show()
        end
    end)
    percentileHeader:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    for _, category in ipairs(self.items.categories) do
        for _, id in ipairs(category.itemIDs) do
            local itemID = id
            local row = CreateFrame("Button", nil, self.catalogue)
            row:SetSize(WIDTH - 32, ROW_HEIGHT)
            row:SetPoint("TOPLEFT", self.catalogue, "TOPLEFT", 16, -ROW_TOP)
            Theme.Surface(row, "canvas")
            row.selection = row:CreateTexture(nil, "BACKGROUND", nil, 1)
            row.selection:SetAllPoints(row); row.selection:SetColorTexture(unpack(Theme.colors.selected))
            row.accent = row:CreateTexture(nil, "ARTWORK")
            row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0); row.accent:SetSize(3, ROW_HEIGHT)
            row.accent:SetColorTexture(unpack(Theme.colors.gold))
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(24, 24); row.icon:SetPoint("LEFT", row, "LEFT", 12, 0)
            row.text = label(row, "", 44, -12, 125)
            row.columns = {}
            for _, col in ipairs(COLUMNS) do row.columns[col[2]] = label(row, "-", col[3] - 16, -12, col[4]) end
            local badge = row:CreateTexture(nil, "BACKGROUND", nil, 2)
            badge:SetPoint("TOPLEFT", row, "TOPLEFT", 508, -8); badge:SetSize(110, 22)
            badge:SetColorTexture(unpack(Theme.colors.button))
            row:SetScript("OnClick", function() self:Guard(self.ClickItem, itemID) end)
            self.rows[itemID] = row
        end
    end
    self.previous = button("<", self.catalogue, 16, -300, 32, function(s) s:Page(-1) end, 26)
    self.pageLabel = label(self.catalogue, "", 64, -308, WIDTH - 128)
    self.pageLabel:SetJustifyH("CENTER"); Theme.Color(self.pageLabel, "muted")
    self.next = button(">", self.catalogue, WIDTH - 48, -300, 32, function(s) s:Page(1) end, 26)
    self.detail = CreateFrame("Frame", nil, self.body)
    self.detail:SetPoint("TOPLEFT", self.body, "TOPLEFT", 0, -DETAIL_TOP)
    self.detail:SetSize(WIDTH, 800)
    -- Inset card leaves the same summary width used for wrapping and scroll bounds.
    Theme.Surface(self.detail)
    self.detailIcon = self.detail:CreateTexture(nil, "ARTWORK")
    self.detailIcon:SetPoint("TOPLEFT", self.detail, "TOPLEFT", 28, -16); self.detailIcon:SetSize(28, 28)
    self.name = label(self.detail, "", 68, -18, 230, "GameFontNormal")
    Theme.Color(self.name, "gold"); self.name:SetHeight(18)
    self.detailMaturity = label(self.detail, "", 68, -43, 230)
    Theme.Color(self.detailMaturity, "muted")
    self.currentButton = button("Summary", self.detail, WIDTH - 242, -16, 100, function(s) s:Detail("CURRENT") end)
    self.historyButton = button("History", self.detail, WIDTH - 134, -16, 106, function(s) s:Detail("HISTORY") end)
    self.scan = button("Scan", self.detail, 28, -58, WIDTH - 56, self.Scan)
    self.summaryTitle = label(self.detail, "Market Summary", 14, -102, WIDTH - 28, "GameFontNormal")
    self.summary = label(self.detail, "", 14, -123, WIDTH - 28)
    self.summary:SetWordWrap(true); self.summary:SetJustifyV("TOP")
    self.currentDetails = CreateFrame("Frame", nil, self.detail)
    self.historicalDetails = CreateFrame("Frame", nil, self.detail)
    self.currentDetails:SetSize(WIDTH, 380); self.historicalDetails:SetSize(WIDTH, 380)
    self.metricTiles, self.historyTiles = {}, {}
    local function tiles(parent, fields, values, collection)
        local width = (WIDTH - 28) / 4
        for index, field in ipairs(fields) do
            local tile = CreateFrame("Frame", nil, parent)
            tile:SetPoint("TOPLEFT", parent, "TOPLEFT", 14 + ((index - 1) % 4) * width, -math.floor((index - 1) / 4) * 78)
            tile:SetSize(width, 78); Theme.Surface(tile)
            Theme.Color(label(tile, field[1]:upper(), 12, -12, width - 24), "muted")
            local value = label(tile, "Not available", 12, -33, width - 24)
            value:SetWordWrap(true); value:SetJustifyV("TOP")
            values[field[2]], collection[index] = value, tile
        end
    end
    tiles(self.currentDetails, FIELDS, self.values, self.metricTiles)
    tiles(self.historicalDetails, HISTORY_FIELDS, self.historyValues, self.historyTiles)
    self.exclusion = label(self.currentDetails, "", 14, -246, WIDTH - 28)
    self.exclusion:SetHeight(32); self.exclusion:SetWordWrap(true)
    self.message = label(self.currentDetails, "", 14, -286, WIDTH - 28)
    self.message:SetHeight(64); self.message:SetWordWrap(true); Theme.Color(self.message, "muted")
    -- Report is a separate native card view, sharing the existing report model.
    self.reportText = CreateFrame("Frame", nil, self.body)
    self.reportText:SetPoint("TOPLEFT", self.body, "TOPLEFT", 16, -154)
    self.reportText:SetSize(WIDTH - 32, 480); self.reportText:Hide()
    self.reportCards = {}
    local cardWidth = (WIDTH - 44) / 2
    for index, title in ipairs({ "Rising markets", "Below historical range", "Unusual return volatility", "Meaningful changes" }) do
        local card = CreateFrame("Frame", nil, self.reportText)
        card:SetPoint("TOPLEFT", self.reportText, "TOPLEFT", ((index - 1) % 2) * (cardWidth + 12), -math.floor((index - 1) / 2) * 154)
        card:SetSize(cardWidth, 142); Theme.Surface(card)
        Theme.Color(label(card, title, 14, -16, cardWidth - 28, "GameFontHighlight"), index == 1 and "green" or (index == 2 and "blue" or "gold"))
        card.body = label(card, "", 14, -42, cardWidth - 28)
        card.body:SetWordWrap(true); card.body:SetJustifyV("TOP"); Theme.Color(card.body, "muted")
        self.reportCards[index] = card
    end
    self.maturityCard = CreateFrame("Frame", nil, self.reportText)
    self.maturityCard:SetPoint("TOPLEFT", self.reportText, "TOPLEFT", 0, -308)
    self.maturityCard:SetSize(WIDTH - 32, 110); Theme.Surface(self.maturityCard)
    label(self.maturityCard, "Data maturity", 14, -16, WIDTH - 60, "GameFontHighlight")
    self.maturityBar, self.maturityLabels = {}, {}
    for index, color in ipairs({ "green", "blue", "gold", "muted" }) do
        local segment = self.maturityCard:CreateTexture(nil, "ARTWORK")
        segment:SetColorTexture(unpack(Theme.colors[color])); segment:SetHeight(8)
        self.maturityBar[index] = segment
        local text = label(self.maturityCard, "", 14 + (index - 1) * (WIDTH - 60) / 4, -72, (WIDTH - 60) / 4)
        Theme.Color(text, color); self.maturityLabels[index] = text
    end
    self.reportNote = label(self.reportText, "Descriptive observations; p-values are approximate.", 0, -438, WIDTH - 32)
    Theme.Color(self.reportNote, "muted")
    self.expandedHeight = HEIGHT
    self.watchContentHeight, self.reportContentHeight = DETAIL_TOP + 600, 634
    self.scrollLimit = self.watchContentHeight - (HEIGHT - 84)
    self.footer = CreateFrame("Frame", nil, panel)
    self.footer:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0); self.footer:SetSize(WIDTH, 30)
    Theme.Surface(self.footer)
    label(self.footer, "|cff52d1a1^ rising|r    |cffff6b76v falling|r    = stable    - needs history", 16, -9, WIDTH - 32)
end

function UI:LayoutMetrics()
    local height = 0
    for _, group in ipairs({ { self.metricTiles, FIELDS, self.values }, { self.historyTiles, HISTORY_FIELDS, self.historyValues } }) do
        local offset = 0
        for first = 1, #group[2], 4 do
            local rowHeight = 78
            for i = first, math.min(first + 3, #group[2]) do
                rowHeight = math.max(rowHeight, 45 + math.ceil(group[3][group[2][i][2]]:GetStringHeight()))
            end
            for i = first, math.min(first + 3, #group[2]) do
                local tile = group[1][i]
                tile:ClearAllPoints()
                tile:SetPoint("TOPLEFT", tile:GetParent(), "TOPLEFT", 14 + ((i - 1) % 4) * (WIDTH - 28) / 4, -offset)
                tile:SetHeight(rowHeight)
            end
            offset = offset + rowHeight
        end
        height = math.max(height, offset)
    end
    self.exclusion:ClearAllPoints(); self.exclusion:SetPoint("TOPLEFT", self.currentDetails, "TOPLEFT", 14, -height - 12)
    self.message:ClearAllPoints(); self.message:SetPoint("TOPLEFT", self.currentDetails, "TOPLEFT", 14, -height - 52)
    local messageHeight = math.max(64, math.ceil(self.message:GetStringHeight()))
    self.message:SetHeight(messageHeight)
    local tableHeight = math.max(380, height + 52 + messageHeight + 14)
    self.currentDetails:SetHeight(tableHeight); self.historicalDetails:SetHeight(tableHeight)
    self.detail:SetHeight(self.tableTop + tableHeight)
    self.watchContentHeight = DETAIL_TOP + self.tableTop + tableHeight + 14
end

function UI:UpdateReport(report)
    local cards = MP.UIViewModel.ReportCards(report, self.items)
    self.reportText.text = MP.UIViewModel.Report(report, self.items) -- Detached readable representation for diagnostics/tests.
    local offset = 0
    for first = 1, 4, 2 do
        local height = 142
        for index = first, first + 1 do
            local card = self.reportCards[index]
            card.body:SetText(cards[index].text)
            height = math.max(height, 58 + math.ceil(card.body:GetStringHeight()))
        end
        for index = first, first + 1 do
            local card = self.reportCards[index]
            card:ClearAllPoints(); card:SetPoint("TOPLEFT", self.reportText, "TOPLEFT", ((index - 1) % 2) * (WIDTH - 20) / 2, -offset)
            card:SetHeight(height)
        end
        offset = offset + height + 12
    end
    self.maturityCard:ClearAllPoints(); self.maturityCard:SetPoint("TOPLEFT", self.reportText, "TOPLEFT", 0, -offset)
    local total = 0
    for _, n in pairs(report.maturity) do total = total + n end
    local x = 14
    for index, state in ipairs({ "30D READY", "7D READY", "EARLY", "NEW" }) do
        local n, segment = report.maturity[state], self.maturityBar[index]
        local width = total > 0 and (WIDTH - 60) * n / total or 0
        segment:ClearAllPoints(); segment:SetPoint("TOPLEFT", self.maturityCard, "TOPLEFT", x, -50)
        segment:SetWidth(math.max(1, width)); segment:SetShown(width > 0); x = x + width
        self.maturityLabels[index]:SetText(MP.UIViewModel.Maturity(state) .. ": " .. n)
    end
    self.reportNote:ClearAllPoints(); self.reportNote:SetPoint("TOPLEFT", self.reportText, "TOPLEFT", 0, -offset - 128)
    self.reportText:SetHeight(offset + 156)
    self.reportContentHeight = 154 + offset + 170
end

function UI:Open()
    if not self.scanner.ahOpen and not self.watchRequested then return false end
    self:StopDrag()
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
        self:ApplyWindowLayer()
        self.frame:SetScale(self.preferences and self.preferences:Get("watchScale") or 1)
        self:FitViewport()
        self.frame:SetMovable(mode == "STANDALONE" and not (self.preferences and self.preferences:Get("lockWindows")))
        self.frame:ClearAllPoints()
        if mode == "AH" then self.frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
        else MP.Preferences.ApplyPosition(self.frame, UIParent, self.preferences and self.preferences:Get("watchPosition")) end
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

function UI:UpdateInsight(data, now)
    self.insight = MP.UIViewModel.Insight(MP.MarketInsight.Build(data, {
        itemID = self.selectedItemID, scannerItemID = self.scanner.itemID,
        scannerState = self.scanner.state, now = now,
    }))
    local historical = self.detailMode == "HISTORY"
    local summaryTop = self:IsReadOnly() and 85 or 123
    self.scan:SetShown(not self:IsReadOnly())
    self.summaryTitle:ClearAllPoints()
    self.summaryTitle:SetPoint("TOPLEFT", self.detail, "TOPLEFT", 14, -summaryTop + 21)
    self.summary:ClearAllPoints()
    self.summary:SetPoint("TOPLEFT", self.detail, "TOPLEFT", 14, -summaryTop)
    self.summaryTitle:SetText(historical and "Historical Context" or "Market Summary")
    self.summary:SetText(historical and self.insight.history or self.insight.current)
    -- Measure the wrapped font at the existing local width. Scaling the window
    -- scales text and frames together; no timer or per-frame layout is needed.
    local tableTop = summaryTop + math.ceil(self.summary:GetStringHeight()) + 14
    self.tableTop = tableTop
    for _, details in ipairs({ self.currentDetails, self.historicalDetails }) do
        details:ClearAllPoints()
        details:SetPoint("TOPLEFT", self.detail, "TOPLEFT", 0, -tableTop)
    end
    self.detail:SetHeight(tableTop + 380)
    self.watchContentHeight = DETAIL_TOP + tableTop + 394
end

function UI:Close()
    self:StopDrag()
    if self.frame then self.frame:Hide() end
end

function UI:Update()
    local readOnly = self.mode == "STANDALONE"
    self.view = MP.UIViewModel.Build(self.scanner, self.selectedItemID, self.items.Metadata(self.selectedItemID), readOnly)
    if not self.frame or not self.anchor then return end
    if not self.scanner.ahOpen and not readOnly then self:Close(); return end
    local view = self.view
    self.frame:SetHeight(self.collapsed and 52 or self.expandedHeight)
    self.toggle:SetText(self.collapsed and "+" or "-")
    if self.collapsed then self.body:Hide(); self.scroll:Hide(); self.footer:Hide()
    else self.body:Show(); self.scroll:Show(); self.footer:Show() end
    local data = self.market:Get(self.selectedItemID)
    local now = self.clock()
    self:UpdateInsight(data, now)
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
    if self.reportMode then self.detail:Hide(); self.catalogue:Hide(); self.reportText:Show()
        self:UpdateReport(self.market:Report())
    else self.reportText:Hide(); self.detail:Show(); self.catalogue:Show() end
    Theme.Paint(self.reportButton, self.reportMode == true)
    Theme.Paint(self.watchButton, not self.reportMode)
    if self.detailMode == "HISTORY" then self.historicalDetails:Show(); self.currentDetails:Hide()
    else self.historicalDetails:Hide(); self.currentDetails:Show() end
    if self.detailMode == "HISTORY" then self.historyButton:Disable(); self.currentButton:Enable()
    else self.currentButton:Disable(); self.historyButton:Enable() end
    Theme.Paint(self.historyButton, self.detailMode == "HISTORY")
    Theme.Paint(self.currentButton, self.detailMode ~= "HISTORY")
    local history = MP.UIViewModel.History(data, now)
    history.changes = history.change7 .. " / " .. history.change30
    for key, widget in pairs(self.historyValues) do widget:SetText(history[key]) end
    self.progress:SetText(readOnly and "READ ONLY | Stored history | Open AH to scan"
        or (self.batch.state == "IDLE" and self.scanner.state == "IDLE" and "Ready | " .. #self.items.List() .. " materials"
        or MP.UIViewModel.State(self.batch.state) .. "  " .. self.batch.completed .. " / " .. self.batch.total
            .. "  |  " .. MP.UIViewModel.State(view.state)))
    self.historyStatus:SetText(self.market.db.status == "OK" and "History: account-wide / realm + faction" or MP.UIViewModel.Error(self.market.db.error))
    if self:IsReadOnly() or self.batch.active or self.scanner:IsActive() or self.scanner.uncertainQuery
        or self.scanner.blockedReason then self.batchButton:Disable() else self.batchButton:Enable() end
    if not self:IsReadOnly() and self.batch.active then self.cancelButton:Enable() else self.cancelButton:Disable() end
    self.name:SetText(view.name)
    self.detailMaturity:SetText(MP.UIViewModel.Maturity(data.analytics.maturity))
    self.detailIcon:SetTexture(view.icon)
    for _, field in ipairs(FIELDS) do
        self.values[field[2]]:SetText(field[2] == "state" and MP.UIViewModel.State(view.state) or view[field[2]])
    end
    self.message:SetText(view.message)
    self.exclusion:SetText(view.exclusion)
    self:LayoutMetrics()
    self.scan:SetText(view.buttonText)
    if view.scanEnabled and not self.batch.active then self.scan:Enable() else self.scan:Disable() end
    local list, visible = self.items.List(self.category), {}
    local pages = math.max(1, math.ceil(#list / PAGE_SIZE))
    self.page = math.max(1, math.min(pages, self.page))
    for i = 1, PAGE_SIZE do
        local id = list[(self.page - 1) * PAGE_SIZE + i]
        if id then visible[id] = i end
    end
    self.pageLabel:SetText(string.format("%d-%d of %d items | %s | page %d/%d", (self.page - 1) * PAGE_SIZE + 1, math.min(self.page * PAGE_SIZE, #list), #list, self.category, self.page, pages))
    if self.page == 1 then self.previous:Disable() else self.previous:Enable() end
    if self.page == pages then self.next:Disable() else self.next:Enable() end
    for name, widget in pairs(self.categoryButtons) do
        if name == self.category then widget:Disable() else widget:Enable() end
        Theme.Paint(widget, name == self.category)
    end
    for itemID, row in pairs(self.rows) do
        local info = self.items.Metadata(itemID)
        row.text:SetText(info.name)
        row.icon:SetTexture(info.icon)
        local watch = MP.UIViewModel.Watch(self.market:Get(itemID))
        for key, widget in pairs(row.columns) do widget:SetText(watch[key]) end
        if itemID == view.itemID then row.selection:Show() else row.selection:Hide() end
        if itemID == view.itemID then row.accent:Show() else row.accent:Hide() end
        if view.itemsEnabled or self.batch.active then row:Enable() else row:Disable() end
        if visible[itemID] then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.catalogue, "TOPLEFT", 16, -ROW_TOP - (visible[itemID] - 1) * ROW_HEIGHT)
            row:Show()
        else row:Hide() end
    end
    local contentHeight = self.reportMode and self.reportContentHeight or self.watchContentHeight
    self.body:SetHeight(contentHeight)
    self.scrollLimit = math.max(0, contentHeight - self.scroll:GetHeight())
    self.scroll:SetVerticalScroll(math.min(self.scroll:GetVerticalScroll(), self.scrollLimit))

end

function UI:MetadataReceived(itemID, success)
    if success == true and self.items.Contains(itemID) and self.items.InvalidateMetadata(itemID) then
        self:Update()
    end
end
