-- Exercises AuctionScanner against stubbed game APIs.

local function setup(auctions, opts)
    opts = opts or {}
    local timers = {}
    local frame
    local replicateCalls = 0

    CreateFrame = function()
        frame = {
            events = {},
            RegisterEvent = function(self, e) self.events[e] = true end,
            UnregisterEvent = function(self, e) self.events[e] = nil end,
            SetScript = function(self, _, fn) self.onEvent = fn end,
        }
        return frame
    end
    C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    C_Item = {
        GetItemInfoInstant = function(id)
            local class = opts.classes and opts.classes[id] or 7
            return id, "t", "s", "", 0, class, 5
        end,
    }
    C_AuctionHouse = {
        ReplicateItems = function() replicateCalls = replicateCalls + 1 end,
        GetNumReplicateItems = function() return #auctions end,
        GetReplicateItemInfo = function(i)
            local a = auctions[i + 1]
            return "n", 0, a.count, 1, true, 0, 0, 0, 0, a.buyout, 0, "", "", "", "", 0, a.item, true
        end,
    }

    local S = load_addon("Core/Config.lua", "Core/Clock.lua", "Core/EventBus.lua", "Data/Rollup.lua",
        "Data/ReadingStore.lua", "Market/Aggregate.lua", "Market/AuctionScanner.lua")
    S.Clock.now = function() return opts.now or 100000 end
    S.db = { scan = {} }
    S.store = S.ReadingStore.New(S.db)

    local events = {}
    for _, name in ipairs({ "SCAN_STARTED", "SCAN_COMPLETE", "SCAN_FAILED", "SCAN_SKIPPED" }) do
        S.Events:On(name, function(...) events[#events + 1] = { name, ... } end)
    end

    local function flush()
        local guard = 0
        while #timers > 0 and guard < 1000 do
            local fn = table.remove(timers, 1)
            fn()
            guard = guard + 1
        end
    end

    return S, frame, events, flush, function() return replicateCalls end
end

local function fire(frame, event) frame.onEvent(frame, event) end

test("scan records one reading per trade-goods item, skipping other classes", function()
    local auctions = {
        { item = 10, count = 5, buyout = 500 },   -- 100 each
        { item = 10, count = 5, buyout = 1000 },  -- 200 each
        { item = 20, count = 1, buyout = 777 },
        { item = 99, count = 1, buyout = 5000 },  -- not trade goods
    }
    local S, frame, events, flush = setup(auctions, { classes = { [99] = 2 } })
    fire(frame, "AUCTION_HOUSE_SHOW")
    fire(frame, "REPLICATE_ITEM_LIST_UPDATE")
    flush()

    local ten = S.store:Latest(10)
    eq(ten.min, 100); eq(ten.qty, 10); near(ten.price, 150)
    eq(S.store:Latest(20).price, 777)
    is_nil(S.store:Latest(99))
    eq(S.store:GetMeta(10).class, 7)
    eq(S.db.scan.last, 100000)
    eq(events[#events][1], "SCAN_COMPLETE")
    eq(events[#events][2], 2)
end)

test("scan ignores auctions with no buyout or zero count", function()
    local auctions = {
        { item = 10, count = 5, buyout = 0 },
        { item = 10, count = 0, buyout = 500 },
        { item = 10, count = 2, buyout = 400 },
    }
    local S, frame, _, flush = setup(auctions)
    fire(frame, "AUCTION_HOUSE_SHOW")
    fire(frame, "REPLICATE_ITEM_LIST_UPDATE")
    flush()
    eq(S.store:Latest(10).qty, 2)
    eq(S.store:Latest(10).price, 200)
end)

test("large lists are processed in several batches", function()
    local auctions = {}
    for i = 1, 1200 do auctions[i] = { item = 10, count = 1, buyout = 100 } end
    local S, frame, _, flush = setup(auctions)
    fire(frame, "AUCTION_HOUSE_SHOW")
    fire(frame, "REPLICATE_ITEM_LIST_UPDATE")
    -- first batch ran synchronously; the rest wait on timers
    is_nil(S.store:Latest(10), "not finished after one batch")
    flush()
    eq(S.store:Latest(10).qty, 1200)
end)

test("a second scan inside the throttle window is refused", function()
    local S, frame, events, flush, replicates = setup({ { item = 10, count = 1, buyout = 100 } })
    fire(frame, "AUCTION_HOUSE_SHOW")
    fire(frame, "REPLICATE_ITEM_LIST_UPDATE")
    flush()
    eq(replicates(), 1)

    S.Clock.now = function() return 100000 + 60 end
    fire(frame, "AUCTION_HOUSE_SHOW")
    eq(replicates(), 1, "no second replicate call")
    eq(events[#events][1], "SCAN_SKIPPED")

    S.Clock.now = function() return 100000 + 15 * 60 + 1 end
    fire(frame, "AUCTION_HOUSE_SHOW")
    eq(replicates(), 2)
end)

test("closing the Auction House mid-scan aborts it", function()
    local S, frame, events = setup({ { item = 10, count = 1, buyout = 100 } })
    fire(frame, "AUCTION_HOUSE_SHOW")
    fire(frame, "AUCTION_HOUSE_CLOSED")
    eq(events[#events][1], "SCAN_FAILED")
    eq(S.Scanner.inProgress, false)
    is_nil(S.db.scan.last)
end)

test("manual Start refuses when the Auction House is not open", function()
    local S = setup({})
    local ok, reason = S.Scanner:Start()
    eq(ok, false)
    eq(reason, "open the Auction House first")
end)

test("an API error mid-scan fails the scan instead of crashing", function()
    local S, frame, events, flush = setup({ { item = 10, count = 1, buyout = 100 } })
    C_AuctionHouse.GetReplicateItemInfo = function() error("secret value") end
    fire(frame, "AUCTION_HOUSE_SHOW")
    fire(frame, "REPLICATE_ITEM_LIST_UPDATE")
    flush()
    eq(events[#events][1], "SCAN_FAILED")
    eq(S.Scanner.inProgress, false)
end)
