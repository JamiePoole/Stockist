local function setup()
    local S = load_addon("Core/EventBus.lua", "Core/Registry.lua", "Core/Format.lua", "Core/Commands.lua",
        "Core/Help.lua", "Core/HelpTopics.lua", "Features/StatusCommands.lua")
    local out = {}
    S.Print = function(msg) out[#out + 1] = msg end
    S.settings = {}
    S.store = {}
    S.calls = {}
    S.Scanner = { Start = function(_, force) S.calls[#S.calls + 1] = force; return false, "next scan available in 3:00" end }
    return S, out
end

test("/stockist scan asks the scanner without forcing", function()
    local S, out = setup()
    S.Commands:Dispatch("scan")
    eq(S.calls[1], false)
    eq(out[#out], "can't scan: next scan available in 3:00")
end)

test("/stockist scan force asks the scanner to skip our own wait", function()
    local S = setup()
    S.Commands:Dispatch("scan force")
    S.Commands:Dispatch("scan FORCE")
    eq(S.calls[1], true); eq(S.calls[2], true)
end)
