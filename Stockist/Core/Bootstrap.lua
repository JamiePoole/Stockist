local ADDON_NAME, Stockist = ...

local SCHEMA_VERSION = 1

-- Price history is kept per market. The Auction House is shared by a realm (or connected realms),
-- so the key is the normalized realm name. Revisit if Forever splits it by faction.
function Stockist.MarketKey()
    return (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or "unknown"
end

--- Run the data cleanup and tell listeners what it removed. `when` is "login" or "logout".
local function cleanup(when)
    local removed, stats = Stockist.store:Prune(Stockist.Clock.now())
    if removed > 0 or stats.items > 0 then Stockist.Events:Fire("DATA_PRUNED", stats, when) end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        StockistDB = StockistDB or {}
        StockistDB.schema = StockistDB.schema or SCHEMA_VERSION
        StockistDB.markets = StockistDB.markets or {}
        StockistDB.settings = StockistDB.settings or {}
        StockistDB.settings.tracked = StockistDB.settings.tracked or {}
        StockistDB.settings.retention = StockistDB.settings.retention or {}
        Stockist.settings = StockistDB.settings
        Stockist.tracked = Stockist.Tracked.New(Stockist.settings.tracked)

        local key = Stockist.MarketKey()
        local market = StockistDB.markets[key]
        if not market then
            market = {}
            StockistDB.markets[key] = market
        end
        market.scan = market.scan or {}

        Stockist.marketKey = key
        Stockist.db = market
        Stockist.store = Stockist.ReadingStore.New(market, Stockist.RetentionOptions())
        cleanup("login") -- also covers sessions that ended in a crash and never ran the logout cleanup
        Stockist.Events:Fire("ADDON_READY")
    elseif event == "PLAYER_LOGOUT" and Stockist.store then
        cleanup("logout")
    end
end)
