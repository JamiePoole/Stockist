local ADDON_NAME, Stockist = ...

-- Hover help for any widget, driven by the Help topics.
--   Stockist.UI.Tooltip.Attach(button, "sma")
-- The title and one-line description always show; the longer explanation joins them when tutorial
-- mode is on.
local UI = Stockist.UI or {}
Stockist.UI = UI

local Tooltip = {}
UI.Tooltip = Tooltip

-- Our own tooltip frame, never the shared GameTooltip. The whole game UI uses GameTooltip, and calling its methods
-- from addon code marks it as tainted: later, when the game fills it from its own secure code (a unit's health
-- bar, an item comparison), values the game marks secret get compared in code tainted by Stockist, and Lua
-- raises "attempt to compare a secret number value (execution tainted by 'Stockist')". A private tooltip of the
-- same kind shows our text and items without that.
local frame
function Tooltip.Frame()
    if not frame then
        frame = CreateFrame("GameTooltip", "StockistTooltip", UIParent, "GameTooltipTemplate")
    end
    return frame
end

local function show(frame, key, extra)
    local title, short, detail = Stockist.Help.Lines(key)
    if not title then return end
    Stockist.UI.Tooltip.Frame():SetOwner(frame, "ANCHOR_RIGHT")
    Stockist.UI.Tooltip.Frame():AddLine(title, 1, 1, 1)
    if short then Stockist.UI.Tooltip.Frame():AddLine(short, 0.8, 0.8, 0.8, true) end
    if detail then
        Stockist.UI.Tooltip.Frame():AddLine(" ")
        Stockist.UI.Tooltip.Frame():AddLine(detail, 0.55, 0.8, 1, true)
    end
    -- A situational line, e.g. why a button is disabled right now.
    local note = extra and extra()
    if note then
        Stockist.UI.Tooltip.Frame():AddLine(" ")
        Stockist.UI.Tooltip.Frame():AddLine(note, 1, 0.55, 0.25, true)
    end
    Stockist.UI.Tooltip.Frame():Show()
end

--- `extra` (optional) is a function returning one more line to show, or nil.
function Tooltip.Attach(frame, key, extra)
    frame:HookScript("OnEnter", function(self) show(self, key, extra) end)
    frame:HookScript("OnLeave", function() Stockist.UI.Tooltip.Frame():Hide() end)
end

--- Enable or disable a button while keeping its tooltip working. A normally disabled button stops
--- sending hover events, so there would be no tooltip to say why it is disabled. Where the client
--- allows hover while disabled we use a real disabled button; otherwise we fake it (greyed out,
--- still hoverable) and click handlers must ask Tooltip.IsAvailable.
function Tooltip.SetAvailable(button, available)
    if button.SetMotionScriptsWhileDisabled then
        button:SetMotionScriptsWhileDisabled(true)
        button:SetEnabled(available)
        button.stockistUnavailable = nil
    else
        button.stockistUnavailable = not available
        button:SetAlpha(available and 1 or 0.5)
    end
end

function Tooltip.IsAvailable(button)
    return not button.stockistUnavailable and button:IsEnabled()
end
