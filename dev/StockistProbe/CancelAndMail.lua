-- /stkprobe cancelwatch : watch what happens to your gold and messages while YOU cancel one of your own
--   auctions by hand in the normal Auction House window. The probe never cancels anything itself.
--   Steps: run it, cancel ONE cheap listing within 3 minutes, note any popup text, then /reload.
-- /stkprobe mailcut : with the mailbox OPEN, read sale/purchase invoices in the inbox (sale price, deposit,
--   Auction House cut). Needs at least one auction mail ("Auction successful" etc.) waiting.
-- Results: StockistProbeDB.cancelwatch and StockistProbeDB.mailcut.

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

local function snapshotOwned()
    local out = { auctions = {} }
    if not (C_AuctionHouse and C_AuctionHouse.GetNumOwnedAuctions) then return out end
    local ok, n = safe(C_AuctionHouse.GetNumOwnedAuctions)
    out.count = ok and n or ("ERROR " .. str(n))
    for i = 1, ok and tonumber(n) or 0 do
        local okI, info = safe(C_AuctionHouse.GetOwnedAuctionInfo, i)
        if okI and type(info) == "table" then
            local okC, cost = safe(C_AuctionHouse.GetCancelCost, info.auctionID)
            out.auctions[#out.auctions + 1] = {
                id = str(info.auctionID), item = str(info.itemKey and info.itemKey.itemID),
                buyout = str(info.buyoutAmount), bid = str(info.bidAmount), cancelCost = okC and str(cost) or "ERROR",
            }
        end
    end
    return out
end

local WATCH_EVENTS = {
    "PLAYER_MONEY", "AUCTION_CANCELED", "CHAT_MSG_SYSTEM", "CHAT_MSG_MONEY", "UI_INFO_MESSAGE",
    "UI_ERROR_MESSAGE", "MAIL_INBOX_UPDATE", "OWNED_AUCTIONS_UPDATED",
}
local watching, watch = false, nil
local f = CreateFrame("Frame")
for _, e in ipairs(WATCH_EVENTS) do pcall(f.RegisterEvent, f, e) end
f:SetScript("OnEvent", function(_, event, ...)
    if not watching then return end
    local packed, n = { ... }, select("#", ...)
    local ok, args = pcall(function() return table.concat({ tostringall(unpack(packed, 1, n)) }, " | ") end)
    watch.events[#watch.events + 1] = {
        at = math.floor((GetTime() - watch.startedAt) * 10) / 10, event = event,
        args = ok and args or "?", money = GetMoney(),
    }
end)

StockistProbeCommands = StockistProbeCommands or {}
StockistProbeCommands.cancelwatch = function()
    watch = { events = {}, startedAt = GetTime(), moneyBefore = GetMoney(), ownedBefore = snapshotOwned() }
    StockistProbeDB = StockistProbeDB or {}
    StockistProbeDB.cancelwatch = watch
    watching = true
    say(("watching for 3 minutes. Gold now: %s copper. Cancel ONE cheap listing in the AH window."):format(str(watch.moneyBefore)))
    C_Timer.After(180, function()
        watching = false
        watch.moneyAfter = GetMoney()
        watch.ownedAfter = snapshotOwned()
        say(("watch finished. Gold change: %s copper. /reload to save."):format(str(watch.moneyAfter - watch.moneyBefore)))
    end)
end

StockistProbeCommands.mailcut = function()
    local rec = { invoices = {} }
    StockistProbeDB = StockistProbeDB or {}
    StockistProbeDB.mailcut = rec
    if not GetInboxNumItems then
        rec.error = "GetInboxNumItems missing"
        return say("mail API missing")
    end
    local n = GetInboxNumItems()
    rec.inboxCount = n
    for i = 1, n do
        local okI, invoiceType, itemName, playerName, bid, buyout, deposit, consignment = safe(GetInboxInvoiceInfo, i)
        local okH, _, _, sender, subject, money = safe(GetInboxHeaderInfo, i)
        rec.invoices[#rec.invoices + 1] = {
            index = i, sender = okH and str(sender) or "?", subject = okH and str(subject) or "?",
            attachedMoney = okH and str(money) or "?",
            invoiceType = okI and str(invoiceType) or nil, item = okI and str(itemName) or nil,
            bid = okI and str(bid) or nil, buyout = okI and str(buyout) or nil,
            deposit = okI and str(deposit) or nil, consignment = okI and str(consignment) or nil,
        }
    end
    say(("read %d mail items (open the mailbox first). /reload to save."):format(n))
end
