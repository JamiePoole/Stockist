local ADDON_NAME, Stockist = ...

-- Chat-based interface for this early phase. The windowed UI replaces it later; the commands stay
-- as shortcuts. Output goes through Stockist.Print so it can be redirected.
local Format = Stockist.Format

local function say(msg) print("|cff33ff99Stockist|r " .. msg) end
Stockist.Print = say

local function itemName(id)
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if not name and GetItemInfo then name = GetItemInfo(id) end
    return name or ("item:" .. id)
end

local function parseItemID(text)
    return tonumber(text) or tonumber((text or ""):match("item:(%d+)"))
end
Stockist.ItemName = itemName
Stockist.ParseItemID = parseItemID

-- With no argument, chart the item we hold the most history for.
local function richestItem()
    local best, bestCount = nil, -1
    for _, id in ipairs(Stockist.store:Items()) do
        local count = #Stockist.store:GetCandles(id, "hourly")
        if count > bestCount then best, bestCount = id, count end
    end
    return best
end

local function chart(arg)
    local id = arg ~= "" and parseItemID(arg) or richestItem()
    if not id then return say("no data yet. Open the Auction House to take a reading, or give an item ID.") end
    Stockist.PriceChart.Show(id)
end

local function status()
    local store = Stockist.store
    local last = Stockist.db.scan.last
    say(("market '%s': tracking %d items."):format(Stockist.marketKey, #store:Items()))
    if last then
        say(("last scan %s, recorded %d items."):format(
            Format.Age(Stockist.Clock.now() - last), Stockist.db.scan.items or 0))
    else
        say("no scan yet. Open the Auction House to take the first reading.")
    end
    local wait = Stockist.Scanner:SecondsUntilNextScan()
    if wait > 0 then say(("next scan in %dm."):format(math.ceil(wait / 60))) end
end

local function item(arg)
    local id = parseItemID(arg)
    local last = id and Stockist.store:Latest(id)
    if not id then return say("usage: /stockist item <itemID or link>") end
    if not last then return say(itemName(id) .. ": no data yet.") end
    local now = Stockist.Clock.now()
    local line = ("%s: %s (low %s, %d listed, %s)"):format(
        itemName(id), Format.Money(last.price), Format.Money(last.min), last.qty,
        Format.Age(now - last.ts))
    local pct = Stockist.store:Change(id, 86400, now)
    if pct then line = line .. "  24h " .. Format.Percent(pct) end
    say(line)
end

local function movers()
    local now = Stockist.Clock.now()
    local rows = {}
    for _, id in ipairs(Stockist.store:Items()) do
        local pct = Stockist.store:Change(id, 86400, now)
        if pct then rows[#rows + 1] = { id = id, pct = pct } end
    end
    if #rows == 0 then return say("no 24h changes yet: needs readings at least a day apart.") end
    table.sort(rows, function(a, b) return a.pct > b.pct end)
    say("top risers (24h):")
    for i = 1, math.min(5, #rows) do
        say(("  %s %s"):format(Format.Percent(rows[i].pct), itemName(rows[i].id)))
    end
    say("top fallers (24h):")
    for i = #rows, math.max(1, #rows - 4), -1 do
        say(("  %s %s"):format(Format.Percent(rows[i].pct), itemName(rows[i].id)))
    end
end

-- Diagnostic: prints every clock the game exposes so time labels can be checked against a wall clock.
local function timeinfo()
    local server = GetServerTime()
    local function fmt(f, t) return date(f, t) end
    say("--- time diagnostic (compare with your computer's clock) ---")
    say(("GetServerTime() = %d  (should be about %d)"):format(server, os and os.time and os.time() or server))
    say("date('%H:%M:%S')            local now   : " .. fmt("%H:%M:%S"))
    say("date('%H:%M:%S', server)    local format: " .. fmt("%H:%M:%S", server))
    say("date('!%H:%M:%S', server)   UTC format  : " .. fmt("!%H:%M:%S", server))
    say(("time() = %d  (time() - GetServerTime() = %d s)"):format(time(), time() - server))
    say(("tzOffset used for chart ticks = %d s"):format(Stockist.Clock.tzOffset()))
    if GetGameTime then
        local h, m = GetGameTime()
        say(("realm time (GetGameTime) = %02d:%02d"):format(h, m))
    end
    local last = Stockist.db.scan.last
    if last then
        say(("last scan: %d -> date() says %s (%s)"):format(last, fmt("%Y-%m-%d %H:%M:%S", last),
            Format.Age(server - last)))
    end
    local id = richestItem()
    if id then
        local ticks = Stockist.store:Ticks(id)
        say(("item %d: %d recorded scans%s"):format(id, #ticks, #ticks > 0 and
            (", first " .. fmt("%H:%M:%S", ticks[1].x) .. ", last " .. fmt("%H:%M:%S", ticks[#ticks].x)) or ""))
        local hourly = Stockist.store:GetCandles(id, "hourly")
        for i = math.max(1, #hourly - 3), #hourly do
            say(("  hourly candle t=%d -> %s"):format(hourly[i].t, fmt("%Y-%m-%d %H:%M", hourly[i].t)))
        end
    end
end

local commands = {
    status = status,
    time = timeinfo,
    scan = function()
        local ok, reason = Stockist.Scanner:Start()
        if not ok then say("can't scan: " .. reason) end
    end,
    item = item,
    movers = movers,
    chart = chart,
    auto = function(arg)
        arg = arg:lower()
        if arg == "on" then
            Stockist.settings.autoScan = true
        elseif arg == "off" then
            Stockist.settings.autoScan = false
        elseif arg ~= "" then
            return say("usage: /stockist auto [on|off]")
        end
        say("auto-scan is " .. (Stockist.Scanner:AutoEnabled() and "on" or "off")
            .. " (scans when the Auction House opens and every 15 minutes while it stays open).")
    end,
}

SLASH_STOCKIST1 = "/stockist"
SLASH_STOCKIST2 = "/stk"
SlashCmdList["STOCKIST"] = function(input)
    if not Stockist.store then return say("not ready yet.") end
    local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "" then cmd = "status" end
    local fn = commands[cmd:lower()]
    if fn then
        fn(rest)
    else
        say("commands: status, scan, item <id>, chart [id], movers, auto [on|off], time")
    end
end

-- Report scan outcomes.
Stockist.Events:On("SCAN_COMPLETE", function(count)
    say(("scan complete: %d items recorded."):format(count))
end)
Stockist.Events:On("SCAN_FAILED", function(reason)
    say("scan failed: " .. tostring(reason))
end)
Stockist.Events:On("SCAN_SKIPPED", function(reason)
    say("scan skipped: " .. tostring(reason))
end)
