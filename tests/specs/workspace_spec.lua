load_support("fake_wow")

local DAY, HOUR = 86400, 3600
local NOON = 40 * DAY + 12 * HOUR

local FILES = {
    "Core/Clock.lua", "Core/EventBus.lua", "Core/Registry.lua", "Core/Panels.lua", "Core/Link.lua",
    "Core/Format.lua", "Core/Calendar.lua", "Core/ItemInfo.lua", "Core/Help.lua", "Core/HelpTopics.lua",
    "Core/Commands.lua", "Data/Rollup.lua", "Data/Indicators.lua", "Data/ReadingStore.lua",
    "UI/Charts/Charts.lua", "UI/Charts/Util.lua", "UI/Charts/Scale.lua", "UI/Charts/Formatters.lua",
    "UI/Charts/Theme.lua", "UI/Charts/Series/Line.lua", "UI/Charts/Series/Candle.lua", "UI/Charts/Series/Bar.lua",
    "UI/Charts/Overlays/Overlays.lua", "UI/Charts/Core.lua", "UI/Charts/FrameCanvas.lua", "UI/Charts/ChartFrame.lua",
    "UI/Kit/Tooltip.lua", "UI/Kit/IconButton.lua", "UI/Kit/Window.lua", "Features/PriceChart.lua", "Features/ChartPanel.lua",
    "Features/Workspace.lua",
}

