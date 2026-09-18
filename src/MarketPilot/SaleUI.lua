local _, MP = ...
local SaleUI = {}
SaleUI.__index = SaleUI
MP.SaleUI = SaleUI

local function label(parent, text, x, y, width, height)
    local value = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    value:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    value:SetSize(width, height or 22)
    value:SetJustifyH("LEFT")
    value:SetText(text)
    return value
end

function SaleUI:Act(method, ...)
    local ok, err = pcall(method, self.sale, ...)
    if not ok then self.sale.message = "UNKNOWN: sale action " .. tostring(err); self.sale.report(self.sale.message) end
    self.update()
end

function SaleUI.New(parent, sale, items, update, y)
    local self = setmetatable({ sale = sale, items = items, update = update, rows = {}, values = {}, durations = {}, targets = {} }, SaleUI)
    self.sectionTop = y
    self.editor = CreateFrame("Frame", nil, parent)
    self.editor:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    self.confirmation = CreateFrame("Frame", nil, parent)
    self.confirmation:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    self.confirmation:SetSize(320, 390)
    self.confirmation:Hide()
    parent, y = self.editor, 0
    local function button(text, x, top, width, action)
        local value = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        value:SetPoint("TOPLEFT", parent, "TOPLEFT", x, top)
        value:SetSize(width, 24)
        value:SetText(text)
        if action then value:SetScript("OnClick", action) end
        return value
    end
    label(parent, "Sale Assistant", 14, y, 292)
    self.bags = label(parent, "", 14, y - 24, 292)
    y = y - 48
    self.listTop = y
    local rowCount = 0
    for _, category in ipairs(items.categories) do
        for _, id in ipairs(category.itemIDs) do
            local itemID = id
            rowCount = rowCount + 1
            local row = button("", 14, y, 292, function() self:Act(sale.Select, itemID) end)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(18, 18)
            row.icon:SetPoint("LEFT", row, "LEFT", 3, 0)
            row.name = label(row, "", 25, -2, 264)
            self.rows[itemID] = row
        end
    end
    y = y - rowCount * 26 -- Reserve a bounded list area; bag events never recreate widgets.
    self.name = label(parent, "", 14, y, 292, 30)
    y = y - 32
    for _, field in ipairs({ { "Owned", "owned" }, { "Scanner", "state" }, { "Current lowest", "lowest" },
        { "Fast", "fast" }, { "Normal", "normal" }, { "Patient", "patient" } }) do
        label(parent, field[1], 14, y, 105)
        self.values[field[2]] = label(parent, "UNKNOWN", 121, y, 185)
        y = y - 23
    end
    for index, kind in ipairs({ "FAST", "NORMAL", "PATIENT" }) do
        local target = kind
        self.targets[kind] = button(kind, 14 + (index - 1) * 99, y, 94, function() self:Act(sale.SetTarget, target) end)
    end
    y = y - 32
    label(parent, "Quantity", 14, y, 75)
    self.quantity = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    self.quantity:SetPoint("TOPLEFT", parent, "TOPLEFT", 99, y)
    self.quantity:SetSize(110, 24)
    self.quantity:SetAutoFocus(false)
    self.quantity:SetNumeric(true)
    self.quantity:SetMaxLetters(16)
    self.quantity:SetScript("OnEnterPressed", function(box)
        self:Act(sale.SetQuantity, tonumber(box:GetText())); box:ClearFocus()
    end)
    self.quantity:SetScript("OnEscapePressed", function(box)
        box:SetText(sale.quantity and string.format("%.0f", sale.quantity) or "")
        box:ClearFocus(); self.update()
    end)
    self.quantity:SetScript("OnEditFocusLost", function(box)
        if sale.itemID then self:Act(sale.SetQuantity, tonumber(box:GetText())) end
    end)
    self.maximum = button("Max", 219, y, 87, function() self:Act(sale.SetQuantity, sale.inventory:Owned(sale.itemID)) end)
    y = y - 30
    for index, hours in ipairs({ 12, 24, 48 }) do
        local duration = hours
        self.durations[hours] = button(hours .. "h", 14 + (index - 1) * 99, y, 94,
            function() self:Act(sale.SetDuration, duration) end)
    end
    y = y - 32
    label(parent, "Deposit", 14, y, 105)
    self.values.deposit = label(parent, "UNKNOWN", 121, y, 185, 30)
    self.capabilities = label(parent, "", 14, y - 34, 292, 140)
    self.message = label(parent, "", 14, y - 176, 292, 46)
    self.check = button("Check sell API (no post)", 14, y - 228, 292, function() self:Act(sale.CheckCapabilities) end)
    self.prepare = button("Prepare Sale", 14, y - 258, 292, function()
        -- Commit the visible input before freezing; never prepare an older hidden quantity.
        local valid = sale:SetQuantity(tonumber(self.quantity:GetText()))
        self.quantity:ClearFocus()
        if valid then self:Act(sale.Prepare) else self.update() end
    end)
    self.editor:SetSize(320, -y + 296)
    self.bottom = self.sectionTop + y - 296
    parent = self.confirmation
    self.summary = label(parent, "", 14, 0, 292, 296)
    self.cancel = button("Cancel", 14, -300, 292, function() self:Act(sale.Cancel) end)
    self.post = button("Live Post Test - disabled", 14, -334, 292)
    self.post:Disable() -- Deliberately has no action handler.
    return self
end

function SaleUI:Update()
    local view = MP.UIViewModel.Sale(self.sale:State(), self.items)
    self.view = view
    if view.plan then
        if self.confirmedPlan ~= view.plan then
            self.confirmedPlan = view.plan
            self.frozenView = MP.UIViewModel.Prepared(view.plan, self.items.Metadata(view.plan.itemID))
        end
        self.summary:SetText(self.frozenView.text)
        self.editor:Hide(); self.confirmation:Show()
    else
        self.confirmedPlan, self.frozenView = nil, nil
        self.confirmation:Hide(); self.editor:Show()
    end
    self.bags:SetText(view.bags)
    for _, row in pairs(self.rows) do row:Hide() end
    for index, item in ipairs(view.rows) do
        local row = self.rows[item.itemID]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", row:GetParent(), "TOPLEFT", 14, self.listTop - (index - 1) * 26)
        row.name:SetText((item.itemID == self.sale.itemID and "> " or "") .. item.name .. " x" .. item.count)
        row.icon:SetTexture(item.icon)
        if view.enabled then row:Enable() else row:Disable() end
        row:Show()
    end
    self.name:SetText(view.name)
    for key, value in pairs(self.values) do value:SetText(view[key]) end
    if not self.quantity:HasFocus() then self.quantity:SetText(view.quantity == "UNKNOWN" and "" or view.quantity) end
    for hours, button in pairs(self.durations) do button:SetText((hours == view.duration and "> " or "") .. hours .. "h") end
    for kind, button in pairs(self.targets) do
        button:SetText((kind == view.targetKind and "> " or "") .. kind)
        if view.targetsEnabled[kind] then button:Enable() else button:Disable() end
    end
    if view.prepareEnabled then self.prepare:Enable() else self.prepare:Disable() end
    self.capabilities:SetText(view.capabilities)
    self.message:SetText(view.message)
    self.post:Disable()
end
