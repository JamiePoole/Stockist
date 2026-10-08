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
    "Features/ItemPicker.lua", "Features/ChartPanel.lua", "Features/Workspace.lua", "Features/StatusCommands.lua",
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
    eq(ui.catcher.shown, false, "no screen-covering layer: the rest of the UI stays usable")
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

-- Layout details -------------------------------------------------------------------------------------

test("the popup sits a small gap below the item name, and the results start below the help text", function()
    local S = setup()
    local name = anchor()
    S.ItemPicker.Show(name, function() end)
    local ui = S.ItemPicker._debug()
    local p = ui.popup.points[#ui.popup.points]
    eq(p[2], name); eq(p[3], "BOTTOMLEFT")
    eq(p[5], -4, "a few pixels of air between the name and the border")
    local list = ui.list.points
    eq(list[1][5], -50, "the list starts well below the help text (search box 8 + 20, hint ~12, margin)")
    eq(ui.hint.shown, true); eq(ui.edit.shown, true)
    Fake.uninstall()
end)

test("the scroll bar appears only when the list is longer than the window and follows the scrolling", function()
    local S = setup()
    S.ItemPicker.Show(anchor(), function() end)
    local ui, state = S.ItemPicker._debug()
    eq(ui.track.shown, false, "7 rows fit: no bar")
    S.ItemPicker.Hide()
    for id = 100, 140 do S.store:Add({ item = id, ts = NOON, price = 5, qty = 1 }) end
    S.ItemPicker.Show(anchor(), function() end)
    eq(ui.track.shown, true); eq(ui.thumb.shown, true)
    local top0 = ui.thumb.points[#ui.thumb.points][5]
    eq(top0, 0, "thumb at the top")
    Fake.fire(ui.popup, "OnMouseWheel", -1); Fake.fire(ui.popup, "OnMouseWheel", -1)
    eq(ui.thumb.points[#ui.thumb.points][5] < 0, true, "and it moves down as the list scrolls")
    local right = ui.list.points[2][4]
    eq(right, -16, "the rows leave room for the bar")
    ui.edit:SetText("wool"); Fake.fire(ui.edit, "OnTextChanged", true)
    eq(ui.track.shown, false, "gone again when the list is short")
    eq(ui.list.points[2][4], -4)
    Fake.uninstall()
end)

test("scroll bar maths: thumb size and position, and dragging", function()
    local S = setup()
    local P = S.ItemPicker
    is_nil(P.Thumb(10, 12, 0, 240), "everything fits: no thumb")
    local top, h = P.Thumb(48, 12, 0, 240)
    eq(top, 0); eq(h, 60, "a quarter of the list is visible: a quarter of the track")
    top = P.Thumb(48, 12, 36, 240)
    eq(top, 180, "scrolled to the end: the thumb is at the bottom of the track")
    top, h = P.Thumb(1000, 12, 0, 240)
    eq(h, 16, "never smaller than a grab-able minimum")
    eq(P.OffsetForDrag(48, 12, 240, 0, 90), 18, "half the free track is half the way")
    eq(P.OffsetForDrag(48, 12, 240, 0, 9999), 36, "clamped to the end")
    eq(P.OffsetForDrag(48, 12, 240, 10, -9999), 0, "and to the start")
    eq(P.OffsetForDrag(5, 12, 240, 0, 50), 0, "nothing to scroll")
    Fake.uninstall()
end)

test("dragging the thumb scrolls the list", function()
    local S = setup()
    for id = 100, 140 do S.store:Add({ item = id, ts = NOON, price = 5, qty = 1 }) end
    S.ItemPicker.Show(anchor(), function() end)
    local ui, state = S.ItemPicker._debug()
    local y = 500
    GetCursorPosition = function() return 0, y end
    IsMouseButtonDown = function() return true end
    Fake.fire(ui.thumb, "OnMouseDown")
    y = 400 -- 100px down
    Fake.fire(ui.thumb, "OnUpdate")
    eq(state.offset > 0, true, "scrolled")
    local mid = state.offset
    y = 0
    Fake.fire(ui.thumb, "OnUpdate")
    eq(state.offset, #state.rows - 12, "dragged to the end")
    Fake.fire(ui.thumb, "OnMouseUp")
    y = 500
    Fake.fire(ui.thumb, "OnUpdate")
    eq(state.offset, #state.rows - 12, "released: no more dragging")
    GetCursorPosition, IsMouseButtonDown = nil, nil
    Fake.uninstall()
end)

test("the item name has a dotted underline, brighter under the mouse, as wide as the name", function()
    local S = setup()
    local panel = S.ChartPanel.Create(UIParent)
    panel:SetItem(7)
    local shown = 0
    for _, dot in ipairs(panel.dots) do if dot.shown then shown = shown + 1 end end
    eq(shown, math.floor(panel.nameHit.size[1] / 4), "one dot every 4px across the name")
    eq(shown > 0, true)
    eq(panel.dots[1].color[4], 0.5, "quiet at rest")
    Fake.fire(panel.nameHit, "OnEnter")
    eq(panel.dots[1].color[4], 1, "bright on hover")
    Fake.fire(panel.nameHit, "OnLeave")
    eq(panel.dots[1].color[4], 0.5)
    -- a shorter name uses fewer dots; the spare ones are hidden, not left hanging
    S.ItemInfo.ColoredName = function() return "Ab" end
    panel:Refresh()
    local after = 0
    for _, dot in ipairs(panel.dots) do if dot.shown then after = after + 1 end end
    eq(after < shown, true)
    Fake.uninstall()
end)

-- The title-bar search box ---------------------------------------------------------------------------

local function titleSearch()
    for _, o in ipairs(Fake.objects) do
        if o.kind == "EditBox" and o.parent == StockistWorkspace then return o end
    end
end

test("the workspace has a search box in its title bar; focusing it opens just the results under it", function()
    local S = setup()
    S.Workspace.Show()
    local search = titleSearch()
    eq(search ~= nil, true, "a search box in the title bar")
    eq(search.size[2], 24, "as tall as the header buttons")
    eq(search.points[1][1], "CENTER", "centred in the title bar, both ways")
    Fake.fire(search, "OnEditFocusGained")
    eq(S.ItemPicker.IsShown(), true)
    local ui = S.ItemPicker._debug()
    eq(ui.edit.shown, false, "the popup's own box and hint are hidden")
    eq(ui.hint.shown, false)
    eq(ui.popup.points[#ui.popup.points][2], search, "anchored under the title-bar box")
    eq(ui.list.points[1][5], -8, "results start near the top, with no search box inside")
    eq(#shownLabels(ui) > 0, true)
    Fake.uninstall()
end)

test("typing in the title bar filters, Enter picks into the workspace's group and clears the box", function()
    local S = setup()
    S.Workspace.Show()
    local search = titleSearch()
    Fake.fire(search, "OnEditFocusGained")
    search:SetText("wool"); Fake.fire(search, "OnTextChanged", true)
    local ui = S.ItemPicker._debug()
    eq(#shownLabels(ui), 2)
    Fake.fire(search, "OnEnterPressed")
    eq(S.Link.Get("A"), 10, "Wool Cloth is selected for the group, so the chart follows")
    eq(S.ItemPicker.IsShown(), false)
    eq(search.text, "", "the box is empty again")
    Fake.uninstall()
end)

test("Escape in the title-bar box closes the results and empties it", function()
    local S = setup()
    S.Workspace.Show()
    local search = titleSearch()
    Fake.fire(search, "OnEditFocusGained")
    search:SetText("lin"); Fake.fire(search, "OnTextChanged", true)
    Fake.fire(search, "OnEscapePressed")
    eq(S.ItemPicker.IsShown(), false)
    eq(search.text, "")
    Fake.uninstall()
end)

test("only one picker is open at a time, whichever way it was opened", function()
    local S = setup()
    S.Workspace.Show()
    local search = titleSearch()
    local panel = S.ChartPanel.Create(UIParent, { link = "A" })

    Fake.fire(search, "OnEditFocusGained")
    search:SetText("lin"); Fake.fire(search, "OnTextChanged", true)
    Fake.fire(panel.nameHit, "OnMouseUp") -- the item name opens its own picker
    local ui, state = S.ItemPicker._debug()
    eq(S.ItemPicker.IsShown(), true)
    eq(state.edit, ui.edit, "now serving the name's picker")
    eq(search.text, "", "the title-bar box was closed and cleared")
    eq(ui.edit.shown, true)

    Fake.fire(search, "OnEditFocusGained") -- and the other way round
    eq(state.edit, search)
    eq(ui.edit.shown, false)
    eq(S.ItemPicker.IsShown(), true)
    Fake.uninstall()
end)

-- Clicking away, and shift-clicking items into the box ---------------------------------------------------

local function press(ui) Fake.fire(ui.events, "OnEvent", "GLOBAL_MOUSE_DOWN", "LeftButton") end

test("a plain click elsewhere closes the picker; a click on it, its box or what opened it does not", function()
    local S = setup()
    local name = anchor()
    S.ItemPicker.Show(name, function() end)
    local ui = S.ItemPicker._debug()
    eq(ui.globalClicks, true)
    ui.popup.IsMouseOver = function() return true end
    press(ui)
    eq(S.ItemPicker.IsShown(), true, "a click inside the popup")
    ui.popup.IsMouseOver = function() return false end
    name.IsMouseOver = function() return true end
    press(ui)
    eq(S.ItemPicker.IsShown(), true, "a click on the item name that opened it")
    name.IsMouseOver = function() return false end
    ui.edit.IsMouseOver = function() return true end
    press(ui)
    eq(S.ItemPicker.IsShown(), true, "a click in the search box")
    ui.edit.IsMouseOver = function() return false end
    press(ui)
    eq(S.ItemPicker.IsShown(), false, "a click anywhere else")
    Fake.uninstall()
end)

test("a click with Shift, Ctrl or Alt held does not close it, so items can be shift-clicked into the box", function()
    local S = setup()
    S.ItemPicker.Show(anchor(), function() end)
    local ui = S.ItemPicker._debug()
    for _, key in ipairs({ "IsShiftKeyDown", "IsControlKeyDown", "IsAltKeyDown" }) do
        _G[key] = function() return true end
        press(ui)
        eq(S.ItemPicker.IsShown(), true, key)
        _G[key] = nil
    end
    press(ui)
    eq(S.ItemPicker.IsShown(), false, "plain click still closes")
    Fake.uninstall()
end)

test("an item link offered while the search box has the keyboard goes into the box and finds that item", function()
    local hooks = {}
    hooksecurefunc = function(name, fn) hooks[name] = fn end
    ChatEdit_InsertLink = function() return false end
    local S = setup()
    S.ParseItemID = S.ParseItemID or function(t) return tonumber(t:match("^%s*(%d+)%s*$") or t:match("item:(%d+)")) end
    S.ItemPicker.Show(anchor(), function() end)
    local ui = S.ItemPicker._debug()
    eq(type(hooks.ChatEdit_InsertLink), "function", "hooked, without replacing the game's function")
    ui.edit.HasFocus = function() return true end
    ui.edit.Insert = function(self, text) self.text = (self.text or "") .. text end
    hooks.ChatEdit_InsertLink("|cff1eff00|Hitem:7::::|h[Linen Cloth]|h|r")
    eq(ui.edit.text:find("Hitem:7", 1, true) ~= nil, true, "the link is in the box")
    Fake.fire(ui.edit, "OnTextChanged", true)
    eq(shownLabels(ui)[1], "Watchlist")
    eq(#shownLabels(ui), 2, "just that item, found by its ID")

    -- the same click reported twice (the game has two names for the function) inserts once
    ui.edit.text = ""
    GetTime = function() return 5 end
    local link = "|cff1eff00|Hitem:7::::|h[Linen Cloth]|h|r"
    hooks.ChatEdit_InsertLink(link); hooks.ChatEdit_InsertLink(link)
    eq(ui.edit.text, link, "once, not twice")
    GetTime = nil

    ui.edit.text = ""
    hooks.ChatEdit_InsertLink("not a link")
    hooks.ChatEdit_InsertLink("|cffa335ee|Hspell:133|h[Fireball]|h|r")
    eq(ui.edit.text, "", "only item links are taken")
    ui.edit.HasFocus = function() return false end
    hooks.ChatEdit_InsertLink("|cff1eff00|Hitem:7::::|h[Linen Cloth]|h|r")
    eq(ui.edit.text, "", "and only while the box has the keyboard")
    hooksecurefunc, ChatEdit_InsertLink = nil, nil
    Fake.uninstall()
end)

test("an item link in the box for an item we have no data on offers to open it", function()
    local S = setup()
    S.ParseItemID = S.ParseItemID or function(t) return tonumber(t:match("^%s*(%d+)%s*$") or t:match("item:(%d+)")) end
    local rows = S.ItemPicker.Entries(S.ItemPicker.Source(), "|cff1eff00|Hitem:2589::::|h[Linen Cloth]|h|r")
    eq(describe(rows), "open 2589")
    rows = S.ItemPicker.Entries(S.ItemPicker.Source(), "|cff1eff00|Hitem:8::::|h[Mageweave Cloth]|h|r")
    eq(describe(rows), "# Items with prices | Mageweave Cloth", "a known item is simply listed")
    Fake.uninstall()
end)

test("clicking the item name again closes its picker", function()
    local S = setup()
    local panel = S.ChartPanel.Create(UIParent, { link = "A" })
    Fake.fire(panel.nameHit, "OnMouseUp")
    eq(S.ItemPicker.IsShown(), true)
    Fake.fire(panel.nameHit, "OnMouseUp")
    eq(S.ItemPicker.IsShown(), false)
    Fake.fire(panel.nameHit, "OnMouseUp")
    eq(S.ItemPicker.IsShown(), true, "and a third opens it again")
    Fake.uninstall()
end)

test("without GLOBAL_MOUSE_DOWN the old click-catching layer is used instead", function()
    local S = setup()
    local real = CreateFrame
    CreateFrame = function(...)
        local f = real(...)
        local reg = f.RegisterEvent
        f.RegisterEvent = function(self, e, ...)
            if e == "GLOBAL_MOUSE_DOWN" then error("unknown event") end
            return reg(self, e, ...)
        end
        return f
    end
    S.ItemPicker.Show(anchor(), function() end)
    CreateFrame = real
    local ui = S.ItemPicker._debug()
    eq(ui.globalClicks, false)
    eq(ui.catcher.shown, true)
    Fake.fire(ui.catcher, "OnClick")
    eq(S.ItemPicker.IsShown(), false)
    Fake.uninstall()
end)

-- The placeholder in the title-bar box ------------------------------------------------------------------

--- A title-bar box whose focus the test controls. Hooks are cleared, as the real client does when the item
--- picker replaces the box's scripts, so only what the picker itself does can keep the placeholder right.
local function focusableSearch(S)
    S.Workspace.Show()
    local search = titleSearch()
    local focused = false
    search.HasFocus = function() return focused end
    search.SetFocus = function() focused = true end
    search.ClearFocus = function() focused = false end
    search.hooks = {}
    local function click() focused = true; Fake.fire(search, "OnEditFocusGained") end
    local function type_(text) search:SetText(text); Fake.fire(search, "OnTextChanged", true) end
    return search, click, type_
end

test("title-bar placeholder: shown when empty, gone while typing, back after Enter or picking", function()
    local S = setup()
    local search, click, type_ = focusableSearch(S)
    search.paintPlaceholder()
    eq(search.placeholder.shown, true, "'Search items' at rest")

    click()
    eq(search.placeholder.shown, false, "gone once the box is in use")
    type_("wo")
    eq(search.placeholder.shown, false, "and not showing behind what is typed")

    Fake.fire(search, "OnEnterPressed") -- picks Wool Cloth
    eq(search.text, "")
    eq(search.placeholder.shown, true, "back, never a blank box, after choosing")

    click(); type_("lin")
    local ui = S.ItemPicker._debug()
    Fake.fire(ui.rows[2], "OnClick") -- click a result instead of Enter
    eq(search.placeholder.shown, true, "also after clicking a result")
    Fake.uninstall()
end)

test("title-bar placeholder returns after Escape, and after clicking away", function()
    local S = setup()
    local search, click, type_ = focusableSearch(S)
    click(); type_("lin")
    Fake.fire(search, "OnEscapePressed")
    eq(search.placeholder.shown, true)

    click(); type_("lin")
    Fake.fire(S.ItemPicker._debug().events, "OnEvent", "GLOBAL_MOUSE_DOWN", "LeftButton")
    eq(S.ItemPicker.IsShown(), false)
    eq(search.placeholder.shown, true, "clicking away empties the box and shows it again")
    Fake.uninstall()
end)

test("backspacing the title-bar text to nothing leaves it empty while still in use, then clears on leaving", function()
    local S = setup()
    local search, click, type_ = focusableSearch(S)
    click(); type_("lin"); type_("")
    eq(search.placeholder.shown, false, "still focused: the caret is there, no placeholder under it")
    Fake.fire(S.ItemPicker._debug().events, "OnEvent", "GLOBAL_MOUSE_DOWN", "LeftButton")
    eq(search.placeholder.shown, true)
    Fake.uninstall()
end)

test("shift-clicking a stack into the box does not leave the stack-split dialog open", function()
    local hooks = {}
    hooksecurefunc = function(name, fn) hooks[name] = fn end
    ChatEdit_InsertLink = function() return false end
    local S = setup()
    S.ItemPicker.Show(anchor(), function() end)
    local ui = S.ItemPicker._debug()
    ui.edit.HasFocus = function() return true end
    ui.edit.Insert = function(self, text) self.text = (self.text or "") .. text end
    local split = Fake.new("Frame")
    StackSplitFrame = split
    split:Show()
    hooks.ChatEdit_InsertLink("|cff1eff00|Hitem:7::::|h[Linen Cloth]|h|r")
    eq(split.shown, false, "closed at once if it is already up")
    split:Show() -- the bag opens it a moment after our hook ran
    Fake.flush()
    eq(split.shown, false, "and closed again on the next frame")
    StackSplitFrame, hooksecurefunc, ChatEdit_InsertLink = nil, nil, nil
    Fake.uninstall()
end)
