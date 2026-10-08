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

--- title, short, detail for a topic. `detail` is nil unless tutorial mode is on. Returns nil for
--- an unknown key.
function Help.Lines(key)
    local topic = Help.topics:Get(key)
    if not topic then return nil end
    return topic.title, topic.short, Help.TutorialEnabled() and topic.detail or nil
end
