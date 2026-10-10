load_support("fake_wow")

--- The guard on its own, with a pretend Auction House window (a frame with a close button).
local function setup(withWindow)
    Fake.install()
    local S = load_addon("Core/EventBus.lua", "Features/AuctionHouseGuard.lua")
    S.Scanner = { inProgress = false, phase = nil, progress = 0 }
    local state = { closed = 0, serverClosed = 0 }
    -- the game's popup system must never be used: make any call a visible failure
    StaticPopup_Show = function() error("the guard must not use StaticPopup") end
    C_AuctionHouse = { CloseAuctionHouse = function() state.serverClosed = state.serverClosed + 1 end }
    if withWindow ~= false then
        local ah = CreateFrame("Frame", "AuctionHouseFrame", UIParent)
        ah.CloseButton = CreateFrame("Button", nil, ah)
        ah.CloseButton:SetScript("OnClick", function() state.closed = state.closed + 1 end)
        state.ah = ah
    end
    return S, state
end

local function cleanup()
    AuctionHouseFrame, StaticPopup_Show, C_AuctionHouse, StockistConfirmClose = nil, nil, nil, nil
    Fake.uninstall()
end

local function openScan(S)
    S.Events:Fire("AH_OPENED")
    S.Scanner.inProgress = true
    S.Events:Fire("SCAN_STARTED")
end

-- Words ---------------------------------------------------------------------------------------------

test("the banner says what is happening: waiting for the server, then how far along the reading is", function()
    local S = setup(false)
    local G = S.AuctionHouseGuard
    eq(G.BannerText(0, "waiting"):find("waiting for the Auction House", 1, true) ~= nil, true)
    eq(G.BannerText(0, "waiting"):find("Keep this window open", 1, true) ~= nil, true)
    eq(G.BannerText(0.4, "reading"), "Stockist is scanning (40%). Keep this window open.")
    eq(G.BannerText(1, "reading"):find("100%%") ~= nil, true)
    cleanup()
end)

test("the confirmation says what closing costs", function()
    local S = setup(false)
    local text = S.AuctionHouseGuard.ConfirmText()
    eq(text:find("cancels it", 1, true) ~= nil, true)
    eq(text:find("15 minutes", 1, true) ~= nil, true)
    cleanup()
end)

-- The banner ----------------------------------------------------------------------------------------

test("opening the Auction House builds a banner along the top of its window, hidden until a scan starts", function()
    local S, state = setup()
    S.Events:Fire("AH_OPENED")
    local banner = S.AuctionHouseGuard.banner
    eq(banner ~= nil, true)
    eq(banner.frame.shown, false, "hidden at first")
    local left, right
    for _, pt in ipairs(banner.frame.points) do
        if pt[1] == "BOTTOMLEFT" then left = pt elseif pt[1] == "BOTTOMRIGHT" then right = pt end
    end
    eq(left[2], state.ah); eq(left[3], "TOPLEFT", "sits on the window's top edge, left corner")
    eq(right[2], state.ah); eq(right[3], "TOPRIGHT", "as wide as the window, where it cannot be missed")
    cleanup()
end)

test("the banner follows the scan: shown waiting, then with percentages, hidden when it ends or the window closes", function()
    local S = setup()
    S.Events:Fire("AH_OPENED")
    local b = S.AuctionHouseGuard.banner
    S.Events:Fire("SCAN_STARTED")
    eq(b.frame.shown, true)
    eq(b.text.text:find("waiting for the Auction House", 1, true) ~= nil, true)
    S.Events:Fire("SCAN_PROGRESS", 0.55, "reading")
    eq(b.text.text:find("55%%") ~= nil, true, b.text.text)
    eq(b.bar.size[1] > 100, true, "the bar has grown")
    S.Events:Fire("SCAN_COMPLETE", 10, 0)
    eq(b.frame.shown, false, "gone when it completes")

    S.Events:Fire("SCAN_STARTED")
    S.Events:Fire("SCAN_FAILED", "x")
    eq(b.frame.shown, false, "and when it fails")
    S.Events:Fire("SCAN_STARTED")
    S.Events:Fire("AH_CLOSED")
    eq(b.frame.shown, false, "and when the window closes")
    cleanup()
end)

test("the banner is built once per window, however often the Auction House opens", function()
    local S = setup()
    S.Events:Fire("AH_OPENED")
    local first = S.AuctionHouseGuard.banner
    S.Events:Fire("AH_OPENED"); S.Events:Fire("AH_OPENED")
    eq(S.AuctionHouseGuard.banner, first)
    cleanup()
end)

test("with no Auction House window yet nothing is built and nothing fails; it installs once the window exists", function()
    local S = setup(false)
    S.Events:Fire("AH_OPENED")
    eq(S.AuctionHouseGuard.banner, nil)
    S.Events:Fire("SCAN_STARTED"); S.Events:Fire("SCAN_PROGRESS", 0.3, "reading"); S.Events:Fire("SCAN_COMPLETE", 1, 0)
    local ah = CreateFrame("Frame", "AuctionHouseFrame", UIParent)
    ah.CloseButton = CreateFrame("Button", nil, ah)
    S.Events:Fire("AH_OPENED")
    eq(S.AuctionHouseGuard.banner ~= nil, true)
    cleanup()
end)

