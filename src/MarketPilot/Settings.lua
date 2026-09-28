local _, MP = ...
local Settings = {}
Settings.__index = Settings
MP.Settings = Settings

function Settings.New(preferences, callbacks, report)
    return setmetatable({ preferences = preferences, callbacks = callbacks or {}, report = report or function() end }, Settings)
end
function Settings:Guard(callback, ...)
    local ok, err = pcall(callback, self, ...)
    if not ok then
        if self.frame and not self.created then
            local partial = self.frame
            self.frame, self.checkbox, self.titleHandle = nil, nil, nil
            pcall(partial.Hide, partial)
        end
        self.report("Settings unavailable: " .. tostring(err))
    end
    return ok
end
function Settings:StopDrag()
    if not self.dragging then return end
    self.dragging = false
    self.frame:StopMovingOrSizing()
    local value = MP.Preferences.CapturePosition(self.frame, UIParent)
    if value then
        self.preferences:Set("settingsPosition", value)
        if self.callbacks.onChanged then self.callbacks.onChanged("settingsPosition") end
    end
end
local function label(parent, text, x, y, width, font)
    local value = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    value:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    value:SetWidth(width); value:SetJustifyH("LEFT"); value:SetText(text)
    return value
end
function Settings:Create()
    if not UIParent or type(CreateFrame) ~= "function" then error("standard UI frame is not ready") end
    local panel = CreateFrame("Frame", nil, UIParent)
    self.frame = panel
    panel:Hide(); panel:SetSize(330, 205); panel:EnableMouse(true); panel:SetMovable(true)
    if panel.SetFrameStrata then panel:SetFrameStrata("DIALOG") end
    MP.Preferences.ApplyPosition(panel, UIParent, self.preferences:Get("settingsPosition"))
    local background = panel:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(panel); background:SetColorTexture(0.035, 0.045, 0.06, 0.98)
    label(panel, "MarketPilot settings", 14, -13, 265, "GameFontNormal")
    local title = CreateFrame("Frame", nil, panel)
    self.titleHandle = title
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0); title:SetSize(285, 36)
    title:EnableMouse(true); title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() self:Guard(function(s) s.frame:StartMoving(); s.dragging = true end) end)
    title:SetScript("OnDragStop", function() self:Guard(self.StopDrag) end)
    panel:SetScript("OnHide", function() self:Guard(self.StopDrag) end)
    local close = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    self.closeButton = close
    close:SetSize(26, 24); close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8); close:SetText("x")
    close:SetScript("OnClick", function() panel:Hide() end)
    local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    self.checkbox = check
    check:SetSize(26, 26); check:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -48)
    label(panel, "Show minimap icon", 42, -54, 255)
    check:SetScript("OnClick", function() self:Guard(function(s)
        s.preferences:Set("minimapShown", not not check:GetChecked())
        if s.callbacks.onChanged then s.callbacks.onChanged("minimapShown") end
        s:Refresh()
    end) end)
    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    self.resetButton = reset
    reset:SetSize(220, 25); reset:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -90); reset:SetText("Reset window positions")
    reset:SetScript("OnClick", function() self:Guard(function(s)
        s:StopDrag(); s.preferences:ResetPositions()
        MP.Preferences.ApplyPosition(s.frame, UIParent, nil)
        if s.callbacks.onResetPositions then s.callbacks.onResetPositions() end
    end) end)
    self.help = label(panel, "Drag a window title to move it.\nMinimap: left click Market Watch; right click settings.\nDrag the icon to place it around the minimap.\n/mp settings always opens this window.", 14, -132, 302)
    if self.help.SetWordWrap then self.help:SetWordWrap(true) end
    self.created = true
end
function Settings:Refresh()
    return self:Guard(function(s)
        if s.frame then
            s.checkbox:SetChecked(s.preferences:Get("minimapShown"))
            if not s.dragging then MP.Preferences.ApplyPosition(s.frame, UIParent, s.preferences:Get("settingsPosition")) end
        end
    end)
end
function Settings:Toggle()
    return self:Guard(function(s)
        if not s.frame then s:Create() end
        if s.frame:IsShown() then s:StopDrag(); s.frame:Hide()
        else s:Refresh(); s.frame:Show() end
    end)
end
