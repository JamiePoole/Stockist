local function ns()
    return load_addon("Core/EventBus.lua", "Core/Registry.lua", "Core/Format.lua", "Core/ItemInfo.lua",
        "Core/Help.lua", "Core/HelpTopics.lua")
end

-- Help -----------------------------------------------------------------------------------------

test("Help returns the long explanation only while tutorial mode is on", function()
    local S = ns()
    S.settings = {}
    local title, short, detail = S.Help.Lines("sma")
    eq(title, "Moving average (SMA)")
    eq(type(short), "string"); eq(type(detail), "string")

    S.Help.SetTutorial(false)
    local _, short2, detail2 = S.Help.Lines("sma")
    eq(short2, short)
    is_nil(detail2)

    S.Help.SetTutorial(true)
    eq(type(select(3, S.Help.Lines("sma"))), "string")
end)

test("tutorial mode defaults to on and fires an event when changed", function()
    local S = ns()
    S.settings = {}
    eq(S.Help.TutorialEnabled(), true)
    local seen
    S.Events:On("TUTORIAL_CHANGED", function(on) seen = on end)
    S.Help.SetTutorial(false)
    eq(seen, false)
    eq(S.Help.TutorialEnabled(), false)
end)

test("unknown help keys return nothing instead of erroring", function()
    local S = ns()
    S.settings = {}
    is_nil(S.Help.Lines("no-such-topic"))
end)

test("every topic has a title and a one-line description", function()
    local S = ns()
    S.settings = {}
    for _, key in ipairs(S.Help.topics:List()) do
        local topic = S.Help.topics:Get(key)
        eq(type(topic.title) == "string" and #topic.title > 0, true, key .. " title")
        eq(type(topic.short) == "string" and #topic.short > 0, true, key .. " short")
    end
end)

-- Item names ----------------------------------------------------------------------------------

test("Format.ColorCode and Colored", function()
    local S = ns()
    eq(S.Format.ColorCode(0, 1, 0), "|cff00ff00")
    eq(S.Format.ColorCode(0.12, 0.5, 1), "|cff1f80ff")
    eq(S.Format.Colored("Linen", 1, 1, 1), "|cffffffffLinen|r")
end)

test("Format.MoneyColored colours gold, silver and copper separately", function()
    local S = ns()
    local m = S.Format.MoneyColored(123456)
    eq(m, "|cffffd100" .. "12g|r |cffc7c7cf34s|r |cffeda65e56c|r")
    eq(S.Format.MoneyColored(120000), "|cffffd10012g|r")
    eq(S.Format.MoneyColored(0), "|cffeda65e0c|r")
end)

test("Format.MoneyDisplay uses the game's coin icons when they exist, coloured text otherwise", function()
    local S = ns()
    eq(S.Format.MoneyDisplay(50), S.Format.MoneyColored(50))
    GetCoinTextureString = function(c) return "icons:" .. c end
    eq(S.Format.MoneyDisplay(12345.4), "icons:12345")
    GetCoinTextureString = nil
end)

test("ColoredName wraps a cached item in its rarity colour", function()
    local S = ns()
    ITEM_QUALITY_COLORS = { [2] = { r = 0.12, g = 1, b = 0 } }
    C_Item = {
        GetItemNameByID = function() return "Peacebloom" end,
        GetItemQualityByID = function() return 2 end,
    }
    eq(S.ItemInfo.ColoredName(2447), "|cff1fff00Peacebloom|r")
    C_Item, ITEM_QUALITY_COLORS = nil, nil
end)

test("ColoredName asks the client to load an uncached item and falls back to its id", function()
    local S = ns()
    local requested
    C_Item = {
        GetItemNameByID = function() return nil end,
        RequestLoadItemDataByID = function(id) requested = id end,
    }
    eq(S.ItemInfo.ColoredName(777), "item:777")
    eq(requested, 777)
    C_Item = nil
end)

test("ColoredName leaves the name plain when the quality colour is unknown", function()
    local S = ns()
    C_Item = { GetItemNameByID = function() return "Mystery" end }
    eq(S.ItemInfo.ColoredName(5), "Mystery")
    C_Item = nil
end)
