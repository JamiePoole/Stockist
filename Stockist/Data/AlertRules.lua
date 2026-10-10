local ADDON_NAME, Stockist = ...

-- Alert rules: what the player wants to be told about, and the pure test of whether it is true right now.
-- A rule is plain saved data:
--   { id, kind, item = itemID or nil, value, direction, severity = "alert" | "warn" | "info", enabled, cooldown }
-- Kinds:
--   below   the item's price is at or under `value` copper
--   above   the item's price is at or over `value` copper
--   move    the item's move (24h, or as far back as we hold, see Ticker.Move) is at least `value` percent,
--           `direction` "up", "down" or "any"; with no item it watches every tracked item
--   stale   our newest prices are older than `value` hours (a warning about the data, not about an item)
-- Nothing here touches the game or the saved variables: the caller passes in what it knows.
local AlertRules = {}
Stockist.AlertRules = AlertRules

AlertRules.KINDS = { "below", "above", "move", "stale" }
AlertRules.SEVERITIES = { "info", "warn", "alert" }
AlertRules.DEFAULT_COOLDOWN = 3600 -- seconds before the same rule may fire again for the same item

local function oneOf(list, value)
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end

--- Is this a usable rule? Returns true, or false and the reason.
function AlertRules.Validate(rule)
    if type(rule) ~= "table" then return false, "not a rule" end
    if not oneOf(AlertRules.KINDS, rule.kind) then return false, "unknown kind '" .. tostring(rule.kind) .. "'" end
    if type(rule.value) ~= "number" or rule.value <= 0 then return false, "needs a number above zero" end
    if (rule.kind == "below" or rule.kind == "above") and type(rule.item) ~= "number" then
        return false, "needs an item"
    end
    if rule.kind == "move" then
        if not oneOf({ "up", "down", "any" }, rule.direction or "any") then return false, "direction is up, down or any" end
    end
    if rule.severity ~= nil and not oneOf(AlertRules.SEVERITIES, rule.severity) then
        return false, "severity is info, warn or alert"
    end
    return true
end

--- A rule in plain words: "Linen Cloth below 5s", "any tracked item up 10% or more".
--- `nameOf(itemID)` gives an item's name; `money(copper)` words an amount.
function AlertRules.Describe(rule, nameOf, money)
    local who = rule.item and nameOf(rule.item) or "any tracked item"
    if rule.kind == "below" then return ("%s below %s"):format(who, money(rule.value)) end
    if rule.kind == "above" then return ("%s above %s"):format(who, money(rule.value)) end
    if rule.kind == "move" then
        local dir = rule.direction or "any"
        local how = dir == "up" and "up" or (dir == "down" and "down" or "moves")
        return ("%s %s %s%% or more"):format(who, how, rule.value)
    end
    if rule.kind == "stale" then return ("prices older than %s hours"):format(rule.value) end
    return "unknown rule"
end

--- Whether one rule is true for one item right now.
---   ctx = { now, lastScan, priceOf(itemID) -> copper or nil, moveOf(itemID) -> percent or nil }
--- Returns true plus a plain sentence about it, or false.
local function holds(rule, itemID, ctx, nameOf, money)
    if rule.kind == "below" or rule.kind == "above" then
        local price = ctx.priceOf(itemID)
        if not price then return false end
        if rule.kind == "below" and price <= rule.value then
            return true, ("%s is down to %s (your limit: %s)"):format(nameOf(itemID), money(price), money(rule.value))
        end
        if rule.kind == "above" and price >= rule.value then
            return true, ("%s is up to %s (your limit: %s)"):format(nameOf(itemID), money(price), money(rule.value))
        end
        return false
    end
    if rule.kind == "move" then
        local move = ctx.moveOf(itemID)
        if not move then return false end
        local dir = rule.direction or "any"
        local hit = (dir ~= "down" and move >= rule.value) or (dir ~= "up" and move <= -rule.value)
        if hit then
            return true, ("%s has %s %.1f%% (you asked about %s%%)"):format(
                nameOf(itemID), move >= 0 and "risen" or "fallen", math.abs(move), rule.value)
        end
        return false
    end
    if rule.kind == "stale" then
        if not ctx.lastScan then return true, "no prices have been recorded yet" end
        local hours = (ctx.now - ctx.lastScan) / 3600
        if hours >= rule.value then
            return true, ("the prices are %.0f hours old (you asked about %s)"):format(hours, rule.value)
        end
    end
    return false
end

--- Test every enabled rule against the items it covers and return what has just become true.
---   rules    the saved rules
---   trackedIds   the items a rule with no item of its own covers
---   active   { [key] = true } of conditions that were already true at the last check; updated here, so a
---            condition fires once when it becomes true, and again only after it has stopped being true
--- Returns a list of { key, rule, itemID, text }.
function AlertRules.Evaluate(rules, trackedIds, ctx, active, nameOf, money)
    local fired = {}
    for _, rule in ipairs(rules) do
        if rule.enabled ~= false and AlertRules.Validate(rule) then
            local ids
            if rule.kind == "stale" then ids = { false }
            elseif rule.item then ids = { rule.item }
            else ids = trackedIds end
            for _, itemID in ipairs(ids) do
                local key = rule.id .. ":" .. tostring(itemID)
                local on, text = holds(rule, itemID or nil, ctx, nameOf, money)
                if on and not active[key] then
                    active[key] = true
                    fired[#fired + 1] = { key = key, rule = rule, itemID = itemID or nil, text = text }
                elseif not on then
                    active[key] = nil
                end
            end
        end
    end
    return fired
end
