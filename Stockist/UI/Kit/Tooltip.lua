local ADDON_NAME, Stockist = ...

-- Hover help for any widget, driven by the Help topics.
--   Stockist.UI.Tooltip.Attach(button, "sma")
-- The title and one-line description always show; the longer explanation joins them when tutorial
-- mode is on.
local UI = Stockist.UI or {}
Stockist.UI = UI

local Tooltip = {}
UI.Tooltip = Tooltip

local function show(frame, key, extra)
    local title, short, detail = Stockist.Help.Lines(key)
    if not title then return end
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title, 1, 1, 1)
    if short then GameTooltip:AddLine(short, 0.8, 0.8, 0.8, true) end
    if detail then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(detail, 0.55, 0.8, 1, true)
    end
    -- A situational line, e.g. why a button is disabled right now.
    local note = extra and extra()
    if note then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(note, 1, 0.55, 0.25, true)
    end
    GameTooltip:Show()
end

--- `extra` (optional) is a function returning one more line to show, or nil.
function Tooltip.Attach(frame, key, extra)
    frame:HookScript("OnEnter", function(self) show(self, key, extra) end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end
