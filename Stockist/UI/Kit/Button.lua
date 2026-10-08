local ADDON_NAME, Stockist = ...

-- Helpers for the plain text buttons used across windows.
--   Stockist.UI.Button.SetSelected(btn, true)   mark the active choice in a row of buttons
-- "Selected" is not "disabled": the button keeps its tooltip and normal text, it just shows which choice
-- is current and no longer reacts to the mouse (no hover, no pressed look, no text indent, no click).
-- Use Tooltip.SetAvailable for the other case, a choice that cannot be used right now.
--
-- The selected look keeps the game's own button art (embossed border, shaded centre) and recolours it
-- blue: the textures are desaturated to grey, then tinted. A flat fill would lose the bevel.
local UI = Stockist.UI or {}
Stockist.UI = UI

local Button = {}
UI.Button = Button

local SELECTED_TINT = { 0.35, 0.60, 1.00 }
local SELECTED_TEXT = { 1, 1, 1 }
local NORMAL_TEXT = { 1, 0.82, 0 } -- the game's button text gold

--- The textures that make up the button's body (not its hover glow). Which of these exist depends on the
--- client's version of the template, so gather every one we can find.
local function bodyTextures(btn)
    if btn.stockistBody then return btn.stockistBody end
    local list, seen = {}, {}
    local highlight = btn:GetHighlightTexture()
    local function add(tex)
        -- Template pieces are tables when present; anything else under that name is not a texture.
        if type(tex) == "table" and tex ~= highlight and not seen[tex] and tex.SetVertexColor then
            seen[tex] = true
            list[#list + 1] = tex
        end
    end
    add(btn:GetNormalTexture())
    for _, key in ipairs({ "Left", "Middle", "Right", "Center" }) do add(btn[key]) end
    for _, region in ipairs({ btn:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "Texture" then add(region) end
    end
    btn.stockistBody = list
    return list
end

function Button.SetSelected(btn, selected)
    selected = selected and true or false
    btn.stockistSelected = selected

    for _, tex in ipairs(bodyTextures(btn)) do
        if selected then
            tex:SetDesaturated(true)
            tex:SetVertexColor(SELECTED_TINT[1], SELECTED_TINT[2], SELECTED_TINT[3])
        else
            tex:SetDesaturated(false)
            tex:SetVertexColor(1, 1, 1)
        end
    end

    -- The button that is already active has nothing to offer on hover or press.
    local highlight, pushed = btn:GetHighlightTexture(), btn:GetPushedTexture()
    if highlight then highlight:SetAlpha(selected and 0 or 1) end
    if pushed then pushed:SetAlpha(selected and 0 or 1) end
    btn:SetPushedTextOffset(selected and 0 or 1, selected and 0 or -1) -- no indent of the label
    if selected then
        btn:RegisterForClicks() -- no clicks at all, so no pressed state either; hover still works
    else
        btn:RegisterForClicks("LeftButtonUp")
    end

    local text = selected and SELECTED_TEXT or NORMAL_TEXT
    btn:GetFontString():SetTextColor(text[1], text[2], text[3])
end

function Button.IsSelected(btn)
    return btn.stockistSelected == true
end
