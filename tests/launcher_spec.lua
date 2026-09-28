-- Standalone launcher/settings event tests; no actual client frames are rendered.
local function fixture(configure)
    local f = { objects = {}, output = {}, watch = 0, settings = 0, changed = {}, reset = 0, cursorX = 600, cursorY = 500 }
    local env = setmetatable({}, { __index = _G }); f.env = env
    local function widget(parent)
        local w = { parent = parent, shown = true, scripts = {}, width = 140, height = 140, cx = 500, cy = 500, scale = 1 }
        f.objects[#f.objects + 1] = w
        function w:SetSize(width, height) self.width, self.height = width, height end
        function w:SetWidth(value) self.width = value end
        function w:GetWidth() return self.width end
        function w:GetHeight() return self.height end
        function w:GetCenter() return self.cx, self.cy end
        function w:GetEffectiveScale() return self.scale end
        function w:SetPoint(...) self.point = { ... } end
        function w:ClearAllPoints() self.point = nil end
        function w:SetAllPoints(value) self.allPoints = value end
        function w:SetColorTexture(...) self.color = { ... } end
        function w:SetTexture(value) self.texture = value end
        function w:SetHighlightTexture(...) self.highlight = { ... } end
        function w:SetText(value) self.text = value end
        function w:SetJustifyH(value) self.justify = value end
        function w:SetWordWrap(value) self.wrap = value end
        function w:SetMovable(value) self.movable = value end
        function w:SetFrameStrata(value) self.strata = value end
        function w:SetClampedToScreen(value) self.clamped = value end
        function w:EnableMouse(value) self.mouse = value end
        function w:RegisterForDrag(...) self.dragButtons = { ... } end
        function w:RegisterForClicks(...) self.clickButtons = { ... } end
        function w:StartMoving() assert(self.movable); self.moving = true end
        function w:StopMovingOrSizing() self.moving = false end
        function w:SetChecked(value) self.checked = value end
        function w:GetChecked() return self.checked end
        function w:IsShown() return self.shown end
        function w:Show() self.shown = true end
        function w:Hide()
            local shown = self.shown; self.shown = false
            if shown and self.scripts.OnHide then self.scripts.OnHide(self) end
        end
        function w:SetScript(event, callback)
            assert(event ~= "OnUpdate", "no polling")
            self.scripts[event] = callback
        end
        function w:Fire(event, ...) if self.scripts[event] then return self.scripts[event](self, ...) end end
        function w:Click(button)
            self:Fire("OnMouseDown", button); self:Fire("OnClick", button or "LeftButton")
        end
        function w:CreateTexture() return widget(self) end
        function w:CreateFontString() return widget(self) end
        return w
    end
    env.CreateFrame = function(_, name, parent) assert(name == nil); return widget(parent) end
    env.UIParent, env.Minimap = widget(), widget()
    env.GetCursorPosition = function() return f.cursorX, f.cursorY end
    env.GameTooltip = { lines = {} }
    function env.GameTooltip:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
    function env.GameTooltip:SetText(text) self.text, self.lines = text, {} end
    function env.GameTooltip:AddLine(text) self.lines[#self.lines + 1] = text end
    function env.GameTooltip:Show() self.shown = true end
    function env.GameTooltip:Hide() self.shown = false end
    if configure then configure(f) end
    f.mp = {}
    for _, file in ipairs({ "Preferences.lua", "Settings.lua", "Minimap.lua" }) do
        setfenv(assert(loadfile("src/MarketPilot/" .. file)), env)("MarketPilot", f.mp)
    end
    f.root = { schema = 1, markets = { untouched = { items = {} } }, _svCanary = 20 }
    f.prefs = f.mp.Preferences.New(f.root)
    local report = function(message) f.output[#f.output + 1] = message end
    f.launcher = f.mp.Minimap.New(f.prefs, { watch = function() f.watch = f.watch + 1 end,
        settings = function() f.settings = f.settings + 1 end }, report)
    f.window = f.mp.Settings.New(f.prefs, { onChanged = function(key) f.changed[#f.changed + 1] = key; f.launcher:Refresh() end,
        onResetPositions = function() f.reset = f.reset + 1 end }, report)
    return f
end
local passed = 0
local function test(name, run) run(); passed = passed + 1; print("PASS " .. name) end
local function near(a, b) assert(math.abs(a - b) < 0.000001) end

test("minimap lazily creates branded icon with left/right actions and tooltip", function()
    local f = fixture(); assert(f.launcher.button == nil)
    assert(f.launcher:Refresh())
    local button = f.launcher.button
    assert(button.parent == f.env.Minimap and button.shown and f.launcher.icon.texture == "Interface\\AddOns\\MarketPilot\\Media\\Icon.tga")
    button:Click("LeftButton"); button:Click("RightButton"); button:Click("MiddleButton")
    assert(f.watch == 1 and f.settings == 1 and f.root.preferences == nil)
    button:Fire("OnEnter"); assert(f.env.GameTooltip.shown and #f.env.GameTooltip.lines == 3)
    button:Fire("OnLeave"); assert(not f.env.GameTooltip.shown)
    local count = #f.objects; f.launcher:Refresh(); assert(#f.objects == count)
end)
test("missing minimap reports once and can recover when standard frame appears", function()
    local f = fixture(function(f) f.env.Minimap = nil end)
    assert(not f.launcher:Refresh() and not f.launcher:Refresh() and #f.output == 1 and not f.launcher.button)
    f.env.Minimap = f.env.UIParent
    assert(f.launcher:Refresh() and f.launcher.button.shown and f.root.preferences == nil)
end)
test("explicit hiding does not create an icon and settings checkbox restores it", function()
    local f = fixture(); f.prefs:Set("minimapShown", false)
    assert(f.launcher:Refresh() and f.launcher.button == nil)
    f.window:Toggle(); assert(f.window.frame.parent == f.env.UIParent and not f.window.checkbox.checked)
    f.window.checkbox.checked = true; f.window.checkbox:Click()
    assert(f.prefs:Get("minimapShown") and f.launcher.button.shown)
    f.window.checkbox.checked = false; f.window.checkbox:Click()
    assert(not f.launcher.button.shown and f.changed[#f.changed] == "minimapShown")
    assert(f.window.frame.shown and f.root.markets.untouched and f.root._svCanary == 20)
end)
test("drag stops persist minimap angle once with scale and no click-through action", function()
    local f = fixture(); f.launcher:Refresh()
    local button = f.launcher.button
    f.env.Minimap.scale = 0.5
    button:Fire("OnMouseDown", "LeftButton"); button:Fire("OnDragStart")
    assert(button.moving and f.root.preferences == nil)
    f.cursorX, f.cursorY = 250, 300
    button:Fire("OnDragStop"); assert(not button.moving)
    near(f.prefs:Get("minimapAngle"), 90)
    near(button.point[4], 0); near(button.point[5], 78)
    button:Fire("OnClick", "LeftButton"); assert(f.watch == 0)
    button:Click("LeftButton"); assert(f.watch == 1)
    assert(button.scripts.OnUpdate == nil)
end)
test("invalid cursor cannot overwrite saved angle and hiding stops native movement", function()
    local f = fixture(); f.prefs:Set("minimapAngle", 10); f.launcher:Refresh()
    f.launcher.button:Fire("OnDragStart"); f.cursorX = 0/0
    f.prefs:Set("minimapShown", false); f.launcher:Refresh()
    assert(not f.launcher.dragging and not f.launcher.button.moving and not f.launcher.button.shown)
    assert(f.prefs:Get("minimapAngle") == 10)
end)
test("settings is independent draggable UIParent window with persisted position and close", function()
    local f = fixture(function(f) f.env.Minimap = nil end)
    assert(not f.window.frame); f.window:Toggle()
    local panel, title = f.window.frame, f.window.titleHandle
    assert(panel.parent == f.env.UIParent and panel.shown and panel.clamped)
    title:Fire("OnDragStart"); assert(panel.moving)
    panel.cx, panel.cy = 650, 430
    title:Fire("OnDragStop")
    assert(not panel.moving and f.prefs:Get("settingsPosition").x == 150 and f.prefs:Get("settingsPosition").y == -70)
    local count = #f.objects
    f.window.closeButton:Click(); assert(not panel.shown)
    f.window:Toggle(); assert(panel.shown and #f.objects == count)
    assert(panel.point[4] == 150 and panel.point[5] == -70)
end)
test("closing a moving settings window ends movement and reset preserves minimap/history", function()
    local f = fixture(); f.window:Toggle()
    f.window.titleHandle:Fire("OnDragStart"); f.window.frame.cx = 600
    f.window.closeButton:Click(); assert(not f.window.dragging and not f.window.frame.moving)
    assert(f.prefs:Get("settingsPosition").x == 100)
    f.prefs:Set("watchPosition", { x = 900, y = 500 }); f.prefs:Set("minimapShown", false); f.prefs:Set("minimapAngle", 66)
    f.window:Toggle(); f.window.resetButton:Click()
    assert(f.prefs:Get("watchPosition") == nil and f.prefs:Get("settingsPosition") == nil and f.reset == 1)
    assert(f.window.frame.point[4] == 0 and f.window.frame.point[5] == 0)
    assert(not f.prefs:Get("minimapShown") and f.prefs:Get("minimapAngle") == 66)
    assert(f.root.markets.untouched and f.root._svCanary == 20)
end)
test("settings refresh after root bind reads saved visibility and position without writes", function()
    local f = fixture(); f.window:Toggle()
    local saved = { schema = 1, markets = {}, preferences = { version = 1, minimapShown = false, settingsPosition = { x = 40, y = 90 } } }
    f.prefs:Bind(saved); f.window:Refresh()
    assert(not f.window.checkbox.checked and f.window.frame.point[4] == 40 and f.window.frame.point[5] == 90)
    assert(saved.preferences.minimapAngle == nil and saved.preferences.watchPosition == nil)
end)
test("launcher and settings callback failures are guarded and keep scanner-free controls usable", function()
    local f = fixture(); f.launcher:Refresh(); f.window:Toggle()
    f.launcher.callbacks.watch = function() error("watch failure") end
    f.launcher.button:Click("LeftButton"); assert(#f.output == 1 and f.output[1]:find("watch failure", 1, true))
    f.window.callbacks.onChanged = function() error("settings failure") end
    f.window.checkbox:Click(); assert(#f.output == 2 and f.output[2]:find("settings failure", 1, true))
    f.launcher.button:Click("RightButton"); assert(f.settings == 1)
end)
test("partial frame creation failures are hidden and retry without wedging either window", function()
    local f = fixture()
    local create = f.env.CreateFrame
    f.env.CreateFrame = function(...)
        local frame = create(...)
        frame.SetMovable = function() error("movement unavailable") end
        return frame
    end
    assert(not f.window:Toggle() and not f.window.frame)
    assert(not f.launcher:Refresh() and not f.launcher.button)
    assert(f.window:Refresh())
    f.env.CreateFrame = create
    assert(f.window:Toggle() and f.window.frame.shown)
    assert(f.launcher:Refresh() and f.launcher.button.shown)
    assert(#f.output == 2)
end)
test("lifecycle refresh never reanchors a natively moving settings window or minimap icon", function()
    local f = fixture(); f.window:Toggle(); f.launcher:Refresh()
    f.window.titleHandle:Fire("OnDragStart"); f.launcher.button:Fire("OnDragStart")
    local settingsPoint, iconPoint = f.window.frame.point, f.launcher.button.point
    f.window:Refresh(); f.launcher:Refresh()
    assert(f.window.frame.point == settingsPoint and f.launcher.button.point == iconPoint)
    assert(f.window.frame.moving and f.launcher.button.moving)
    f.window.titleHandle:Fire("OnDragStop"); f.launcher.button:Fire("OnDragStop")
    assert(not f.window.frame.moving and not f.launcher.button.moving)
end)
test("settings and launcher contain no AH, scan, polling, or framework dependencies", function()
    for _, name in ipairs({ "Preferences.lua", "Settings.lua", "Minimap.lua" }) do
        local file = assert(io.open("src/MarketPilot/" .. name, "rb")); local source = file:read("*a"); file:close()
        for _, forbidden in ipairs({ "C_AuctionHouse", "Scanner", "OnUpdate", "C_Timer", "Ace", "LibDBIcon", "HookScript" }) do
            assert(not source:find(forbidden, 1, true), name .. " " .. forbidden)
        end
    end
end)
print("PASS " .. passed .. " launcher/settings offline tests (Lua 5.1)")
