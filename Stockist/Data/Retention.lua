local ADDON_NAME, Stockist = ...

-- Turns retention settings (days, with player overrides) into the options the ReadingStore uses.
local Retention = {}
Stockist.Retention = Retention

local DAY = 86400

-- Name used on the command line -> key in Config.retention.
Retention.NAMES = {
    hourly = "hourlyDays",
    daily = "dailyDays",
    idle = "idleDays",
    ["tracked-hourly"] = "trackedHourlyDays",
    ["tracked-daily"] = "trackedDailyDays",
    cap = "maxCandles",
}
Retention.ORDER = { "hourly", "daily", "idle", "tracked-hourly", "tracked-daily", "cap" }

local LIMITS = {
    maxCandles = { 1000, 500000 },
    default = { 1, 3650 },
}

--- Defaults with the player's overrides applied. Unknown or invalid overrides are ignored.
function Retention.Effective(overrides)
    local out = {}
    for _, key in pairs(Retention.NAMES) do
        local v = overrides and overrides[key]
        local limit = LIMITS[key] or LIMITS.default
        if type(v) == "number" and v >= limit[1] and v <= limit[2] then
            out[key] = v
        else
            out[key] = Stockist.Config.retention[key]
        end
    end
    return out
end

--- Set one override. `name` is a command-line name (e.g. "hourly"). Returns true, or false + reason.
function Retention.Set(overrides, name, value)
    local key = Retention.NAMES[name]
    if not key then return false, "unknown setting '" .. tostring(name) .. "'" end
    local limit = LIMITS[key] or LIMITS.default
    if type(value) ~= "number" or value ~= math.floor(value) or value < limit[1] or value > limit[2] then
        return false, ("%s must be a whole number from %d to %d"):format(name, limit[1], limit[2])
    end
    overrides[key] = value
    return true
end

--- Clear one override (back to the default), or all of them when `name` is nil.
function Retention.Reset(overrides, name)
    if name == nil then
        for k in pairs(overrides) do overrides[k] = nil end
        return true
    end
    local key = Retention.NAMES[name]
    if not key then return false, "unknown setting '" .. tostring(name) .. "'" end
    overrides[key] = nil
    return true
end

--- ReadingStore options. `isTracked(itemID)` says which items get the longer tracked windows.
function Retention.StoreOptions(effective, isTracked)
    return {
        hourlyKeepSec = effective.hourlyDays * DAY,
        dailyKeepSec = effective.dailyDays * DAY,
        idleKeepSec = effective.idleDays * DAY,
        trackedHourlyKeepSec = effective.trackedHourlyDays * DAY,
        trackedDailyKeepSec = effective.trackedDailyDays * DAY,
        maxCandles = effective.maxCandles,
        isTracked = isTracked,
    }
end
