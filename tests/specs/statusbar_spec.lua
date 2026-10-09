load_support("fake_wow")

local DAY, HOUR = 86400, 3600
local NOON = 40 * DAY + 12 * HOUR

local FILES = {
    "Core/Clock.lua", "Core/EventBus.lua", "Core/Registry.lua", "Core/Panels.lua", "Core/Link.lua",
    "Core/Format.lua", "Core/Calendar.lua", "Core/ItemInfo.lua", "Core/Help.lua", "Core/HelpTopics.lua",
    "Core/Commands.lua", "Data/Rollup.lua", "Data/Indicators.lua", "Data/ReadingStore.lua", "Data/Tracked.lua",
    "UI/Charts/Charts.lua", "UI/Charts/Util.lua", "UI/Charts/Scale.lua", "UI/Charts/Formatters.lua",
    "UI/Charts/Theme.lua", "UI/Charts/Series/Line.lua", "UI/Charts/Series/Candle.lua", "UI/Charts/Series/Bar.lua",
    "UI/Charts/Overlays/Overlays.lua", "UI/Charts/Core.lua", "UI/Charts/FrameCanvas.lua", "UI/Charts/ChartFrame.lua",
    "UI/Kit/Tooltip.lua", "UI/Kit/Button.lua", "UI/Kit/IconButton.lua", "UI/Kit/Guide.lua", "UI/Kit/Window.lua",
    "Features/PopOut.lua", "Features/PriceChart.lua", "Features/ItemPicker.lua", "Features/ChartPanel.lua",
    "Features/Watchlist.lua", "Features/Ticker.lua", "Features/Movers.lua", "Features/StatusBar.lua",
    "Features/Workspace.lua",
}

