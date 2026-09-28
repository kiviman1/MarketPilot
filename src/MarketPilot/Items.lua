local _, MP = ...

local Items = {
    testItemID = 2770,
    -- Standard Classic raw materials; names/icons remain client-owned.
    -- ID provenance: nexus-devs/wow-classic-items data/json/data.json.
    -- Catalogue inclusion does not confirm Forever availability or commodity support.
    categories = {
        { name = "Mining", itemIDs = {
            2770, 2771, 2775, 2772, 2776, 3858, 7911, 10620, 11370,
            2835, 2836, 2838, 7912, 12365,
        } },
        { name = "Herbalism", itemIDs = {
            2447, 765, 2449, 785, 2450, 2452, 2453, 3820, 3355, 3369,
            3356, 3357, 3358, 3818, 3821, 3819, 4625, 8831, 8153, 8836, 8838,
            8839, 8845, 8846, 13463, 13464, 13465, 13466, 13467, 13468, 19726,
        } },
        { name = "Skinning", itemIDs = { 2318, 2319, 4234, 4304, 8170, 2934, 783, 4232, 4235, 8169, 8171 } },
    },
}
MP.Items = Items

function Items.List(categoryName)
    local result = {}
    for _, category in ipairs(Items.categories) do
        if not categoryName or categoryName == "All" or category.name == categoryName then
            for _, id in ipairs(category.itemIDs) do result[#result + 1] = id end
        end
    end
    return result
end

function Items.Contains(itemID)
    for _, category in ipairs(Items.categories) do
        for _, id in ipairs(category.itemIDs) do if id == itemID then return true end end
    end
    return false
end

local metadata, loading = {}, {}
function Items.Metadata(itemID)
    if metadata[itemID] then return metadata[itemID] end
    local info = { name = "Item #" .. itemID .. " (loading)", icon = "Interface\\Icons\\INV_Misc_QuestionMark", known = false }
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
