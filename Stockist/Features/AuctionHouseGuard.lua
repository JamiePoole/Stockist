local ADDON_NAME, Stockist = ...

-- Looking after a running scan while the Auction House window is open:
--   * a banner under the window says a scan is running and to keep the window open, with how far it has got;
--   * pressing the window's close button during a scan asks first, because closing cancels it and a full scan
--     cannot be repeated for about 15 minutes.
-- Closing cannot be prevented outright: the server closes the window when the player walks away or enters
-- combat, and Esc is not intercepted. This covers the deliberate close, the commonest accident.
local Guard = {}
Stockist.AuctionHouseGuard = Guard

local POPUP = "STOCKIST_CLOSE_AUCTION_HOUSE"
local BANNER_WIDTH, BANNER_HEIGHT = 380, 24

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

local function buildBanner(ahFrame)
    local frame = CreateFrame("Frame", nil, ahFrame)
    frame:SetSize(BANNER_WIDTH, BANNER_HEIGHT)
    frame:SetPoint("TOP", ahFrame, "BOTTOM", 0, -2)
    local back = frame:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0.06, 0.09, 0.14, 0.92)
    local bar = frame:CreateTexture(nil, "BORDER")
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("BOTTOMLEFT")
    bar:SetWidth(1)
    bar:SetColorTexture(0.2, 0.45, 0.9, 0.55)
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER")
    text:SetTextColor(0.6, 0.8, 1)
    frame:Hide()
    return { frame = frame, bar = bar, text = text }
end

local function showProgress(progress, phase)
    if not banner then return end
    banner.text:SetText(Guard.BannerText(progress, phase))
    banner.bar:SetWidth(math.max(1, BANNER_WIDTH * (phase == "waiting" and 0 or (progress or 0))))
    banner.frame:Show()
end

local function hideBanner()
    if banner then banner.frame:Hide() end
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
        if _G.HideUIPanel then return _G.HideUIPanel(ahFrame) end
        ahFrame:Hide()
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

--- Called each time the Auction House opens; builds the banner and the guard once for the window.
function Guard.Install()
    local ahFrame = _G.AuctionHouseFrame
    if not ahFrame or installedOn == ahFrame then return end
    installedOn = ahFrame
    banner = buildBanner(ahFrame)
    guardCloseButton(ahFrame)
    Guard.banner = banner
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
Stockist.Events:On("SCAN_STARTED", function() showProgress(0, "waiting") end, Guard)
Stockist.Events:On("SCAN_PROGRESS", showProgress, Guard)
Stockist.Events:On("SCAN_COMPLETE", hideBanner, Guard)
Stockist.Events:On("SCAN_FAILED", hideBanner, Guard)
Stockist.Events:On("AH_CLOSED", function()
    hideBanner()
    Guard.pending = nil
    if _G.StaticPopup_Hide then _G.StaticPopup_Hide(POPUP) end -- the window is already gone: nothing left to confirm
end, Guard)
