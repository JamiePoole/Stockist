load_support("fake_wow")

local DAY, HOUR = 86400, 3600
local NOON = 40 * DAY + 12 * HOUR

local FILES = {
    "Core/Clock.lua", "Core/EventBus.lua", "Core/Registry.lua", "Core/Panels.lua", "Core/Link.lua",
    "Core/Format.lua", "Core/Calendar.lua", "Core/ItemInfo.lua", "Core/Help.lua", "Core/HelpTopics.lua",
    "Core/Commands.lua", "Data/Rollup.lua", "Data/Indicators.lua", "Data/ReadingStore.lua", "Data/Tracked.lua",
    "Data/AlertRules.lua",
    "UI/Charts/Charts.lua", "UI/Charts/Util.lua", "UI/Charts/Scale.lua", "UI/Charts/Formatters.lua",
    "UI/Charts/Theme.lua", "UI/Charts/Series/Line.lua", "UI/Charts/Series/Candle.lua", "UI/Charts/Series/Bar.lua",
    "UI/Charts/Overlays/Overlays.lua", "UI/Charts/Core.lua", "UI/Charts/FrameCanvas.lua", "UI/Charts/ChartFrame.lua",
    "UI/Kit/Tooltip.lua", "UI/Kit/Button.lua", "UI/Kit/IconButton.lua", "UI/Kit/Guide.lua", "UI/Kit/Window.lua",
    "Features/PopOut.lua", "Features/PriceChart.lua", "Features/ItemPicker.lua", "Features/ChartPanel.lua",
    "Features/Watchlist.lua", "Features/Ticker.lua", "Features/Movers.lua", "Features/StatusBar.lua",
    "Features/Workspace.lua", "Features/StatusCommands.lua", "Features/AlertService.lua", "Features/AlertToasts.lua",
}

local NAMES = { [1] = "Linen Cloth", [2] = "Wool Cloth", [3] = "Silk Cloth" }

