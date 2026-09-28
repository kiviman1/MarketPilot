local _, MP = ...
local Launcher = {}
Launcher.__index = Launcher
MP.Minimap = Launcher
local ICON = "Interface\\AddOns\\MarketPilot\\Media\\Icon.tga"

function Launcher.New(preferences, callbacks, report)
    return setmetatable({ preferences = preferences, callbacks = callbacks or {}, report = report or function() end }, Launcher)
end
function Launcher:Warn(message)
    if self.lastWarning ~= message then self.report("Minimap icon unavailable: " .. message) end
    self.lastWarning = message
end
function Launcher:Guard(callback, ...)
    local ok, err = pcall(callback, self, ...)
    if not ok then
        if self.button and not self.created then
            local partial = self.button
            self.button, self.icon = nil, nil
            pcall(partial.Hide, partial)
        end
        self:Warn(tostring(err))
    end
    return ok
end
local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function angle(x, y)
    if x == 0 then return y > 0 and 90 or 270 end
    local degrees = math.atan(y / x) * 180 / math.pi
    if x < 0 then degrees = degrees + 180 end
    return degrees % 360
end
function Launcher:Place()
    local radians = self.preferences:Get("minimapAngle") * math.pi / 180
    local width, height = self.anchor:GetWidth(), self.anchor:GetHeight()
    if not finite(width) or not finite(height) or width <= 0 or height <= 0 then error("minimap size is not ready") end
    local radius = math.min(width, height) / 2 + 8
    self.button:ClearAllPoints()
    self.button:SetPoint("CENTER", self.anchor, "CENTER", math.cos(radians) * radius, math.sin(radians) * radius)
end
function Launcher:StopDrag()
    if not self.dragging then return end
    self.dragging = false
    self.button:StopMovingOrSizing()
    if type(GetCursorPosition) == "function" then
        local cursorOK, x, y = pcall(GetCursorPosition)
        local cx, cy = self.anchor:GetCenter()
        local scale = self.anchor.GetEffectiveScale and self.anchor:GetEffectiveScale() or 1
        if cursorOK and finite(x) and finite(y) and finite(cx) and finite(cy) and finite(scale) and scale > 0 then
            local dx, dy = x / scale - cx, y / scale - cy
            if dx ~= 0 or dy ~= 0 then self.preferences:Set("minimapAngle", angle(dx, dy)) end
        end
    end
    self:Place()
end
function Launcher:Create()
    self.anchor = Minimap
    local button = CreateFrame("Button", nil, self.anchor)
    self.button = button
    button:Hide(); button:SetSize(30, 30); button:EnableMouse(true); button:SetMovable(true)
    if button.SetFrameStrata then button:SetFrameStrata("MEDIUM") end
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp"); button:RegisterForDrag("LeftButton")
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(button); background:SetColorTexture(0.08, 0.10, 0.14, 1)
    local icon = button:CreateTexture(nil, "ARTWORK")
    self.icon = icon
    icon:SetPoint("CENTER", button, "CENTER", 0, 0); icon:SetSize(24, 24); icon:SetTexture(ICON)
    if button.SetHighlightTexture then button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD") end
    button:SetScript("OnClick", function(_, which)
        if self.dragging or self.suppressClick then self.suppressClick = false; return end
        local callback = which == "RightButton" and self.callbacks.settings or (which == "LeftButton" and self.callbacks.watch)
        if callback then self:Guard(function() callback() end) end
    end)
    button:SetScript("OnMouseDown", function() self.suppressClick = false end)
    button:SetScript("OnDragStart", function() self:Guard(function(s)
        if GameTooltip then GameTooltip:Hide() end
        s.button:StartMoving(); s.dragging, s.suppressClick = true, true
    end) end)
    button:SetScript("OnDragStop", function() self:Guard(self.StopDrag) end)
    button:SetScript("OnHide", function() self:Guard(self.StopDrag); if GameTooltip then GameTooltip:Hide() end end)
    button:SetScript("OnEnter", function() self:Guard(function(s)
        if not GameTooltip then return end
        GameTooltip:SetOwner(s.button, "ANCHOR_LEFT"); GameTooltip:SetText("MarketPilot")
        GameTooltip:AddLine("Left click: Market Watch", 1, 1, 1)
        GameTooltip:AddLine("Right click: settings", 1, 1, 1)
        GameTooltip:AddLine("Drag: move icon", 0.7, 0.7, 0.7); GameTooltip:Show()
    end) end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    self.created = true
end
function Launcher:Refresh()
    if not self.preferences:Get("minimapShown") then
        if self.button then self:Guard(self.StopDrag); self.button:Hide() end
        return true
    end
    if not Minimap or type(CreateFrame) ~= "function" then self:Warn("minimap frame is not ready"); return false end
    return self:Guard(function(s)
        if not s.button then s:Create() end
        if not s.dragging then s:Place() end
        s.button:Show(); s.lastWarning = nil
    end)
end
