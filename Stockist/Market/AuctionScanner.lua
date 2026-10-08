local ADDON_NAME, Stockist = ...

-- Adapter between the game's Auction House API and the rest of the addon. Everything that touches
-- C_AuctionHouse lives here, so the data layer never sees a game call.
--
-- Flow (same shape as Auctionator's full scan on this client):
--   AUCTION_HOUSE_SHOW -> ReplicateItems() -> REPLICATE_ITEM_LIST_UPDATE -> read every auction in
--   batches -> keep trade goods -> reduce each item's tiers -> store one reading per item.
--
-- GetReplicateItemInfo(i) returns (positions we use): 3 = count, 10 = buyoutPrice, 17 = itemID.
-- The server allows a replicate about every 15 minutes (Config.scan.minIntervalSec).
local Aggregate = Stockist.Aggregate

local Scanner = { inProgress = false, ahOpen = false }
Stockist.Scanner = Scanner

local BATCH = 500
local TRADE_GOODS = (Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods) or 7

-- How long we wait for the server's answer before giving up. The server ignores a ReplicateItems request
-- made during its wait, so without this an ignored request would leave a scan "in progress" forever.
local ANSWER_TIMEOUT = 45
-- After an ignored request, retry after 2 minutes, then 4, 8 ... up to 15: this finds the end of the
-- server's wait without hammering it.
local BACKOFF_FIRST, BACKOFF_MAX = 120, 900
local LOG_SIZE = 10 -- recent requests kept in the saved data, to learn how the server behaves

--- Seconds until it is worth sending another full-scan request. Two things hold us back:
---  * the server's wait, which runs from when the last request was MADE (as in Auctionator), not from
---    when it finished: closing the window half way through a scan does not give the request back;
---  * a short retry delay after a request the server ignored.
function Scanner:SecondsUntilNextScan()
    local scan = Stockist.db.scan
    local now = Stockist.Clock.now()
    local since = math.max(scan.last or 0, scan.requested or 0)
    local wait = since + Stockist.Config.scan.minIntervalSec - now
    local retry = (scan.retryAt or 0) - now
    return math.max(0, wait, retry)
end

local function waitText(seconds)
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

local function logRequest(scan, entry)
    scan.log = scan.log or {}
    scan.log[#scan.log + 1] = entry
    while #scan.log > LOG_SIZE do table.remove(scan.log, 1) end
end

--- Begin a scan. `force` skips our own wait (the server may still ignore the request). Returns true, or
--- false plus a human-readable reason.
function Scanner:Start(force)
    if self.inProgress then return false, "a scan is already running" end
    if not self.ahOpen then return false, "open the Auction House first" end
    local wait = self:SecondsUntilNextScan()
    if wait > 0 and not force then
        return false, "next scan available in " .. waitText(wait)
    end

    local scan = Stockist.db.scan
    local now = Stockist.Clock.now()
    self.inProgress = true
    self.gotAnswer = false
    self.scanId = (self.scanId or 0) + 1
    local id = self.scanId
    local previousRequest = scan.requested
    scan.requested = now
    self.frame:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    local ok, err = pcall(C_AuctionHouse.ReplicateItems)
    if not ok then
        -- The client refused the call, so the server never saw a request: it starts no wait. Release the
        -- scan quietly; the caller reports the reason (once) to the player.
        scan.requested = previousRequest
        self.inProgress = false
        self.frame:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
        return false, "the Auction House refused the request: " .. tostring(err)
    end
    local entry = { at = now }
    self.currentRequest = entry
    logRequest(scan, entry)
    Stockist.Events:Fire("SCAN_STARTED")

    C_Timer.After(ANSWER_TIMEOUT, function()
        if self.inProgress and self.scanId == id and not self.gotAnswer then
            -- An ignored request starts no wait of its own: forget it, and retry after a growing delay.
            entry.answered = false
            scan.requested = previousRequest
            scan.misses = (scan.misses or 0) + 1
            scan.retryAt = Stockist.Clock.now() + math.min(BACKOFF_MAX, BACKOFF_FIRST * 2 ^ (scan.misses - 1))
            self:Abort(("no answer from the server after %d seconds; it is probably still on its wait from an earlier scan"):format(ANSWER_TIMEOUT))
        end
    end)
    return true
end

--- The server answered our request: it is no longer ignoring us.
function Scanner:NoteAnswered()
    self.gotAnswer = true
    local scan = Stockist.db and Stockist.db.scan
    if not scan then return end
    scan.misses, scan.retryAt = 0, nil
    local entry = self.currentRequest
    if entry then
        entry.answered = true
        entry.seconds = Stockist.Clock.now() - entry.at
    end
end

--- Auto-scan is on unless the player turned it off (account-wide setting).
function Scanner:AutoEnabled()
    local setting = Stockist.settings and Stockist.settings.autoScan
    if setting == nil then return Stockist.Config.scan.autoOnOpen end
    return setting
end

local WATCH_INTERVAL = 30 -- seconds between "is a scan due?" checks while the window is open

--- While the Auction House stays open, start the next scan as soon as the throttle allows.
function Scanner:StartWatching()
    if self.ticker then return end
    self.ticker = C_Timer.NewTicker(WATCH_INTERVAL, function()
        if not self.ahOpen then return self:StopWatching() end
        if self:AutoEnabled() and not self.inProgress and self:SecondsUntilNextScan() == 0 then
            self:Start()
        end
    end)
end

function Scanner:StopWatching()
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
end

function Scanner:Abort(reason)
    if not self.inProgress then return end
    self.inProgress = false
    self.frame:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    local wait = Stockist.db and self:SecondsUntilNextScan() or 0
    if wait > 0 then reason = reason .. ". Next scan in " .. waitText(wait) end
    Stockist.Events:Fire("SCAN_FAILED", reason)
end

local classCache = {}
local function itemClass(itemID)
    local cached = classCache[itemID]
    if cached then return cached[1], cached[2] end
    local info = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    local _, _, _, _, _, classID, subClassID = info(itemID)
    if classID then classCache[itemID] = { classID, subClassID } end
    return classID, subClassID
end

function Scanner:Finish(tiersByItem, classes)
    local cfg = Stockist.Config.scan
    local now = Stockist.Clock.now()
    local recorded = 0
    for itemID, tiers in pairs(tiersByItem) do
        local agg = Aggregate.Reduce(tiers, cfg.cheapestUnits)
        if agg and Stockist.store:Add({
            item = itemID, ts = now, price = agg.median, min = agg.min, qty = agg.qty,
        }) then
            recorded = recorded + 1
            local c = classes[itemID]
            if c then Stockist.store:SetMeta(itemID, c[1], c[2]) end
        end
    end
    Stockist.db.scan.last = now
    Stockist.db.scan.items = recorded
    self.inProgress = false
    Stockist.Events:Fire("SCAN_COMPLETE", recorded, now)
end

--- Walk the replicate list in batches so the client does not stall.
function Scanner:Collect()
    local total = C_AuctionHouse.GetNumReplicateItems()
    local tiersByItem, classes = {}, {}
    local index = 0

    local function step()
        if not self.inProgress then return end
        local stop = math.min(index + BATCH, total)
        local ok, err = pcall(function()
            while index < stop do
                local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID =
                    C_AuctionHouse.GetReplicateItemInfo(index)
                index = index + 1
                if itemID and itemID > 0 and count and count > 0 and buyout and buyout > 0 then
                    local classID, subClassID = itemClass(itemID)
                    -- Trade goods are the commodities we chart by default. An item the player tracks is
                    -- recorded whatever it is (a recipe, armour...), so tracking something always works.
                    if classID == TRADE_GOODS or (Stockist.tracked and Stockist.tracked:Has(itemID)) then
                        local list = tiersByItem[itemID]
                        if not list then
                            list = {}
                            tiersByItem[itemID] = list
                            classes[itemID] = { classID, subClassID }
                        end
                        list[#list + 1] = { price = buyout / count, qty = count }
                    end
                end
            end
        end)
        if not ok then
            return self:Abort("error reading auctions: " .. tostring(err))
        end
        if index >= total then
            -- If saving the results fails, still release the scan; a stuck "in progress" blocks every later one.
            local saved, saveErr = pcall(self.Finish, self, tiersByItem, classes)
            if not saved then self:Abort("error saving the scan: " .. tostring(saveErr)) end
        else
            C_Timer.After(0, step)
        end
    end
    step()
end

local frame = CreateFrame("Frame")
Scanner.frame = frame
frame:RegisterEvent("AUCTION_HOUSE_SHOW")
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
frame:SetScript("OnEvent", function(_, event)
    if event == "AUCTION_HOUSE_SHOW" then
        Scanner.ahOpen = true
        Stockist.Events:Fire("AH_OPENED")
        if Stockist.db then
            Scanner:StartWatching()
            if Scanner:AutoEnabled() then
                local ok, reason = Scanner:Start()
                if not ok then Stockist.Events:Fire("SCAN_SKIPPED", reason) end
            end
        end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        Scanner.ahOpen = false
        Scanner:StopWatching()
        Stockist.Events:Fire("AH_CLOSED")
        Scanner:Abort("Auction House closed during the scan")
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        Scanner:NoteAnswered()
        frame:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
        Scanner:Collect()
    end
end)