--- Items 1-3 with two days of scans. Item 1 ends at 1000 copper; 2 rose about 30%; 3 fell about 30%.
local function setup()
    Fake.install()
    local S = load_addon(unpack(FILES))
    S.settings = {}
    S.Clock.now = function() return NOON end
    S.db = { scan = { last = NOON } }
    S.store = S.ReadingStore.New(S.db)
    local ends = { [1] = { 1000, 1000 }, [2] = { 1000, 1300 }, [3] = { 1000, 700 } }
    for id, p in pairs(ends) do
        for h = 47, 0, -1 do S.store:Add({ item = id, ts = NOON - h * HOUR, price = p[1] + (p[2] - p[1]) * (47 - h) / 47, qty = 5 }) end
    end
    S.tracked = S.Tracked.New({})
    S.tracked:Add(1); S.tracked:Add(2); S.tracked:Add(3)
    S.ItemInfo.Name = function(id) return NAMES[id] end
    local printed = {}
    S.Print = function(msg) printed[#printed + 1] = msg end
    return S, printed
end

local function money(c) return c .. "c" end
local function nameOf(id) return NAMES[id] or ("item:" .. id) end

-- Money text ----------------------------------------------------------------------------------------

test("prices are read with their coins, in any order and spacing, and a bare number is refused", function()
    local S = setup()
    local P = S.Format.ParseMoney
    eq(P("5s"), 500); eq(P("1g"), 10000); eq(P("250c"), 250)
    eq(P("1g20s5c"), 12005); eq(P("1g 20s 5c"), 12005); eq(P("  5S  "), 500, "any case")
    eq(P("1.5g"), 15000, "a decimal amount")
    eq(P("5"), nil, "which coin?"); eq(P(""), nil); eq(P("abc"), nil); eq(P("5x"), nil)
    eq(P("1s2s"), nil, "a coin twice"); eq(P("g5"), nil)
    Fake.uninstall()
end)

-- Rules ---------------------------------------------------------------------------------------------

test("a rule must say enough to be tested", function()
    local S = setup()
    local V = S.AlertRules.Validate
    eq(V({ kind = "below", item = 1, value = 500 }), true)
    eq(V({ kind = "move", value = 10 }), true, "a move rule may cover every tracked item")
    eq(V({ kind = "stale", value = 6 }), true)
    local ok, why = V({ kind = "below", value = 500 })
    eq(ok, false); eq(why, "needs an item")
    eq(V({ kind = "sideways", value = 1 }), false)
    eq(V({ kind = "below", item = 1, value = 0 }), false, "zero is not a limit")
    eq(V({ kind = "below", item = 1, value = "5s" }), false, "the value is a number of copper")
    eq(V({ kind = "move", value = 10, direction = "left" }), false)
    eq(V({ kind = "below", item = 1, value = 5, severity = "panic" }), false)
    eq(V("nonsense"), false)
    Fake.uninstall()
end)

test("rules read as plain words", function()
    local S = setup()
    local D = S.AlertRules.Describe
    eq(D({ kind = "below", item = 1, value = 500 }, nameOf, money), "Linen Cloth below 500c")
    eq(D({ kind = "above", item = 2, value = 900 }, nameOf, money), "Wool Cloth above 900c")
    eq(D({ kind = "move", value = 10, direction = "up" }, nameOf, money), "any tracked item up 10% or more")
    eq(D({ kind = "move", item = 3, value = 5 }, nameOf, money), "Silk Cloth moves 5% or more")
    eq(D({ kind = "stale", value = 6 }, nameOf, money), "prices older than 6 hours")
    Fake.uninstall()
end)

local function ctx(over)
    local base = { now = NOON, lastScan = NOON, priceOf = function(id) return ({ [1] = 1000, [2] = 1300, [3] = 700 })[id] end,
        moveOf = function(id) return ({ [1] = 0, [2] = 30, [3] = -30 })[id] end }
    for k, v in pairs(over or {}) do base[k] = v end
    return base
end

test("below and above fire when the price crosses the limit, in either direction of the test", function()
    local S = setup()
    local E = S.AlertRules.Evaluate
    local rules = { { id = 1, kind = "below", item = 3, value = 800 }, { id = 2, kind = "above", item = 2, value = 1200 },
        { id = 3, kind = "below", item = 1, value = 900 } }
    local fired = E(rules, { 1, 2, 3 }, ctx(), {}, nameOf, money)
    eq(#fired, 2, "item 3 is under 800 and item 2 is over 1200; item 1 is not under 900")
    local keys = { fired[1].key, fired[2].key }
    table.sort(keys)
    eq(keys[1], "1:3"); eq(keys[2], "2:2")
    eq(fired[1].text:find("700c", 1, true) ~= nil or fired[2].text:find("700c", 1, true) ~= nil, true, "says the price")
    Fake.uninstall()
end)

test("a limit exactly met counts, and an item with no price is never alerted", function()
    local S = setup()
    local E = S.AlertRules.Evaluate
    eq(#E({ { id = 1, kind = "below", item = 1, value = 1000 } }, {}, ctx(), {}, nameOf, money), 1, "at the limit")
    eq(#E({ { id = 1, kind = "below", item = 9, value = 5000 } }, {}, ctx({ priceOf = function() return nil end }), {}, nameOf, money), 0)
    Fake.uninstall()
end)

test("a condition fires once when it becomes true, not on every check, and again after it has cleared", function()
    local S = setup()
    local E = S.AlertRules.Evaluate
    local rules = { { id = 1, kind = "below", item = 3, value = 800 } }
    local active = {}
    eq(#E(rules, {}, ctx(), active, nameOf, money), 1, "first time")
    eq(#E(rules, {}, ctx(), active, nameOf, money), 0, "still true: quiet")
    eq(#E(rules, {}, ctx({ priceOf = function() return 900 end }), active, nameOf, money), 0, "no longer true")
    eq(#E(rules, {}, ctx(), active, nameOf, money), 1, "true again: fires again")
    Fake.uninstall()
end)

test("a move rule watches the direction asked for, and 'any' watches both", function()
    local S = setup()
    local E = S.AlertRules.Evaluate
    local function ids(rule)
        local out = {}
        for _, f in ipairs(E({ rule }, { 1, 2, 3 }, ctx(), {}, nameOf, money)) do out[#out + 1] = f.itemID end
        table.sort(out)
        return table.concat(out, ",")
    end
    eq(ids({ id = 1, kind = "move", value = 20, direction = "up" }), "2")
    eq(ids({ id = 1, kind = "move", value = 20, direction = "down" }), "3")
    eq(ids({ id = 1, kind = "move", value = 20 }), "2,3", "no direction: both")
    eq(ids({ id = 1, kind = "move", value = 50 }), "", "too small a move")
    eq(ids({ id = 1, kind = "move", item = 2, value = 20, direction = "up" }), "2", "one item only")
    Fake.uninstall()
end)

test("a move alert says which way and how far", function()
    local S = setup()
    local fired = S.AlertRules.Evaluate({ { id = 1, kind = "move", item = 3, value = 20 } }, {}, ctx(), {}, nameOf, money)
    eq(fired[1].text:find("fallen 30.0%%") ~= nil, true, fired[1].text)
    fired = S.AlertRules.Evaluate({ { id = 1, kind = "move", item = 2, value = 20 } }, {}, ctx(), {}, nameOf, money)
    eq(fired[1].text:find("risen 30.0%%") ~= nil, true, fired[1].text)
    Fake.uninstall()
end)

test("a stale rule warns when the newest prices are older than the limit, and when there are none", function()
    local S = setup()
    local E = S.AlertRules.Evaluate
    local rule = { id = 1, kind = "stale", value = 6 }
    eq(#E({ rule }, {}, ctx({ lastScan = NOON - 5 * HOUR }), {}, nameOf, money), 0, "5 hours: fine")
    local fired = E({ rule }, {}, ctx({ lastScan = NOON - 7 * HOUR }), {}, nameOf, money)
    eq(#fired, 1); eq(fired[1].itemID, nil, "about the data, not an item")
    eq(#E({ rule }, {}, ctx({ lastScan = false }), {}, nameOf, money), 1, "never scanned")
    Fake.uninstall()
end)

test("disabled and broken rules are skipped", function()
    local S = setup()
    local E = S.AlertRules.Evaluate
    eq(#E({ { id = 1, kind = "below", item = 3, value = 800, enabled = false } }, {}, ctx(), {}, nameOf, money), 0)
    eq(#E({ { id = 1, kind = "below", value = 800 } }, {}, ctx(), {}, nameOf, money), 0, "no item")
    Fake.uninstall()
end)

-- The service ---------------------------------------------------------------------------------------

--- A presenter that records what it was shown, under a name routing can reach.
local function recorder(S, name)
    local shown = {}
    if not S.Alerts.presenters:Get(name) then S.Alerts.presenters:Register(name, { show = function(a) shown[#shown + 1] = a end }) end
    return shown
end

local function silence(S)
    S.Alerts.State().routing = { alert = { "spy" }, warn = { "spy" }, info = { "spy" } }
    return recorder(S, "spy")
end

test("raising an alert shows it through the presenters its severity is routed to, and logs it", function()
    local S = setup()
    local spy = silence(S)
    local ok = S.Alerts.Raise({ key = "k", severity = "warn", title = "T", body = "B", itemID = 1 })
    eq(ok, true)
    eq(#spy, 1); eq(spy[1].title, "T")
    local log = S.Alerts.State().log
    eq(#log, 1); eq(log[1].title, "T"); eq(log[1].itemID, 1); eq(log[1].time, NOON)
    Fake.uninstall()
end)

test("the default routing puts alerts on chat, toast and sound, warnings on chat and toast, info on chat", function()
    local S = setup()
    eq(table.concat(S.Alerts.Routing("alert"), ","), "chat,toast,sound")
    eq(table.concat(S.Alerts.Routing("warn"), ","), "chat,toast")
    eq(table.concat(S.Alerts.Routing("info"), ","), "chat")
    eq(table.concat(S.Alerts.Routing("nonsense"), ","), "chat", "an unknown severity is treated as info")
    Fake.uninstall()
end)

test("the same alert is not repeated inside its cooldown, and is allowed again after it", function()
    local S = setup()
    local spy = silence(S)
    eq(S.Alerts.Raise({ key = "same", title = "x" }), true)
    local ok, why = S.Alerts.Raise({ key = "same", title = "x" })
    eq(ok, false); eq(why, "cooling down")
    eq(S.Alerts.Raise({ key = "other", title = "y" }), true, "a different key is separate")
    S.Clock.now = function() return NOON + 3601 end
    eq(S.Alerts.Raise({ key = "same", title = "x" }), true, "after the default hour")
    eq(S.Alerts.Raise({ key = "short", title = "z", cooldown = 60 }), true)
    S.Clock.now = function() return NOON + 3601 + 61 end
    eq(S.Alerts.Raise({ key = "short", title = "z", cooldown = 60 }), true, "a rule's own cooldown")
    eq(#spy, 5)
    Fake.uninstall()
end)

test("snoozing silences everything until it ends, and nothing is shown or logged meanwhile", function()
    local S = setup()
    local spy = silence(S)
    S.Alerts.Snooze(600)
    eq(S.Alerts.SnoozedFor(), 600)
    local ok, why = S.Alerts.Raise({ key = "a", title = "x" })
    eq(ok, false); eq(why, "snoozed")
    eq(#spy, 0); eq(#S.Alerts.State().log, 0)
    S.Clock.now = function() return NOON + 601 end
    eq(S.Alerts.SnoozedFor(), 0)
    eq(S.Alerts.Raise({ key = "a", title = "x" }), true, "over")
    S.Alerts.Snooze(600); S.Alerts.Snooze(0)
    eq(S.Alerts.SnoozedFor(), 0, "snooze off")
    Fake.uninstall()
end)

test("the log keeps the last fifty", function()
    local S = setup()
    silence(S)
    for i = 1, 60 do S.Alerts.Raise({ title = "n" .. i }) end
    local log = S.Alerts.State().log
    eq(#log, 50); eq(log[1].title, "n11"); eq(log[50].title, "n60")
    Fake.uninstall()
end)

test("a presenter that fails does not stop the others or the alert", function()
    local S = setup()
    S.Alerts.presenters:Register("bad", { show = function() error("boom") end })
    local good = recorder(S, "good")
    S.Alerts.State().routing = { alert = { "bad", "good" } }
    local old = geterrorhandler
    geterrorhandler = function() return function() end end
    eq(S.Alerts.Raise({ title = "x" }), true)
    geterrorhandler = old
    eq(#good, 1)
    Fake.uninstall()
end)

test("raising fires ALERT_RAISED for anyone listening", function()
    local S = setup()
    silence(S)
    local seen
    S.Events:On("ALERT_RAISED", function(a) seen = a end)
    S.Alerts.Raise({ title = "heard", severity = "info" })
    eq(seen.title, "heard")
    Fake.uninstall()
end)

test("an unknown presenter name in the routing is ignored", function()
    local S = setup()
    S.Alerts.State().routing = { alert = { "nonexistent" } }
    eq(S.Alerts.Raise({ title = "x" }), true)
    Fake.uninstall()
end)

-- Rules in the service, and checking after a scan ------------------------------------------------------

test("rules are added with an id, validated, removed, and kept in the saved settings", function()
    local S = setup()
    local id = S.Alerts.AddRule({ kind = "below", item = 3, value = 800 })
    eq(id, 1); eq(S.settings.alerts.rules[1].id, 1)
    eq(S.Alerts.AddRule({ kind = "above", item = 2, value = 900 }), 2)
    local none, why = S.Alerts.AddRule({ kind = "below", value = 5 })
    eq(none, nil); eq(why, "needs an item")
    eq(S.Alerts.Describe(S.Alerts.FindRule(1)), "Silk Cloth below 8s")
    eq(S.Alerts.RemoveRule(1), true); eq(S.Alerts.RemoveRule(1), false)
    eq(#S.settings.alerts.rules, 1)
    eq(S.Alerts.AddRule({ kind = "stale", value = 3 }), 3, "ids are never reused")
    Fake.uninstall()
end)

test("a scan completing checks the rules and raises what has just become true", function()
    local S = setup()
    local spy = silence(S)
    S.Alerts.AddRule({ kind = "below", item = 3, value = 800 })
    S.Alerts.AddRule({ kind = "move", value = 10, direction = "up" })
    S.Events:Fire("SCAN_COMPLETE", 3, NOON)
    eq(#spy, 2, "silk is under 800 and wool rose more than 10% over the day")
    local titles = { spy[1].title, spy[2].title }
    table.sort(titles)
    eq(titles[1], "Silk Cloth"); eq(titles[2], "Wool Cloth")
    S.Events:Fire("SCAN_COMPLETE", 3, NOON)
    eq(#spy, 2, "the next scan finds the same state and says nothing more")
    Fake.uninstall()
end)

test("with no rules a scan does nothing", function()
    local S = setup()
    local spy = silence(S)
    S.Events:Fire("SCAN_COMPLETE", 3, NOON)
    eq(#spy, 0)
    Fake.uninstall()
end)

test("removing a rule forgets that it was true, so a new rule can fire at once", function()
    local S = setup()
    local spy = silence(S)
    local id = S.Alerts.AddRule({ kind = "below", item = 3, value = 800, cooldown = 1 })
    S.Alerts.Check()
    eq(#spy, 1)
    S.Alerts.RemoveRule(id)
    S.Clock.now = function() return NOON + 10 end
    S.Alerts.AddRule({ kind = "below", item = 3, value = 800, cooldown = 1 })
    S.Alerts.Check()
    eq(#spy, 2)
    Fake.uninstall()
end)

test("a stale rule raises a warning, not an alert", function()
    local S = setup()
    local spy = silence(S)
    S.db.scan.last = NOON - 10 * HOUR
    S.Alerts.AddRule({ kind = "stale", value = 6, severity = "warn" })
    S.Alerts.Check()
    eq(spy[1].severity, "warn"); eq(spy[1].title, "Prices are out of date")
    Fake.uninstall()
end)

-- Commands ------------------------------------------------------------------------------------------

test("/stockist alert below and above add rules, by item ID or by part of a name", function()
    local S, out = setup()
    S.Commands:Dispatch("alert below 3 8s")
    eq(S.settings.alerts.rules[1].kind, "below"); eq(S.settings.alerts.rules[1].item, 3); eq(S.settings.alerts.rules[1].value, 800)
    eq(out[#out], "alert 1 added: Silk Cloth below 8s.")
    S.Commands:Dispatch("alert above wool 15s")
    eq(S.settings.alerts.rules[2].item, 2, "found by name"); eq(S.settings.alerts.rules[2].value, 1500)
    S.Commands:Dispatch("alert below cloth 1s")
    eq(out[#out]:find("3 items match 'cloth'", 1, true) ~= nil, true, out[#out])
    eq(#S.settings.alerts.rules, 2, "an ambiguous name adds nothing")
    S.Commands:Dispatch("alert below zzz 1s")
    eq(out[#out]:find("no item with prices matches 'zzz'", 1, true) ~= nil, true)
    S.Commands:Dispatch("alert below 3 5")
    eq(out[#out]:find("needs its coins", 1, true) ~= nil, true, "a bare number is refused")
    eq(#S.settings.alerts.rules, 2)
    Fake.uninstall()
end)

test("/stockist alert move takes an item or 'all', a percentage and an optional direction", function()
    local S, out = setup()
    S.Commands:Dispatch("alert move all 10 up")
    local r = S.settings.alerts.rules[1]
    eq(r.kind, "move"); eq(r.item, nil); eq(r.value, 10); eq(r.direction, "up")
    S.Commands:Dispatch("alert move wool cloth 5")
    r = S.settings.alerts.rules[2]
    eq(r.item, 2); eq(r.value, 5); eq(r.direction, "any")
    S.Commands:Dispatch("alert move 3 12 down")
    eq(S.settings.alerts.rules[3].direction, "down")
    S.Commands:Dispatch("alert move all lots")
    eq(#S.settings.alerts.rules, 3, "a nonsense percentage adds nothing")
    Fake.uninstall()
end)

test("/stockist alert stale adds a warning rule", function()
    local S = setup()
    S.Commands:Dispatch("alert stale 8")
    local r = S.settings.alerts.rules[1]
    eq(r.kind, "stale"); eq(r.value, 8); eq(r.severity, "warn")
    Fake.uninstall()
end)

test("/stockist alert list, off, on and remove manage the rules", function()
    local S, out = setup()
    S.Commands:Dispatch("alert list")
    eq(out[#out]:find("no alerts yet", 1, true) ~= nil, true)
    S.Commands:Dispatch("alert below 3 8s")
    S.Commands:Dispatch("alert above 2 15s")
    S.Commands:Dispatch("alert list")
    eq(out[#out - 1]:find("1: Silk Cloth below 8s", 1, true) ~= nil, true, out[#out - 1])
    eq(out[#out]:find("2: Wool Cloth above 15s", 1, true) ~= nil, true)
    S.Commands:Dispatch("alert off 1")
    eq(S.settings.alerts.rules[1].enabled, false)
    S.Commands:Dispatch("alert list")
    eq(out[#out - 1]:find("(off)", 1, true) ~= nil, true)
    S.Commands:Dispatch("alert on 1")
    eq(S.settings.alerts.rules[1].enabled, true)
    S.Commands:Dispatch("alert remove 1")
    eq(#S.settings.alerts.rules, 1)
    S.Commands:Dispatch("alert remove 99")
    eq(out[#out]:find("no alert with that number", 1, true) ~= nil, true)
    Fake.uninstall()
end)

test("/stockist alert snooze silences alerts and can be ended", function()
    local S, out = setup()
    S.Commands:Dispatch("alert snooze 30")
    eq(S.Alerts.SnoozedFor(), 1800)
    eq(out[#out], "alerts snoozed for 30 minutes.")
    S.Commands:Dispatch("alert list")
    eq(out[#out]:find("snoozed", 1, true) ~= nil, true)
    S.Commands:Dispatch("alert snooze off")
    eq(S.Alerts.SnoozedFor(), 0)
    S.Commands:Dispatch("alert snooze soon")
    eq(out[#out]:find("usage: /stockist alert snooze", 1, true) ~= nil, true)
    Fake.uninstall()
end)

test("/stockist alert test shows a sample alert, and says if snoozed", function()
    local S, out = setup()
    local spy = silence(S)
    S.Commands:Dispatch("alert test")
    eq(spy[1].title, "Test alert")
    S.Alerts.Snooze(60)
    S.Commands:Dispatch("alert test")
    eq(out[#out], "not shown: snoozed")
    Fake.uninstall()
end)

test("/stockist alert with nothing or something odd prints how to use it", function()
    local S, out = setup()
    S.Commands:Dispatch("alert sideways")
    eq(out[1], "alerts:")
    eq(#out > 4, true)
    Fake.uninstall()
end)

test("the chat presenter writes the alert in the severity colour", function()
    local S, out = setup()
    S.Alerts.State().routing = { alert = { "chat" } }
    S.Alerts.Raise({ severity = "alert", title = "Wool Cloth", body = "is up" })
    eq(out[#out]:find("Alert: Wool Cloth", 1, true) ~= nil, true)
    eq(out[#out]:find("is up", 1, true) ~= nil, true)
    eq(out[#out]:find("|cffffd100", 1, true) ~= nil, true, "gold for an alert")
    Fake.uninstall()
end)

-- Toasts --------------------------------------------------------------------------------------------

test("a toast shows the title and body, newest on top, at most three at a time", function()
    local S = setup()
    local T = S.AlertToasts
    local first = T.Show({ severity = "alert", title = "one", body = "b1", itemID = 1 })
    eq(first.title.text, "one"); eq(first.body.text, "b1"); eq(first.frame.shown, true)
    T.Show({ title = "two" }); T.Show({ title = "three" })
    eq(#T.active, 3)
    eq(T.active[1].title.text, "three", "newest first")
    T.Show({ title = "four" })
    eq(#T.active, 3, "a fourth pushes the oldest off")
    eq(first.frame.shown, false)
    local y1 = T.active[1].frame.points[#T.active[1].frame.points][5]
    local y2 = T.active[2].frame.points[#T.active[2].frame.points][5]
    eq(y2 < y1, true, "stacked downwards")
    Fake.uninstall()
end)

test("a toast goes away by itself, and a reused frame is not dismissed by its old timer", function()
    local S = setup()
    local T = S.AlertToasts
    local t = T.Show({ title = "a" })
    Fake.flush()
    eq(t.frame.shown, false, "gone after its time")
    eq(#T.active, 0)
    local again = T.Show({ title = "b" })
    eq(again, t, "the frame was reused")
    T.Show({ title = "c" }); -- reuses nothing; two on screen
    eq(#T.active, 2)
    Fake.uninstall()
end)

test("clicking a toast shows its item in the chart and opens the workspace; right-click only dismisses it", function()
    local S = setup()
    local T = S.AlertToasts
    local chart = S.ChartPanel.Create(UIParent, { link = "A" })
    local t = T.Show({ title = "x", itemID = 2 })
    Fake.fire(t.frame, "OnClick", "RightButton")
    eq(t.frame.shown, false); eq(S.Link.Get("A"), nil, "right-click only dismisses")
    local u = T.Show({ title = "y", itemID = 2 })
    Fake.fire(u.frame, "OnClick", "LeftButton")
    eq(S.Link.Get("A"), 2); eq(chart:GetItem(), 2)
    eq(S.Workspace.IsShown(), true, "the workspace opened")
    eq(u.frame.shown, false)
    Fake.uninstall()
end)

test("a toast with no item just goes away when clicked", function()
    local S = setup()
    local t = S.AlertToasts.Show({ title = "system" })
    Fake.fire(t.frame, "OnClick", "LeftButton")
    eq(t.frame.shown, false); eq(S.Link.Get("A"), nil)
    Fake.uninstall()
end)
