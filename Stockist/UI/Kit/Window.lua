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

local TITLE_HEIGHT = 24

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
    title:SetPoint("LEFT", 10, 0)
    title:SetText(opts.title or "")

    -- Header buttons sit inside the title bar, right-aligned: close, then the tutorial toggle.
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -3, -1)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- Tutorial mode is one account-wide setting shared by every window and tooltip.
    local help = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    help:SetSize(22, 22)
    help:SetPoint("RIGHT", close, "LEFT", -2, 0)
    help:SetText("?")
    local function paintHelp()
        local fs = help:GetFontString()
        if Stockist.Help.TutorialEnabled() then
            fs:SetTextColor(0.3, 1, 0.5)
        else
            fs:SetTextColor(0.7, 0.7, 0.7)
        end
    end
    help:SetScript("OnClick", function()
        Stockist.Help.SetTutorial(not Stockist.Help.TutorialEnabled())
        GameTooltip:Hide()
    end)
    UI.Tooltip.Attach(help, "tutorial")
    Stockist.Events:On("TUTORIAL_CHANGED", paintHelp)
    paintHelp()

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", 8, -TITLE_HEIGHT - 4)
    content:SetPoint("BOTTOMRIGHT", -8, 8)

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

    return { frame = frame, content = content, title = title }
end