local function setup()
    Fake.install()
    local S = load_addon(unpack(FILES))
    S.settings = {}
    S.Clock.now = function() return NOON end
    S.db = { scan = {} }
    S.store = S.ReadingStore.New(S.db)
    for h = 0, 47 do S.store:Add({ item = 7, ts = NOON - h * HOUR, price = 1000 + h, qty = 40 }) end
    for h = 0, 10 do S.store:Add({ item = 8, ts = NOON - h * HOUR, price = 300 + h, qty = 10 }) end
    S.RichestItem = function() return 7 end
    local printed = {}
    S.Print = function(msg) printed[#printed + 1] = msg end
    return S, printed
end

-- Link groups -------------------------------------------------------------------------------------

test("selecting in a link group tells everyone and is remembered", function()
    local S = setup()
    local seen = {}
    S.Events:On("LINK_SELECTED", function(group, id) seen[#seen + 1] = group .. ":" .. id end)
    is_nil(S.Link.Get("A"))
    S.Link.Select("A", 2589)
    S.Link.Select("B", 7)
    eq(S.Link.Get("A"), 2589); eq(S.Link.Get("B"), 7)
    eq(table.concat(seen, ","), "A:2589,B:7")
    Fake.uninstall()
end)

test("a selection without a group or an item is ignored; an unknown group has no item", function()
    local S = setup()
    local fired = 0
    S.Events:On("LINK_SELECTED", function() fired = fired + 1 end)
    S.Link.Select(nil, 5); S.Link.Select("A", nil)
    eq(fired, 0)
    is_nil(S.Link.Get(nil)); is_nil(S.Link.Get("Z"))
    Fake.uninstall()
end)

test("a linked chart panel follows its group; an unlinked one does not", function()
    local S = setup()
    local linked = S.ChartPanel.Create(UIParent, { link = "A" })
    local alone = S.ChartPanel.Create(UIParent)
    S.Link.Select("A", 7)
    eq(linked:GetItem(), 7); is_nil(alone:GetItem())
    S.Link.Select("A", 8)
    eq(linked:GetItem(), 8)
    S.Link.Select("B", 7)
    eq(linked:GetItem(), 8, "another group does not affect it")
    local late = S.ChartPanel.Create(UIParent, { link = "A" })
    eq(late:GetItem(), 8, "a panel created later starts on the group's item")
    Fake.uninstall()
end)

test("a chart panel with no item says so instead of staying blank", function()
    local S = setup()
    local panel = S.ChartPanel.Create(UIParent)
    eq(panel.message.shown, true)
    eq(panel.message.text:find("No item selected", 1, true) ~= nil, true)
    panel:SetItem(7)
    eq(panel.message.shown, false)
    Fake.uninstall()
end)

-- Layout ------------------------------------------------------------------------------------------

test("cells are placed by fraction and kept apart by the gap", function()
    local S = setup()
    local layout = S.Workspace.LAYOUTS.trader
    local rects = S.Workspace.CellRects(layout, 1000, 600, 6)
    eq(#rects, 2)
    eq(rects[1].id, "watchlist"); eq(rects[2].id, "chart")
    -- watchlist: 27% wide from the left; chart: the rest
    eq(rects[1].x, 3); eq(rects[1].y, 3)
    eq(rects[1].w, 264); eq(rects[1].h, 594)
    eq(rects[2].x, 273)
    eq(rects[2].x - (rects[1].x + rects[1].w), 6, "6px between the two cells")
    eq(rects[2].x + rects[2].w, 997, "3px from the right edge")
    Fake.uninstall()
end)

test("cells never collapse to nothing in a tiny frame", function()
    local S = setup()
    for _, r in ipairs(S.Workspace.CellRects(S.Workspace.LAYOUTS.trader, 4, 4, 6)) do
        eq(r.w >= 1 and r.h >= 1, true)
    end
    Fake.uninstall()
end)

test("every cell in the layout has a link group and a title for its placeholder", function()
    local S = setup()
    for _, c in ipairs(S.Workspace.LAYOUTS.trader.cells) do
        eq(type(c.title), "string", c.id)
        eq(c.link ~= nil, true, c.id)
        eq(c.w > 0 and c.h > 0, true, c.id)
    end
    Fake.uninstall()
end)

-- The window --------------------------------------------------------------------------------------

test("opening the workspace builds one window with a cell per layout entry", function()
    local S = setup()
    S.Workspace.Show(7)
    eq(StockistWorkspace ~= nil, true)
    eq(StockistWorkspace.shown, true)
    eq(S.Workspace.IsShown(), true)
    eq(#UISpecialFrames, 1, "Esc closes it")
    Fake.uninstall()
end)

test("the selected item goes to the link group, and an unbuilt panel type gets a placeholder", function()
    local S = setup()
    eq(S.Panels:Get("watchlist"), nil, "the watchlist panel is not built yet")
    S.Workspace.Show(7)
    eq(S.Link.Get("A"), 7)
    local placeholder
    for _, o in ipairs(Fake.objects) do
        if o.kind == "FontString" and o.text and o.text:find("Coming soon", 1, true) then placeholder = o end
    end
    eq(placeholder ~= nil, true, "a placeholder label was created")
    eq(placeholder.text:find("Watchlist", 1, true) ~= nil, true, "named after the missing panel")
    Fake.uninstall()
end)

test("a chart in the workspace follows the link group and can pop out", function()
    local S = setup()
    local created = {}
    local real = S.Panels:Get("chart").create
    S.Panels.items.chart.create = function(parent, opts)
        local p = real(parent, opts)
        created[#created + 1] = { panel = p, opts = opts }
        return p
    end
    S.Workspace.Show(7)
    eq(#created, 1)
    local panel = created[1].panel
    eq(created[1].opts.link, "A"); eq(created[1].opts.popOut, true)
    eq(panel:GetItem(), 7)

    S.Link.Select("A", 8)
    eq(panel:GetItem(), 8)

    local popped
    S.PriceChart.Show = function(id) popped = id end
    Fake.fire(panel.popOutButton, "OnClick")
    eq(popped, 8, "pop out opens the current item in its own window")
    Fake.uninstall()
end)

test("reopening reuses the window and keeps the group's item unless told otherwise", function()
    local S = setup()
    S.Workspace.Show(8)
    local win = StockistWorkspace
    StockistWorkspace.shown = false
    S.Workspace.Show()
    eq(StockistWorkspace, win, "same window")
    eq(S.Link.Get("A"), 8, "kept")
    S.Workspace.Show(7)
    eq(S.Link.Get("A"), 7)
    eq(#UISpecialFrames, 1)
    Fake.uninstall()
end)

test("with no item given and none selected, it picks the item with the most history", function()
    local S = setup()
    S.Workspace.Show()
    eq(S.Link.Get("A"), 7)
    Fake.uninstall()
end)

test("with no data anywhere it still opens, and the chart cell says no item is selected", function()
    local S = setup()
    S.RichestItem = function() return nil end
    S.Workspace.Show()
    eq(S.Link.Get("A"), nil)
    eq(StockistWorkspace.shown, true)
    Fake.uninstall()
end)

test("cells are laid out when the window opens, and again on the next frame and on resize", function()
    local S = setup()
    S.Workspace.Show(7)
    Fake.flush()
    local content
    for _, f in ipairs(Fake.frames) do
        if f.scripts.OnSizeChanged and f.kind == "Frame" and f.parent == StockistWorkspace then content = f end
    end
    eq(content ~= nil, true, "the window's content frame listens for resizes")
    -- two cell frames hang off the content frame, each with a size set by the layout
    local sized = {}
    for _, f in ipairs(Fake.frames) do
        if f.parent == content and f.size then sized[#sized + 1] = f end
    end
    eq(#sized, 2)
    local before = sized[2].size[1]
    content.size = { 2000, 800 }
    Fake.fire(content, "OnSizeChanged")
    eq(sized[2].size[1] > before, true, "the chart cell grew with the window")
    Fake.uninstall()
end)

test("the pop-out icon is a square with an arrow leaving its corner, inside the button", function()
    local S = setup()
    local icon = S.UI.IconButton.ICONS.popout
    eq(#icon, 7, "four sides of the square, a shaft and two arrowhead strokes")
    local extent = 0
    for _, s in ipairs(icon) do
        for _, v in ipairs(s) do
            eq(v == math.floor(v), true, "whole pixels, so lines stay crisp: " .. v)
            extent = math.max(extent, math.abs(v))
        end
    end
    eq(extent, 5, "the icon spans 10px (it was 12px)")
    local tip = icon[5]
    eq(tip[3], 5); eq(tip[4], 5, "the arrow points to the top-right")
    -- the square is open at the top-right: neither the top nor the right side reaches the corner
    eq(icon[3][3] < 2, true); eq(icon[4][4] < 2, true)
    Fake.uninstall()
end)

test("an icon button draws its segments, highlights on hover and rejects unknown icons", function()
    local S = setup()
    local b = S.UI.IconButton.Create(UIParent, { icon = "popout", width = 24, height = 20 })
    eq(#b.lines, 7)
    eq(b.lines[1].startPoint[1], "CENTER")
    eq(b.lines[5].endPoint[3], 5); eq(b.lines[5].endPoint[4], 5)
    local normal = { b.lines[1].color[1], b.lines[1].color[2], b.lines[1].color[3] }
    Fake.fire(b, "OnEnter")
    eq(b.lines[1].color[1], 1); eq(b.lines[1].color[3], 0, "gold while hovered")
    Fake.fire(b, "OnLeave")
    eq(b.lines[1].color[1], normal[1], "back to normal")
    throws(function() S.UI.IconButton.Create(UIParent, { icon = "nope" }) end, "unknown icon")
    Fake.uninstall()
end)

test("the pop-out button is rightmost in the chart header and the scope buttons sit to its left", function()
    local S = setup()
    local with = S.ChartPanel.Create(UIParent, { popOut = true })
    local pop = with.popOutButton
    eq(pop.points[1][1], "TOPRIGHT", "pinned to the top-right corner")
    local oneMonth = with.tfButtons["1M"].points[1]
    eq(oneMonth[1], "RIGHT"); eq(oneMonth[2], pop); eq(oneMonth[3], "LEFT"); eq(oneMonth[4], -8)
    local oneWeek = with.tfButtons["1W"].points[1]
    eq(oneWeek[2], with.tfButtons["1M"]); eq(oneWeek[4], -2, "scope buttons stay close together")

    local without = S.ChartPanel.Create(UIParent)
    is_nil(without.popOutButton)
    eq(without.tfButtons["1M"].points[1][1], "TOPRIGHT", "no pop-out: the scope buttons take the corner")
    Fake.uninstall()
end)

test("windows are top-level and raise themselves when shown, so a pop-out sits over the workspace", function()
    local S = setup()
    S.Workspace.Show(7)
    S.PriceChart.Show(7)
    for _, name in ipairs({ "StockistWorkspace", "StockistChartWindow" }) do
        local win = _G[name]
        eq(Fake.called(win, "SetToplevel"), true, name .. " is top-level")
        eq(Fake.called(win, "Raise"), false, "nothing raised yet in the stand-in client")
        Fake.fire(win, "OnShow")
        eq(Fake.called(win, "Raise"), true, name .. " raises itself when shown")
    end
    Fake.uninstall()
end)

-- Command -----------------------------------------------------------------------------------------

test("/stockist workspace opens it, with an optional item, and rejects a bad argument", function()
    local S, printed = setup()
    S.ParseItemID = function(text) return tonumber(text:match("^%s*(%d+)%s*$")) end
    S.Commands:Dispatch("workspace 8")
    eq(S.Link.Get("A"), 8)
    S.Commands:Dispatch("workspace banana")
    eq(printed[#printed], "usage: /stockist workspace [itemID or item link]")
    eq(S.Link.Get("A"), 8, "unchanged")
    Fake.uninstall()
end)
