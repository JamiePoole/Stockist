local ADDON_NAME, Stockist = ...

-- Looking after a running scan while the Auction House window is open:
--   * a banner along the window's top edge says a scan is running and to keep the window open, with progress;
--   * pressing the window's close button, or Esc, during a scan asks first, because closing cancels it and a
--     full scan cannot be repeated for about 15 minutes.
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

--- Nothing here may touch the Auction House's own close button or hide its window from our code. Replacing the
--- button's click handler (the first version did) makes everything the click then does run tainted, and the
--- game's own close path then trips over protected calls ("tried to call the protected function
--- SpellStopCasting()"). So the guard is a separate transparent button laid over the close button that only
--- takes the mouse while a scan runs, and closing, once the player agrees, is asked of the server
--- (`C_AuctionHouse.CloseAuctionHouse`), whose answer the game's own code handles securely.

--- Is the guard standing aside for a moment, so the player's own click on the real close button goes through?
local allowed = false
local windowOpen = false -- the Auction House window is up (set by AH_OPENED and AH_CLOSED)

local function shouldGuard()
    return windowOpen and not allowed and Guard.ShouldConfirm()
end

--- Called after the player says "Close anyway": ask the server to close, and if the window is still up a moment
--- later, let the next click or Esc through untouched (nothing of ours in its way).
local function closeAfterAgreeing(ahFrame)
    allowed = true
    Guard.applyGuards()
    if _G.C_AuctionHouse and _G.C_AuctionHouse.CloseAuctionHouse then pcall(_G.C_AuctionHouse.CloseAuctionHouse) end
    C_Timer.After(0.5, function()
        if ahFrame:IsShown() and Stockist.Print then
            Stockist.Print("Click the Auction House's close button (or press Esc) again to close it.")
        end
    end)
    C_Timer.After(10, function()
        allowed = false
        Guard.applyGuards()
    end)
end

--- A transparent button over the window's close button. Inert (it does not take the mouse at all) except while a
--- scan runs, so with no scan the player's click reaches the real button untouched.
local function buildCloseCover(ahFrame)
    local button = ahFrame.CloseButton or _G.AuctionHouseFrameCloseButton
    if not button then return nil end
    local cover = CreateFrame("Button", nil, button:GetParent() or ahFrame)
    cover:SetAllPoints(button)
    cover:SetFrameLevel((button:GetFrameLevel() or 1) + 10)
    cover:RegisterForClicks("LeftButtonUp")
    cover:EnableMouse(false)
    cover:SetScript("OnClick", function()
        Guard.pending = function() closeAfterAgreeing(ahFrame) end
        StaticPopup_Show(POPUP)
    end)
    return cover
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
        if key == "ESCAPE" and ahFrame:IsShown() and shouldGuard() and not askingAlready then
            self:SetPropagateKeyboardInput(false) -- this Esc is ours
            Guard.pending = function() closeAfterAgreeing(ahFrame) end
            StaticPopup_Show(POPUP)
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    return keys
end

--- Listen for Esc, and take the mouse over the close button, only while there is something to protect.
function Guard.applyGuards()
    local on = shouldGuard()
    if Guard.keys then Guard.keys:EnableKeyboard(on) end
    if Guard.closeCover then Guard.closeCover:EnableMouse(on) end
end
local function setKeyGuard() Guard.applyGuards() end

--- Called each time the Auction House opens; builds the banner and the guards once for the window.
function Guard.Install()
    local ahFrame = _G.AuctionHouseFrame
    if not ahFrame or installedOn == ahFrame then return end
    installedOn = ahFrame
    banner = buildBanner(ahFrame)
    Guard.closeCover = buildCloseCover(ahFrame)
    Guard.banner = banner
    Guard.keys = buildKeyGuard(ahFrame)
    Guard.applyGuards()
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

Stockist.Events:On("AH_OPENED", function()
    windowOpen = true
    Guard.Install()
    Guard.applyGuards()
end, Guard)
Stockist.Events:On("SCAN_STARTED", function() showProgress(0, "waiting"); Guard.applyGuards() end, Guard)
Stockist.Events:On("SCAN_PROGRESS", showProgress, Guard)
Stockist.Events:On("SCAN_COMPLETE", function() hideBanner(); Guard.applyGuards() end, Guard)
Stockist.Events:On("SCAN_FAILED", function() hideBanner(); Guard.applyGuards() end, Guard)
Stockist.Events:On("AH_CLOSED", function()
    hideBanner()
    windowOpen = false
    allowed = false
    Guard.pending = nil
    Guard.applyGuards()
    if _G.StaticPopup_Hide then _G.StaticPopup_Hide(POPUP) end -- the window is already gone: nothing left to confirm
end, Guard)
