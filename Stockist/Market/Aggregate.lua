local ADDON_NAME, Stockist = ...

-- Reduces an item's price tiers to the figures we record. Pure maths, no game API.
-- A tier is { price = copper per unit, qty = units listed at that price }.
local Aggregate = {}
Stockist.Aggregate = Aggregate

local function sortedCopy(tiers)
    local out = {}
    for _, t in ipairs(tiers) do
        if t.price > 0 and t.qty > 0 then out[#out + 1] = { price = t.price, qty = t.qty } end
    end
    table.sort(out, function(a, b) return a.price < b.price end)
    return out
end

--- Returns { min, median, qty } or nil for an empty listing.
---   min     lowest unit price
---   median  median unit price of the cheapest `cheapestUnits` units (outlier-resistant headline)
---   qty     total units listed (supply)
function Aggregate.Reduce(tiers, cheapestUnits)
    local sorted = sortedCopy(tiers)
    if #sorted == 0 then return nil end

    local total = 0
    for _, t in ipairs(sorted) do total = total + t.qty end

    local take = math.min(total, cheapestUnits)
    -- Price of the unit at 1-based rank r among the cheapest `take` units.
    local function priceAtRank(r)
        local seen = 0
        for _, t in ipairs(sorted) do
            seen = seen + t.qty
            if r <= seen then return t.price end
        end
    end
    local lo = priceAtRank(math.floor((take + 1) / 2))
    local hi = priceAtRank(math.floor(take / 2) + 1)

    return { min = sorted[1].price, median = (lo + hi) / 2, qty = total }
end

--- Units listed within `pct` percent above the lowest price (market depth near the top).
function Aggregate.DepthWithin(tiers, pct)
    local sorted = sortedCopy(tiers)
    if #sorted == 0 then return 0 end
    local limit = sorted[1].price * (1 + pct / 100)
    local qty = 0
    for _, t in ipairs(sorted) do
        if t.price <= limit then qty = qty + t.qty end
    end
    return qty
end
