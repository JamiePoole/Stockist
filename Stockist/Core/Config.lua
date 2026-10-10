local ADDON_NAME, Stockist = ...

-- Defaults only; the player's overrides live in StockistDB.settings and layer on top.
Stockist.Config = {
    scan = {
        minIntervalSec = 15 * 60, -- ReplicateItems is server-throttled to about once per 15 minutes
        cheapestUnits = 200,      -- charts and moves follow the median of this many cheapest units; the shown price is the cheapest
        autoOnOpen = true,
    },
    -- How long price history is kept, in days. Tracked items (see Data/Tracked.lua) are kept longer
    -- and are never dropped as idle.
    retention = {
        hourlyDays = 7,
        dailyDays = 180,
        idleDays = 90,          -- an untracked item with no reading for this long is removed entirely
        trackedHourlyDays = 30,
        trackedDailyDays = 730,
        maxCandles = 80000,     -- hard cap on stored candles; the oldest untracked data goes first
    },
}
