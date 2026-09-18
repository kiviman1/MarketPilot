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
    local self = setmetatable({ sale = sale, items = items, update = update, rows = {}, values = {}, durations = {} }, SaleUI)
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
    self.post = button("Post - awaiting beta validation", 14, y - 258, 292)
    self.post:Disable() -- Deliberately has no action handler.
    self.bottom = y - 296
    return self
end

function SaleUI:Update()
    local view = MP.UIViewModel.Sale(self.sale:State(), self.items)
    self.view = view
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
    self.capabilities:SetText(view.capabilities)
    self.message:SetText(view.message)
    self.post:Disable()
end
