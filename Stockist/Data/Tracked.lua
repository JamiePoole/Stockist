local ADDON_NAME, Stockist = ...

-- The set of items the player cares about. Tracked items keep their history longer and are never
-- cleaned up as idle. The watchlist and alerts build on this same set.
-- `set` is a plain table { [itemID] = true } so it can live directly in SavedVariables.
local Tracked = {}
Tracked.__index = Tracked
Stockist.Tracked = Tracked

function Tracked.New(set)
    return setmetatable({ set = set }, Tracked)
end

--- Returns true if the item was newly added.
function Tracked:Add(itemID)
    if type(itemID) ~= "number" or itemID <= 0 or self.set[itemID] then return false end
    self.set[itemID] = true
    return true
end

--- Returns true if the item was tracked.
function Tracked:Remove(itemID)
    if not self.set[itemID] then return false end
    self.set[itemID] = nil
    return true
end

function Tracked:Has(itemID)
    return self.set[itemID] == true
end

--- Sorted item IDs.
function Tracked:List()
    local out = {}
    for id in pairs(self.set) do out[#out + 1] = id end
    table.sort(out)
    return out
end

function Tracked:Count()
    local n = 0
    for _ in pairs(self.set) do n = n + 1 end
    return n
end
