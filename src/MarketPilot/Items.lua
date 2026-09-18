local _, MP = ...

local Items = {
    testItemID = 2770,
    -- Representative IDs only. 2770, 2447 and 2318 commodity scans are beta-confirmed.
    categories = {
        { name = "Mining", itemIDs = { 2770, 2771, 2775 } },
        { name = "Herbalism", itemIDs = { 2447 } },
        { name = "Skinning", itemIDs = { 2318 } },
    },
}
MP.Items = Items

function Items.Contains(itemID)
    for _, category in ipairs(Items.categories) do
        for _, id in ipairs(category.itemIDs) do if id == itemID then return true end end
    end
    return false
end

local metadata, loading = {}, {}
function Items.Metadata(itemID)
    if metadata[itemID] then return metadata[itemID] end
    local info = { name = "Item #" .. itemID .. " (UNKNOWN)", icon = "Interface\\Icons\\INV_Misc_QuestionMark", known = false }
    metadata[itemID] = info
    -- Display metadata only. Guard both documented client namespace variants.
    local getInfo = type(C_Item) == "table" and C_Item.GetItemInfo or GetItemInfo
    if type(getInfo) == "function" then
        loading[itemID] = true
        local result = { pcall(getInfo, itemID) }
        loading[itemID] = nil
        if result[1] and type(result[2]) == "string" then
            info.name, info.known = result[2], true
            if type(result[11]) == "string" or type(result[11]) == "number" then info.icon = result[11] end
        end
    end
    metadata[itemID] = info
    return info
end

function Items.InvalidateMetadata(itemID)
    if itemID then
        if loading[itemID] then return false end
        metadata[itemID] = nil
    else
        for id, info in pairs(metadata) do if not info.known then metadata[id] = nil end end
    end
    return true
end
