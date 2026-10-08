local DAY = 86400

-- Loads the command layer and the cleanup feature against a real store, capturing output.
local function setup()
    local S = load_addon("Core/Config.lua", "Core/Clock.lua", "Core/EventBus.lua", "Core/Registry.lua",
        "Core/Format.lua", "Core/Commands.lua", "Data/Rollup.lua", "Data/ReadingStore.lua",
        "Data/Retention.lua", "Data/Tracked.lua", "Features/DataCleanup.lua")
    local out = {}
    S.Print = function(msg) out[#out + 1] = msg end
    S.Clock.now = function() return 300 * DAY end
    S.settings = { tracked = {}, retention = {} }
    S.tracked = S.Tracked.New(S.settings.tracked)
    S.store = S.ReadingStore.New({}, S.RetentionOptions())
    -- item helpers normally defined by StatusCommands
    S.ParseItemID = function(t) return tonumber(t) or tonumber((t or ""):match("item:(%d+)")) end
    S.ItemName = function(id) return "Item" .. id end
    return S, out
end

local function joined(out) return table.concat(out, "\n") end

test("Commands dispatches by name, defaults to status, and prints help for unknown names", function()
    local S, out = setup()
    local seen = {}
    S.Commands:Register("ping", { help = "ping", run = function(args) seen[#seen + 1] = args end })
    S.Commands:Register("status", { help = "status", run = function() seen[#seen + 1] = "status" end })
    S.Commands:Dispatch("ping  a b ")
    S.Commands:Dispatch("PING x")
    S.Commands:Dispatch("")
    eq(table.concat(seen, "|"), "a b|x|status")
    S.Commands:Dispatch("nonsense")
    eq(joined(out):find("commands:", 1, true) ~= nil, true)
    eq(joined(out):find("/stockist ping", 1, true) ~= nil, true)
end)

test("Commands refuses to run before the store exists", function()
    local S, out = setup()
    S.store = nil
    S.Commands:Dispatch("track 5")
    eq(out[#out], "not ready yet.")
end)

test("track and untrack update the set and fire an event", function()
    local S, out = setup()
    local events = {}
    S.Events:On("TRACKED_CHANGED", function(id, on) events[#events + 1] = id .. ":" .. tostring(on) end)
    S.Commands:Dispatch("track 2589")
    eq(S.tracked:Has(2589), true)
    eq(S.settings.tracked[2589], true, "persisted in the settings table")
    S.Commands:Dispatch("track item:2589")
    eq(out[#out], "Item2589 is already tracked.")
    S.Commands:Dispatch("untrack 2589")
    eq(S.tracked:Has(2589), false)
    eq(table.concat(events, ","), "2589:true,2589:false")
    S.Commands:Dispatch("track banana")
    eq(out[#out], "usage: /stockist track <itemID or link>")
end)

test("tracked lists items with their latest price", function()
    local S, out = setup()
    S.Commands:Dispatch("tracked")
    eq(out[#out], "no tracked items. Use /stockist track <item>.")
    S.tracked:Add(7)
    S.store:Add({ item = 7, ts = 100, price = 12345, qty = 1 })
    S.Commands:Dispatch("tracked")
    eq(joined(out):find("Item7  1g 23s 45c", 1, true) ~= nil, true)
end)

test("keep shows defaults, sets a value, applies it to the live store, and resets", function()
    local S, out = setup()
    S.Commands:Dispatch("keep")
    eq(joined(out):find("hourly", 1, true) ~= nil, true)
    eq(joined(out):find("(default)", 1, true) ~= nil, true)

    S.Commands:Dispatch("keep hourly 3")
    eq(S.settings.retention.hourlyDays, 3)
    eq(S.store.hourlyKeep, 3 * DAY, "store reconfigured")

    S.Commands:Dispatch("keep hourly banana")
    eq(joined(out):find("must be a whole number", 1, true) ~= nil, true)
    eq(S.settings.retention.hourlyDays, 3, "bad value ignored")

    S.Commands:Dispatch("keep reset hourly")
    is_nil(S.settings.retention.hourlyDays)
    eq(S.store.hourlyKeep, S.Config.retention.hourlyDays * DAY)
    S.Commands:Dispatch("keep nope 3")
    eq(joined(out):find("unknown setting", 1, true) ~= nil, true)
end)

test("tracked items pick up the longer window through RetentionOptions", function()
    local S = setup()
    S.tracked:Add(1)
    local o = S.RetentionOptions()
    eq(o.isTracked(1), true); eq(o.isTracked(2), false)
    eq(o.trackedHourlyKeepSec, S.Config.retention.trackedHourlyDays * DAY)
    eq(o.trackedHourlyKeepSec > o.hourlyKeepSec, true)
end)

test("cleanup reports what it removed", function()
    local S, out = setup()
    S.store:Add({ item = 1, ts = 10 * DAY, price = 5, qty = 1 }) -- ~290 days old: past every untracked window
    S.Commands:Dispatch("cleanup")
    eq(out[#out]:find("cleanup removed", 1, true) ~= nil, true)
    eq(#S.store:Items(), 0)
end)

test("DATA_PRUNED prints at login only when something was removed", function()
    local S, out = setup()
    S.Events:Fire("DATA_PRUNED", { candles = 0, items = 0, capped = 0 }, "login")
    S.Events:Fire("DATA_PRUNED", { candles = 5, items = 1, capped = 0 }, "logout")
    eq(#out, 0)
    S.Events:Fire("DATA_PRUNED", { candles = 5, items = 1, capped = 0 }, "login")
    eq(out[1], "cleaned up 5 old candles and 1 idle items.")
end)
