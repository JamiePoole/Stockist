local ADDON_NAME, Stockist = ...

-- A movable, resizable, closable window with a title and a content area. Position and size are
-- remembered per window name in the account-wide settings.
--   local win = Stockist.UI.Window.Create({ name = "StockistChart", title = "Chart", width = 640, height = 420 })
--   win.content   -- child frame to fill
--   win.frame     -- the window itself (Show/Hide/IsShown)
local UI = Stockist.UI or {}
Stockist.UI = UI

local Window = {}
UI.Window = Window

local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
}

-- Title bar layout: a 30px bar holds 24px controls (buttons, search box) with 3px above and below, all
-- centred vertically on the bar. PADDING is the space at the window's left and right edges and around the
-- content, the same everywhere, so the controls line up with the panels below.
local TITLE_HEIGHT = 30
local CONTROL_HEIGHT = 24
local PADDING = 8
local CONTENT_GAP = 4 -- between the title bar and the content
Window.TITLE_HEIGHT, Window.CONTROL_HEIGHT, Window.PADDING = TITLE_HEIGHT, CONTROL_HEIGHT, PADDING

local function saveGeometry(frame, name)
    if not (Stockist.settings and name) then return end
    local point, _, relPoint, x, y = frame:GetPoint()
    local w, h = frame:GetSize()
    Stockist.settings.windows = Stockist.settings.windows or {}
    Stockist.settings.windows[name] = { point = point, relPoint = relPoint, x = x, y = y, w = w, h = h }
end

local function restoreGeometry(frame, name, opts)
    local saved = Stockist.settings and Stockist.settings.windows and Stockist.settings.windows[name]
    if saved then
        frame:SetSize(saved.w or opts.width, saved.h or opts.height)
        frame:ClearAllPoints()
        frame:SetPoint(saved.point or "CENTER", UIParent, saved.relPoint or "CENTER", saved.x or 0, saved.y or 0)
    else
        frame:SetSize(opts.width, opts.height)
        frame:SetPoint("CENTER")
    end
end

function Window.Create(opts)
    local frame = CreateFrame("Frame", opts.name, UIParent, "BackdropTemplate")
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(0.04, 0.05, 0.07, 0.96)
    frame:SetBackdropBorderColor(1, 1, 1, 0.15)
    frame:SetFrameStrata("HIGH")
    -- Overlapping windows: what draws on top is decided by frame level, and a window's children sit above
    -- its own background. Without this, the child frames of an older window (a chart, say) are drawn over
    -- the background of a newer one. Top-level windows are raised whole, children included, when clicked,
    -- and we raise a window as it opens so it starts on top.
    frame:SetToplevel(true)
    frame:HookScript("OnShow", function(self) self:Raise() end)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true) -- the whole window is solid: clicks on empty areas must not reach the world behind
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(opts.minWidth or 360, opts.minHeight or 240)
    elseif frame.SetMinResize then
        frame:SetMinResize(opts.minWidth or 360, opts.minHeight or 240)
    end
    restoreGeometry(frame, opts.name, opts)

    -- Title bar doubles as the drag handle.
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(TITLE_HEIGHT)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() frame:StartMoving() end)
    bar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        saveGeometry(frame, opts.name)
    end)

    local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", bar, "LEFT", PADDING, 0)
    title:SetText(opts.title or "")

    -- Header buttons sit inside the title bar, right-aligned: close, then the tutorial toggle.
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetSize(CONTROL_HEIGHT, CONTROL_HEIGHT)
    close:SetPoint("RIGHT", bar, "RIGHT", -PADDING, 0)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- Tutorial mode is one account-wide setting shared by every window and tooltip.
    local help = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    help:SetSize(CONTROL_HEIGHT, CONTROL_HEIGHT)
    help:SetPoint("RIGHT", close, "LEFT", -4, 0)
    help:SetText("?")
    -- Bold, to stand up next to the close button's artwork: the outline thickens the strokes.
    local face, size = help:GetFontString():GetFont()
    help:GetFontString():SetFont(face or "Fonts\\FRIZQT__.TTF", (size or 12) + 2, "THICKOUTLINE")
    -- Sit above the draggable title bar, which spans the same strip and would otherwise take the click.
    help:SetFrameLevel(bar:GetFrameLevel() + 10)
    close:SetFrameLevel(bar:GetFrameLevel() + 10)
    help:RegisterForClicks("LeftButtonUp")
    local function paintHelp()
        local on = Stockist.Help.TutorialEnabled()
        UI.Button.SetActive(help, on)
        if not on then help:GetFontString():SetTextColor(0.7, 0.7, 0.7) end -- off: a dim grey "?"
    end
    help:SetScript("OnClick", function()
        Stockist.Help.SetTutorial(not Stockist.Help.TutorialEnabled())
        GameTooltip:Hide()
    end)
    UI.Tooltip.Attach(help, "tutorial")
    Stockist.Events:On("TUTORIAL_CHANGED", paintHelp)
    paintHelp()

    -- Optional search box in the middle of the title bar (opts.search). The caller wires it up, for example
    -- with Stockist.ItemPicker.Attach(win.searchBox, onPick).
    local search
    if opts.search then
        search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        search:SetAutoFocus(false)
        search:SetSize(280, CONTROL_HEIGHT)
        search:SetPoint("CENTER", bar, "CENTER", 0, 0)
        search:SetFrameLevel(bar:GetFrameLevel() + 10)
        local placeholder = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        placeholder:SetPoint("LEFT", 2, 0)
        placeholder:SetText("Search items")
        -- The placeholder shows while the box is empty and not being typed in. Whoever sets the box's own
        -- scripts (the item picker does) must call search.paintPlaceholder after changing its text or focus:
        -- SetScript replaces the hooks we could add here.
        local function paint() placeholder:SetShown((search:GetText() or "") == "" and not search:HasFocus()) end
        search.placeholder, search.paintPlaceholder = placeholder, paint
        search:HookScript("OnEditFocusLost", paint)
        paint()
    end

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", PADDING, -(TITLE_HEIGHT + CONTENT_GAP))
    content:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)

    -- Resize grip, bottom-right corner.
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        saveGeometry(frame, opts.name)
    end)

    if opts.name then tinsert(UISpecialFrames, opts.name) end -- Esc closes it
    frame:Hide()

    return { frame = frame, content = content, title = title, helpButton = help, searchBox = search }
end
