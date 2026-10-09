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
    "Features/Watchlist.lua", "Features/Ticker.lua", "Features/Movers.lua", "Features/StatusBar.lua", "Features/Workspace.lua",
}

local function setup(tutorial)
    Fake.install()
    local S = load_addon(unpack(FILES))
    S.settings = { tutorial = tutorial }
    S.Clock.now = function() return NOON end
    S.db = { scan = {} }
    S.store = S.ReadingStore.New(S.db)
    for id = 1, 3 do
        for h = 47, 0, -1 do S.store:Add({ item = id, ts = NOON - h * HOUR, price = 1000 + (47 - h) * id * 3, qty = 1 }) end
    end
    S.tracked = S.Tracked.New({})
    S.tracked:Add(1); S.tracked:Add(2)
    S.ItemInfo.Name = function(id) return "Item" .. id end
    S.Print = function() end
    return S
end

test("a guide reads as a heading, a key and a 'what it might mean' section, in colour", function()
    local S = setup(true)
    local text = S.Help.Guide("movers")
    eq(text:find("Reading the movers", 1, true) ~= nil, true, "heading")
    eq(text:find("|cffffd100Mover|r", 1, true) ~= nil, true, "gold key labels")
    eq(text:find("|cff4da6ffWhat it might mean|r", 1, true) ~= nil, true, "the blue tips heading")
    eq(text:find("good moment to sell", 1, true) ~= nil, true, "says what a rise might mean")
    eq(text:find("stock up cheaply", 1, true) ~= nil, true, "and what a fall might mean")
    eq(text:find("Hints, not advice", 1, true) ~= nil, true, "and that these are hints")
    eq(S.Help.Guide("watchlist"):find("Small line", 1, true) ~= nil, true, "the watchlist guide explains the line")
    is_nil(S.Help.Guide("nothing"), "no guide for an unknown panel")
    Fake.uninstall()
end)

test("the guide block is shown in tutorial mode, hidden otherwise, and cut to the room it is given", function()
    local S = setup(true)
    local panel = CreateFrame("Frame", nil, UIParent)
    panel:SetSize(280, 400)
    local guide = S.UI.Guide.Create(panel, "movers")
    local h = guide:Fit(500)
    eq(h > 0, true); eq(guide.frame.shown, true)
    eq(guide.text.text:find("Reading the movers", 1, true) ~= nil, true)
    local tall = h
    h = guide:Fit(tall - 20)
    eq(h, tall - 20, "cut off to the room, not squeezing anything else")
    eq(guide:Fit(40), 0, "hardly any room: left out")
    eq(guide.frame.shown, false)

    S.settings.tutorial = false
    eq(guide:Fit(500), 0, "tutorial mode off: hidden")
    eq(guide.frame.shown, false)
    Fake.uninstall()
end)

test("a panel with no guide shows nothing", function()
    local S = setup(true)
    local panel = CreateFrame("Frame", nil, UIParent)
    panel:SetSize(280, 400)
    local guide = S.UI.Guide.Create(panel, "no such guide")
    eq(guide:Fit(500), 0); eq(guide.frame.shown, false)
    Fake.uninstall()
end)

local function rowsShown(widgets)
    local n = 0
    for _, w in ipairs(widgets) do if w.shown ~= false and w.itemID then n = n + 1 end end
    return n
end

test("the movers panel shows its guide in tutorial mode and gives the room back when it is off", function()
    local S = setup(true)
    local p = S.Movers.Create(UIParent, { link = "A" })
    p.frame:SetSize(280, 450); p:Refresh()
    eq(p.guide.frame.shown, true, "in tutorial mode the guide is there")
    local withGuide = S.Movers.Capacity(450, p.guide.height)
    local without = S.Movers.Capacity(450, 0)
    eq(withGuide < without, true, "the lists have fewer rows to make room")

    S.Help.SetTutorial(false) -- fires TUTORIAL_CHANGED
    eq(p.guide.frame.shown, false, "turning tutorial mode off hides it at once")
    S.Help.SetTutorial(true)
    eq(p.guide.frame.shown, true, "and on brings it back")
    Fake.uninstall()
end)

test("the guide never takes the room of the last two rows of each movers list", function()
    local S = setup(true)
    local p = S.Movers.Create(UIParent, { link = "A" })
    p.frame:SetSize(280, 400); p:Refresh()
    local room = S.Movers.GuideRoom(400)
    eq(p.guide.height <= room, true, "the guide is cut to what is left")
    eq(S.Movers.Capacity(400, p.guide.height) >= 2, true, "two rows each remain")
    p.frame:SetSize(280, 190); p:Refresh()
    eq(p.guide.frame.shown, false, "in a small panel there is no room, so it is left out")
    Fake.uninstall()
end)

test("the watchlist shows its guide above the button in tutorial mode, and the list shrinks to match", function()
    local S = setup(true)
    local w = S.Watchlist.Create(UIParent, { link = "A" })
    w.frame:SetSize(280, 600); w:Refresh()
    eq(w.guide.frame.shown, true)
    local pts = w.list.points
    local last = pts[#pts]
    eq(last[1], "BOTTOMRIGHT")
    eq(last[3] > 26, true, "the list ends above the guide, which is above the footer button")
    S.Help.SetTutorial(false)
    pts = w.list.points
    eq(pts[#pts][3], 26, "tutorial off: the list runs down to the footer again")
    Fake.uninstall()
end)

test("hovering the watchlist's small line explains it, and clicking it still selects the row", function()
    local S = setup(true)
    local w = S.Watchlist.Create(UIParent, { link = "A" })
    w.list:SetSize(220, 300); w:Refresh()
    local row
    for _, r in ipairs(w.rowFrames) do if r.itemID == 1 then row = r end end
    eq(row.lineHit ~= nil, true, "an area over the line")
    eq(S.Help.Lines("watchlist-line") ~= nil, true)
    local _, short, detail = S.Help.Lines("watchlist-line")
    eq(short:find("7 days", 1, true) ~= nil, true, short)
    eq(detail:find("green", 1, true) ~= nil and detail:find("red", 1, true) ~= nil, true, "tutorial mode explains the colours")
    Fake.fire(row.lineHit, "OnMouseUp", "LeftButton")
    eq(S.Link.Get("A"), 1, "a click on the line is a click on the row")
    S.settings.tutorial = false
    local _, _, plain = S.Help.Lines("watchlist-line")
    eq(plain, nil, "the longer explanation is tutorial-only")
    Fake.uninstall()
end)

test("every help key the watchlist uses has a topic, including the line", function()
    local S = setup(true)
    for _, key in ipairs(S.Watchlist.HELP_KEYS) do eq(S.Help.topics:Get(key) ~= nil, true, key) end
    Fake.uninstall()
end)
