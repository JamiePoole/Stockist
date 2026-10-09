local ADDON_NAME, Stockist = ...

-- Looking after a running scan while the Auction House window is open:
--   * a banner under the window says a scan is running and to keep the window open, with how far it has got;
--   * pressing the window's close button during a scan asks first, because closing cancels it and a full scan
--     cannot be repeated for about 15 minutes.
-- Closing cannot be prevented outright: the server closes the window when the player walks away or enters
-- combat. This covers the deliberate closes, the commonest accident: the close button and Esc.
local Guard = {}
Stockist.AuctionHouseGuard = Guard

local POPUP = "STOCKIST_CLOSE_AUCTION_HOUSE"
local BANNER_HEIGHT = 28

---------------------------------------------------------------------------------------------------
-- Words (pure)
---------------------------------------------------------------------------------------------------

--- The banner's text for a scan at `progress` (0 to 1) in `phase` ("waiting" for the server, or "reading").
function Guard.BannerText(progress, phase)
    if phase == "waiting" or not phase then
        return "Stockist is scanning: waiting for the Auction House's answer. Keep this window open."
    end
    return ("Stockist is scanning (%d%%). Keep this window open."):format(math.floor((progress or 0) * 100))
end

--- The question asked when the close button is pressed during a scan.
function Guard.ConfirmText()
    return "A Stockist scan is in progress. Closing the Auction House now cancels it, and the next full scan "
        .. "cannot start for about 15 minutes. Close anyway?"
end

--- Is a scan running, so that closing needs confirming?
function Guard.ShouldConfirm()
    return Stockist.Scanner ~= nil and Stockist.Scanner.inProgress == true
end

---------------------------------------------------------------------------------------------------
-- Game side
---------------------------------------------------------------------------------------------------

local banner, installedOn

--- A strip along the top edge of the window, as wide as the window, where it cannot be missed (below the window
--- it fell behind the tabs, and off to one side).
local function buildBanner(ahFrame)
    local frame = CreateFrame("Frame", nil, ahFrame)
    frame:SetHeight(BANNER_HEIGHT)
    frame:SetPoint("BOTTOMLEFT", ahFrame, "TOPLEFT", 0, 2)
    frame:SetPoint("BOTTOMRIGHT", ahFrame, "TOPRIGHT", 0, 2)
    frame:SetFrameStrata("DIALOG")
    local back = frame:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0.05, 0.12, 0.28, 0.96)
    local bar = frame:CreateTexture(nil, "BORDER")
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("BOTTOMLEFT")
    bar:SetWidth(1)
    bar:SetColorTexture(0.2, 0.5, 1, 0.7)
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER")
    text:SetTextColor(0.75, 0.9, 1)
    frame:Hide()
    return { frame = frame, bar = bar, text = text }
end

local function showProgress(progress, phase)
    if not banner then return end
    banner.text:SetText(Guard.BannerText(progress, phase))
    local width = banner.frame:GetWidth()
    banner.bar:SetWidth(math.max(1, width * (phase == "waiting" and 0 or (progress or 0))))
    banner.frame:Show()
end

local function hideBanner()
    if banner then banner.frame:Hide() end
end

--- Close the window the way its own close button does.
local function closeWindow(ahFrame)
    if _G.HideUIPanel then return _G.HideUIPanel(ahFrame) end
    ahFrame:Hide()
end

--- Put the close confirmation in front of the window's close button. The button's own handler still does the
--- closing, once the player agrees.
local function guardCloseButton(ahFrame)
    local button = ahFrame.CloseButton or _G.AuctionHouseFrameCloseButton
    if not (button and button.SetScript) or button.stockistGuarded then return end
    button.stockistGuarded = true
    local original = button:GetScript("OnClick")
    local function close(self, ...)
        if original then return original(self, ...) end
        closeWindow(ahFrame)
    end
    button:SetScript("OnClick", function(self, ...)
        if Guard.ShouldConfirm() then
            local args = { ... }
            Guard.pending = function() close(self, unpack(args)) end
            StaticPopup_Show(POPUP)
        else
            close(self, ...)
        end
    end)
end

--- Esc: while a scan runs, a frame that listens to the keyboard takes the Esc press and asks first, instead of
--- letting the game close the window. It listens only during a scan, and lets every other key (and Esc when
--- there is no scan, or when our question is already up and wants it) go on to the game as usual.
local function buildKeyGuard(ahFrame)
    local keys = CreateFrame("Frame", nil, UIParent)
    keys:SetPropagateKeyboardInput(true)
    keys:EnableKeyboard(false)
    keys:SetScript("OnKeyDown", function(self, key)
        local askingAlready = _G.StaticPopup_Visible and _G.StaticPopup_Visible(POPUP)
        if key == "ESCAPE" and ahFrame:IsShown() and Guard.ShouldConfirm() and not askingAlready then
            self:SetPropagateKeyboardInput(false) -- this Esc is ours
            Guard.pending = function() closeWindow(ahFrame) end
            StaticPopup_Show(POPUP)
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    return keys
end

--- Listen for Esc only while there is something to protect.
local function setKeyGuard(on)
    if Guard.keys then Guard.keys:EnableKeyboard(on) end
end

--- Called each time the Auction House opens; builds the banner and the guards once for the window.
function Guard.Install()
    local ahFrame = _G.AuctionHouseFrame
    if not ahFrame or installedOn == ahFrame then return end
    installedOn = ahFrame
    banner = buildBanner(ahFrame)
    guardCloseButton(ahFrame)
    Guard.banner = banner
    Guard.keys = buildKeyGuard(ahFrame)
    setKeyGuard(Guard.ShouldConfirm())
end

_G.StaticPopupDialogs = _G.StaticPopupDialogs or {}
_G.StaticPopupDialogs[POPUP] = {
    text = Guard.ConfirmText(),
    button1 = "Close anyway",
    button2 = "Keep open",
    OnAccept = function()
        local close = Guard.pending
        Guard.pending = nil
        if close then close() end
    end,
    OnCancel = function() Guard.pending = nil end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

Stockist.Events:On("AH_OPENED", Guard.Install, Guard)
Stockist.Events:On("SCAN_STARTED", function() showProgress(0, "waiting"); setKeyGuard(true) end, Guard)
Stockist.Events:On("SCAN_PROGRESS", showProgress, Guard)
Stockist.Events:On("SCAN_COMPLETE", function() hideBanner(); setKeyGuard(false) end, Guard)
Stockist.Events:On("SCAN_FAILED", function() hideBanner(); setKeyGuard(false) end, Guard)
Stockist.Events:On("AH_CLOSED", function()
    hideBanner()
    setKeyGuard(false)
    Guard.pending = nil
    if _G.StaticPopup_Hide then _G.StaticPopup_Hide(POPUP) end -- the window is already gone: nothing left to confirm
end, Guard)
