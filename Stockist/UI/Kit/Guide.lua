local ADDON_NAME, Stockist = ...

-- A panel's written guide, shown at its foot while tutorial mode is on (the ? button in a window's title bar).
--   local guide = Stockist.UI.Guide.Create(panelFrame, "movers", { bottom = 0 })
--   local room = guide:Fit(maxHeight)    -- shows or hides it for the room there is; returns the height it takes
-- The text comes from Help.Guide(name). The guide is a block of wrapped text; when the room is less than its
-- height it is cut off (clipped) rather than squeezing the panel's real content, and when there is hardly any
-- room it is left out (the panel's hover tooltips still carry the same explanations).
local UI = Stockist.UI or {}
Stockist.UI = UI

local Guide = {}
Guide.__index = Guide
UI.Guide = Guide

local PAD = 8
local MIN_HEIGHT = 60 -- below this much room the guide is not shown at all

--- `opts.bottom`: distance from the panel's bottom edge (default 0), e.g. to sit above a button row.
function Guide.Create(panel, name, opts)
    opts = opts or {}
    local self = setmetatable({ name = name, panel = panel, bottom = opts.bottom or 0, height = 0 }, Guide)
    self.frame = CreateFrame("Frame", nil, panel)
    self.frame:SetClipsChildren(true)
    self.frame:SetPoint("BOTTOMLEFT", 0, self.bottom)
    self.frame:SetPoint("BOTTOMRIGHT", 0, self.bottom)
    self.frame:Hide()
    self.text = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.text:SetPoint("TOPLEFT", PAD, -PAD / 2)
    self.text:SetJustifyH("LEFT")
    self.text:SetJustifyV("TOP")
    self.text:SetWordWrap(true)
    self.text:SetTextColor(1, 1, 1)
    return self
end

--- Show the guide in at most `maxHeight` pixels (or hide it: tutorial mode off, no guide, or too little room).
--- Returns the height the guide now takes, 0 when hidden.
function Guide:Fit(maxHeight)
    local text = Stockist.Help.TutorialEnabled() and Stockist.Help.Guide(self.name) or nil
    if not text or maxHeight < MIN_HEIGHT then
        self.frame:Hide()
        self.height = 0
        return 0
    end
    local width = math.max(1, self.panel:GetWidth() - 2 * PAD)
    self.text:SetWidth(width)
    self.text:SetText(text)
    local wanted = self.text:GetStringHeight() + PAD
    self.height = math.min(wanted, maxHeight)
    self.frame:SetHeight(self.height)
    self.frame:Show()
    return self.height
end
