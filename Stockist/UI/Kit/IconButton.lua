local ADDON_NAME, Stockist = ...

-- A button with a small drawn icon instead of text, in the same style as the other header buttons.
-- Icons are drawn from line segments, so they need no texture files and scale with the button.
--   local b = Stockist.UI.IconButton.Create(parent, { icon = "popout", width = 24, height = 20 })
--   b:SetScript("OnClick", ...)
local UI = Stockist.UI or {}
Stockist.UI = UI

local IconButton = {}
UI.IconButton = IconButton

-- Segments are { x1, y1, x2, y2 } in pixels from the button's centre (x right, y up), inside +/-7.
IconButton.ICONS = {
    -- "Open in a new window": a square with its top-right corner open and an arrow leaving through it.
    popout = {
        { -6, -6, -6, 3 },  -- square: left
        { -6, -6, 3, -6 },  -- bottom
        { -6, 3, -1, 3 },   -- top, stopping short of the corner
        { 3, -6, 3, -1 },   -- right, stopping short of the corner
        { -1, -1, 6, 6 },   -- arrow shaft
        { 6, 6, 1, 6 },     -- arrowhead
        { 6, 6, 6, 1 },
    },
}

local NORMAL = { 0.85, 0.88, 0.92 }
local HOVER = { 1, 0.82, 0 }

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
        for _, line in ipairs(lines) do line:SetColorTexture(color[1], color[2], color[3], 1) end
    end
    paint(NORMAL)
    b:HookScript("OnEnter", function() paint(HOVER) end)
    b:HookScript("OnLeave", function() paint(NORMAL) end)
    b.lines = lines
    return b
end
