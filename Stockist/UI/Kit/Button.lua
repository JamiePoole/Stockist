local ADDON_NAME, Stockist = ...

-- Helpers for the plain text buttons used across windows. Two ways to show a button as "on":
--
--   Button.SetSelected(btn, bool, style)   one choice out of several (the time scope). The button keeps its
--                                          tooltip and normal text but no longer reacts to the mouse: no
--                                          hover, no pressed look, no text indent, no click.
--   Button.SetActive(btn, bool, style)     a switch (SMA, Bollinger, tutorial). Only the look changes: the
--                                          button stays fully clickable so it can be switched off again.
--
-- Use Tooltip.SetAvailable for a choice that cannot be used right now (that is "disabled", not "on").
--
-- The "on" look keeps the game's own button art (embossed border, shaded centre) in three steps:
--   1. the art is desaturated to grey, which leaves a grey border and the original shading;
--   2. a coloured layer is ADDED over the centre (additive blending brightens the shading instead of
--      replacing it; tinting the red art by multiplying could only ever darken it);
--   3. a vignette: soft dark fades along the four inner edges (normal blending, transparent to dark), so
--      the centre stays bright and the edges fall off like the stock art does.
-- `style` picks the colour of step 2. The numbers below are the knobs to turn if the look needs adjusting.
local UI = Stockist.UI or {}
Stockist.UI = UI

local Button = {}
UI.Button = Button

-- Colours added to the grey art (r, g, b); GLOW_ALPHA is how strongly.
Button.STYLES = {
    blue = { 0.10, 0.36, 0.85 },
    green = { 0.12, 0.72, 0.28 },
    gold = { 0.88, 0.64, 0.06 },
}
Button.STYLE_NAMES = { "blue", "green", "gold" }
local GLOW_ALPHA = 0.65
local INSET_X, INSET_Y = 4, 3          -- the layers stay inside the border
local VIGNETTE_SIDE = { width = 0.30, darkness = 0.55 }   -- left and right fades: fraction of width, strength at the edge
local VIGNETTE_CAP = { height = 0.38, darkness = 0.40 }   -- top and bottom fades
local ON_TEXT = { 1, 1, 1 }
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

--- A texture that fades from `from` to `to` (each { r, g, b, a }) along `orientation`
--- ("HORIZONTAL": left to right, "VERTICAL": bottom to top). The client changed the call's shape
--- between versions, so try the current one and then the older one; false if neither works.
local function setFade(tex, orientation, from, to)
    tex:SetColorTexture(1, 1, 1, 1)
    local ok = pcall(function()
        tex:SetGradient(orientation, CreateColor(from[1], from[2], from[3], from[4]), CreateColor(to[1], to[2], to[3], to[4]))
    end)
    if not ok and tex.SetGradientAlpha then
        ok = pcall(tex.SetGradientAlpha, tex, orientation, from[1], from[2], from[3], from[4], to[1], to[2], to[3], to[4])
    end
    return ok
end

--- The coloured layer and the four vignette fades, created once per button and shown only while "on".
local function buildLayers(btn)
    local layers = {}

    local glow = btn:CreateTexture(nil, "ARTWORK", nil, 3)
    glow:SetPoint("TOPLEFT", INSET_X, -INSET_Y)
    glow:SetPoint("BOTTOMRIGHT", -INSET_X, INSET_Y)
    glow:SetBlendMode("ADD")
    btn.selectedGlow = glow
    layers[#layers + 1] = glow

    local w, h = btn:GetWidth(), btn:GetHeight()
    local sideW, capH = math.floor(w * VIGNETTE_SIDE.width), math.floor(h * VIGNETTE_CAP.height)
    local side, cap = { 0, 0, 0, VIGNETTE_SIDE.darkness }, { 0, 0, 0, VIGNETTE_CAP.darkness }
    local clear = { 0, 0, 0, 0 }
    local function strip(p1, x1, y1, p2, x2, y2, size, horizontal, orientation, from, to)
        local tex = btn:CreateTexture(nil, "ARTWORK", nil, 4)
        tex:SetPoint(p1, x1, y1)
        tex:SetPoint(p2, x2, y2)
        if horizontal then tex:SetWidth(size) else tex:SetHeight(size) end
        tex:SetBlendMode("BLEND")
        if setFade(tex, orientation, from, to) then
            layers[#layers + 1] = tex
        else
            tex:Hide() -- without a fade it would be a solid white block; the coloured layer alone is fine
        end
    end
    --      anchors                                          size   horiz   orientation   dark end -> clear end
    strip("TOPLEFT", INSET_X, -INSET_Y, "BOTTOMLEFT", INSET_X, INSET_Y, sideW, true, "HORIZONTAL", side, clear)
    strip("TOPRIGHT", -INSET_X, -INSET_Y, "BOTTOMRIGHT", -INSET_X, INSET_Y, sideW, true, "HORIZONTAL", clear, side)
    strip("TOPLEFT", INSET_X, -INSET_Y, "TOPRIGHT", -INSET_X, -INSET_Y, capH, false, "VERTICAL", clear, cap)
    strip("BOTTOMLEFT", INSET_X, INSET_Y, "BOTTOMRIGHT", -INSET_X, INSET_Y, capH, false, "VERTICAL", cap, clear)

    btn.selectedLayers = layers
end

--- Draw (or remove) the coloured look: grey art, coloured layer, vignette, white text.
local function applyLook(btn, on, style)
    local colour = assert(Button.STYLES[style], "unknown button style '" .. tostring(style) .. "'")
    for _, tex in ipairs(bodyTextures(btn)) do
        tex:SetDesaturated(on)
        tex:SetVertexColor(1, 1, 1)
    end
    if not btn.selectedLayers then buildLayers(btn) end
    btn.selectedGlow:SetColorTexture(colour[1], colour[2], colour[3], GLOW_ALPHA)
    for _, layer in ipairs(btn.selectedLayers) do layer:SetShown(on) end
    local text = on and ON_TEXT or NORMAL_TEXT
    btn:GetFontString():SetTextColor(text[1], text[2], text[3])
end

function Button.SetSelected(btn, selected, style)
    selected = selected and true or false
    btn.stockistSelected = selected
    applyLook(btn, selected, style or "blue")

    -- The button that is already the current choice has nothing to offer on hover or press.
    local highlight, pushed = btn:GetHighlightTexture(), btn:GetPushedTexture()
    if highlight then highlight:SetAlpha(selected and 0 or 1) end
    if pushed then pushed:SetAlpha(selected and 0 or 1) end
    btn:SetPushedTextOffset(selected and 0 or 1, selected and 0 or -1) -- no indent of the label
    if selected then
        btn:RegisterForClicks() -- no clicks at all, so no pressed state either; hover still works
    else
        btn:RegisterForClicks("LeftButtonUp")
    end
end

function Button.IsSelected(btn)
    return btn.stockistSelected == true
end

function Button.SetActive(btn, on, style)
    on = on and true or false
    btn.stockistActive = on
    applyLook(btn, on, style or Button.ToggleStyle())
end

function Button.IsActive(btn)
    return btn.stockistActive == true
end

--- The colour used for switches (SMA, Bollinger, tutorial). A player setting, so it can be tried live with
--- /stockist togglestyle; the default is green, the usual colour for "on".
function Button.ToggleStyle()
    local s = Stockist.settings and Stockist.settings.toggleStyle
    return Button.STYLES[s] and s or "green"
end

function Button.SetToggleStyle(style)
    if not Button.STYLES[style] then return false end
    Stockist.settings.toggleStyle = style
    Stockist.Events:Fire("TOGGLE_STYLE_CHANGED", style)
    return true
end
