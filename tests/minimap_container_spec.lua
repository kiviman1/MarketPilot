-- Contract fixtures for the installed EllesmereUIMinimap collector. These are
-- small behavioral mocks, not a rendered-client or third-party implementation.
local function fixture()
    local f = { objects = {}, reports = {}, watch = 0, settings = 0, named = {} }
    local env = setmetatable({}, { __index = _G })
    f.env = env
    local function widget(kind, name, parent)
        if name then assert(not f.named[name], "duplicate named frame") end
        local w = { kind = kind, name = name, parent = parent, shown = true, mouse = true,
            width = 140, height = 140, alpha = 1, scripts = {}, points = {}, showCalls = 0 }
        f.objects[#f.objects + 1] = w
        if name then f.named[name] = w end
        function w:GetName() return self.name end
        function w:IsObjectType(value) return self.kind == value end
        function w:GetParent() return self.parent end
        function w:SetParent(value) self.parent = value end
        function w:SetSize(x, y) self.width, self.height = x, y end
        function w:GetWidth() return self.width end
        function w:GetHeight() return self.height end
        function w:GetCenter() return 500, 500 end
        function w:GetEffectiveScale() return 1 end
        function w:ClearAllPoints() self.points = {} end
        function w:SetPoint(...) self.points[#self.points + 1] = { ... } end
        function w:GetPoint(i) return unpack(self.points[i or 1] or {}) end
        function w:SetMovable(value) self.movable = value end
        function w:SetFrameStrata(value) self.strata = value end
        function w:SetAlpha(value) self.alpha = value end
        function w:GetAlpha() return self.alpha end
        function w:EnableMouse(value) self.mouse = value end
        function w:RegisterForClicks(...) self.clicks = { ... } end
        function w:RegisterForDrag(...) self.drags = { ... } end
        function w:SetTexture(value)
            if f.failTexture then error("fixture texture failure") end
            self.texture = value
        end
        function w:SetHighlightTexture(...) self.highlight = { ... } end
        function w:CreateTexture() return widget("Texture", nil, self) end
        function w:SetScript(event, callback)
            assert(event ~= "OnUpdate", "launcher must not poll")
            self.scripts[event] = callback
        end
        function w:Fire(event, ...) if self.scripts[event] then return self.scripts[event](self, ...) end end
        function w:IsShown() return self.shown end
        function w:IsVisible() return self.shown and self.alpha > 0 and (not self.parent or self.parent:IsVisible()) end
        function w:SetShown(shown)
            local previous = self.shown
            self.shown = shown
            if previous ~= shown then self:Fire(shown and "OnShow" or "OnHide") end
        end
        function w:Show() self.showCalls = self.showCalls + 1; self:SetShown(true) end
        function w:Hide() self:SetShown(false) end
        function w:StartMoving() assert(self.movable); self.moving = true end
        function w:StopMovingOrSizing() self.moving = false end
        function w:Click(which)
            self:Fire("OnMouseDown", which)
            self:Fire("OnClick", which or "LeftButton")
        end
        return w
    end
    env.CreateFrame = widget
    env.Minimap = widget("Frame", "Minimap")
    env.GetCursorPosition = function() return 578, 500 end
    f.mp = {}
    for _, file in ipairs({ "Preferences.lua", "Minimap.lua" }) do
        setfenv(assert(loadfile("src/MarketPilot/" .. file)), env)("MarketPilot", f.mp)
    end
    f.root = { schema = 1, markets = { keep = { items = {} } }, _svCanary = 123 }
    f.prefs = f.mp.Preferences.New(f.root)
    f.launcher = f.mp.Minimap.New(f.prefs, {
        watch = function() f.watch = f.watch + 1 end,
        settings = function() f.settings = f.settings + 1 end,
    }, function(text) f.reports[#f.reports + 1] = text end)
    f.widget = widget

    function f:collector()
        local c = { wanted = {}, hooked = {}, buttons = {}, suppress = false }
        c.flyout = widget("Frame", "FixtureFlyout")
        c.flyout:Hide()
        function c:Gather()
            self.buttons = {}
            for _, child in ipairs(f.objects) do
                local name = child:GetName()
                -- Installed collector: named minimap/flyout Buttons, no numeric
                -- suffix; >=20px on first discovery, retained after resizing.
                if (child:GetParent() == env.Minimap or child:GetParent() == self.flyout)
                    and child:IsObjectType("Button") and name and not name:match("%d+$")
                    and (child:GetWidth() >= 20 or self.wanted[child] ~= nil) then
                    if self.wanted[child] == nil then self.wanted[child] = child:IsShown() end
                    self.buttons[#self.buttons + 1] = child
                end
            end
        end
        function c:HideOnMap()
            self:Gather()
            for _, button in ipairs(self.buttons) do
                self.suppress = true; button:Hide(); button:SetAlpha(0); self.suppress = false
                if not self.hooked[button] then
                    local show, hide = button.Show, button.Hide
                    function button:Show()
                        show(self)
                        if not c.suppress and not c.flyout:IsShown() then c.wanted[self] = true end
                        if not c.flyout:IsShown() then self:SetAlpha(0) end
                    end
                    function button:Hide()
                        hide(self)
                        if not c.suppress then
                            if c.flyout:IsShown() then self:Show(); return end
                            c.wanted[self] = false
                        end
                    end
                    self.hooked[button] = true
                end
            end
        end
        function c:Open()
            self:Gather(); self.flyout:Show()
            for _, button in ipairs(self.buttons) do
                if self.wanted[button] ~= false then
                    button:SetParent(self.flyout)
                    button:ClearAllPoints(); button:SetPoint("TOPLEFT", self.flyout, "TOPLEFT", 8, -8)
                    button:SetSize(24, 24)
                    self.suppress = true; button:SetAlpha(1); button:Show(); self.suppress = false
                    -- Collector takes the explicit icon instead of guessing a
                    -- decorative background from the texture-region ordering.
                    self.icon = button.icon or button.Icon
                    assert(self.icon)
                    self.icon:ClearAllPoints(); self.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
                end
            end
        end
        function c:Close() self.flyout:Hide() end
        return c
    end
    return f
end

local passed = 0
local function test(name, run) run(); passed = passed + 1; print("PASS " .. name) end
local function point(button) return { button:GetPoint(1) } end
local function samePoint(button, expected)
    local actual = point(button)
    for i = 1, 5 do assert(actual[i] == expected[i]) end
end

test("native named icon meets installed collector discovery without a library", function()
    local f = fixture(); assert(f.launcher:Refresh())
    local button = f.launcher.button
    assert(button:GetName() == "MarketPilotMinimapButton" and button:GetWidth() == 30)
    assert(button.icon == f.launcher.icon and button.icon.texture:find("MarketPilot", 1, true))
    assert(button:GetName():gsub("MinimapButton$", "") == "MarketPilot")
    local legacy = f.widget("Button", nil, f.env.Minimap)
    legacy:SetSize(30, 30)
    local c = f:collector(); c:Gather()
    assert(#c.buttons == 1 and c.buttons[1] == button)
    assert(f.root.preferences == nil and f.root._svCanary == 123)
end)

test("collector can discover the icon in either addon load order", function()
    for _, order in ipairs({ "collector-first", "launcher-first" }) do
        local f, c = fixture()
        if order == "collector-first" then c = f:collector(); c:HideOnMap(); assert(#c.buttons == 0) end
        f.launcher:Refresh()
        if not c then c = f:collector() end
        c:HideOnMap(); c:Open()
        assert(#c.buttons == 1 and f.launcher.button:GetParent() == c.flyout)
        assert(c.icon == f.launcher.icon and f.launcher.button:IsVisible())
        f.launcher.button:Click("LeftButton"); f.launcher.button:Click("RightButton")
        assert(f.watch == 1 and f.settings == 1)
    end
end)

test("lifecycle refreshes never unhide a collected icon or reset its container anchor", function()
    local f = fixture(); f.launcher:Refresh()
    local c = f:collector(); c:HideOnMap()
    local button, before = f.launcher.button, point(f.launcher.button)
    local calls = button.showCalls
    f.launcher:Refresh() -- Collected and hidden, but first flyout has not opened.
    assert(not button:IsShown() and button.showCalls == calls)
    samePoint(button, before)
    c:Open(); c:Close()
    before, calls = point(button), button.showCalls
    for _ = 1, 4 do assert(f.launcher:Refresh()) end -- AH/login/settings refreshes.
    assert(not c.flyout:IsShown() and not button:IsVisible() and button.showCalls == calls)
    assert(button:GetParent() == c.flyout); samePoint(button, before)
    c:Open(); before, calls = point(button), button.showCalls
    f.launcher:Refresh(); assert(button:IsVisible() and button.showCalls == calls)
    samePoint(button, before)
end)

test("a collector-owned row anchor on the minimap is also respected", function()
    local f = fixture(); f.launcher:Refresh()
    local button = f.launcher.button
    button:ClearAllPoints(); button:SetPoint("TOPLEFT", f.env.Minimap, "BOTTOMRIGHT", 10, -25)
    local before = point(button)
    assert(f.launcher:IsManaged())
    f.launcher:Refresh(); samePoint(button, before)
    button:Fire("OnDragStart"); button:Fire("OnDragStop")
    assert(not button.moving and f.root.preferences == nil); samePoint(button, before)
end)

test("container drag attempts do not move the button or overwrite native angle", function()
    local f = fixture(); f.prefs:Set("minimapAngle", 66); f.launcher:Refresh()
    local c = f:collector(); c:HideOnMap(); c:Open()
    local button, before = f.launcher.button, point(f.launcher.button)
    button:Fire("OnDragStart"); assert(not button.moving and not f.launcher.dragging)
    button:Fire("OnDragStop"); button:Fire("OnClick", "LeftButton")
    assert(f.watch == 0 and f.prefs:Get("minimapAngle") == 66); samePoint(button, before)
    button:Click("LeftButton"); assert(f.watch == 1)
end)

test("hide preference survives a collector force-show hook while its flyout is open", function()
    local f = fixture(); f.launcher:Refresh()
    local c = f:collector(); c:HideOnMap(); c:Open()
    local button, before = f.launcher.button, point(f.launcher.button)
    f.prefs:Set("minimapShown", false); f.launcher:Refresh()
    assert(c.flyout:IsShown() and not button:IsShown() and not button.mouse)
    button:Click("LeftButton"); button:Click("RightButton"); assert(f.watch == 0 and f.settings == 0)
    c:Close(); c:Open() -- A later layout must not resurrect the disabled icon.
    assert(not button:IsShown() and not button.mouse); samePoint(button, before)
    f.prefs:Set("minimapShown", true); f.launcher:Refresh()
    assert(button:IsVisible() and button.mouse and button:GetParent() == c.flyout)
    button:Click("RightButton"); assert(f.settings == 1)
end)

test("explicit hide and show while container is closed preserve its hidden parent", function()
    local f = fixture(); f.launcher:Refresh()
    local c = f:collector(); c:HideOnMap(); c:Open(); c:Close()
    local button, before = f.launcher.button, point(f.launcher.button)
    f.prefs:Set("minimapShown", false); f.launcher:Refresh()
    assert(c.wanted[button] == false and not button:IsVisible())
    f.prefs:Set("minimapShown", true); f.launcher:Refresh()
    assert(c.wanted[button] == true and not c.flyout:IsShown() and not button:IsVisible())
    samePoint(button, before)
    c:Open(); assert(button:IsVisible())
end)

test("partial named creation retries the same frame rather than colliding with its global", function()
    local f = fixture(); f.failTexture = true
    assert(not f.launcher:Refresh())
    local partial = f.launcher.button
    assert(partial and not partial:IsShown() and not f.launcher.created)
    f.failTexture = false; assert(f.launcher:Refresh())
    assert(f.launcher.button == partial and partial:IsVisible() and f.launcher.created)
    assert(f.named.MarketPilotMinimapButton == partial and #f.reports == 1)
end)

test("optional installed bridge handles enabling an omitted icon while flyout is already open", function()
    local f = fixture(); f.launcher:Refresh()
    local c = f:collector(); c:HideOnMap(); c:Open(); c:Close()
    local button, other = f.launcher.button, {}
    c.wanted[other] = false
    f.env._EBS_AddonVisible = c.wanted
    local applications = 0
    f.env._EMM_ApplyMinimap = function()
        applications = applications + 1
        c:Close(); c:HideOnMap()
    end
    f.prefs:Set("minimapShown", false); f.launcher:Refresh()
    assert(c.wanted[button] == false and applications == 1)
    c:Open(); assert(not button:IsVisible())
    f.prefs:Set("minimapShown", true); f.launcher:Refresh()
    assert(c.wanted[button] == true and applications == 2 and not c.flyout:IsShown())
    c:Open(); assert(button:IsVisible() and c.icon == button.icon)
    f.launcher:Refresh(); f.launcher:Refresh()
    assert(applications == 2 and c.wanted[other] == false)
    f.prefs:Set("minimapShown", false); f.launcher:Refresh()
    assert(applications == 3 and not button:IsVisible() and c.wanted[button] == false)
    assert(f.root.markets.keep and f.root._svCanary == 123)
end)

test("optional collector bridge never registers unknown buttons or changes unrelated intent", function()
    local f = fixture(); local other, applications = {}, 0
    f.env._EBS_AddonVisible = { [other] = true }
    f.env._EMM_ApplyMinimap = function() applications = applications + 1 end
    f.launcher:Refresh()
    f.prefs:Set("minimapShown", false); f.launcher:Refresh()
    f.prefs:Set("minimapShown", true); f.launcher:Refresh()
    assert(applications == 0 and f.env._EBS_AddonVisible[f.launcher.button] == nil)
    assert(f.env._EBS_AddonVisible[other] == true)
    f.env._EBS_AddonVisible[f.launcher.button] = true
    f.env._EMM_ApplyMinimap = false
    f.prefs:Set("minimapShown", false); f.launcher:Refresh()
    assert(f.env._EBS_AddonVisible[f.launcher.button] == true) -- Missing bridge stays untouched.
end)

test("failed optional collector refresh reports the issue and preserves requested own intent", function()
    local f = fixture(); f.launcher:Refresh()
    local other, applications = {}, 0
    f.env._EBS_AddonVisible = { [f.launcher.button] = true, [other] = false }
    f.env._EMM_ApplyMinimap = function() applications = applications + 1; error("collector fixture failure") end
    f.prefs:Set("minimapShown", false)
    assert(f.launcher:Refresh() and not f.launcher.button:IsVisible())
    assert(f.env._EBS_AddonVisible[f.launcher.button] == false and f.env._EBS_AddonVisible[other] == false)
    assert(applications == 1 and #f.reports == 1 and f.reports[1]:find("collector refresh failed", 1, true))
    f.launcher:Refresh(); assert(applications == 1)
end)

test("collector compatibility adds no framework hooks polling or auction dependency", function()
    local file = assert(io.open("src/MarketPilot/Minimap.lua", "rb"))
    local text = file:read("*a"); file:close()
    for _, forbidden in ipairs({ "LibStub", "LibDBIcon", "C_AuctionHouse", "C_Timer", "OnUpdate", "hooksecurefunc" }) do
        assert(not text:find(forbidden, 1, true), forbidden)
    end
    local f = fixture(); f.launcher:Refresh()
    assert(f.root.markets.keep and f.root.preferences == nil and f.root._svCanary == 123)
end)

print("PASS " .. passed .. " minimap collector offline tests (Lua 5.1); live container rendering remains unverified")
