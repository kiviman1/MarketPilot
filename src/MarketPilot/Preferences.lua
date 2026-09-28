local _, MP = ...
local Preferences = {}
Preferences.__index = Preferences
MP.Preferences = Preferences

local defaults = { minimapShown = true, minimapAngle = 220, watchScale = 1,
    defaultCategory = "All", lockWindows = false, debugLogging = false }
local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function position(value)
    if type(value) ~= "table" or not finite(rawget(value, "x")) or not finite(rawget(value, "y")) then return nil end
    if math.abs(value.x) > 100000 or math.abs(value.y) > 100000 then return nil end
    return { x = value.x, y = value.y }
end
local function validate(key, value)
    if key == "minimapShown" or key == "lockWindows" or key == "debugLogging" then return type(value) == "boolean", value end
    if key == "minimapAngle" then return finite(value), finite(value) and value % 360 or nil end
    if key == "watchScale" then
        return value == 0.8 or value == 0.9 or value == 1 or value == 1.1 or value == 1.2, value
    end
    if key == "defaultCategory" then
        return value == "All" or value == "Mining" or value == "Herbalism" or value == "Skinning", value
    end
    if key == "watchPosition" or key == "settingsPosition" then
        if value == nil then return true, nil end
        local copy = position(value); return copy ~= nil, copy
    end
    return false
end
local function saved(self)
    local root = self.root
    if type(root) ~= "table" or rawget(root, "schema") ~= 1 or type(rawget(root, "markets")) ~= "table" then return nil, false end
    local prefs = rawget(root, "preferences")
    if prefs == nil then return nil, true end
    if type(prefs) == "table" and rawget(prefs, "version") == 1 then return prefs, true end
    return nil, false -- Preserve unsupported formats; this session can still use defaults.
end

function Preferences.New(root)
    return setmetatable({ root = root, session = {}, overrides = {} }, Preferences)
end
function Preferences:Bind(root)
    if self.root ~= root then self.root, self.session, self.overrides = root, {}, {} end
end
function Preferences:Get(key)
    if self.overrides[key] then
        local _, value = validate(key, self.session[key]); return value
    end
    local prefs = saved(self)
    if prefs then
        local value = rawget(prefs, key)
        if value ~= nil then local ok, copy = validate(key, value); if ok then return copy end end
    end
    return defaults[key]
end
function Preferences:Set(key, value)
    local ok, copy = validate(key, value)
    if not ok then return false end
    local prefs, writable = saved(self)
    if writable then
        if not prefs and copy ~= nil then
            prefs = { version = 1 }; rawset(self.root, "preferences", prefs)
        end
        if prefs then rawset(prefs, key, copy) end
        self.session[key], self.overrides[key] = nil, nil
        return true, "SAVED"
    end
    self.session[key], self.overrides[key] = copy, true
    return true, "SESSION_ONLY"
end
function Preferences:ResetPositions()
    self:Set("watchPosition", nil)
    self:Set("settingsPosition", nil)
end

local function method(frame, name)
    return frame and (type(frame) == "table" or type(frame) == "userdata") and type(frame[name]) == "function"
end
local function scale(frame)
    if method(frame, "GetEffectiveScale") then
        local ok, value = pcall(frame.GetEffectiveScale, frame)
        if ok and finite(value) and value > 0 then return value end
    end
    return 1
end
function Preferences.CapturePosition(frame, parent)
    if not method(frame, "GetCenter") or not method(parent, "GetCenter") then return nil end
    local ok, x, y = pcall(frame.GetCenter, frame)
    local parentOK, px, py = pcall(parent.GetCenter, parent)
    if not ok or not parentOK or not finite(x) or not finite(y) or not finite(px) or not finite(py) then return nil end
    local ratio = scale(frame) / scale(parent)
    return position({ x = x * ratio - px, y = y * ratio - py })
end
function Preferences.ApplyPosition(frame, parent, value)
    if not parent or not method(frame, "ClearAllPoints") or not method(frame, "SetPoint") then return false end
    local p = position(value) or { x = 0, y = 0 }
    local ratio = scale(parent) / scale(frame)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", parent, "CENTER", p.x * ratio, p.y * ratio)
    if method(frame, "SetClampedToScreen") then frame:SetClampedToScreen(true) end
    return true
end
