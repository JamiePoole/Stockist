local ADDON_NAME, Stockist = ...

local SCHEMA_VERSION = 1

-- Price history is kept per market. The Auction House is shared by a realm (or connected realms),
-- so the key is the normalized realm name. Revisit if Forever splits it by faction.
function Stockist.MarketKey()
    return (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or "unknown"
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        StockistDB = StockistDB or {}
        StockistDB.schema = StockistDB.schema or SCHEMA_VERSION
        StockistDB.markets = StockistDB.markets or {}

        local key = Stockist.MarketKey()
        local market = StockistDB.markets[key]
        if not market then
            market = {}
            StockistDB.markets[key] = market
        end
        market.scan = market.scan or {}

        Stockist.marketKey = key
        Stockist.db = market
        Stockist.store = Stockist.ReadingStore.New(market, Stockist.Config.retention)
        Stockist.Events:Fire("ADDON_READY")
    elseif event == "PLAYER_LOGOUT" and Stockist.store then
        Stockist.store:Prune(Stockist.Clock.now())
    end
end)
