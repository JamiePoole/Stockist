local ADDON_NAME, Stockist = ...

-- Item names and rarity colours. Item data is cached lazily by the client: a name can be nil the
-- first time we ask, so ColoredName asks the client to load it, and callers refresh on
-- GET_ITEM_INFO_RECEIVED.
local Format = Stockist.Format

local ItemInfo = {}
Stockist.ItemInfo = ItemInfo

--- The item's name, or nil if the client has not cached it yet.
function ItemInfo.Name(id)
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if not name and GetItemInfo then name = (GetItemInfo(id)) end
    return name
end

--- Does the game have an item with this ID? Works for items the client has not cached yet. Returns
--- true or false, or nil when the client cannot say (so callers treat nil as "maybe").
function ItemInfo.Exists(id)
    if C_Item and C_Item.DoesItemExistByID then
        local ok, exists = pcall(C_Item.DoesItemExistByID, id)
        if ok then return exists and true or false end
    end
    return nil
end

--- Quality 0 (poor) .. 7, or nil if unknown.
function ItemInfo.Quality(id)
    local q = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
    if q == nil and GetItemInfo then q = select(3, GetItemInfo(id)) end
    return q
end

function ItemInfo.Request(id)
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
end

--- Name wrapped in its rarity colour (grey/white/green/blue/purple/orange...). While the item is
--- not cached this returns "item:<id>" and asks the client to load it.
function ItemInfo.ColoredName(id)
    local name = ItemInfo.Name(id)
    if not name then
        ItemInfo.Request(id)
        return "item:" .. id
    end
    local q = ItemInfo.Quality(id)
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return Format.Colored(name, c.r, c.g, c.b) end
    return name
end
