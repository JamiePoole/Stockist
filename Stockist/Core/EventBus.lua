local ADDON_NAME, Stockist = ...

-- Internal publish/subscribe. Features talk through events, never by reaching into each other.
local Events = { handlers = {} }
Stockist.Events = Events

local function reportError(err)
    local handler = geterrorhandler and geterrorhandler() or print
    handler(err)
end

--- Subscribe to an event. `owner` is optional and lets a module drop all its subscriptions at once.
--- Returns a subscription token for Off().
function Events:On(event, fn, owner)
    local list = self.handlers[event]
    if not list then
        list = {}
        self.handlers[event] = list
    end
    local sub = { fn = fn, owner = owner }
    list[#list + 1] = sub
    return sub
end

function Events:Off(event, sub)
    local list = self.handlers[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == sub then
            list[i].dead = true
            table.remove(list, i)
        end
    end
end

function Events:OffOwner(owner)
    for _, list in pairs(self.handlers) do
        for i = #list, 1, -1 do
            if list[i].owner == owner then
                list[i].dead = true
                table.remove(list, i)
            end
        end
    end
end

--- Call every handler for `event`. A failing handler is reported and does not stop the others.
function Events:Fire(event, ...)
    local list = self.handlers[event]
    if not list then return end
    local snapshot = {}
    for i = 1, #list do snapshot[i] = list[i] end -- handlers may unsubscribe while we iterate
    for i = 1, #snapshot do
        local sub = snapshot[i]
        if not sub.dead then
            local ok, err = pcall(sub.fn, ...)
            if not ok then reportError(err) end
        end
    end
end
