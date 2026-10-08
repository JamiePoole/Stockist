local ADDON_NAME, Stockist = ...

-- Keeps the saved data from growing without bound, and lets the player choose what to keep.
--   /stockist track <item>      keep this item's history longer; never cleaned up as idle
--   /stockist untrack <item>
--   /stockist tracked           list tracked items
--   /stockist keep [name days]  show or change how long data is kept
--   /stockist cleanup           run the cleanup now
-- The cleanup itself runs at login and logout (Core/Bootstrap.lua) and is implemented by
-- ReadingStore:Prune; this file is the player-facing side.
local Format = Stockist.Format
local Retention = Stockist.Retention

local function say(msg) Stockist.Print(msg) end

--- Options for the store from the player's current settings. Used at startup and after `keep`.
function Stockist.RetentionOptions()
    local effective = Retention.Effective(Stockist.settings.retention)
    return Retention.StoreOptions(effective, function(id) return Stockist.tracked:Has(id) end)
end

local function describe(stats)
    return ("%d old candles and %d idle items"):format(stats.candles, stats.items)
end

local function track(arg)
    local id = Stockist.ParseItemID(arg)
    if not id then return say("usage: /stockist track <itemID or link>") end
    if Stockist.ItemInfo.Exists(id) == false then return say(("no item has the ID %d, so there is nothing to track."):format(id)) end
    local name = Stockist.ItemName(id)
    if Stockist.tracked:Add(id) then
        say(("tracking %s: history kept %d days hourly, %d days daily."):format(name,
            Retention.Effective(Stockist.settings.retention).trackedHourlyDays,
            Retention.Effective(Stockist.settings.retention).trackedDailyDays))
        Stockist.Events:Fire("TRACKED_CHANGED", id, true)
    else
        say(name .. " is already tracked.")
    end
end

local function untrack(arg)
    local id = Stockist.ParseItemID(arg)
    if not id then return say("usage: /stockist untrack <itemID or link>") end
    if Stockist.tracked:Remove(id) then
        say("no longer tracking " .. Stockist.ItemName(id) .. ".")
        Stockist.Events:Fire("TRACKED_CHANGED", id, false)
    else
        say(Stockist.ItemName(id) .. " was not tracked.")
    end
end

local function tracked()
    local list = Stockist.tracked:List()
    if #list == 0 then return say("no tracked items. Use /stockist track <item>.") end
    say(("%d tracked items:"):format(#list))
    for _, id in ipairs(list) do
        local last = Stockist.store:Latest(id)
        say(("  %s  %s"):format(Stockist.ItemName(id), last and Format.Money(last.price) or "no data yet"))
    end
end

local function showRetention()
    local overrides = Stockist.settings.retention or {}
    local effective = Retention.Effective(overrides)
    say("how long data is kept (days; cap is a candle count):")
    for _, name in ipairs(Retention.ORDER) do
        local key = Retention.NAMES[name]
        say(("  %-15s %d%s"):format(name, effective[key], overrides[key] and "" or "  (default)"))
    end
end

local function keep(arg)
    if arg == "" then return showRetention() end
    local name, value = arg:match("^(%S+)%s*(.-)$")
    Stockist.settings.retention = Stockist.settings.retention or {}
    if name == "reset" then
        local ok, reason = Retention.Reset(Stockist.settings.retention, value ~= "" and value or nil)
        if not ok then return say(reason) end
    else
        local ok, reason = Retention.Set(Stockist.settings.retention, name, tonumber(value))
        if not ok then
            return say(reason .. ". Names: " .. table.concat(Retention.ORDER, ", ") .. ".")
        end
    end
    Stockist.store:Configure(Stockist.RetentionOptions())
    showRetention()
end

local function cleanup()
    local _, stats = Stockist.store:Prune(Stockist.Clock.now())
    say("cleanup removed " .. describe(stats) .. (stats.capped > 0 and (" (" .. stats.capped .. " over the cap)") or "") .. ".")
end

local C = Stockist.Commands
C:Register("track", { help = "track <item>        keep its history longer", run = track })
C:Register("untrack", { help = "untrack <item>", run = untrack })
C:Register("tracked", { help = "tracked             list tracked items", run = tracked })
C:Register("keep", { help = "keep [name days]   show or set how long data is kept (keep reset to undo)", run = keep })
C:Register("cleanup", { help = "cleanup             delete data past the limits now", run = cleanup })

-- Only mention a login cleanup if it actually removed something.
Stockist.Events:On("DATA_PRUNED", function(stats, when)
    if when == "login" and (stats.candles > 0 or stats.items > 0) then
        say("cleaned up " .. describe(stats) .. ".")
    end
end)
