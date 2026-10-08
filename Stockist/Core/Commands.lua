local ADDON_NAME, Stockist = ...

-- The /stockist command line. Features register their own subcommands here, so adding one never
-- means editing a shared file:
--   Stockist.Commands:Register("keep", { help = "keep <what> <days>   ...", run = function(args) ... end })
-- `run` receives the rest of the line after the subcommand name.
local Commands = Stockist.NewRegistry("command")
Stockist.Commands = Commands

--- All user-facing output goes through here so it can be redirected (tests replace it).
function Stockist.Print(msg)
    print("|cff33ff99Stockist|r " .. msg)
end

function Commands:PrintHelp()
    Stockist.Print("commands:")
    for _, name in ipairs(self:List()) do
        Stockist.Print("  /stockist " .. self:Get(name).help)
    end
end

--- Run one command line, e.g. "item 2589". An empty line runs `status`; an unknown name prints help.
function Commands:Dispatch(input)
    if not Stockist.store then return Stockist.Print("not ready yet.") end
    local name, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    if name == "" then name = "status" end
    local command = self:Get(name:lower())
    if command then
        command.run(rest)
    else
        self:PrintHelp()
    end
end

if SlashCmdList then
    SLASH_STOCKIST1 = "/stockist"
    SLASH_STOCKIST2 = "/stk"
    SlashCmdList["STOCKIST"] = function(input) Commands:Dispatch(input) end
end
