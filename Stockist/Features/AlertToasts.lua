local ADDON_NAME, Stockist = ...

-- The toast presenter: a small card near the top of the screen for each alert, newest on top, gone after a few
-- seconds. Click one to show its item in the chart (opening the workspace if it is closed); right-click to
-- dismiss it. At most three are shown; a fourth pushes the oldest off.
local Toasts = { pool = {}, active = {} }
Stockist.AlertToasts = Toasts

local WIDTH, HEIGHT, GAP = 340, 54, 6
local TOP_OFFSET = 140
local LIFETIME = 8
local MAX_SHOWN = 3
local COLOURS = { alert = { 1, 0.82, 0 }, warn = { 1, 0.6, 0.2 }, info = { 0.6, 0.8, 1 } }

local function layout()
    for i, toast in ipairs(Toasts.active) do
        toast.frame:ClearAllPoints()
        toast.frame:SetPoint("TOP", UIParent, "TOP", 0, -TOP_OFFSET - (i - 1) * (HEIGHT + GAP))
    end
end

--- Take a toast off the screen and keep its frame for the next one.
local function dismiss(toast)
    toast.frame:Hide()
    for i, t in ipairs(Toasts.active) do
        if t == toast then
            table.remove(Toasts.active, i)
            Toasts.pool[#Toasts.pool + 1] = toast
            break
        end
    end
    layout()
end

local function build()
    local frame = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    frame:SetBackdropColor(0.06, 0.07, 0.09, 0.96)
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local toast = { frame = frame }
    toast.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    toast.title:SetPoint("TOPLEFT", 10, -7)
    toast.title:SetPoint("TOPRIGHT", -10, -7)
    toast.title:SetJustifyH("LEFT")
    toast.title:SetWordWrap(false)
    toast.body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    toast.body:SetPoint("TOPLEFT", toast.title, "BOTTOMLEFT", 0, -3)
    toast.body:SetPoint("RIGHT", -10, 0)
    toast.body:SetJustifyH("LEFT")
    toast.body:SetJustifyV("TOP")
    frame:SetScript("OnClick", function(_, button)
        if button == "LeftButton" and toast.itemID and Stockist.Link then
            Stockist.Link.Select("A", toast.itemID)
            if Stockist.Workspace then Stockist.Workspace.Reveal() end
        end
        dismiss(toast)
    end)
    frame:Hide()
    return toast
end

--- Show an alert as a toast. `alert`: { severity, title, body, itemID }.
function Toasts.Show(alert)
    local toast = table.remove(Toasts.pool) or build()
    toast.serial = (toast.serial or 0) + 1
    local mine = toast.serial
    toast.itemID = alert.itemID
    local c = COLOURS[alert.severity] or COLOURS.info
    toast.title:SetText(alert.title or "")
    toast.title:SetTextColor(c[1], c[2], c[3])
    toast.body:SetText(alert.body or "")
    toast.frame:SetBackdropBorderColor(c[1], c[2], c[3], 0.8)
    toast.frame:Show()
    table.insert(Toasts.active, 1, toast)
    while #Toasts.active > MAX_SHOWN do
        dismiss(Toasts.active[#Toasts.active])
    end
    layout()
    C_Timer.After(LIFETIME, function()
        if toast.serial == mine and toast.frame:IsShown() then dismiss(toast) end
    end)
    return toast
end

Stockist.Alerts.presenters:Register("toast", { show = Toasts.Show })
