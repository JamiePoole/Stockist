local ADDON_NAME, Stockist = ...

-- The alert service: the one place alerts are raised, de-duplicated, snoozed, recorded and shown. Rules say what
-- the player wants to hear about (Data/AlertRules.lua); this turns a rule that has just become true into an
-- alert, and presenters (chat, toast, sound; more can register) show it. Warnings about the addon's own state
-- use the same path, so there is one place to snooze and one place that explains what happened.
--   Alerts.Raise({ key = "...", severity = "alert", title = "...", body = "...", itemID = 2589 })
--   Alerts.presenters:Register("flash", { show = function(alert) ... end })
local Format = Stockist.Format
local AlertRules = Stockist.AlertRules

local Alerts = {}
Stockist.Alerts = Alerts
Alerts.presenters = Stockist.NewRegistry("alert presenter")

local LOG_SIZE = 50

-- Which presenters show an alert of each severity. The log records every one, whatever the routing.
Alerts.DEFAULT_ROUTING = {
    alert = { "chat", "toast", "sound" },
    warn = { "chat", "toast" },
    info = { "chat" },
}

---------------------------------------------------------------------------------------------------
-- State (saved with the account's settings)
---------------------------------------------------------------------------------------------------

--- The saved alert state: { rules, nextId, lastFired = { key = time }, snoozedUntil, log, routing }.
function Alerts.State()
    local settings = Stockist.settings
    if not settings then return { rules = {}, nextId = 1, lastFired = {}, snoozedUntil = 0, log = {} } end
    local s = settings.alerts
    if not s then
        s = { rules = {}, nextId = 1, lastFired = {}, snoozedUntil = 0, log = {} }
        settings.alerts = s
    end
    s.rules, s.lastFired, s.log = s.rules or {}, s.lastFired or {}, s.log or {}
    s.nextId, s.snoozedUntil = s.nextId or 1, s.snoozedUntil or 0
    return s
end

local active = {} -- conditions that are true right now (session only: after a reload they may fire once more)

local function now() return Stockist.Clock.now() end

---------------------------------------------------------------------------------------------------
-- Snooze and routing
---------------------------------------------------------------------------------------------------

--- Silence every alert for `seconds` (nil or 0 to end a snooze). Alerts that would have fired are not shown later.
function Alerts.Snooze(seconds)
    local s = Alerts.State()
    s.snoozedUntil = (seconds and seconds > 0) and (now() + seconds) or 0
end

function Alerts.SnoozedFor()
    return math.max(0, Alerts.State().snoozedUntil - now())
end

--- The presenters that show an alert of this severity.
function Alerts.Routing(severity)
    local custom = Alerts.State().routing
    return (custom and custom[severity]) or Alerts.DEFAULT_ROUTING[severity] or Alerts.DEFAULT_ROUTING.info
end

---------------------------------------------------------------------------------------------------
-- Raising
---------------------------------------------------------------------------------------------------

--- Raise an alert. `alert`: { key (for de-duplication), severity, title, body, itemID?, cooldown? }.
--- Returns true if it was shown, or false and why ("snoozed" or "cooling down").
function Alerts.Raise(alert)
    local s = Alerts.State()
    local t = now()
    if s.snoozedUntil > t then return false, "snoozed" end
    local cooldown = alert.cooldown or AlertRules.DEFAULT_COOLDOWN
    local last = alert.key and s.lastFired[alert.key]
    if last and t - last < cooldown then return false, "cooling down" end
    if alert.key then s.lastFired[alert.key] = t end

    alert.severity = alert.severity or "alert"
    alert.time = t
    s.log[#s.log + 1] = {
        time = t, severity = alert.severity, title = alert.title, body = alert.body, itemID = alert.itemID, key = alert.key,
    }
    while #s.log > LOG_SIZE do table.remove(s.log, 1) end

    for _, name in ipairs(Alerts.Routing(alert.severity)) do
        local presenter = Alerts.presenters:Get(name)
        if presenter then
            local ok, err = pcall(presenter.show, alert)
            if not ok and geterrorhandler then geterrorhandler()(err) end
        end
    end
    Stockist.Events:Fire("ALERT_RAISED", alert)
    return true
end

---------------------------------------------------------------------------------------------------
-- Rules
---------------------------------------------------------------------------------------------------

local function nameOf(id)
    return Stockist.ItemInfo and Stockist.ItemInfo.Name(id) or ("item:" .. id)
end

--- Add a rule; returns its id, or nil and the reason. Missing fields get their defaults.
function Alerts.AddRule(rule)
    rule.severity = rule.severity or "alert"
    rule.enabled = rule.enabled ~= false
    local ok, reason = AlertRules.Validate(rule)
    if not ok then return nil, reason end
    local s = Alerts.State()
    rule.id = s.nextId
    s.nextId = s.nextId + 1
    s.rules[#s.rules + 1] = rule
    return rule.id
end

--- Remove a rule by id; true if it existed.
function Alerts.RemoveRule(id)
    local s = Alerts.State()
    for i, rule in ipairs(s.rules) do
        if rule.id == id then
            table.remove(s.rules, i)
            for key in pairs(active) do if key:find("^" .. id .. ":") then active[key] = nil end end
            return true
        end
    end
    return false
end

function Alerts.FindRule(id)
    for _, rule in ipairs(Alerts.State().rules) do if rule.id == id then return rule end end
end

function Alerts.Describe(rule)
    return AlertRules.Describe(rule, nameOf, Format.Money)
end

--- Test every rule against the latest prices and raise what has just become true. Called after each scan, and
--- by hand with `now` overridden in tests. Returns the number of alerts shown.
function Alerts.Check()
    local s = Alerts.State()
    if #s.rules == 0 or not Stockist.store then return 0 end
    local ctx = {
        now = now(),
        lastScan = Stockist.db and Stockist.db.scan and Stockist.db.scan.last or nil,
        priceOf = function(id)
            local last = Stockist.store:Latest(id)
            return last and last.price or nil
        end,
        moveOf = function(id)
            return (Stockist.Ticker.Move(Stockist.store, id, now()))
        end,
    }
    local tracked = Stockist.tracked and Stockist.tracked:List() or {}
    local fired = AlertRules.Evaluate(s.rules, tracked, ctx, active, nameOf, Format.Money)
    local shown = 0
    for _, f in ipairs(fired) do
        local title = f.rule.kind == "stale" and "Prices are out of date" or nameOf(f.itemID)
        local ok = Alerts.Raise({
            key = f.key, severity = f.rule.severity, title = title, body = f.text, itemID = f.itemID,
            cooldown = f.rule.cooldown,
        })
        if ok then shown = shown + 1 end
    end
    return shown
end

Stockist.Events:On("SCAN_COMPLETE", function() Alerts.Check() end, Alerts)

---------------------------------------------------------------------------------------------------
-- Presenters
---------------------------------------------------------------------------------------------------

local SEVERITY_COLOUR = { alert = { 1, 0.82, 0 }, warn = { 1, 0.6, 0.2 }, info = { 0.6, 0.8, 1 } }

Alerts.presenters:Register("chat", {
    show = function(alert)
        local c = SEVERITY_COLOUR[alert.severity] or SEVERITY_COLOUR.info
        Stockist.Print(Format.Colored("Alert: " .. (alert.title or ""), c[1], c[2], c[3]) .. " " .. (alert.body or ""))
    end,
})

Alerts.presenters:Register("sound", {
    show = function(alert)
        local kit = _G.SOUNDKIT and (_G.SOUNDKIT.TELL_MESSAGE or _G.SOUNDKIT.RAID_WARNING)
        if kit and _G.PlaySound then pcall(_G.PlaySound, kit) end
    end,
})

---------------------------------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------------------------------

local function say(msg) Stockist.Print(msg) end

--- An item from text: an ID or link, or part of a name among the items we hold. Returns the ID, or nil after
--- saying what was wrong.
local function resolveItem(text)
    local id = Stockist.ParseItemID(text)
    if id then return id end
    if text == "" then say("which item? Give an item ID, a link or part of its name.") return nil end
    local found = Stockist.ItemPicker.Search(Stockist.ItemPicker.Source(), text)
    if #found == 1 then return found[1].id end
    if #found == 0 then say(("no item with prices matches '%s'. Give an ID or a link instead."):format(text)) return nil end
    local names = {}
    for i = 1, math.min(4, #found) do names[i] = ("%s (%d)"):format(found[i].name, found[i].id) end
    say(("%d items match '%s': %s. Be more specific, or use an ID."):format(#found, text, table.concat(names, ", ")))
    return nil
end

local USAGE = {
    "alert below <item> <price>      e.g. alert below linen 5s",
    "alert above <item> <price>",
    "alert move <item|all> <percent> [up|down]     e.g. alert move all 10 up",
    "alert stale <hours>             warn when the prices get old",
    "alert list | remove <id> | off <id> | on <id> | snooze <minutes|off> | test",
}

local function printUsage()
    say("alerts:")
    for _, line in ipairs(USAGE) do say("  /stockist " .. line) end
end

local function added(id, reason)
    if not id then return say("could not add that alert: " .. tostring(reason)) end
    say(("alert %d added: %s."):format(id, Alerts.Describe(Alerts.FindRule(id))))
end

local function priceRule(kind, rest)
    local itemText, priceText = rest:match("^(.-)%s+(%S+)$")
    if not itemText then return printUsage() end
    local price = Format.ParseMoney(priceText)
    if not price then return say("a price needs its coins, like 5s, 1g20s or 250c (not just a number).") end
    local id = resolveItem(itemText)
    if not id then return end
    added(Alerts.AddRule({ kind = kind, item = id, value = price }))
end

local function moveRule(rest)
    local words = {}
    for word in rest:gmatch("%S+") do words[#words + 1] = word end
    local direction = "any"
    if #words >= 3 and (words[#words] == "up" or words[#words] == "down") then direction = table.remove(words) end
    local percent = tonumber(table.remove(words) or "")
    if not percent then return printUsage() end
    local itemText = table.concat(words, " ")
    local id
    if itemText:lower() ~= "all" then
        id = resolveItem(itemText)
        if not id then return end
    end
    added(Alerts.AddRule({ kind = "move", item = id, value = percent, direction = direction }))
end

local function list()
    local s = Alerts.State()
    if #s.rules == 0 then say("no alerts yet. Try: /stockist alert below <item> <price>") end
    for _, rule in ipairs(s.rules) do
        say(("  %d: %s%s"):format(rule.id, Alerts.Describe(rule), rule.enabled == false and " (off)" or ""))
    end
    local snooze = Alerts.SnoozedFor()
    if snooze > 0 then say(("alerts are snoozed for another %s."):format(Format.Span(snooze))) end
end

local function alert(arg)
    local sub, rest = arg:match("^(%S*)%s*(.-)$")
    sub = sub:lower()
    if sub == "below" or sub == "above" then return priceRule(sub, rest) end
    if sub == "move" then return moveRule(rest) end
    if sub == "stale" then
        local hours = tonumber(rest)
        if not hours then return printUsage() end
        return added(Alerts.AddRule({ kind = "stale", value = hours, severity = "warn", cooldown = 6 * 3600 }))
    end
    if sub == "list" or sub == "" then return list() end
    if sub == "remove" or sub == "off" or sub == "on" then
        local id = tonumber(rest)
        local rule = id and Alerts.FindRule(id)
        if not rule then return say("no alert with that number. See /stockist alert list.") end
        if sub == "remove" then
            Alerts.RemoveRule(id)
            return say("alert " .. id .. " removed.")
        end
        rule.enabled = sub == "on"
        return say(("alert %d is %s."):format(id, sub))
    end
    if sub == "snooze" then
        if rest == "off" or rest == "0" then
            Alerts.Snooze(0)
            return say("alerts are on again.")
        end
        local minutes = tonumber(rest)
        if not minutes or minutes <= 0 then return say("usage: /stockist alert snooze <minutes> (or off)") end
        Alerts.Snooze(minutes * 60)
        return say(("alerts snoozed for %d minutes."):format(minutes))
    end
    if sub == "test" then
        local ok, why = Alerts.Raise({ key = nil, severity = "alert", title = "Test alert",
            body = "This is how an alert looks and sounds." })
        if not ok then say("not shown: " .. why) end
        return
    end
    printUsage()
end

Stockist.Commands:Register("alert", { help = "alert ...            price and move alerts (alert for usage)", run = alert })