-- The close button ----------------------------------------------------------------------------------

test("the real close button is never touched: its own click handler stays exactly as the game set it", function()
    local S, state = setup()
    local before = state.ah.CloseButton:GetScript("OnClick")
    openScan(S)
    eq(state.ah.CloseButton:GetScript("OnClick"), before, "no handler was replaced or wrapped")
    Fake.fire(state.ah.CloseButton, "OnClick")
    eq(state.closed, 1, "and it still closes the window by itself")
    cleanup()
end)

test("the cover over the close button takes the mouse only while a scan runs", function()
    local S = setup()
    S.Events:Fire("AH_OPENED")
    local cover = S.AuctionHouseGuard.closeCover
    eq(cover ~= nil, true)
    eq(cover.mouseEnabled, false, "inert with no scan: clicks reach the real button")
    S.Scanner.inProgress = true
    S.Events:Fire("SCAN_STARTED")
    eq(cover.mouseEnabled, true, "in the way during a scan")
    S.Scanner.inProgress = false
    S.Events:Fire("SCAN_COMPLETE", 1, 0)
    eq(cover.mouseEnabled, false, "and out of the way again")
    S.Scanner.inProgress = true
    S.Events:Fire("SCAN_STARTED")
    S.Events:Fire("AH_CLOSED")
    eq(cover.mouseEnabled, false, "and not once the window is gone")
    cleanup()
end)

test("clicking the cover during a scan asks with our own dialog, and agreeing asks the server to close", function()
    local S, state = setup()
    openScan(S)
    Fake.fire(S.AuctionHouseGuard.closeCover, "OnClick")
    local d = S.AuctionHouseGuard.dialog
    eq(d.frame.shown, true, "the question is up")
    eq(d.text.text:find("cancels it", 1, true) ~= nil, true)
    eq(d.accept.text, "Close anyway"); eq(d.cancel.text, "Keep open")
    eq(state.serverClosed, 0, "nothing closed yet")
    Fake.fire(d.accept, "OnClick")
    eq(d.frame.shown, false)
    eq(state.serverClosed, 1, "'Close anyway' asks the server, not the window")
    eq(state.closed, 0, "our code never presses or hides the game's own button or window")
    cleanup()
end)

test("answering 'Keep open' closes nothing and the next click is asked about again", function()
    local S, state = setup()
    openScan(S)
    local cover = S.AuctionHouseGuard.closeCover
    Fake.fire(cover, "OnClick")
    local d = S.AuctionHouseGuard.dialog
    Fake.fire(d.cancel, "OnClick")
    eq(d.frame.shown, false); eq(state.serverClosed, 0); eq(S.AuctionHouseGuard.pending, nil)
    Fake.fire(cover, "OnClick")
    eq(d.frame.shown, true, "asked again")
    cleanup()
end)

test("after 'Close anyway' the guard stands aside, so the player's own click on the real button goes through", function()
    local S, state = setup()
    state.ah.shown = true
    openScan(S)
    local cover = S.AuctionHouseGuard.closeCover
    Fake.fire(cover, "OnClick")
    Fake.fire(S.AuctionHouseGuard.dialog.accept, "OnClick")
    eq(cover.mouseEnabled, false, "out of the way: the next click reaches the real button")
    cleanup()
end)

test("if the window closes by itself (walking away) the question disappears and a late answer does nothing", function()
    local S, state = setup()
    openScan(S)
    Fake.fire(S.AuctionHouseGuard.closeCover, "OnClick")
    local d = S.AuctionHouseGuard.dialog
    S.Events:Fire("AH_CLOSED")
    eq(d.frame.shown, false, "the question was taken down")
    eq(S.AuctionHouseGuard.pending, nil)
    Fake.fire(d.accept, "OnClick")
    eq(state.serverClosed, 0)
    cleanup()
end)

test("when the scan ends the question goes away, as there is nothing left to cancel", function()
    local S, state = setup()
    openScan(S)
    Fake.fire(S.AuctionHouseGuard.closeCover, "OnClick")
    S.Scanner.inProgress = false
    S.Events:Fire("SCAN_COMPLETE", 3, 0)
    eq(S.AuctionHouseGuard.dialog.frame.shown, false)
    cleanup()
end)

test("the cover is built once per window, however often the Auction House opens", function()
    local S = setup()
    S.Events:Fire("AH_OPENED")
    local first = S.AuctionHouseGuard.closeCover
    S.Events:Fire("AH_OPENED"); S.Events:Fire("AH_OPENED")
    eq(S.AuctionHouseGuard.closeCover, first)
    cleanup()
end)

