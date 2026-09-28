local _, MP = ...
local Settings = {}
Settings.__index = Settings
MP.Settings = Settings
local SCALES = { 0.8, 0.9, 1, 1.1, 1.2 }
local CATEGORIES = { "All", "Mining", "Herbalism", "Skinning" }

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
function Settings:Change(key, value)
    if self.preferences:Get(key) == value or not self.preferences:Set(key, value) then return false end
    if self.callbacks.onChanged then self.callbacks.onChanged(key) end
    self:Refresh()
    return true
end
function Settings:AdjustScale(direction)
    if direction ~= -1 and direction ~= 1 then return false end
    local value = self.preferences:Get("watchScale")
    for index, scale in ipairs(SCALES) do
        if scale == value and SCALES[index + direction] then return self:Change("watchScale", SCALES[index + direction]) end
    end
    return false
end
function Settings:CycleCategory()
    local value = self.preferences:Get("defaultCategory")
    for index, category in ipairs(CATEGORIES) do
        if category == value then return self:Change("defaultCategory", CATEGORIES[index % #CATEGORIES + 1]) end
    end
    return false
end
local function label(parent, text, x, y, width, font)
    local value = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    value:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    value:SetWidth(width); value:SetJustifyH("LEFT"); value:SetText(text)
    return value
end
local function button(parent, text, x, y, width, callback)
    local widget = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    widget:SetSize(width, 25); widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    widget:SetText(text); widget:SetScript("OnClick", callback)
    return widget
end
local function checkbox(parent, text, y, callback)
    local widget = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    widget:SetSize(26, 26); widget:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y)
    label(parent, text, 42, y - 6, 270)
    widget:SetScript("OnClick", callback)
    return widget
end
function Settings:Create()
    if not UIParent or type(CreateFrame) ~= "function" then error("standard UI frame is not ready") end
    local panel = CreateFrame("Frame", nil, UIParent)
    self.frame = panel
    panel:Hide(); panel:SetSize(330, 325); panel:EnableMouse(true); panel:SetMovable(true)
    if panel.SetFrameStrata then panel:SetFrameStrata("DIALOG") end
    MP.Preferences.ApplyPosition(panel, UIParent, self.preferences:Get("settingsPosition"))
    local background = panel:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(panel); background:SetColorTexture(0.035, 0.045, 0.06, 0.98)
    label(panel, "MarketPilot settings", 14, -13, 265, "GameFontNormal")
    local title = CreateFrame("Frame", nil, panel)
    self.titleHandle = title
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0); title:SetSize(285, 36)
    title:EnableMouse(true); title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() self:Guard(function(s)
        if s.preferences:Get("lockWindows") then return end
        s.frame:StartMoving(); s.dragging = true
    end) end)
    title:SetScript("OnDragStop", function() self:Guard(self.StopDrag) end)
    panel:SetScript("OnHide", function() self:Guard(self.StopDrag) end)
    local close = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    self.closeButton = close
    close:SetSize(26, 24); close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8); close:SetText("x")
    close:SetScript("OnClick", function() panel:Hide() end)
    label(panel, "Market Watch size", 14, -56, 145)
    self.scaleMinus = button(panel, "-", 170, -50, 25, function() self:Guard(self.AdjustScale, -1) end)
    self.scaleValue = label(panel, "100%", 205, -56, 45)
    self.scalePlus = button(panel, "+", 260, -50, 25, function() self:Guard(self.AdjustScale, 1) end)
    label(panel, "Start category", 14, -96, 145)
    self.categoryButton = button(panel, "All >", 168, -89, 145, function() self:Guard(self.CycleCategory) end)
    self.lockCheckbox = checkbox(panel, "Lock window positions", -126, function(widget)
        self:Guard(self.Change, "lockWindows", not not widget:GetChecked())
    end)
    self.debugCheckbox = checkbox(panel, "Detailed scan log", -163, function(widget)
        self:Guard(self.Change, "debugLogging", not not widget:GetChecked())
    end)
    self.checkbox = checkbox(panel, "Show minimap icon", -200, function(widget)
        self:Guard(self.Change, "minimapShown", not not widget:GetChecked())
    end)
    self.resetButton = button(panel, "Reset window positions", 14, -244, 220, function() self:Guard(function(s)
        s:StopDrag(); s.preferences:ResetPositions()
        MP.Preferences.ApplyPosition(s.frame, UIParent, nil)
        if s.callbacks.onResetPositions then s.callbacks.onResetPositions() end
    end) end)
    self.help = label(panel, "Changes apply immediately.\n/mp settings always reopens this window.", 14, -286, 302)
    if self.help.SetWordWrap then self.help:SetWordWrap(true) end
    self.created = true
end
function Settings:Refresh()
    return self:Guard(function(s)
        if s.frame then
            s.checkbox:SetChecked(s.preferences:Get("minimapShown"))
            local locked = s.preferences:Get("lockWindows")
            s.lockCheckbox:SetChecked(locked)
            s.debugCheckbox:SetChecked(s.preferences:Get("debugLogging"))
            s.categoryButton:SetText(s.preferences:Get("defaultCategory") .. " >")
            local scale = s.preferences:Get("watchScale")
            s.scaleValue:SetText(string.format("%.0f%%", scale * 100))
            if scale == SCALES[1] then s.scaleMinus:Disable() else s.scaleMinus:Enable() end
            if scale == SCALES[#SCALES] then s.scalePlus:Disable() else s.scalePlus:Enable() end
            if locked then s:StopDrag() end
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
