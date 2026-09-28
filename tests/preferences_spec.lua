-- Pure Lua 5.1 preferences; no client or market math dependencies.
local MP = {}
assert(loadfile("src/MarketPilot/Preferences.lua"))("MarketPilot", MP)
local P, passed = MP.Preferences, 0
local function test(name, run) run(); passed = passed + 1; print("PASS " .. name) end
local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, item in pairs(value) do result[key] = clone(item) end; return result
end
local function equal(a, b)
    assert(type(a) == type(b))
    if type(a) ~= "table" then assert(a == b); return end
    for key, value in pairs(a) do equal(value, b[key]) end
    for key in pairs(b) do assert(a[key] ~= nil) end
end
local function root()
    return { schema = 1, markets = { fixture = { items = { [2770] = { snapshots = { { t = 100, cleanMedian = 20 } } } } } }, _svCanary = 123 }
end

test("reading defaults and binding never creates preferences or changes history", function()
    local saved = root(); local before = clone(saved)
    local prefs = P.New(saved)
    assert(prefs:Get("minimapShown") == true and prefs:Get("minimapAngle") == 220)
    assert(prefs:Get("watchPosition") == nil and prefs:Get("settingsPosition") == nil)
    assert(prefs:Get("unrecognized") == nil)
    prefs:Bind(saved); prefs:ResetPositions()
    equal(saved, before)
end)
test("explicit settings are account-wide and preserve schema history and canary", function()
    local saved = root(); local before = clone(saved)
    local prefs = P.New(saved)
    assert(prefs:Set("minimapShown", false))
    assert(prefs:Set("minimapAngle", -90))
    assert(prefs:Set("watchPosition", { x = 120, y = -45 }))
    assert(prefs:Set("settingsPosition", { x = -220, y = 70 }))
    assert(saved.preferences.version == 1 and saved.preferences.minimapAngle == 270)
    local reload = P.New(saved)
    assert(reload:Get("minimapShown") == false and reload:Get("minimapAngle") == 270)
    equal(reload:Get("watchPosition"), { x = 120, y = -45 })
    local copy = clone(saved); copy.preferences = nil; equal(copy, before)
end)
test("position inputs and reads are defensive copies", function()
    local saved = root(); local prefs = P.New(saved)
    local value = { x = 50, y = 20, unwanted = "omit" }
    prefs:Set("watchPosition", value); value.x = 900
    local read = prefs:Get("watchPosition"); read.y = 800
    equal(saved.preferences.watchPosition, { x = 50, y = 20 })
    equal(prefs:Get("watchPosition"), { x = 50, y = 20 })
end)
test("invalid values do not create or overwrite preference storage", function()
    local saved = root(); local prefs = P.New(saved)
    for _, pair in ipairs({ { "minimapShown", 1 }, { "minimapAngle", math.huge }, { "minimapAngle", 0/0 },
        { "watchPosition", { x = 1 } }, { "settingsPosition", { x = 0, y = 0/0 } },
        { "watchPosition", { x = 100001, y = 2 } }, { "unknown", true } }) do
        assert(not prefs:Set(pair[1], pair[2]))
    end
    assert(saved.preferences == nil)
    saved.preferences = { version = 1, minimapShown = "invalid", minimapAngle = math.huge, watchPosition = { x = 3 } }
    local before = clone(saved)
    assert(prefs:Get("minimapShown") and prefs:Get("minimapAngle") == 220 and prefs:Get("watchPosition") == nil)
    equal(saved, before)
end)
test("unsupported roots and future preference versions stay untouched with session settings", function()
    for _, saved in ipairs({ false, "invalid", { schema = 2, markets = {} },
        { schema = 1, markets = {}, preferences = { version = 2, minimapShown = false, future = "keep" } },
        { schema = 1, markets = {}, preferences = "unsupported" } }) do
        local before, prefs = clone(saved), P.New(saved)
        assert(prefs:Get("minimapShown") == true)
        local ok, status = prefs:Set("minimapShown", false)
        assert(ok and status == "SESSION_ONLY" and prefs:Get("minimapShown") == false)
        prefs:Set("watchPosition", { x = 1, y = 2 }); prefs:ResetPositions()
        assert(prefs:Get("watchPosition") == nil)
        equal(saved, before)
    end
    local prefs = P.New(nil); prefs:Set("minimapAngle", 10)
    assert(prefs.root == nil and prefs:Get("minimapAngle") == 10)
end)
test("late binding reads saved values and never copies session defaults into history", function()
    local prefs = P.New(nil); prefs:Set("minimapShown", false)
    local saved = root(); saved.preferences = { version = 1, minimapShown = true, minimapAngle = 33 }
    local before = clone(saved); prefs:Bind(saved)
    assert(prefs:Get("minimapShown") == true and prefs:Get("minimapAngle") == 33)
    equal(saved, before)
end)
test("reset removes only window positions and preserves minimap and future fields", function()
    local saved = root()
    saved.preferences = { version = 1, minimapShown = false, minimapAngle = 12, extra = "keep",
        watchPosition = { x = 2, y = 3 }, settingsPosition = { x = 4, y = 5 } }
    local prefs, before = P.New(saved), clone(saved)
    prefs:ResetPositions()
    before.preferences.watchPosition, before.preferences.settingsPosition = nil, nil
    equal(saved, before)
end)
test("window positions capture scaled center coordinates and apply with screen clamping", function()
    local parent = { GetCenter = function() return 500, 400 end, GetEffectiveScale = function() return 0.8 end }
    local frame = { GetCenter = function() return 300, 250 end, GetEffectiveScale = function() return 1.6 end }
    function frame:ClearAllPoints() self.cleared = true end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:SetClampedToScreen(value) self.clamped = value end
    local value = P.CapturePosition(frame, parent)
    equal(value, { x = 100, y = 100 })
    assert(P.ApplyPosition(frame, parent, value))
    assert(frame.point[1] == "CENTER" and frame.point[2] == parent and frame.point[4] == 50 and frame.point[5] == 50)
    assert(frame.cleared and frame.clamped)
    P.ApplyPosition(frame, parent, nil); assert(frame.point[4] == 0 and frame.point[5] == 0)
    frame.GetCenter = function() return nil, nil end
    assert(P.CapturePosition(frame, parent) == nil and P.CapturePosition(nil, parent) == nil)
    assert(P.ApplyPosition(nil, parent, value) == false)
end)
print("PASS " .. passed .. " preferences offline tests (Lua 5.1)")
