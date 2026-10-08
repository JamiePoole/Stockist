load_support("fake_wow")

local DAY, HOUR = 86400, 3600
local NOON = 40 * DAY + 12 * HOUR

-- ItemInfo.Exists ----------------------------------------------------------------------------------

test("ItemInfo.Exists reports whether the game has the item, or nil when it cannot say", function()
    local S = load_addon("Core/Format.lua", "Core/ItemInfo.lua")
    is_nil(S.ItemInfo.Exists(5), "no item API at all: unknown")
    C_Item = { DoesItemExistByID = function(id) return id == 2589 end }
    eq(S.ItemInfo.Exists(2589), true)
    eq(S.ItemInfo.Exists(99999999), false)
    C_Item = { DoesItemExistByID = function() error("secret value") end }
    is_nil(S.ItemInfo.Exists(1), "a failing call counts as unknown, not as missing")
    C_Item = nil
end)

test("ItemInfo.Exists trusts the client's item database first", function()
    local S = load_addon("Core/Format.lua", "Core/ItemInfo.lua")
    -- the real-client failure: DoesItemExistByID said yes to a made-up ID, GetItemInfoInstant said nothing
    C_Item = {
        DoesItemExistByID = function() return true end,
        GetItemInfoInstant = function(id) if id == 2589 then return 2589, "Tradeskill" end end,
    }
    eq(S.ItemInfo.Exists(2589), true)
    eq(S.ItemInfo.Exists(99999999), false, "not in the item database: not an item")
    C_Item = nil
end)

test("ItemInfo.Exists falls back to the global GetItemInfoInstant, then to DoesItemExistByID", function()
    local S = load_addon("Core/Format.lua", "Core/ItemInfo.lua")
    GetItemInfoInstant = function(id) if id == 7 then return 7 end end
    eq(S.ItemInfo.Exists(7), true); eq(S.ItemInfo.Exists(8), false)
    GetItemInfoInstant = nil
    C_Item = { DoesItemExistByID = function(id) return id == 7 end }
    eq(S.ItemInfo.Exists(7), true); eq(S.ItemInfo.Exists(8), false)
    C_Item = { GetItemInfoInstant = function() error("secret value") end }
    is_nil(S.ItemInfo.Exists(7), "a failing lookup is unknown, not missing")
    C_Item = nil
end)

test("a failed item load marks the ID as missing, a successful one clears it", function()
    local S = load_addon("Core/Format.lua", "Core/ItemInfo.lua")
    C_Item = { GetItemInfoInstant = function(id) return id end } -- the database says yes
    eq(S.ItemInfo.Exists(55), true)
    S.ItemInfo.NoteLoadResult(55, false)
    eq(S.ItemInfo.Exists(55), false, "the client could not load it after all")
    S.ItemInfo.NoteLoadResult(55, true)
    eq(S.ItemInfo.Exists(55), true)
    C_Item = nil
end)

-- PriceChart.Status --------------------------------------------------------------------------------

local function statusSetup()
    local S = load_addon("Core/Format.lua", "Core/Calendar.lua", "Data/Rollup.lua", "Data/Indicators.lua",
        "Data/ReadingStore.lua", "Features/PriceChart.lua")
    local store = S.ReadingStore.New({})
    store:Add({ item = 7, ts = NOON, price = 1000, qty = 5 })
    return S, store
end

test("an item that does not exist is a 404, whatever data we hold", function()
    local S, store = statusSetup()
    local s = S.PriceChart.Status(store, 99999999, false, nil, NOON)
    eq(s.kind, "notfound")
    eq(s.text:find("No item has the ID 99999999", 1, true) ~= nil, true)
    eq(S.PriceChart.Status(store, 7, false, NOON, NOON).kind, "notfound")
end)

test("a real item with no prices says why, depending on whether any scan has run", function()
    local S, store = statusSetup()
    local never = S.PriceChart.Status(store, 8, true, nil, NOON)
    eq(never.kind, "nodata")
    eq(never.text:find("Open the Auction House", 1, true) ~= nil, true)
    local after = S.PriceChart.Status(store, 8, true, NOON - 20 * 60, NOON)
    eq(after.kind, "nodata")
    eq(after.text:find("wasn't on the Auction House at the last scan (20m ago)", 1, true) ~= nil, true, after.text)
    eq(after.text:find("soulbound", 1, true) ~= nil, true)
end)

test("an item with data, or one the client cannot vouch for either way, is fine", function()
    local S, store = statusSetup()
    eq(S.PriceChart.Status(store, 7, true, NOON, NOON).kind, "ok")
    eq(S.PriceChart.Status(store, 7, nil, NOON, NOON).kind, "ok", "unknown existence is not a 404")
    eq(S.PriceChart.Status(store, 8, nil, NOON, NOON).kind, "nodata", "unknown existence but no prices")
end)

-- The panel ----------------------------------------------------------------------------------------

