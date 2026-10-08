-- /stkprobe craft : what recipe and reagent data can an addon read on this client?
-- Steps: run the command, then OPEN a profession window (it only exposes recipes while open), wait a
-- couple of seconds, then /reload. Results: StockistProbeDB.craft.

local function say(msg) print("|cff33ff99StockistProbe|r " .. msg) end

local function safe(fn, ...)
    local r = { pcall(fn, ...) }
    if not r[1] then return false, tostring(r[2]) end
    return true, unpack(r, 2)
end

local function str(v)
    local ok, s = pcall(tostring, v)
    return ok and s or "<unprintable>"
end

local MAINLINE = {
    "GetAllRecipeIDs", "GetRecipeInfo", "GetRecipeSchematic", "GetBaseProfessionInfo",
    "GetChildProfessionInfo", "IsTradeSkillReady", "GetRecipeItemLink", "GetRecipeNumItemsProduced",
}
local CLASSIC = {
    "GetNumTradeSkills", "GetTradeSkillInfo", "GetTradeSkillItemLink", "GetTradeSkillNumReagents",
    "GetTradeSkillReagentInfo", "GetTradeSkillReagentItemLink", "GetTradeSkillLine",
}
local EVENTS = { "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED" }

local rec
local armed = false
local pending = false

local function capturePrimary()
    local out = { api = "C_TradeSkillUI", samples = {} }
    local okIds, ids = safe(C_TradeSkillUI.GetAllRecipeIDs)
    local count = (okIds and type(ids) == "table") and #ids or 0
    out.recipeCount = okIds and count or ("ERROR " .. str(ids))
    for i = 1, math.min(5, count) do
        local id = ids[i]
        local s = { id = str(id), reagents = {} }
        local okI, info = safe(C_TradeSkillUI.GetRecipeInfo, id)
        if okI and type(info) == "table" then
            s.name, s.learned = str(info.name), str(info.learned)
        else
            s.infoError = str(info)
        end
        local okS, schematic = safe(C_TradeSkillUI.GetRecipeSchematic, id, false)
        if okS and type(schematic) == "table" then
            s.outputItemID = str(schematic.outputItemID)
            for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
                local r = slot.reagents and slot.reagents[1]
                s.reagents[#s.reagents + 1] = (r and str(r.itemID) or "?") .. " x" .. str(slot.quantityRequired)
            end
        else
            s.schematicError = str(schematic)
        end
        out.samples[#out.samples + 1] = s
    end
    return out
end

local function captureClassic()
    local out = { api = "classic globals", samples = {} }
    local okN, n = safe(GetNumTradeSkills)
    out.recipeCount = okN and n or ("ERROR " .. str(n))
    for i = 1, math.min(5, okN and tonumber(n) or 0) do
        local s = { index = i, reagents = {} }
        local ok1, name, kind = safe(GetTradeSkillInfo, i)
        s.name, s.kind = ok1 and str(name) or "ERROR", ok1 and str(kind) or ""
        local ok2, link = safe(GetTradeSkillItemLink, i)
        s.outputLink = ok2 and str(link) or "ERROR"
        local ok3, nr = safe(GetTradeSkillNumReagents, i)
        for r = 1, ok3 and tonumber(nr) or 0 do
            local ok4, rname, _, rcount = safe(GetTradeSkillReagentInfo, i, r)
            local ok5, rlink = safe(GetTradeSkillReagentItemLink, i, r)
            s.reagents[#s.reagents + 1] = (ok4 and str(rname) or "?") .. " x" .. (ok4 and str(rcount) or "?")
                .. " " .. (ok5 and str(rlink) or "")
        end
        out.samples[#out.samples + 1] = s
    end
    return out
end

local function capture(event)
    if not (armed and rec) then return end
    rec.eventsSeen[#rec.eventsSeen + 1] = event
    if pending then return end
    pending = true
    C_Timer.After(1.5, function()
        pending = false
        local capture1
        if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
            capture1 = capturePrimary()
        elseif GetNumTradeSkills then
            capture1 = captureClassic()
        else
            capture1 = { api = "none available" }
        end
        capture1.afterEvent = event
        rec.captures[#rec.captures + 1] = capture1
        say(("captured %s: %s recipes (after %s). /reload to save."):format(
            capture1.api, str(capture1.recipeCount), event))
    end)
end

local f = CreateFrame("Frame")
for _, e in ipairs(EVENTS) do pcall(f.RegisterEvent, f, e) end
f:SetScript("OnEvent", function(_, event) capture(event) end)

local function present(namespace, names)
    local have, missing = {}, {}
    for _, name in ipairs(names) do
        if namespace and type(namespace[name]) == "function" then have[#have + 1] = name else missing[#missing + 1] = name end
    end
    return have, missing
end

StockistProbeCommands = StockistProbeCommands or {}
StockistProbeCommands.craft = function()
    rec = { eventsSeen = {}, captures = {} }
    local have, missing = present(C_TradeSkillUI, MAINLINE)
    rec.namespace = C_TradeSkillUI and "present" or "ABSENT"
    rec.mainlinePresent, rec.mainlineMissing = have, missing
    local g = {}
    for _, name in ipairs(CLASSIC) do if type(_G[name]) == "function" then g[#g + 1] = name end end
    rec.classicGlobals = g
    if GetProfessions then
        local ok, a, b, c, d, e = safe(GetProfessions)
        rec.professions = ok and { str(a), str(b), str(c), str(d), str(e) } or ("ERROR " .. str(a))
    end
    StockistProbeDB = StockistProbeDB or {}
    StockistProbeDB.craft = rec
    armed = true
    say("C_TradeSkillUI: " .. rec.namespace .. "; present " .. #have .. "/" .. #MAINLINE .. "; classic globals " .. #g)
    say("now OPEN a profession window (any recipe list), wait a couple of seconds, then /reload.")
end
