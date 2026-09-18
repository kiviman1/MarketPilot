local _, MP = ...
local Inventory = {}
Inventory.__index = Inventory
MP.Inventory = Inventory

local function integer(value, minimum)
    return type(value) == "number" and value >= minimum and value <= 9007199254740991 and value % 1 == 0
end

function Inventory.New(items)
    return setmetatable({ configured = items, items = {}, generation = 0, status = "UNKNOWN" }, Inventory)
end

function Inventory:Invalidate(reason)
    self.generation = self.generation + 1
    self.items, self.status, self.error = {}, "UNKNOWN", reason
end

-- Read-only client boundary. Modern documented bag API only; no guessed fallback.
function Inventory:Refresh()
    self:Invalidate("UNKNOWN: inventory not read")
    if self.blockedReason then self.error = self.blockedReason; return false end
    local ok, result = pcall(function()
        assert(type(C_Container) == "table" and type(C_Container.GetContainerNumSlots) == "function"
            and type(C_Container.GetContainerItemInfo) == "function", "C_Container bag readers unavailable")
        local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS
        assert(integer(lastBag, 0) and lastBag <= 20, "equipped bag count unavailable/invalid")
        local found = {}
        for bag = 0, lastBag do
            local slots = C_Container.GetContainerNumSlots(bag)
            assert(integer(slots, 0) and slots <= 1000, "invalid bag slot count")
            for slot = 1, slots do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info ~= nil then
                    assert(type(info) == "table" and integer(info.itemID, 1), "invalid bag item info")
                    if self.configured.Contains(info.itemID) then
                        assert(integer(info.stackCount, 1), "invalid configured item count")
                        local item = found[info.itemID] or { itemID = info.itemID, count = 0, slots = {} }
                        assert(item.count <= 9007199254740991 - info.stackCount, "bag count overflow")
                        item.count = item.count + info.stackCount
                        item.slots[#item.slots + 1] = { bag = bag, slot = slot, generation = self.generation }
                        found[info.itemID] = item
                    end
                end
            end
        end
        return found
    end)
    if not ok then self.error = "UNKNOWN: inventory " .. tostring(result); return false end
    self.items, self.status, self.error = result, "OK", nil
    return true
end

function Inventory:Owned(itemID)
    if self.status ~= "OK" then return nil end
    return self.items[itemID] and self.items[itemID].count or 0
end

-- Build a short-lived client object only for the explicit read-only sell probe.
function Inventory:Location(itemID)
    local item = self.items[itemID]
    if self.status ~= "OK" or not item then return nil, "UNKNOWN: item no longer in bags" end
    local address = item.slots[1]
    local ok, location = pcall(function()
        assert(address.generation == self.generation, "stale bag generation")
        local info = C_Container.GetContainerItemInfo(address.bag, address.slot)
        assert(type(info) == "table" and info.itemID == itemID, "bag slot changed")
        assert(type(ItemLocation) == "table" and type(ItemLocation.CreateFromBagAndSlot) == "function",
            "ItemLocation unavailable")
        local value = ItemLocation:CreateFromBagAndSlot(address.bag, address.slot)
        assert(type(value) == "table", "invalid ItemLocation result")
        return value
    end)
    if not ok then return nil, "UNKNOWN: " .. tostring(location) end
    return location
end
