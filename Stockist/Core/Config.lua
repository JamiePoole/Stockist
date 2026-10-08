local ADDON_NAME, Stockist = ...

-- Defaults only for now; user overrides will layer on top in a later change.
Stockist.Config = {
    scan = {
        minIntervalSec = 15 * 60, -- ReplicateItems is server-throttled to about once per 15 minutes
        cheapestUnits = 200,      -- the headline price is the median of this many cheapest units
        autoOnOpen = true,
    },
    retention = {
        hourlyKeepSec = 7 * 86400,
        dailyKeepSec = 180 * 86400,
    },
}