local FILES = {
    "Core/Clock.lua", "Core/EventBus.lua", "Core/Registry.lua", "Core/Panels.lua", "Core/Link.lua", "Core/Format.lua",
    "Core/Calendar.lua", "Core/ItemInfo.lua", "Core/Help.lua", "Core/HelpTopics.lua", "Data/Rollup.lua",
    "Data/Indicators.lua", "Data/ReadingStore.lua", "UI/Charts/Charts.lua", "UI/Charts/Util.lua",
    "UI/Charts/Scale.lua", "UI/Charts/Formatters.lua", "UI/Charts/Theme.lua", "UI/Charts/Series/Line.lua",
    "UI/Charts/Series/Candle.lua", "UI/Charts/Series/Bar.lua", "UI/Charts/Overlays/Overlays.lua",
    "UI/Charts/Core.lua", "UI/Charts/FrameCanvas.lua", "UI/Charts/ChartFrame.lua", "UI/Kit/Tooltip.lua",
    "UI/Kit/Window.lua", "Features/PriceChart.lua", "Features/ChartPanel.lua",
}

local function panelSetup()
    Fake.install()
    local S = load_addon(unpack(FILES))
    S.settings = {}
    S.Clock.now = function() return NOON end
    S.db = { scan = {} }
    S.store = S.ReadingStore.New(S.db)
    for h = 0, 47 do S.store:Add({ item = 7, ts = NOON - h * HOUR, price = 1000 + h, qty = 40 }) end
    -- the client knows items 7 and 8; 99999999 is not an item
    C_Item = { DoesItemExistByID = function(id) return id == 7 or id == 8 end }
    return S
end

local function cleanup() Fake.uninstall(); C_Item = nil end

test("the panel shows a 404 for an item that does not exist, and no chart", function()
    local S = panelSetup()
    local panel = S.ChartPanel.Create(UIParent)
    panel:SetItem(99999999)
    eq(panel.nameText.text:find("Item not found", 1, true) ~= nil, true)
    eq(panel.message.shown, true)
    eq(panel.message.text:find("No item has the ID 99999999", 1, true) ~= nil, true)
    eq(panel.chart.frame.shown, false, "the empty chart is hidden")
    eq(panel.legendKey.shown, false); eq(panel.legendTips.shown, false)
    for key, btn in pairs(panel.tfButtons) do eq(btn.enabled, false, "scope " .. key .. " disabled") end
    for key, btn in pairs(panel.toggleButtons) do eq(btn.enabled, false, "indicator " .. key .. " disabled") end
    eq(panel.priceText.text, "")
    -- hovering the (non-)name does not ask the game for a tooltip of nothing
    Fake.fire(panel.nameHit, "OnEnter")
    eq(Fake.called(GameTooltip, "SetItemByID"), false)
    cleanup()
end)

test("a failed item load turns an open panel into Item not found", function()
    local S = panelSetup()
    C_Item = { DoesItemExistByID = function() return true end } -- the API says yes, as it did for 99999999
    local panel = S.ChartPanel.Create(UIParent)
    panel:SetItem(424242)
    eq(panel.message.text:find("No prices recorded", 1, true) ~= nil, true, "looks like a normal unscanned item at first")
    -- the loader frame is the last frame the panel created
    local loader
    for _, e in ipairs(Fake.frames) do if e.events.ITEM_DATA_LOAD_RESULT then loader = e end end
    eq(loader ~= nil, true)
    Fake.fire(loader, "OnEvent", "ITEM_DATA_LOAD_RESULT", 424242, false)
    eq(panel.nameText.text:find("Item not found", 1, true) ~= nil, true)
    eq(panel.message.text:find("No item has the ID 424242", 1, true) ~= nil, true)
    cleanup()
end)

test("the panel explains a real item with no prices", function()
    local S = panelSetup()
    local panel = S.ChartPanel.Create(UIParent)
    panel:SetItem(8)
    eq(panel.message.shown, true)
    eq(panel.message.text:find("Open the Auction House", 1, true) ~= nil, true, "no scan yet")
    eq(panel.nameText.text, "item:8", "still shows the item's name, not an error")
    eq(panel.metaText.text, "no data yet")
    eq(panel.chart.frame.shown, false)

    S.db.scan.last = NOON - 600
    panel:Refresh()
    eq(panel.message.text:find("wasn't on the Auction House at the last scan (10m ago)", 1, true) ~= nil, true,
        panel.message.text)
    cleanup()
end)

test("moving from a message back to a real item restores the chart", function()
    local S = panelSetup()
    local panel = S.ChartPanel.Create(UIParent)
    panel:SetItem(99999999)
    eq(panel.chart.frame.shown, false)
    panel:SetItem(7)
    eq(panel.message.shown, false)
    eq(panel.chart.frame.shown, true)
    eq(panel.legendKey.shown, true, "tutorial legend is back")
    eq(panel.tfButtons["1D"].enabled, false, "1D is selected")
    eq(panel.tfButtons["1W"].enabled, true)
    eq(panel.priceText.text ~= "", true)
    eq(panel.statusKind, nil)
    cleanup()
end)