test("with no scanner at all there is nothing to protect and nothing in the way", function()
    local S = setup()
    S.Events:Fire("AH_OPENED")
    S.Scanner = nil
    S.Events:Fire("SCAN_COMPLETE", 1, 0)
    eq(S.AuctionHouseGuard.closeCover.mouseEnabled, false)
    cleanup()
end)

-- Esc ------------------------------------------------------------------------------------------------

--- Set up the guard and capture what it does to the keyboard.
local function withKeys()
    local S, state = setup()
    S.Events:Fire("AH_OPENED")
    state.keys = S.AuctionHouseGuard.keys
    state.propagate, state.listening = nil, nil
    state.keys.SetPropagateKeyboardInput = function(_, v) state.propagate = v end
    state.keys.EnableKeyboard = function(_, on) state.listening = on end
    state.ah.shown = true
    return S, state
end

test("the keyboard guard listens only while a scan runs (or our question is up)", function()
    local S, state = withKeys()
    S.Scanner.inProgress = true
    S.Events:Fire("SCAN_STARTED")
    eq(state.listening, true, "listening during a scan")
    S.Scanner.inProgress = false
    S.Events:Fire("SCAN_COMPLETE", 1, 0)
    eq(state.listening, false, "and not after")
    S.Events:Fire("SCAN_STARTED")
    S.Events:Fire("SCAN_FAILED", "x")
    eq(state.listening, false)
    S.Events:Fire("SCAN_STARTED")
    S.Events:Fire("AH_CLOSED")
    eq(state.listening, false, "and not once the window is gone")
    cleanup()
end)

test("Esc during a scan is taken and asks first; closing happens only if the player agrees", function()
    local S, state = withKeys()
    S.Scanner.inProgress = true
    Fake.fire(state.keys, "OnKeyDown", "ESCAPE")
    eq(state.propagate, false, "the game does not get this Esc")
    local d = S.AuctionHouseGuard.dialog
    eq(d.frame.shown, true, "the question was put")
    eq(state.serverClosed, 0)
    Fake.fire(d.accept, "OnClick")
    eq(state.serverClosed, 1, "'Close anyway' asks the server to close")
    cleanup()
end)

test("Esc while our question is up answers it with 'Keep open', and the window stays", function()
    local S, state = withKeys()
    S.Scanner.inProgress = true
    Fake.fire(state.keys, "OnKeyDown", "ESCAPE")
    local d = S.AuctionHouseGuard.dialog
    eq(d.frame.shown, true)
    Fake.fire(state.keys, "OnKeyDown", "ESCAPE")
    eq(d.frame.shown, false, "dismissed by the second Esc")
    eq(state.propagate, false, "and that Esc was not passed on to close the window")
    eq(state.serverClosed, 0); eq(S.AuctionHouseGuard.pending, nil)
    cleanup()
end)

test("every other key, and Esc with no scan, go on to the game untouched", function()
    local S, state = withKeys()
    S.Scanner.inProgress = true
    for _, key in ipairs({ "A", "ENTER", "SPACE", "F1", "TAB" }) do
        state.propagate = nil
        Fake.fire(state.keys, "OnKeyDown", key)
        eq(state.propagate, true, key .. " passes through")
    end
    eq(S.AuctionHouseGuard.DialogShown(), false, "none of them asked anything")
    S.Scanner.inProgress = false
    Fake.fire(state.keys, "OnKeyDown", "ESCAPE")
    eq(state.propagate, true, "Esc with nothing to protect closes as usual")
    eq(S.AuctionHouseGuard.DialogShown(), false)
    cleanup()
end)

test("Esc is only taken while the Auction House window is actually open", function()
    local S, state = withKeys()
    S.Scanner.inProgress = true
    state.ah.shown = false
    Fake.fire(state.keys, "OnKeyDown", "ESCAPE")
    eq(state.propagate, true)
    eq(S.AuctionHouseGuard.DialogShown(), false)
    cleanup()
end)

-- Not the game's own shared things -------------------------------------------------------------------

test("the guard never uses the game's popup system, which would taint its shared popup frames", function()
    local S = setup()
    local touched = false
    StaticPopupDialogs = setmetatable({}, { __newindex = function() touched = true end })
    openScan(S)
    Fake.fire(S.AuctionHouseGuard.closeCover, "OnClick") -- StaticPopup_Show is a trap that errors if called
    eq(S.AuctionHouseGuard.dialog.frame.shown, true)
    eq(touched, false, "no entry was added to StaticPopupDialogs either")
    StaticPopupDialogs = nil
    cleanup()
end)

test("in combat the scan guard's keyboard listener takes no key at all", function()
    local S, state = withKeys()
    S.Scanner.inProgress = true
    InCombatLockdown = function() return true end
    state.propagate = nil
    Fake.fire(state.keys, "OnKeyDown", "ESCAPE")
    eq(state.propagate, true)
    eq(S.AuctionHouseGuard.DialogShown(), false, "no question put in combat")
    InCombatLockdown = nil
    cleanup()
end)
