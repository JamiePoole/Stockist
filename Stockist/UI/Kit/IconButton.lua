local ADDON_NAME, Stockist = ...

-- A button with a small drawn icon instead of text, in the same style as the other header buttons.
-- Icons are drawn from line segments, so they need no texture files and scale with the button.
--   local b = Stockist.UI.IconButton.Create(parent, { icon = "popout", width = 24, height = 20 })
--   b:SetScript("OnClick", ...)
local UI = Stockist.UI or {}
Stockist.UI = UI

local IconButton = {}
UI.IconButton = IconButton

-- Segments are { x1, y1, x2, y2 } in whole pixels from the button's centre (x right, y up).
IconButton.ICONS = {
    -- "Open in a new window": a square with its top-right corner open and an arrow leaving through it.
    -- Drawn on a 10px grid (+/-5).
    popout = {
        { -5, -5, -5, 2 },  -- square: left
        { -5, -5, 2, -5 },  -- bottom
        { -5, 2, -1, 2 },   -- top, stopping short of the corner
        { 2, -5, 2, -1 },   -- right, stopping short of the corner
        { -1, -1, 5, 5 },   -- arrow shaft
        { 5, 5, 1, 5 },     -- arrowhead
        { 5, 5, 5, 1 },
    },
}

-- A light grey at rest, fully opaque; gold when hovered.
local NORMAL = { 0.85, 0.88, 0.92, 1 }
local HOVER = { 1, 0.82, 0, 1 }

function IconButton.Create(parent, opts)
    local segments = assert(IconButton.ICONS[opts.icon], "unknown icon '" .. tostring(opts.icon) .. "'")
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(opts.width or 24, opts.height or 20)

    local lines = {}
    for i, s in ipairs(segments) do
        local line = b:CreateLine(nil, "OVERLAY")
        line:SetThickness(1.5)
        line:SetStartPoint("CENTER", b, s[1], s[2])
        line:SetEndPoint("CENTER", b, s[3], s[4])
        lines[i] = line
    end
    local function paint(color)
        for _, line in ipairs(lines) do line:SetColorTexture(color[1], color[2], color[3], color[4]) end
    end
    paint(NORMAL)
    b:HookScript("OnEnter", function() paint(HOVER) end)
    b:HookScript("OnLeave", function() paint(NORMAL) end)
    b.lines = lines
    return b
end
