-- /stkprobe owned : what does the client tell an addon about the player's own auctions, cancel costs
-- and deposits? Stand at the Auction House with at least one active listing (best: two or three).
-- This only READS. It never cancels or posts anything. Results: StockistProbeDB.owned.

local function say(msg) print("|cff33ff99StockistProbe|r " .. msg) end

local function safe(fn, ...)
    local r = { pcall(fn, ...) }
    if not r[1] then return false, tostring(r[2]) end
    return true, unpack(r, 2)
end

local function str(v)
    local ok, s = pcall(tostring, v)
    return ok and s or "<unprintable>"
end

local APIS = {
    "QueryOwnedAuctions", "GetNumOwnedAuctions", "GetOwnedAuctionInfo", "GetCancelCost", "CanCancelAuction",
    "CalculateCommodityDeposit", "CalculateItemDeposit", "GetMaxOwnedAuctionCount", "GetAuctionHouseFee",
    "GetAuctionDuration", "IsThrottledMessageSystemReady", "GetAvailablePostCount",
}

local rec
local f = CreateFrame("Frame")
for _, e in ipairs({ "OWNED_AUCTIONS_UPDATED", "AUCTION_CANCELED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" }) do
    pcall(f.RegisterEvent, f, e)
end
f:SetScript("OnEvent", function(_, event)
    if rec then rec.eventsSeen[#rec.eventsSeen + 1] = event end
end)

--- Scalar fields of a table as strings; nested tables are listed by name with their scalar fields too.
local function describe(t, depth)
    local out = {}
    if type(t) ~= "table" then return str(t) end
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return str(a) < str(b) end)
    for _, k in ipairs(keys) do
        local v = t[k]
        if type(v) == "table" then
            out[str(k)] = depth > 0 and describe(v, depth - 1) or "<table>"
        else
            out[str(k)] = str(v)
        end
    end
    return out
end

local function finish()
    local ok, n = safe(C_AuctionHouse.GetNumOwnedAuctions)
    rec.ownedCount = ok and n or ("ERROR " .. str(n))
    rec.auctions = {}
    for i = 1, math.min(5, ok and tonumber(n) or 0) do
        local entry = { index = i }
        local okI, info = safe(C_AuctionHouse.GetOwnedAuctionInfo, i)
        if okI and type(info) == "table" then
            entry.info = describe(info, 2)
            local id = info.auctionID
            if id then
                local okC, cost = safe(C_AuctionHouse.GetCancelCost, id)
                entry.cancelCost = okC and str(cost) or ("ERROR " .. str(cost))
                local okK, can = safe(C_AuctionHouse.CanCancelAuction, id)
                entry.canCancel = okK and str(can) or ("ERROR " .. str(can))
            end
            local itemID = info.itemKey and info.itemKey.itemID
            if itemID and info.quantity then
                -- Deposit for relisting one unit for each duration option (1 = 12h, 2 = 24h, 3 = 48h).
                entry.deposit = {}
                for duration = 1, 3 do
                    local okD, deposit = safe(C_AuctionHouse.CalculateCommodityDeposit, itemID, duration, 1)
                    entry.deposit["duration" .. duration] = okD and str(deposit) or ("ERROR " .. str(deposit))
                end
            end
        else
            entry.infoError = str(info)
        end
        rec.auctions[#rec.auctions + 1] = entry
    end
    StockistProbeDB.owned = rec
    say(("done: %s owned auctions read. /reload to save."):format(str(rec.ownedCount)))
end

StockistProbeCommands = StockistProbeCommands or {}
StockistProbeCommands.owned = function()
    rec = { eventsSeen = {}, apis = {}, missing = {} }
    for _, name in ipairs(APIS) do
        if C_AuctionHouse and type(C_AuctionHouse[name]) == "function" then
            rec.apis[#rec.apis + 1] = name
        else
            rec.missing[#rec.missing + 1] = name
        end
    end
    StockistProbeDB = StockistProbeDB or {}
    StockistProbeDB.owned = rec
    local okThrottle, ready = safe(C_AuctionHouse.IsThrottledMessageSystemReady)
    rec.throttleReady = okThrottle and str(ready) or ("ERROR " .. str(ready))
    local okQ, err = safe(C_AuctionHouse.QueryOwnedAuctions, {})
    rec.query = okQ and "called" or ("ERROR " .. str(err))
    say("owned-auction query " .. rec.query .. "; reading in 4 seconds...")
    C_Timer.After(4, finish)
end
