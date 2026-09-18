local _, MP = ...
local UI = {}
UI.__index = UI
MP.UI = UI

local WIDTH, HEIGHT = 320, 650
local FIELDS = {
    { "Current lowest", "lowest" }, { "Raw median", "rawMedian" },
    { "Clean median", "cleanMedian" }, { "Clean Q1-Q3", "range" },
    { "Total quantity", "quantity" }, { "Price levels", "levels" },
    { "Suspicious", "suspicious" }, { "Extreme", "extreme" },
    { "Anomaly model", "sufficient" }, { "Scanner", "state" },
}

function UI.New(scanner, items, report, sale)
    return setmetatable({ scanner = scanner, items = items, report = report,
        sale = sale, selectedItemID = scanner.itemID, collapsed = false, rows = {}, values = {} }, UI)
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

function UI:ClickItem(itemID)
    if not self.items.Contains(itemID) or not self.scanner.ahOpen or self.scanner:IsActive()
        or self.scanner.blockedReason then return false end
    self.selectedItemID = itemID
    self.scanner:Start(itemID)
    self:Update()
    return true
end

function UI:Scan()
    return self:ClickItem(self.selectedItemID)
end

function UI:Scroll(delta)
    local offset = self.scroll:GetVerticalScroll() + delta
    self.scroll:SetVerticalScroll(math.max(0, math.min(self.scrollLimit, offset)))
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
    panel:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
    panel:EnableMouse(true)
    local background = panel:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(panel)
    background:SetColorTexture(0.035, 0.045, 0.06, 0.97)
    local accent = panel:CreateTexture(nil, "BORDER")
    accent:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    accent:SetSize(WIDTH, 2)
    accent:SetColorTexture(0.65, 0.52, 0.27, 1)
    label(panel, "MARKETPILOT", 14, -13, 220, "GameFontNormalLarge")
    self.toggle = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    self.toggle:SetSize(28, 24)
    self.toggle:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -9)
    self.toggle:SetScript("OnClick", function() self:Guard(self.Toggle) end)

    self.scroll = CreateFrame("ScrollFrame", nil, panel)
    self.scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -42)
    self.scroll:SetSize(WIDTH, HEIGHT - 78)
    self.scroll:EnableMouseWheel(true)
    self.scroll:SetScript("OnMouseWheel", function(_, delta) self:Guard(self.Scroll, -delta * 80) end)
    self.body = CreateFrame("Frame", nil, self.scroll)
    self.body:SetSize(WIDTH, HEIGHT - 78)
    self.scroll:SetScrollChild(self.body)
    self.footer = CreateFrame("Frame", nil, panel)
    self.footer:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
    self.footer:SetSize(WIDTH, 32)
    label(self.footer, "Scroll for Sale Assistant", 14, -8, 204)
    for index, direction in ipairs({ -1, 1 }) do
        local step = direction
        local button = CreateFrame("Button", nil, self.footer, "UIPanelButtonTemplate")
        button:SetSize(40, 24)
        button:SetPoint("TOPLEFT", self.footer, "TOPLEFT", 220 + (index - 1) * 44, -3)
        button:SetText(direction == -1 and "Up" or "Down")
        button:SetScript("OnClick", function() self:Guard(self.Scroll, step * 260) end)
    end
    local y = -2
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
            row.text = label(row, "", 26, -4, WIDTH - 62)
            row.selection = row:CreateTexture(nil, "BACKGROUND")
            row.selection:SetAllPoints(row)
            row.selection:SetColorTexture(0.2, 0.35, 0.48, 0.65)
            row:SetScript("OnClick", function() self:Guard(self.ClickItem, itemID) end)
            self.rows[itemID] = row
            y = y - 23
        end
        y = y - 5
    end
    self.name = label(self.body, "", 14, y - 3, WIDTH - 28, "GameFontNormal")
    self.name:SetHeight(30)
    y = y - 37
    for _, field in ipairs(FIELDS) do
        label(self.body, field[1], 14, y, 110)
        self.values[field[2]] = label(self.body, "UNKNOWN", 125, y, WIDTH - 139)
        self.values[field[2]]:SetJustifyH("RIGHT")
        self.values[field[2]]:SetHeight(26)
        y = y - 24
    end
    self.exclusion = label(self.body, "", 14, y, WIDTH - 28)
    self.exclusion:SetHeight(28)
    self.message = label(self.body, "", 14, y - 30, WIDTH - 28)
    self.message:SetHeight(36)
    self.scan = CreateFrame("Button", nil, self.body, "UIPanelButtonTemplate")
    self.scan:SetPoint("TOPLEFT", self.body, "TOPLEFT", 14, y - 70)
    self.scan:SetSize(WIDTH - 28, 26)
    self.scan:SetScript("OnClick", function() self:Guard(self.Scan) end)
    self.saleUI = MP.SaleUI.New(self.body, self.sale, self.items, function() self:Guard(self.Update) end, y - 110)
    self.expandedHeight = HEIGHT
    self.body:SetHeight(-self.saleUI.bottom)
    self.scrollLimit = math.max(0, -self.saleUI.bottom - (HEIGHT - 78))
    self.anchor = anchor
end

function UI:Open()
    if not self.scanner.ahOpen then return false end
    -- External reference only: top-level AuctionHouseFrame, no child-frame hooks.
    local anchor = AuctionHouseFrame
    if (type(anchor) ~= "table" and type(anchor) ~= "userdata") or type(anchor.GetObjectType) ~= "function" then
        self:Close()
        self:Warn("AuctionHouseFrame unavailable; panel hidden. Debug commands remain available.")
        return false
    end
    local ok, err = pcall(function()
        if not self.frame then self:Create(anchor) end
        if self.anchor ~= anchor then error("AH frame changed; reload required") end
        self.items.InvalidateMetadata()
        self:Update()
        self.frame:Show()
    end)
    if not ok then
        if self.frame then self.frame:Hide() end
        if not self.anchor then self.frame, self.rows, self.values = nil, {}, {} end
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
    self.selectedItemID = self.scanner.itemID
    self.view = MP.UIViewModel.Build(self.scanner, self.selectedItemID, self.items.Metadata(self.selectedItemID))
    if not self.frame or not self.anchor then return end
    if not self.scanner.ahOpen then self:Close(); return end
    local view = self.view
    self.frame:SetHeight(self.collapsed and 42 or self.expandedHeight)
    self.toggle:SetText(self.collapsed and "+" or "-")
    if self.collapsed then self.body:Hide(); self.scroll:Hide(); self.footer:Hide()
    else self.body:Show(); self.scroll:Show(); self.footer:Show() end
    self.name:SetText(view.name)
    for _, field in ipairs(FIELDS) do self.values[field[2]]:SetText(view[field[2]]) end
    self.message:SetText(view.message)
    self.exclusion:SetText(view.exclusion)
    self.scan:SetText(view.buttonText)
    if view.scanEnabled then self.scan:Enable() else self.scan:Disable() end
    for itemID, row in pairs(self.rows) do
        local info = self.items.Metadata(itemID)
        row.text:SetText(info.name)
        row.icon:SetTexture(info.icon)
        if itemID == view.itemID then row.selection:Show() else row.selection:Hide() end
        if view.itemsEnabled then row:Enable() else row:Disable() end
    end
    self.saleUI:Update()
end

function UI:MetadataReceived(itemID, success)
    if success == true and self.items.Contains(itemID) and self.items.InvalidateMetadata(itemID) then
        self:Update()
    end
end
