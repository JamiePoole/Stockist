local ADDON_NAME, Stockist = ...

-- Plain-language explanations for everything on screen. Each topic has:
--   title   what it is called
--   short   one line, always shown in the tooltip
--   detail  longer explanation, shown too only when tutorial mode is on
-- UI code attaches a topic to a widget by key (see UI/Kit/Tooltip.lua); the wording lives in
-- Core/HelpTopics.lua so it can be reviewed and translated in one place.
local Help = { topics = Stockist.NewRegistry("help topic") }
Stockist.Help = Help

function Help.Register(key, title, short, detail)
    Help.topics:Register(key, { title = title, short = short, detail = detail })
end

--- Tutorial mode is a player setting; it starts on so new players get the explanations.
function Help.TutorialEnabled()
    local s = Stockist.settings
    if s and s.tutorial ~= nil then return s.tutorial end
    return true
end

function Help.SetTutorial(on)
    Stockist.settings.tutorial = on and true or false
    if Stockist.Print then
        Stockist.Print("tutorial tips " .. (Help.TutorialEnabled() and "on" or "off") .. ".")
    end
    Stockist.Events:Fire("TUTORIAL_CHANGED", Help.TutorialEnabled())
end

-- Legend colours: white heading, gold labels, grey descriptions; the tips section is blue.
local WHITE, GOLD, GREY, BLUE_HEAD, BLUE = "|cffffffff", "|cffffd100", "|cff9aa0a6", "|cff4da6ff", "|cff9fcdff"

--- The chart legend as two colour-coded text blocks: (key, tips). Nil, nil if no legend is defined.
function Help.Legend()
    local L = Help.legend
    if not L then return nil, nil end
    local key = { WHITE .. L.keyTitle .. "|r" }
    for _, entry in ipairs(L.key) do
        key[#key + 1] = GOLD .. entry[1] .. "|r  " .. GREY .. entry[2] .. "|r"
    end
    local tips = { BLUE_HEAD .. L.tipsTitle .. "|r" }
    for _, tip in ipairs(L.tips) do
        tips[#tips + 1] = BLUE .. "- " .. tip .. "|r"
    end
    return table.concat(key, "\n"), table.concat(tips, "\n")
end

--- The written guide for a panel as one colour-coded text, for the panel to show at its foot in tutorial mode:
--- a white heading, a key (gold labels, grey descriptions), then a blue "what it might mean" section of general
--- hints. Nil if the panel has no guide. Guides are registered in Help.guides (see Core/HelpTopics.lua).
Help.guides = Help.guides or {}
function Help.Guide(name)
    local G = Help.guides[name]
    if not G then return nil end
    local lines = { WHITE .. G.title .. "|r" }
    for _, entry in ipairs(G.key) do
        lines[#lines + 1] = GOLD .. entry[1] .. "|r  " .. GREY .. entry[2] .. "|r"
    end
    lines[#lines + 1] = BLUE_HEAD .. G.tipsTitle .. "|r"
    for _, tip in ipairs(G.tips) do
        lines[#lines + 1] = BLUE .. "- " .. tip .. "|r"
    end
    return table.concat(lines, "\n")
end

--- title, short, detail for a topic. `detail` is nil unless tutorial mode is on. Returns nil for
--- an unknown key.
function Help.Lines(key)
    local topic = Help.topics:Get(key)
    if not topic then return nil end
    return topic.title, topic.short, Help.TutorialEnabled() and topic.detail or nil
end
