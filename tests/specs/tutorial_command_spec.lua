local function setup()
    local S = load_addon("Core/EventBus.lua", "Core/Registry.lua", "Core/Format.lua", "Core/Commands.lua",
        "Core/Help.lua", "Core/HelpTopics.lua", "Features/StatusCommands.lua")
    local out = {}
    S.Print = function(msg) out[#out + 1] = msg end
    S.settings = {}
    S.store = {} -- Commands.Dispatch only checks that the store exists
    return S, out
end

test("/stockist tutorial reports the current state", function()
    local S, out = setup()
    S.Commands:Dispatch("tutorial")
    eq(out[#out]:find("tutorial tips are on", 1, true) ~= nil, true, "defaults to on")
end)

test("/stockist tutorial off and on change the shared setting and tell listeners", function()
    local S, out = setup()
    local seen = {}
    S.Events:On("TUTORIAL_CHANGED", function(on) seen[#seen + 1] = on end)
    S.Commands:Dispatch("tutorial off")
    eq(S.Help.TutorialEnabled(), false)
    eq(S.settings.tutorial, false, "stored in the account-wide settings")
    S.Commands:Dispatch("tutorial ON")
    eq(S.Help.TutorialEnabled(), true)
    eq(seen[1], false); eq(seen[2], true)
    eq(out[1], "tutorial tips off."); eq(out[2], "tutorial tips on.")
end)

test("/stockist tutorial rejects anything else", function()
    local S, out = setup()
    S.Commands:Dispatch("tutorial maybe")
    eq(out[#out], "usage: /stockist tutorial [on|off]")
    eq(S.Help.TutorialEnabled(), true, "unchanged")
end)

test("the help listing mentions the tutorial command", function()
    local S, out = setup()
    S.Commands:Dispatch("nonsense")
    local all = table.concat(out, "\n")
    eq(all:find("/stockist tutorial", 1, true) ~= nil, true)
    eq(all:find("/stockist time", 1, true) ~= nil, true)
end)
