load_support("fake_wow")

--- The guard on its own, with a pretend Auction House window (a frame with a close button) and pretend popups.
local function setup(withWindow)
    Fake.install()
    local S = load_addon("Core/EventBus.lua", "Features/AuctionHouseGuard.lua")
    S.Scanner = { inProgress = false, phase = nil, progress = 0 }
    local state = { closed = 0, popups = {}, hidden = {} }
    StaticPopup_Show = function(name) state.popups[#state.popups + 1] = name end
    StaticPopup_Hide = function(name) state.hidden[#state.hidden + 1] = name end
    if withWindow ~= false then
        local ah = CreateFrame("Frame", "AuctionHouseFrame", UIParent)
        ah.CloseButton = CreateFrame("Button", nil, ah)
        ah.CloseButton:SetScript("OnClick", function() state.closed = state.closed + 1 end)
        state.ah = ah
    end
    return S, state
end

local function cleanup()
    AuctionHouseFrame, StaticPopup_Show, StaticPopup_Hide, StaticPopupDialogs = nil, nil, nil, nil
    Fake.uninstall()
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
    eq(StaticPopupDialogs["STOCKIST_CLOSE_AUCTION_HOUSE"].button1, "Close anyway")
    eq(StaticPopupDialogs["STOCKIST_CLOSE_AUCTION_HOUSE"].button2, "Keep open")
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
    local S, state = setup(false)
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

--- A close request the game would act on: counts C_AuctionHouse.CloseAuctionHouse calls.
local function watchClose(state)
    state.serverClosed = 0
    C_AuctionHouse = { CloseAuctionHouse = function() state.serverClosed = state.serverClosed + 1 end }
end

test("the real close button is never touched: its own click handler stays exactly as the game set it", function()
    local S, state = setup()
    local before = state.ah.CloseButton:GetScript("OnClick")
    S.Events:Fire("AH_OPENED")
    S.Scanner.inProgress = true
    S.Events:Fire("SCAN_STARTED")
    eq(state.ah.CloseButton:GetScript("OnClick"), before, "no handler was replaced or wrapped")
    Fake.fire(state.ah.CloseButton, "OnClick")
    eq(state.closed, 1, "and it still closes the window by itself")
    cleanup()
end)

test("the cover over the close button takes the mouse only while a scan runs", function()
    local S, state = setup()
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

test("clicking the cover during a scan asks first, and agreeing asks the server to close", function()
    local S, state = setup()
    watchClose(state)
    S.Events:Fire("AH_OPENED")
    S.Scanner.inProgress = true
    S.Events:Fire("SCAN_STARTED")
    Fake.fire(S.AuctionHouseGuard.closeCover, "OnClick")
    eq(state.popups[1], "STOCKIST_CLOSE_AUCTION_HOUSE", "the question was put")
    eq(state.serverClosed, 0, "nothing closed yet")
    StaticPopupDialogs["STOCKIST_CLOSE_AUCTION_HOUSE"].OnAccept()
    eq(state.serverClosed, 1, "'Close anyway' asks the server, not the window")
    eq(state.closed, 0, "our code never presses or hides the game's own button or window")
    C_AuctionHouse = nil
    cleanup()
end)

test("answering 'Keep open' closes nothing and the next click is asked about again", function()
    local S, state = setup()
    watchClose(state)
    S.Events:Fire("AH_OPENED")
    S.Scanner.inProgress = true
    S.Events:Fire("SCAN_STARTED")
    local cover = S.AuctionHouseGuard.closeCover
    Fake.fire(cover, "OnClick")
    StaticPopupDialogs["STOCKIST_CLOSE_AUCTION_HOUSE"].OnCancel()
    eq(state.serverClosed, 0); eq(S.AuctionHouseGuard.pending, nil)
    Fake.fire(cover, "OnClick")
    eq(#state.popups, 2, "asked again")
    C_AuctionHouse = nil
    cleanup()
end)

test("after 'Close anyway' the guard stands aside, so the player's own click on the real button goes through", function()
    local S, state = setup()
    watchClose(state)
    state.ah.shown = true
    S.Events:Fire("AH_OPENED")
    S.Scanner.inProgress = true
    S.Events:Fire("SCAN_STARTED")
    local cover = S.AuctionHouseGuard.closeCover
    Fake.fire(cover, "OnClick")
    StaticPopupDialogs["STOCKIST_CLOSE_AUCTION_HOUSE"].OnAccept()
    eq(cover.mouseEnabled, false, "out of the way: the next click reaches the real button")
    eq(S.AuctionHouseGuard.keys.keyboard ~= true, true)
    C_AuctionHouse = nil
    cleanup()
end)

test("if the window closes by itself (walking away) the question disappears", function()
    local S, state = setup()
    S.Events:Fire("AH_OPENED")
    S.Scanner.inProgress = true
    S.Events:Fire("SCAN_STARTED")
    Fake.fire(S.AuctionHouseGuard.closeCover, "OnClick")
    S.Events:Fire("AH_CLOSED")
    eq(state.hidden[1], "STOCKIST_CLOSE_AUCTION_HOUSE", "the popup was taken down")
    eq(S.AuctionHouseGuard.pending, nil, "and a late 'Close anyway' does nothing")
    watchClose(state)
    StaticPopupDialogs["STOCKIST_CLOSE_AUCTION_HOUSE"].OnAccept()
    eq(state.serverClosed, 0)
    C_AuctionHouse = nil
    cleanup()
end)

test("the cover is built once per window, however often the Auction House opens", function()
    local S, state = setup()
    S.Events:Fire("AH_OPENED")
    local first = S.AuctionHouseGuard.closeCover
    S.Events:Fire("AH_OPENED"); S.Events:Fire("AH_OPENED")
    eq(S.AuctionHouseGuard.closeCover, first)
    cleanup()
end)

test("with no scanner at all there is nothing to protect and nothing in the way", function()
    local S, state = setup()
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

test("the keyboard guard listens only while a scan runs", function()
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
    eq(state.popups[1], "STOCKIST_CLOSE_AUCTION_HOUSE", "the question was put")
    watchClose(state)
    StaticPopupDialogs["STOCKIST_CLOSE_AUCTION_HOUSE"].OnAccept()
    eq(state.serverClosed, 1, "'Close anyway' asks the server to close")
    C_AuctionHouse = nil
    cleanup()
end)

test("Esc answered with 'Keep open' leaves the window alone", function()
    local S, state = withKeys()
    S.Scanner.inProgress = true
    Fake.fire(state.keys, "OnKeyDown", "ESCAPE")
    watchClose(state)
    StaticPopupDialogs["STOCKIST_CLOSE_AUCTION_HOUSE"].OnCancel()
    eq(state.serverClosed, 0); eq(S.AuctionHouseGuard.pending, nil)
    C_AuctionHouse = nil
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
    eq(#state.popups, 0, "none of them asked anything")
    S.Scanner.inProgress = false
    Fake.fire(state.keys, "OnKeyDown", "ESCAPE")
    eq(state.propagate, true, "Esc with nothing to protect closes as usual")
    eq(#state.popups, 0)
    cleanup()
end)

test("when our question is already showing, Esc goes to it (to dismiss it) and does not ask again", function()
    local S, state = withKeys()
    S.Scanner.inProgress = true
    StaticPopup_Visible = function(name) return name == "STOCKIST_CLOSE_AUCTION_HOUSE" end
    Fake.fire(state.keys, "OnKeyDown", "ESCAPE")
    eq(state.propagate, true)
    eq(#state.popups, 0)
    StaticPopup_Visible = nil
    cleanup()
end)

test("Esc is only taken while the Auction House window is actually open", function()
    local S, state = withKeys()
    S.Scanner.inProgress = true
    state.ah.shown = false
    Fake.fire(state.keys, "OnKeyDown", "ESCAPE")
    eq(state.propagate, true)
    eq(#state.popups, 0)
    cleanup()
end)

test("opening the Auction House mid-scan starts the keyboard guard straight away", function()
    local S, state = setup()
    S.Scanner.inProgress = true
    local listening
    S.Events:Fire("AH_OPENED")
    local keys = S.AuctionHouseGuard.keys
    eq(keys ~= nil, true)
    cleanup()
end)
