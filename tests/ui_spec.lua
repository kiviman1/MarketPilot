-- Strict mocked frame/client tests, NOT evidence of a rendered Forever panel.
-- Run from repository root: lua tests/ui_spec.lua
local ROOT = "src/MarketPilot/"
local function read(path)
    local file = assert(io.open(path, "rb")); local value = file:read("*a"); file:close(); return value
end
local files = {}
for line in read(ROOT .. "MarketPilot.toc"):gmatch("[^\r\n]+") do
    if line:sub(1, 1) ~= "#" then files[#files + 1] = line end
end

local function fixture(configure)
    local f = { output = {}, objects = {}, sent = {}, infoCalls = {}, ready = true,
        namesReady = true, reads = 0, rows = { { unitPrice = 199, quantity = 100 }, { unitPrice = 200, quantity = 372 } } }
    local env = setmetatable({}, { __index = _G })
    env._G, env.SlashCmdList = env, {}
    f.env = env
    local function widget(kind, parent)
        local w = { kind = kind, parent = parent, shown = true, enabled = true, scripts = {}, events = {} }
        f.objects[#f.objects + 1] = w
        function w:GetObjectType() return self.kind end
        function w:EnableMouseWheel(value) self.mouseWheel = value end
        function w:SetScrollChild(child) self.child = child end
        function w:GetVerticalScroll() return self.offset or 0 end
        function w:SetVerticalScroll(value) self.offset = value end
        function w:SetPoint(...)
            if f.failAnchor and self.kind == "Frame" and self.parent == env.AuctionHouseFrame then error("fixture anchor failure") end
            self.point = { ... }
        end
        function w:SetSize(width, height) self.width, self.height = width, height end
        function w:SetWidth(width) self.width = width end
        function w:SetHeight(height) self.height = height end
        function w:Show() self.shown = true end
        function w:Hide() self.shown = false end
        function w:IsShown() return self.shown end
        function w:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
        function w:Enable() self.enabled = true end
        function w:Disable() self.enabled = false end
        function w:EnableMouse(value) self.mouse = value end
        function w:SetText(value) self.text = value end
        function w:SetJustifyH(value) self.justify = value end
        function w:SetJustifyV(value) self.justifyV = value end
        function w:SetTexture(value) self.texture = value end
        function w:SetColorTexture(...) self.color = { ... } end
        function w:SetAllPoints(value) self.allPoints = value end
        function w:CreateFontString(_, _, font) local item = widget("FontString", self); item.font = font; return item end
        function w:CreateTexture() return widget("Texture", self) end
        function w:SetScript(event, callback)
            assert(event == "OnEvent" or event == "OnClick" or event == "OnMouseWheel", "unexpected hook: " .. event)
            self.scripts[event] = callback
        end
        function w:RegisterEvent(event) self.events[event] = true end
        function w:Click(force)
            if force or (self.enabled and self:IsVisible()) then return self.scripts.OnClick(self) end
        end
        return w
    end
    env.CreateFrame = function(kind, name, parent, template)
        assert(name == nil, "no global widget names needed")
        local frame = widget(kind, parent)
        frame.template = template
        return frame
    end
    f.makeAnchor = function() env.AuctionHouseFrame = widget("Frame"); return env.AuctionHouseFrame end
    f.makeAnchor()
    env.print = function(line) f.output[#f.output + 1] = line end
    f.now = 4000000
    env.time = function() return f.now end
    env.GetRealmName = function() return "Fixture Realm" end
    env.UnitFactionGroup = function(unit) assert(unit == "player"); return "Alliance" end
    env.GetItemInfo = function(id)
        f.infoCalls[id] = (f.infoCalls[id] or 0) + 1
        if not f.namesReady then return nil end
        if f.syncInfo then f:event("GET_ITEM_INFO_RECEIVED", id, true) end
        return "Client item " .. id, nil, nil, nil, nil, nil, nil, nil, nil, id + 10000
    end
    env.C_AuctionHouse = {
        MakeItemKey = function(id) return { itemID = id } end,
        SendSearchQuery = function(key, sorts, flag)
            assert(next(sorts) == nil and flag == true)
            f.sent[#f.sent + 1] = key.itemID
        end,
        IsThrottledMessageSystemReady = function() return f.ready end,
        GetNumCommoditySearchResults = function() return #f.rows end,
        GetCommoditySearchResultInfo = function(_, index) f.reads = f.reads + 1; return f.rows[index] end,
    }
    if configure then configure(f) end
    f.mp = {}
    for _, path in ipairs(files) do setfenv(assert(loadfile(ROOT .. path)), env)("MarketPilot", f.mp) end
    f.panel, f.scanner, f.view = f.mp.panel, f.mp.scanner, f.mp.UIViewModel
    function f:event(event, ...)
        -- Copy recipients: newly created panel widgets are not event recipients.
        local recipients = {}
        for _, w in ipairs(self.objects) do if w.events[event] then recipients[#recipients + 1] = w end end
        for _, w in ipairs(recipients) do if w.scripts.OnEvent then w.scripts.OnEvent(w, event, ...) end end
    end
    function f:open() self:event("AUCTION_HOUSE_SHOW") end
    function f:complete(id) self:event("COMMODITY_SEARCH_RESULTS_UPDATED", id or self.scanner.itemID) end
    function f:has(text)
        for _, line in ipairs(self.output) do if line:find(text, 1, true) then return true end end
        return false
    end
    return f
end

local passed = 0
local function test(name, run) run(); passed = passed + 1; print("PASS " .. name) end

test("UI static boundaries and presentation-only money conversion", function()
    for _, path in ipairs({ "UI.lua", "UIViewModel.lua" }) do
        local source = read(ROOT .. path)
        for _, forbidden in ipairs({ "C_AuctionHouse", "Statistics.Analyze", "math.log", "OnUpdate", "HookScript", "hooksecurefunc",
            "SavedVariables", "PostItem", "PostCommodity", "auctionID", "C_Container", "SetAuction" }) do
            assert(not source:find(forbidden, 1, true), path .. " " .. forbidden)
        end
    end
    local f = fixture()
    assert(f.view.Money(1) == "0g 0s 1c")
    assert(f.view.Money(199) == "0g 1s 99c")
    assert(f.view.Money(10000) == "1g 0s 0c")
    assert(f.view.Money(123456) == "12g 34s 56c")
    assert(f.view.Money(9007199254740991) == "900719925474g 9s 91c")
    for _, value in ipairs({ 0, -1, "200", false, 1.5, math.huge, 0/0, 9007199254740992 }) do
        assert(f.view.Money(value) == "UNKNOWN")
    end
    assert(f.view.Money(nil) == "UNKNOWN")
end)

test("closed/idle model never invents prices or anomaly counts", function()
    local f = fixture()
    f.panel:Update()
    local model = f.panel.view
    assert(model.state == "AH CLOSED" and not model.scanEnabled and model.lowest == "UNKNOWN")
    assert(model.rawMedian == "UNKNOWN" and model.extreme == "UNKNOWN" and model.sufficient == "UNKNOWN")
    f:open()
    assert(f.panel.view.state == "IDLE" and f.panel.view.scanEnabled)
end)

test("right anchor, category rows and lifecycle reuse", function()
    local f = fixture()
    assert(f.panel.frame == nil)
    f:open()
    local panel, anchor = f.panel.frame, f.env.AuctionHouseFrame
    assert(panel.parent == anchor and panel.point[1] == "TOPLEFT" and panel.point[2] == anchor)
    assert(panel.point[3] == "TOPRIGHT" and panel.point[4] == 8 and panel.point[5] == 0)
    assert(anchor.point == nil and anchor.scripts.OnClick == nil and panel:IsVisible())
    local categories = f.mp.Items.categories
    assert(categories[1].name == "Mining" and categories[2].name == "Herbalism" and categories[3].name == "Skinning")
    local objectCount = #f.objects
    f:event("AUCTION_HOUSE_CLOSED")
    assert(not panel:IsShown())
    f:open()
    assert(f.panel.frame == panel and panel:IsShown() and #f.objects == objectCount)
    -- Parenting also hides the panel if the Blizzard parent hides independently.
    anchor:Hide(); assert(not panel:IsVisible()); anchor:Show()
end)

test("click scans selected item once; refresh and debug use same selection", function()
    local f = fixture()
    f:open()
    f.panel.rows[2447]:Click()
    assert(f.scanner.itemID == 2447 and f.panel.view.itemID == 2447 and f.sent[1] == 2447)
    assert(f.panel.view.name == "Client item 2447" and f.panel.rows[2447].icon.texture == 12447)
    assert(f.panel.rows[2447].selection.shown and not f.panel.rows[2770].selection.shown)
    f:complete()
    assert(f.panel.scan.text == "Refresh" and f.panel.scan.enabled)
    f.panel.scan:Click(); f:complete()
    f.env.SlashCmdList.MARKETPILOT("scan")
    assert(#f.sent == 3 and f.sent[2] == 2447 and f.sent[3] == 2447)
end)

test("waiting/querying repeated clicks cannot change item or send parallel queries", function()
    local f = fixture()
    f.ready = false
    f:open(); f.panel.rows[2770]:Click()
    assert(f.panel.view.state == "WAITING" and not f.panel.scan.enabled and not f.panel.rows[2771].enabled)
    f.panel.rows[2771]:Click(true); f.panel.scan:Click(true)
    assert(f.scanner.itemID == 2770 and #f.sent == 0)
    f.ready = true
    f:event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    f:event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    f.panel.rows[2318]:Click(true); f.panel.scan:Click(true)
    assert(#f.sent == 1 and f.scanner.itemID == 2770 and f.panel.view.state == "QUERYING")
    local sawCollecting = false
    local original = f.env.C_AuctionHouse.GetCommoditySearchResultInfo
    f.env.C_AuctionHouse.GetCommoditySearchResultInfo = function(...)
        sawCollecting = f.panel.view.state == "COLLECTING" and not f.panel.scan.enabled
        return original(...)
    end
    f:complete()
    assert(sawCollecting and f.panel.scan.enabled)
end)

test("four-level insufficient display retains known prices and matches analysis", function()
    local f = fixture()
    -- Synthetic per-level quantities reproducing the user's reported summaries.
    -- The original per-level quantities were not supplied as client evidence.
    f.rows = { { unitPrice = 170, quantity = 10 }, { unitPrice = 180, quantity = 10 },
        { unitPrice = 199, quantity = 200 }, { unitPrice = 200, quantity = 515 } }
    f:open(); f.panel.scan:Click(); f:complete()
    local view = f.panel.view
    assert(view.lowest == "0g 1s 70c" and view.rawMedian == "0g 2s 0c" and view.cleanMedian == view.rawMedian)
    assert(view.quantity == "735" and view.levels == "4" and view.sufficient == "INSUFFICIENT")
    assert(view.suspicious == "0" and view.extreme == "0" and view.message:find("fewer than 5", 1, true))
    f.rows[3].quantity, f.rows[4].quantity = 400, 355
    f.panel.scan:Click(); f:complete()
    assert(f.panel.view.quantity == "775" and f.panel.view.cleanMedian == "0g 1s 99c")
end)

test("UI renders clean range and flagged counts without recalculating statistics", function()
    local f = fixture()
    f.rows = {}
    for price = 8000, 12000, 500 do f.rows[#f.rows + 1] = { unitPrice = price, quantity = 20 } end
    f.rows[#f.rows + 1] = { unitPrice = 1000000000, quantity = 1000000 }
    f:open(); f.panel.scan:Click(); f:complete()
    f.mp.Statistics.Analyze = function() error("UI must not analyze again") end
    f.panel:Update(); f.panel.toggle:Click(); f.panel.toggle:Click()
    local view = f.panel.view
    assert(view.rawMedian == "100000g 0s 0c" and view.cleanMedian == "1g 0s 0c")
    assert(view.range == "0g 90s 0c - 1g 10s 0c" and view.extreme == "1" and view.sufficient == "SUFFICIENT")
    assert(view.exclusion:find("excluded: 1", 1, true) and view.exclusion:find("Suspicious retained", 1, true))
    assert(f.scanner.state == "DONE" and not f:has("UI must not analyze again"))
end)

test("ERROR and empty results never render a zero price", function()
    local f = fixture()
    f.rows[1].unitPrice = nil
    f:open(); f.panel.scan:Click(); f:complete()
    assert(f.panel.view.state == "ERROR" and f.panel.view.lowest == "UNKNOWN" and f.panel.view.range == "UNKNOWN")
    assert(f.panel.view.message:find("unitPrice", 1, true) and f.panel.scan.enabled)
    f.rows = {}
    f.panel.scan:Click(); f:complete()
    assert(f.panel.view.lowest == "UNKNOWN" and f.panel.view.cleanMedian == "UNKNOWN")
    assert(f.panel.view.quantity == "0" and f.panel.view.levels == "0" and f.panel.view.sufficient == "INSUFFICIENT")
end)

test("new selection clears stale display and ignores previous-item results", function()
    local f = fixture()
    f:open(); f.panel.scan:Click(); f:complete()
    f.panel.rows[2771]:Click()
    assert(f.panel.view.lowest == "UNKNOWN" and f.panel.view.itemID == 2771)
    local reads = f.reads
    f:complete(2770)
    assert(f.scanner.state == "QUERYING" and f.reads == reads)
    f:complete(2771)
    assert(f.panel.view.state == "DONE" and f.scanner.sample.itemID == 2771)
    local mismatched = f.view.Build(f.scanner, 2318, { name = "other", icon = 1 })
    assert(mismatched.rawMedian == "UNKNOWN" and mismatched.message:find("UNKNOWN", 1, true))
end)

test("collapse and expand only affect our frame, including reopen", function()
    local f = fixture()
    f:open()
    local count = #f.objects
    local height = f.panel.frame.height
    f.panel.toggle:Click()
    assert(f.panel.frame.height == 42 and not f.panel.body.shown and f.panel.toggle.text == "+")
    assert(f.env.AuctionHouseFrame.shown and #f.sent == 0)
    f:event("AUCTION_HOUSE_CLOSED"); f:open()
    assert(f.panel.collapsed and not f.panel.body.shown)
    f.panel.toggle:Click()
    assert(f.panel.body.shown and f.panel.frame.height == height and #f.objects == count)
end)

test("missing AH anchor fails gracefully and retries on addon-loaded event", function()
    local f = fixture(function(f) f.env.AuctionHouseFrame = nil end)
    f:open()
    assert(f.panel.frame == nil and f.scanner.state == "IDLE" and f:has("AuctionHouseFrame unavailable"))
    f.env.AuctionHouseFrame = 42
    assert(f.panel:Open() == false and f.scanner.state == "IDLE")
    f.makeAnchor(); f:event("ADDON_LOADED", "Blizzard_AuctionHouseUI")
    assert(f.panel.frame:IsShown() and #f.sent == 0)
    f:event("AUCTION_HOUSE_CLOSED"); f:event("ADDON_LOADED", "Other")
    assert(not f.panel.frame:IsShown())
end)

test("anchor failure does not break AH or scanner and can recover on reopen", function()
    local f = fixture(function(f) f.failAnchor = true end)
    f:open()
    assert(f.panel.frame == nil and f.scanner.state == "IDLE" and f.env.AuctionHouseFrame.shown)
    assert(f:has("fixture anchor failure"))
    f.failAnchor = false
    f:event("AUCTION_HOUSE_CLOSED"); f:open()
    assert(f.panel.frame:IsShown())
end)

test("missing metadata shows ID and late item-info event updates cached widgets", function()
    local f = fixture()
    f.namesReady = false
    f:open()
    assert(f.panel.name.text == "Item #2770 (UNKNOWN)")
    local initial = f.infoCalls[2770]
    f.panel:Update(); f:event("GET_ITEM_INFO_RECEIVED", 2770, false)
    assert(f.infoCalls[2770] == initial)
    f.namesReady = true
    f:event("GET_ITEM_INFO_RECEIVED", 2770, true)
    assert(f.panel.name.text == "Client item 2770" and f.infoCalls[2770] == initial + 1)
    f.panel:Update()
    assert(f.infoCalls[2770] == initial + 1)
end)

test("namespaced item info works and synchronous metadata events cannot recurse", function()
    local f = fixture(function(f)
        f.env.C_Item = { GetItemInfo = f.env.GetItemInfo }
        f.env.GetItemInfo = nil
        f.syncInfo = true
    end)
    f:open()
    assert(f.panel.name.text == "Client item 2770" and f.infoCalls[2770] == 1)
    assert(f.scanner.state == "IDLE")
end)

test("absent item info and missing market API keep panel usable", function()
    local f = fixture(function(f)
        f.env.GetItemInfo = nil
        f.env.C_AuctionHouse.SendSearchQuery = nil
    end)
    f:open(); f.panel.scan:Click()
    assert(f.panel.frame:IsShown() and f.panel.view.state == "ERROR")
    assert(f.panel.view.message:find("missing API", 1, true) and f.panel.scan.enabled)
    assert(f.panel.name.text == "Item #2770 (UNKNOWN)")
end)

test("UI render errors do not discard a completed scanner result", function()
    local f = fixture()
    f:open(); f.panel.scan:Click(); f:complete()
    local sample = f.scanner.sample
    f.panel.values.lowest.SetText = function() error("fixture render error") end
    f:event("GET_ITEM_INFO_RECEIVED", 2770, true)
    assert(f.scanner.state == "DONE" and f.scanner.sample == sample and f:has("fixture render error"))
    assert(not f.panel.frame.shown)
end)

test("market dashboard replaces the old placeholder with batch and report actions", function()
    local f = fixture()
    f:open()
    for _, w in ipairs(f.objects) do
        assert(w.text ~= "Sale Assistant" and w.text ~= "Coming in MP-04")
    end
    assert(f.panel.batchButton.text == "Scan Gathering Markets" and f.panel.reportButton.text == "Market Report")
    assert(#f.sent == 0 and f.panel.frame.height == 650)
end)

test("batch serializes all configured queries and persists progress without raw rows", function()
    local f = fixture(); f:open()
    local ids = f.mp.Items.List()
    f.panel.batchButton:Click()
    assert(f.mp.batch.active and #f.sent == 1 and f.mp.batch.completed == 0)
    f.panel.batchButton:Click(true); f.panel.scan:Click(true)
    f.env.SlashCmdList.MARKETPILOT("scan")
    f.panel.rows[2447]:Click()
    assert(#f.sent == 1 and f.panel.selectedItemID == 2447 and f.scanner.itemID == ids[1])
    for i, id in ipairs(ids) do
        assert(#f.sent == i and f.sent[i] == id and f.scanner.state == "QUERYING")
        f:complete(id)
        assert(f.mp.batch.completed == i and f.mp.batch.results[id].state == "DONE")
        local history = f.mp.market.db:History(id)
        assert(#history == 1 and history[1].cleanMedian == 200 and history[1].priceLevels == nil)
    end
    assert(not f.mp.batch.active and f.mp.batch.state == "DONE" and #f.sent == #ids)
    assert(f.panel.progress.text:find("5 / 5", 1, true) and f.panel.selectedItemID == 2447)
    assert(f.env.MarketPilotDB.schema == 1)
    f.env.SlashCmdList.MARKETPILOT("scan"); assert(f.sent[#f.sent] == 2447)
end)

test("batch waits for throttle events between queries and ignores duplicate readiness", function()
    local f = fixture(); f.ready = false; f:open(); f.panel.batchButton:Click()
    assert(f.scanner.state == "WAITING" and #f.sent == 0)
    f.ready = true; f:event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    f.ready = false; f:complete()
    assert(f.scanner.state == "WAITING" and #f.sent == 1 and f.mp.batch.completed == 1)
    f:event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY"); assert(#f.sent == 1)
    f.ready = true; f:event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    f:event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    assert(#f.sent == 2 and f.scanner.itemID == 2771 and f.scanner.state == "QUERYING")
end)

test("cancel waiting sends nothing; cancel dispatched query drains only that reply", function()
    local f = fixture(); f.ready = false; f:open(); f.panel.batchButton:Click()
    f.panel.cancelButton:Click()
    f.ready = true; f:event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    assert(f.scanner.state == "IDLE" and #f.sent == 0 and f.mp.batch.state == "CANCELLED")
    f.panel.batchButton:Click(); f.panel.cancelButton:Click()
    f.panel.batchButton:Click(true); f.panel.scan:Click(true)
    assert(#f.sent == 1 and f.scanner:IsActive() and not f.mp.batch.active)
    f:complete(); f:event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    assert(#f.sent == 1 and f.scanner.state == "DONE" and f.mp.batch.state == "CANCELLED")
    assert(#f.mp.market.db:History(2770) == 1)
    f.panel.batchButton:Click(); assert(#f.sent == 2 and f.mp.batch.active)
end)

test("item result failure is isolated and batch safely advances to the next item", function()
    local f = fixture(); f:open(); f.panel.batchButton:Click()
    f.rows = { { quantity = 2 } }; f:complete()
    assert(f.mp.batch.completed == 1 and f.mp.batch.results[2770].state == "ERROR")
    assert(#f.mp.market.db:History(2770) == 0 and f.panel.rows[2770].columns.now.text == "ERROR")
    assert(f.scanner.itemID == 2771 and #f.sent == 2)
    f.rows = { { unitPrice = 20, quantity = 7 } }; f:complete()
    assert(#f.mp.market.db:History(2771) == 1 and f.mp.market:Get(2771).current.cleanMedian == 20)
    assert(f.mp.batch.results[2770].error:find("unitPrice", 1, true))
end)

test("ambiguous dispatch failure stops batch until AH reopen; no blind retry", function()
    local f = fixture(function(f)
        f.env.C_AuctionHouse.SendSearchQuery = function() error("dispatch unknown") end
    end)
    f:open(); f.panel.batchButton:Click()
    assert(not f.mp.batch.active and f.scanner.uncertainQuery and f.mp.batch.completed == 1)
    assert(f.mp.batch.state == "UNKNOWN: reopen AH")
    f.panel.batchButton:Click(true); f:event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    assert(f.mp.batch.completed == 1)
    f:event("AUCTION_HOUSE_CLOSED"); f:open()
    assert(not f.scanner.uncertainQuery and not f.mp.batch.active)
end)

test("AH close cancels waiting and dispatched batches and never restarts on reopen", function()
    for _, ready in ipairs({ false, true }) do
        local f = fixture(); f.ready = ready; f:open(); f.panel.batchButton:Click()
        f:event("AUCTION_HOUSE_CLOSED")
        local n = #f.sent
        f:complete(2770); f:event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
        assert(not f.mp.batch.active and f.mp.batch.state == "CANCELLED" and #f.sent == n)
        assert(not f.panel.frame.shown and #f.mp.market.db:History(2770) == 0)
        f:open(); assert(#f.sent == n and not f.mp.batch.active)
    end
end)

local DAY = 86400
local function snapshot(t, price)
    return { t = t, rawMedian = price, cleanMedian = price, q1 = price, q3 = price,
        lowest = price, totalQuantity = 100, levelCount = 5, suspicious = 0, extreme = 0, anomalySufficient = true }
end
local function seed(f, id, times, prices)
    for i, age in ipairs(times) do assert(f.mp.market.db:Append(id, snapshot(f.now - age, prices and prices[i] or 200))) end
    f.mp.market.cache = {}; f.panel:Update()
end

test("dashboard renders all maturity stages and withholds premature window metrics", function()
    local f = fixture(); f:open()
    seed(f, 2770, { 0 })
    seed(f, 2771, { DAY, DAY / 2, 0 })
    seed(f, 2775, { 7 * DAY, 6 * DAY, DAY, 0 })
    seed(f, 2447, { 30 * DAY, 29 * DAY, DAY, 0 })
    assert(f.panel.rows[2770].columns.maturity.text == "NEW")
    assert(f.panel.rows[2771].columns.maturity.text == "EARLY" and f.panel.rows[2771].columns.change.text == "?")
    assert(f.panel.rows[2775].columns.maturity.text == "7D READY" and f.panel.rows[2775].columns.percentile.text == "?")
    assert(f.panel.rows[2447].columns.maturity.text == "30D READY" and f.panel.rows[2447].columns.percentile.text == "50")
    assert(f.panel.historyValues.median7.text == "INSUFFICIENT")
    f.panel.selectedItemID = 2447; f.panel:Update()
    assert(f.panel.historyValues.median30.text == "0g 2s 0c" and f.panel.historyValues.observations.text == "4 / 30D READY")
    f.now = f.now + 120; f.panel:Update(); assert(f.panel.historyValues.lastScan.text == "2m ago")
    assert(f.view.ReferenceMoney(199.5) == "199.5c")
    assert(f.view.PValue(0.00000001) == "p<0.0001" and f.view.PValue(0.031) == "p=0.0310")
    assert(f.view.PValue(nil) == "INSUFFICIENT")
end)

test("report includes configured supported facts only and exposes sparse-history maturity", function()
    local f = fixture(); f:open(); f.panel.reportButton:Click()
    assert(f.panel.reportText.shown and not f.panel.detail.shown)
    assert(f.panel.reportText.text:find("No supported observations", 1, true))
    assert(f.panel.reportText.text:find("NEW: 5", 1, true))
    seed(f, 2770, { 30 * DAY, 29 * DAY, DAY, 0 }, { 200, 200, 200, 100 })
    seed(f, 2447, { 2 * DAY, 1.5 * DAY, DAY, DAY / 2, 0 }, { 100, 120, 144, 173, 207 })
    seed(f, 99999, { 30 * DAY, 29 * DAY, DAY, 0 }, { 200, 200, 200, 100 })
    seed(f, 2775, { 8 * DAY, 7 * DAY, 6 * DAY, 5 * DAY, 4 * DAY, 3 * DAY, 2 * DAY, DAY, DAY / 2, 0 },
        { 100, 100, 100, 100, 100, 100, 100, 150, 150, 150 })
    local report = f.mp.market:Report()
    assert(#report.cheap == 1 and report.cheap[1].itemID == 2770)
    assert(report.rising[1].itemID == 2447 and #report.significant == 1 and report.significant[1].itemID == 2775)
    assert(not f.panel.reportText.text:find("99999", 1, true))
    assert(f.panel.reportText.text:find("Client item 2770: 30d percentile 0", 1, true))
    assert(f.panel.reportText.text:find("Client item 2775: p=", 1, true))
    f.mp.market.errors[2447] = "UNKNOWN: last scan failed"; f.mp.market.cache = {}
    for _, row in ipairs(f.mp.market:Report().rising) do assert(row.itemID ~= 2447) end
    f.panel.reportButton:Click(); assert(f.panel.detail.shown and not f.panel.reportText.shown)
end)

test("history survives reload fixture, dedupes refresh and caches pure analytics", function()
    local f = fixture(); f:open(); f.panel.scan:Click(); f:complete()
    f.now = f.now + 60; f.panel.scan:Click(); f:complete()
    assert(#f.mp.market.db:History(2770) == 1 and f.mp.market:Get(2770).lastScan == f.now)
    local g = fixture(function(g) g.env.MarketPilotDB = f.env.MarketPilotDB end)
    g:event("ADDON_LOADED", "MarketPilot"); g:open()
    assert(g.panel.view.cleanMedian == "0g 2s 0c" and #g.mp.market.db:History(2770) == 1 and #g.sent == 0)
    assert(g.mp.market.db.key == f.mp.market.db.key)
    g.mp.HistoricalAnalytics.Analyze = function() error("uncached analysis") end
    g.panel:Update(); g.panel.toggle:Click(); g.panel.toggle:Click(); g.panel.reportButton:Click()
    assert(not g:has("uncached analysis"))
end)

test("unknown identity and future schema preserve saved data while current scans work", function()
    for _, mode in ipairs({ "identity", "schema" }) do
        local root = { schema = 99, future = "keep me" }
        local f = fixture(function(f)
            f.env.MarketPilotDB = root
            if mode == "identity" then f.env.GetRealmName = nil end
        end)
        f:open(); f.panel.scan:Click(); f:complete()
        assert(f.env.MarketPilotDB == root and root.future == "keep me" and root.markets == nil)
        assert(f.panel.view.cleanMedian == "0g 2s 0c" and f.mp.market.db.status == "UNKNOWN")
        assert(f.panel.historyStatus.text:find("UNKNOWN", 1, true))
        assert(f.panel.historyValues.median7.text == "INSUFFICIENT")
    end
end)

print("PASS " .. passed .. " UI/batch offline tests (Lua 5.1); real frame rendering remains unverified")