test("a resize or the deferred layout pass does not bring the legend back over a message", function()
    local S = panelSetup()
    local panel = S.ChartPanel.Create(UIParent)
    panel:SetItem(99999999)
    Fake.fire(panel.frame, "OnSizeChanged")
    panel:LayoutChart()
    eq(panel.legendKey.shown, false)
    eq(panel.chart.frame.shown, false)
    cleanup()
end)

test("the price window opens on a missing item and says so", function()
    local S = panelSetup()
    S.PriceChart.Show(99999999)
    eq(StockistChartWindow.shown, true)
    Fake.flush()
    cleanup()
end)

-- Commands -----------------------------------------------------------------------------------------

local function commandSetup()
    local S = load_addon("Core/EventBus.lua", "Core/Registry.lua", "Core/Format.lua", "Core/ItemInfo.lua",
        "Core/Commands.lua", "Data/Rollup.lua", "Data/ReadingStore.lua", "Data/Retention.lua", "Data/Tracked.lua",
        "Core/Config.lua", "Core/Clock.lua", "Features/StatusCommands.lua", "Features/DataCleanup.lua")
    local out = {}
    S.Print = function(msg) out[#out + 1] = msg end
    S.settings = { tracked = {}, retention = {} }
    S.tracked = S.Tracked.New(S.settings.tracked)
    S.store = S.ReadingStore.New({})
    S.db = { scan = {} }
    S.shown = {}
    S.PriceChart = { Show = function(id) S.shown[#S.shown + 1] = id end }
    C_Item = { DoesItemExistByID = function(id) return id ~= 99999999 end }
    return S, out
end

test("item IDs are parsed strictly", function()
    local S = commandSetup()
    eq(S.ParseItemID("2589"), 2589)
    eq(S.ParseItemID("  2589  "), 2589)
    eq(S.ParseItemID("|cff1eff00|Hitem:2589::::::::25:::::::|h[Linen Cloth]|h|r"), 2589)
    for _, bad in ipairs({ "abc", "", "0", "-5", "12.5", "1e3", "0x10", "12 34", "99999999999999", "item:" }) do
        is_nil(S.ParseItemID(bad), "'" .. bad .. "' is not an item")
    end
    is_nil(S.ParseItemID(nil))
    C_Item = nil
end)

test("/stockist chart with a bad argument says how to use it instead of opening something else", function()
    local S, out = commandSetup()
    S.store:Add({ item = 7, ts = 1000, price = 5, qty = 1 })
    S.Commands:Dispatch("chart abc")
    eq(out[#out], "usage: /stockist chart [itemID or item link]")
    eq(#S.shown, 0, "no window opened, and not the richest item")
    S.Commands:Dispatch("chart 12.5")
    eq(#S.shown, 0)
    C_Item = nil
end)

test("/stockist chart still opens a missing item's window so it can say 'not found', and the default works", function()
    local S, out = commandSetup()
    S.Commands:Dispatch("chart 99999999")
    eq(S.shown[1], 99999999)
    S.store:Add({ item = 7, ts = 1000, price = 5, qty = 1 })
    S.Commands:Dispatch("chart")
    eq(S.shown[2], 7, "no argument: the item with the most history")
    C_Item = nil
end)

test("/stockist chart with no data at all explains what to do", function()
    local S, out = commandSetup()
    S.Commands:Dispatch("chart")
    eq(#S.shown, 0)
    eq(out[#out]:find("Open the Auction House", 1, true) ~= nil, true)
    C_Item = nil
end)

test("/stockist item and /stockist track refuse an item that does not exist", function()
    local S, out = commandSetup()
    S.Commands:Dispatch("item 99999999")
    eq(out[#out], "no item has the ID 99999999.")
    S.Commands:Dispatch("track 99999999")
    eq(out[#out], "no item has the ID 99999999, so there is nothing to track.")
    eq(S.tracked:Has(99999999), false)
    S.Commands:Dispatch("track 2589")
    eq(S.tracked:Has(2589), true, "a real item is still tracked")
    -- an old entry for an item that has vanished can still be removed
    S.tracked:Add(99999999)
    S.Commands:Dispatch("untrack 99999999")
    eq(S.tracked:Has(99999999), false)
    C_Item = nil
end)

test("the commands cope when the client cannot say whether an item exists", function()
    local S, out = commandSetup()
    C_Item = nil
    S.Commands:Dispatch("track 424242")
    eq(S.tracked:Has(424242), true)
    S.Commands:Dispatch("item 424242")
    eq(out[#out]:find("no data yet", 1, true) ~= nil, true)
end)
