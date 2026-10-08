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
    "UI/Kit/Tooltip.lua", "UI/Kit/Button.lua", "UI/Kit/IconButton.lua", "UI/Kit/Window.lua", "Features/PriceChart.lua",
    "Features/ItemPicker.lua", "Features/ChartPanel.lua", "Features/StatusCommands.lua",
}

local NAMES = { [7] = "Linen Cloth", [8] = "Mageweave Cloth", [9] = "Heart of Fire", [10] = "Wool Cloth", [50] = "Zesty Tea" }

--- Items 7-10 have prices. 9 and 7 are tracked, and so is 50, which has no prices yet.
local function setup()
    Fake.install()
    local S = load_addon(unpack(FILES))
    S.settings = {}
    S.Clock.now = function() return NOON end
    S.db = { scan = {} }
    S.store = S.ReadingStore.New(S.db)
    for id = 7, 10 do
        for h = 5, 0, -1 do S.store:Add({ item = id, ts = NOON - h * HOUR, price = 100 * id + h, qty = 10 }) end
    end
    S.tracked = S.Tracked.New({})
    S.tracked:Add(9); S.tracked:Add(7); S.tracked:Add(50)
    S.ItemInfo.Name = function(id) return NAMES[id] end
    local out = {}
    S.Print = function(msg) out[#out + 1] = msg end
    return S, out
end

local function describe(rows)
    local out = {}
    for i, r in ipairs(rows) do
        out[i] = r.kind == "header" and ("# " .. r.text) or (r.kind == "open" and ("open " .. r.id) or r.name)
    end
    return table.concat(out, " | ")
end

-- Pure list -----------------------------------------------------------------------------------------

test("with no search: the watchlist first, a heading, then everything else, each sorted by name", function()
    local S = setup()
    local rows = S.ItemPicker.Entries(S.ItemPicker.Source(), "")
    eq(describe(rows), "# Watchlist | Heart of Fire | Linen Cloth | Zesty Tea | # Everything else | Mageweave Cloth | Wool Cloth")
    Fake.uninstall()
end)

test("typing filters by part of the name, any case, and a section with no matches loses its heading", function()
    local S = setup()
    local P, src = S.ItemPicker, S.ItemPicker.Source()
    eq(describe(P.Entries(src, "cloth")), "# Watchlist | Linen Cloth | # Everything else | Mageweave Cloth | Wool Cloth")
    eq(describe(P.Entries(src, "  HEART ")), "# Watchlist | Heart of Fire")
    eq(describe(P.Entries(src, "wool")), "# Items with prices | Wool Cloth", "no watchlist match: one plain heading")
    eq(describe(P.Entries(src, "nothing like this")), "")
    Fake.uninstall()
end)

test("with nothing tracked there is a single list", function()
    local S = setup()
    S.tracked = S.Tracked.New({})
    local rows = S.ItemPicker.Entries(S.ItemPicker.Source(), "")
    eq(describe(rows), "# Items with prices | Heart of Fire | Linen Cloth | Mageweave Cloth | Wool Cloth")
    Fake.uninstall()
end)

test("an item ID or link typed in is offered as 'open' unless it is already in the list", function()
    local S = setup()
    S.ParseItemID = S.ParseItemID or function(t) return tonumber(t:match("^%s*(%d+)%s*$") or t:match("item:(%d+)")) end
    local P, src = S.ItemPicker, S.ItemPicker.Source()
    eq(describe(P.Entries(src, "123")), "open 123", "an ID we know nothing about")
    eq(describe(P.Entries(src, "|cff1eff00|Hitem:2589::::|h[Linen Cloth]|h|r")):sub(1, 9), "open 2589")
    eq(describe(P.Entries(src, "7")), "# Watchlist | Linen Cloth", "a listed ID is just that item")
    Fake.uninstall()
end)

test("search by name finds items in both lists, sorted, for the chart command", function()
    local S = setup()
    local found = S.ItemPicker.Search(S.ItemPicker.Source(), "Cloth")
    eq(#found, 3)
    eq(found[1].name, "Linen Cloth"); eq(found[3].name, "Wool Cloth")
    eq(#S.ItemPicker.Search(S.ItemPicker.Source(), "zesty"), 1, "tracked items without prices are found too")
    eq(#S.ItemPicker.Search(S.ItemPicker.Source(), "xyz"), 0)
    Fake.uninstall()
end)

test("an uncached name sorts and matches as item:ID", function()
    local S = setup()
    S.ItemInfo.Name = function() return nil end
    local rows = S.ItemPicker.Entries(S.ItemPicker.Source(), "item:8")
    eq(describe(rows), "# Items with prices | item:8")
    Fake.uninstall()
end)

-- The popup -----------------------------------------------------------------------------------------

local function anchor() return CreateFrame("Frame", nil, UIParent) end

local function shownLabels(ui)
    local out = {}
    for _, row in ipairs(ui.rows) do
        if row.shown then out[#out + 1] = row.label.text end
    end
    return out
end

test("opening the picker shows the list and focuses the search box", function()
    local S = setup()
    local picked
    S.ItemPicker.Show(anchor(), function(id) picked = id end)
    local ui = S.ItemPicker._debug()
    eq(S.ItemPicker.IsShown(), true)
    eq(ui.catcher.shown, true, "a click-outside layer is up")
    eq(Fake.called(ui.edit, "SetFocus"), true)
    local labels = shownLabels(ui)
    eq(labels[1], "Watchlist"); eq(#labels, 7)
    eq(ui.empty.shown, false)
    Fake.uninstall()
end)

test("typing narrows the list, and a search with no hits says what to do", function()
    local S = setup()
    S.ItemPicker.Show(anchor(), function() end)
    local ui = S.ItemPicker._debug()
    ui.edit:SetText("wool"); Fake.fire(ui.edit, "OnTextChanged", true)
    eq(#shownLabels(ui), 2, "heading and one item")
    ui.edit:SetText("qqq"); Fake.fire(ui.edit, "OnTextChanged", true)
    eq(#shownLabels(ui), 0)
    eq(ui.empty.shown, true)
    Fake.uninstall()
end)

test("clicking a row picks that item and closes the picker; headings do nothing", function()
    local S = setup()
    local picked = {}
    S.ItemPicker.Show(anchor(), function(id) picked[#picked + 1] = id end)
    local ui = S.ItemPicker._debug()
    Fake.fire(ui.rows[1], "OnClick") -- the "Watchlist" heading
    eq(#picked, 0); eq(S.ItemPicker.IsShown(), true)
    Fake.fire(ui.rows[3], "OnClick") -- Linen Cloth
    eq(picked[1], 7)
    eq(S.ItemPicker.IsShown(), false)
    eq(ui.catcher.shown, false)
    Fake.uninstall()
end)

test("Enter picks the highlighted row, which starts as the first item, and the arrow keys move it", function()
    local S = setup()
    local picked
    S.ItemPicker.Show(anchor(), function(id) picked = id end)
    local ui = S.ItemPicker._debug()
    Fake.fire(ui.edit, "OnEnterPressed")
    eq(picked, 9, "Heart of Fire is the first item")

    picked = nil
    S.ItemPicker.Show(anchor(), function(id) picked = id end)
    Fake.fire(ui.edit, "OnArrowPressed", "DOWN")
    Fake.fire(ui.edit, "OnArrowPressed", "DOWN")
    Fake.fire(ui.edit, "OnEnterPressed")
    eq(picked, 50, "two down: Zesty Tea (the heading is skipped over)")

    picked = nil
    S.ItemPicker.Show(anchor(), function(id) picked = id end)
    Fake.fire(ui.edit, "OnArrowPressed", "UP")
    Fake.fire(ui.edit, "OnEnterPressed")
    eq(picked, 9, "cannot go above the first item")
    for _ = 1, 20 do Fake.fire(ui.edit, "OnArrowPressed", "DOWN") end
    S.ItemPicker.Show(anchor(), function(id) picked = id end) -- reopening starts again from the top
    Fake.fire(ui.edit, "OnEnterPressed")
    eq(picked, 9)
    Fake.uninstall()
end)

test("Enter on an empty result does nothing, and Escape or a click outside closes without picking", function()
    local S = setup()
    local picked = false
    S.ItemPicker.Show(anchor(), function() picked = true end)
    local ui = S.ItemPicker._debug()
    ui.edit:SetText("qqq"); Fake.fire(ui.edit, "OnTextChanged", true)
    Fake.fire(ui.edit, "OnEnterPressed")
    eq(picked, false); eq(S.ItemPicker.IsShown(), true, "still open")
    Fake.fire(ui.edit, "OnEscapePressed")
    eq(picked, false); eq(S.ItemPicker.IsShown(), false)
    S.ItemPicker.Show(anchor(), function() picked = true end)
    Fake.fire(ui.catcher, "OnClick")
    eq(picked, false); eq(S.ItemPicker.IsShown(), false)
    Fake.uninstall()
end)

test("a long list scrolls in steps and keeps the highlighted row in view", function()
    local S = setup()
    for id = 100, 140 do S.store:Add({ item = id, ts = NOON, price = 5, qty = 1 }) end
    S.ItemPicker.Show(anchor(), function() end)
    local ui, state = S.ItemPicker._debug()
    eq(state.offset, 0)
    Fake.fire(ui.popup, "OnMouseWheel", -1)
    eq(state.offset, 3)
    Fake.fire(ui.popup, "OnMouseWheel", 1); Fake.fire(ui.popup, "OnMouseWheel", 1)
    eq(state.offset, 0, "not above the top")
    for _ = 1, 30 do Fake.fire(ui.edit, "OnArrowPressed", "DOWN") end
    eq(state.offset > 0, true, "the view follows the highlight")
    eq(state.selectable[state.cursor] > state.offset and state.selectable[state.cursor] <= state.offset + 12, true)
    Fake.uninstall()
end)

-- In the chart panel and the command ------------------------------------------------------------------

test("clicking the item name in a chart opens the picker, and choosing sets the item for the link group", function()
    local S = setup()
    local a = S.ChartPanel.Create(UIParent, { link = "A" })
    local b = S.ChartPanel.Create(UIParent, { link = "A" })
    local lone = S.ChartPanel.Create(UIParent)
    Fake.fire(a.nameHit, "OnMouseUp")
    eq(S.ItemPicker.IsShown(), true)
    local ui = S.ItemPicker._debug()
    Fake.fire(ui.rows[3], "OnClick") -- Linen Cloth
    eq(S.Link.Get("A"), 7)
    eq(a:GetItem(), 7, "the panel that was clicked")
    eq(b:GetItem(), 7, "and the other panel in the group")
    eq(lone:GetItem(), nil, "an unlinked panel is not affected")

    Fake.fire(lone.nameHit, "OnMouseUp")
    Fake.fire(ui.rows[3], "OnClick")
    eq(lone:GetItem(), 7, "an unlinked panel just sets itself")
    Fake.uninstall()
end)

test("with nothing selected the chart header invites you to choose, and clicking it opens the picker", function()
    local S = setup()
    local panel = S.ChartPanel.Create(UIParent, { link = "A" })
    eq(panel.nameText.text:find("Choose an item", 1, true) ~= nil, true, panel.nameText.text)
    eq(panel.nameHit.size[1] > 1, true, "there is something to click")
    eq(panel.message.text:find("Choose an item", 1, true) ~= nil, true)
    Fake.fire(panel.nameHit, "OnMouseUp")
    eq(S.ItemPicker.IsShown(), true)
    Fake.uninstall()
end)

test("/stockist chart <name> opens a single match, lists several, and says when nothing matches", function()
    local S, out = setup()
    local shown = {}
    S.PriceChart.Show = function(id) shown[#shown + 1] = id end
    S.Commands:Dispatch("chart heart")
    eq(shown[1], 9, "one match opens it")
    S.Commands:Dispatch("chart cloth")
    eq(#shown, 1, "three matches open nothing")
    eq(out[#out]:find("3 items match 'cloth'", 1, true) ~= nil, true, out[#out])
    eq(out[#out]:find("Linen Cloth (7)", 1, true) ~= nil, true, "each with its ID")
    S.Commands:Dispatch("chart zzz")
    eq(out[#out]:find("no item with prices matches 'zzz'", 1, true) ~= nil, true)
    S.Commands:Dispatch("chart 8")
    eq(shown[2], 8, "an ID still works")
    Fake.uninstall()
end)