--- A scanner stand-in whose state the test sets: { wait, ahOpen, inProgress, auto }.
local function setup()
    Fake.install()
    local S = load_addon(unpack(FILES))
    S.settings = {}
    S.Clock.now = function() return NOON end
    S.db = { scan = { last = NOON - 12 * 60 } }
    S.store = S.ReadingStore.New(S.db)
    for id = 1, 3 do S.store:Add({ item = id, ts = NOON, price = 100, qty = 1 }) end
    S.tracked = S.Tracked.New({})
    S.tracked:Add(1)
    local scan = { wait = 0, ahOpen = false, inProgress = false, auto = true, started = 0, startResult = { true } }
    S.Scanner = {
        ahOpen = false, inProgress = false,
        SecondsUntilNextScan = function() return scan.wait end,
        AutoEnabled = function() return scan.auto end,
        Start = function() scan.started = scan.started + 1; return unpack(scan.startResult) end,
    }
    function scan.sync() S.Scanner.ahOpen, S.Scanner.inProgress = scan.ahOpen, scan.inProgress end
    local printed = {}
    S.Print = function(msg) printed[#printed + 1] = msg end
    return S, scan, printed
end

local function info(over)
    local base = { now = NOON, lastScan = NOON - 12 * 60, wait = 0, ahOpen = false, scanning = false, autoOn = true,
        items = 321, tracked = 6 }
    for k, v in pairs(over or {}) do base[k] = v end
    return base
end

local function texts(parts)
    local out = {}
    for i, p in ipairs(parts) do out[i] = p[1] end
    return out
end

-- Pure part -----------------------------------------------------------------------------------------

test("freshness: fresh within 30 minutes, stale within 3 hours, old after that, none without a scan", function()
    local S = setup()
    local F = S.StatusBar.Freshness
    eq(F(0), "fresh"); eq(F(30 * 60), "fresh", "the limit is fresh")
    eq(F(30 * 60 + 1), "stale"); eq(F(3 * 3600), "stale")
    eq(F(3 * 3600 + 1), "old")
    eq(F(nil), "none")
    Fake.uninstall()
end)

test("the age is worded and coloured by freshness", function()
    local S = setup()
    local function first(over) return S.StatusBar.Parts(info(over))[1] end
    local fresh = first({ lastScan = NOON - 600 })
    eq(fresh[1], "Prices updated 10m ago"); eq(fresh[2][2] > fresh[2][1], true, "green")
    local stale = first({ lastScan = NOON - 2 * HOUR })
    eq(stale[1], "Prices updated 2h ago"); eq(stale[2][1] > 0.9 and stale[2][2] > 0.6, true, "amber")
    local old = first({ lastScan = NOON - 2 * DAY })
    eq(old[1], "Prices updated 2d ago"); eq(old[2][1] > old[2][2], true, "red")
    local none = first({ lastScan = false })
    eq(none[1], "No prices yet")
    Fake.uninstall()
end)

test("the second piece says what the scanner is doing and when it can next", function()
    local S = setup()
    local function second(over) return S.StatusBar.Parts(info(over))[2][1] end
    eq(second({ scanning = true }), "scanning...")
    eq(second({ wait = 200 }), "next scan in 3:20")
    eq(second({ wait = 59.2 }), "next scan in 1:00", "rounded up so it never says 0:00 while waiting")
    eq(second({ wait = 3 * 3600 }), "next scan in 3h")
    eq(second({ wait = 0, ahOpen = true }), "ready to scan")
    eq(second({ wait = 0, ahOpen = false }), "scans when you open the Auction House")
    eq(second({ scanning = true, wait = 300 }), "scanning...", "a running scan outranks the countdown")
    local scanning = S.StatusBar.Parts(info({ scanning = true }))[2][2]
    eq(scanning[3] > scanning[2] and scanning[3] > scanning[1], true, "in progress is blue, not green: it may still fail")
    local ready = S.StatusBar.Parts(info({ ahOpen = true }))[2][2]
    eq(ready[2] > ready[1] and ready[2] > ready[3], true, "ready to scan stays green")
    Fake.uninstall()
end)

test("the item count mentions tracked items only when there are some, and auto-scan only when it is off", function()
    local S = setup()
    local t = texts(S.StatusBar.Parts(info()))
    eq(t[3], "321 items (6 tracked)")
    eq(#t, 3, "auto-scan on says nothing")
    t = texts(S.StatusBar.Parts(info({ tracked = 0, items = 1234 })))
    eq(t[3], "1,234 items", "thousands are separated, and no tracked count")
    t = texts(S.StatusBar.Parts(info({ autoOn = false })))
    eq(t[4], "auto-scan off")
    Fake.uninstall()
end)

test("the line joins the pieces with colour codes", function()
    local S = setup()
    local line = S.StatusBar.Line(S.StatusBar.Parts(info()))
    eq(line:find("Prices updated 12m ago", 1, true) ~= nil, true)
    eq(line:find("321 items", 1, true) ~= nil, true)
    eq(line:find("|cff", 1, true) ~= nil, true, "coloured")
    Fake.uninstall()
end)

test("Scan now is offered only when the Auction House is open and nothing blocks a scan", function()
    local S = setup()
    local can = S.StatusBar.CanScanNow
    eq(can(info({ ahOpen = true })), true)
    eq(can(info({ ahOpen = false })), false, "no Auction House")
    eq(can(info({ ahOpen = true, scanning = true })), false, "already scanning")
    eq(can(info({ ahOpen = true, wait = 120 })), false, "the server wait has not passed")
    Fake.uninstall()
end)

-- The panel -----------------------------------------------------------------------------------------

test("the panel shows the line and keeps it current as time passes and scans happen", function()
    local S = setup()
    local bar = S.StatusBar.Create(UIParent)
    eq(bar.text.text:find("Prices updated 12m ago", 1, true) ~= nil, true, bar.text.text)
    eq(bar.text.text:find("3 items (1 tracked)", 1, true) ~= nil, true, "this store holds three items, one tracked")

    S.Clock.now = function() return NOON + 600 end
    Fake.fire(bar.frame, "OnUpdate", 0.4)
    eq(bar.text.text:find("12m ago", 1, true) ~= nil, true, "not redrawn before a second has passed")
    Fake.fire(bar.frame, "OnUpdate", 0.7)
    eq(bar.text.text:find("22m ago", 1, true) ~= nil, true, "the age moves on by itself")

    S.db.scan.last = NOON + 600
    S.Events:Fire("SCAN_COMPLETE", 3, NOON + 600)
    eq(bar.text.text:find("just now", 1, true) ~= nil, true, "and resets after a scan")
    Fake.uninstall()
end)

test("the countdown ticks down and the scan button appears when a scan is allowed", function()
    local S, scan = setup()
    local bar = S.StatusBar.Create(UIParent)
    scan.wait = 125; scan.sync()
    Fake.fire(bar.frame, "OnUpdate", 1.1)
    eq(bar.text.text:find("next scan in 2:05", 1, true) ~= nil, true, bar.text.text)
    eq(bar.scanButton.shown, false, "no button while waiting")
    scan.wait = 0; scan.ahOpen = true; scan.sync()
    S.Events:Fire("AH_OPENED")
    eq(bar.text.text:find("ready to scan", 1, true) ~= nil, true)
    eq(bar.scanButton.shown, true, "ready: the button is offered")
    scan.inProgress = true; scan.sync()
    S.Events:Fire("SCAN_STARTED")
    eq(bar.text.text:find("scanning...", 1, true) ~= nil, true)
    eq(bar.scanButton.shown, false, "hidden again while scanning")
    scan.inProgress = false; scan.ahOpen = false; scan.sync()
    S.Events:Fire("AH_CLOSED")
    eq(bar.scanButton.shown, false)
    Fake.uninstall()
end)

test("pressing Scan now starts a scan, and says why in chat if the game refuses", function()
    local S, scan, printed = setup()
    local bar = S.StatusBar.Create(UIParent)
    scan.ahOpen = true; scan.sync(); S.Events:Fire("AH_OPENED")
    Fake.fire(bar.scanButton, "OnClick")
    eq(scan.started, 1)
    eq(#printed, 0)
    scan.startResult = { false, "next scan available in 14:00" }
    Fake.fire(bar.scanButton, "OnClick")
    eq(scan.started, 2)
    eq(printed[1], "can't scan: next scan available in 14:00")
    Fake.uninstall()
end)

test("the text is kept clear of the buttons, which hold the right edge", function()
    local S = setup()
    local bar = S.StatusBar.Create(UIParent, { popOut = true })
    local rightAnchor
    for _, pt in ipairs(bar.text.points) do if pt[1] == "RIGHT" then rightAnchor = pt end end
    eq(rightAnchor[2], bar.scanButton, "the line ends where the scan button starts")
    local btn
    for _, pt in ipairs(bar.scanButton.points) do if pt[1] == "RIGHT" then btn = pt end end
    eq(btn[2], bar.popOutButton, "and the scan button sits beside the pop-out button")
    Fake.uninstall()
end)

test("a hidden status bar catches up when shown", function()
    local S = setup()
    local bar = S.StatusBar.Create(UIParent)
    bar.frame.shown = false
    S.db.scan.last = NOON
    S.Events:Fire("SCAN_COMPLETE", 3, NOON)
    eq(bar.text.text:find("12m ago", 1, true) ~= nil, true, "not redrawn while hidden")
    bar.frame.shown = true
    Fake.fire(bar.frame, "OnShow")
    eq(bar.text.text:find("just now", 1, true) ~= nil, true)
    Fake.uninstall()
end)

test("the status bar can pop out and has a window title", function()
    local S = setup()
    local bar = S.StatusBar.Create(UIParent, { popOut = true })
    Fake.fire(bar.popOutButton, "OnClick")
    local slot = S.PopOut.Slot("status")
    eq(slot ~= nil and slot.win.frame.shown, true)
    eq(slot.panel.popOutButton, nil, "none inside the pop-out")
    eq(slot.win.title.text, "Stockist - Status")
    eq(slot.panel.text.text:find("Prices updated", 1, true) ~= nil, true)
    Fake.uninstall()
end)

test("the workspace has the status bar as a strip across the bottom, and no panel is a placeholder", function()
    local S = setup()
    S.Workspace.Show()
    local cell
    for _, c in ipairs(S.Workspace.LAYOUTS.trader.cells) do if c.panel == "status" then cell = c end end
    eq(cell ~= nil, true)
    eq(cell.y + cell.h, 1, "reaches the bottom"); eq(cell.w, 1); eq(cell.h < 0.1, true, "a thin strip")
    local placeholder
    for _, o in ipairs(Fake.objects) do
        if o.kind == "FontString" and o.text and o.text:find("Coming soon", 1, true) then placeholder = o end
    end
    eq(placeholder, nil)
    Fake.uninstall()
end)

test("every help key the status bar uses has a topic", function()
    local S = setup()
    for _, key in ipairs(S.StatusBar.HELP_KEYS) do eq(S.Help.topics:Get(key) ~= nil, true, key) end
    Fake.uninstall()
end)
