local ADDON_NAME, Stockist = ...

-- Helpers for the plain text buttons used across windows.
--   Stockist.UI.Button.SetSelected(btn, true)   mark the active choice in a row of buttons
-- "Selected" is not "disabled": the button keeps its tooltip and normal text, it just shows which choice
-- is current (blue fill, white text) and no longer reacts to the mouse (no hover or pressed look).
-- Use Tooltip.SetAvailable for the other case, a choice that cannot be used right now.
local UI = Stockist.UI or {}
Stockist.UI = UI

local Button = {}
UI.Button = Button

local SELECTED_FILL = { 0.12, 0.40, 0.80, 0.9 }
local SELECTED_TEXT = { 1, 1, 1 }
local NORMAL_TEXT = { 1, 0.82, 0 } -- the game's button text gold

function Button.SetSelected(btn, selected)
    selected = selected and true or false
    btn.stockistSelected = selected

    if not btn.selectedFill then
        local fill = btn:CreateTexture(nil, "ARTWORK", nil, 3)
        fill:SetPoint("TOPLEFT", 2, -2)
        fill:SetPoint("BOTTOMRIGHT", -2, 2)
        fill:SetColorTexture(SELECTED_FILL[1], SELECTED_FILL[2], SELECTED_FILL[3], SELECTED_FILL[4])
        btn.selectedFill = fill
    end
    btn.selectedFill:SetShown(selected)

    -- The button that is already active has nothing to offer on hover or press.
    local highlight, pushed = btn:GetHighlightTexture(), btn:GetPushedTexture()
    if highlight then highlight:SetAlpha(selected and 0 or 1) end
    if pushed then pushed:SetAlpha(selected and 0 or 1) end

    local text = selected and SELECTED_TEXT or NORMAL_TEXT
    btn:GetFontString():SetTextColor(text[1], text[2], text[3])
end

function Button.IsSelected(btn)
    return btn.stockistSelected == true
end
