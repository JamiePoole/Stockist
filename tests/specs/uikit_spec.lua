-- The tooltip kit's availability helper, against stand-in buttons.

local function kit()
    return load_addon("Core/Registry.lua", "UI/Kit/Tooltip.lua").UI.Tooltip
end

local function fakeButton(canHoverWhileDisabled)
    local b = { enabled = true, alpha = 1, motion = false }
    function b:SetEnabled(v) self.enabled = v end
    function b:IsEnabled() return self.enabled end
    function b:SetAlpha(a) self.alpha = a end
    if canHoverWhileDisabled then
        function b:SetMotionScriptsWhileDisabled(v) self.motion = v end
    end
    return b
end

test("where the client allows it, a disabled button keeps sending hover events", function()
    local T = kit()
    local b = fakeButton(true)
    T.SetAvailable(b, false)
    eq(b.enabled, false)
    eq(b.motion, true, "hover (and so the tooltip) still works while disabled")
    eq(T.IsAvailable(b), false)
    T.SetAvailable(b, true)
    eq(b.enabled, true)
    eq(T.IsAvailable(b), true)
end)

test("without that client support the button is faked: greyed out, still enabled, clicks refused", function()
    local T = kit()
    local b = fakeButton(false)
    T.SetAvailable(b, false)
    eq(b.enabled, true, "stays enabled so hover keeps working")
    eq(b.alpha, 0.5)
    eq(T.IsAvailable(b), false, "click handlers must ignore it")
    T.SetAvailable(b, true)
    eq(b.alpha, 1)
    eq(T.IsAvailable(b), true)
end)

test("switching between the two states leaves no stale flag", function()
    local T = kit()
    local b = fakeButton(true)
    b.stockistUnavailable = true
    T.SetAvailable(b, true)
    eq(T.IsAvailable(b), true)
end)
