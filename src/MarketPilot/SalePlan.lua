local _, MP = ...
local SalePlan = {}
MP.SalePlan = SalePlan

local MAX_INTEGER = 9007199254740991
local TARGETS = { FAST = "fast", NORMAL = "normal", PATIENT = "patient" }
local FIELDS = { "itemID", "quantity", "durationHours", "unitPrice", "targetKind", "createdAt" }
local function integer(value, minimum)
    return type(value) == "number" and value >= minimum and value <= MAX_INTEGER and value % 1 == 0
end

function SalePlan.Total(quantity, price)
    if not integer(quantity, 1) or not integer(price, 1) or price > math.floor(MAX_INTEGER / quantity) then
        return nil, "UNKNOWN: total listed value exceeds exact integer range or has invalid input"
    end
    return quantity * price
end

-- Pure validation of existing Pricing output and runtime evidence, no client calls.
function SalePlan.Validate(context)
    if context.ahOpen ~= true then return nil, "Open AH before preparing." end
    if context.active or context.scannerState ~= "DONE" then return nil, "Wait for a completed scan." end
    if not integer(context.itemID, 1) or context.scanItemID ~= context.itemID then
        return nil, "UNKNOWN: scan must match the sale item."
    end
    if not integer(context.quantity, 1) or not integer(context.owned, 1) or context.quantity > context.owned then
        return nil, "UNKNOWN: quantity exceeds ownership or item is unavailable."
    end
    if context.durationHours ~= 12 and context.durationHours ~= 24 and context.durationHours ~= 48 then
        return nil, "Duration must be 12h, 24h or 48h."
    end
    if context.sufficient ~= true then return nil, "INSUFFICIENT: robust pricing is unavailable." end
    local key = TARGETS[context.targetKind]
    local target = key and context.targets and context.targets[key]
    if not target or target.status ~= "OK" or not integer(target.copper, 1) then
        return nil, "UNKNOWN: choose an available Fast, Normal or Patient target."
    end
    if context.evidenceFresh ~= true or context.sellValid ~= true or context.copperSupported ~= true
        or context.postPresent ~= true then
        return nil, "Check sell API: fresh sell-valid=true, copper=true and posting presence are required."
    end
    local total, err = SalePlan.Total(context.quantity, target.copper)
    if not total then return nil, err end
    return target.copper
end

function SalePlan.Create(context, createdAt)
    local price, err = SalePlan.Validate(context)
    if not price then return nil, err end
    if not integer(createdAt, 0) then return nil, "UNKNOWN: creation timestamp unavailable." end
    local values = { itemID = context.itemID, quantity = context.quantity, durationHours = context.durationHours,
        unitPrice = price, targetKind = context.targetKind, createdAt = createdAt }
    -- Empty read-only facade: normal assignments cannot overwrite even existing fields.
    -- Copy() exposes an ordinary primitive table without exposing these private values.
    return setmetatable({}, { __index = values, __newindex = function() error("Sale plan is immutable", 2) end,
        __metatable = false })
end

function SalePlan.Copy(plan)
    local copy = {}
    for _, field in ipairs(FIELDS) do copy[field] = plan[field] end
    return copy
end
