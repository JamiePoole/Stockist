local ADDON_NAME, Stockist = ...

-- A named collection of plugins of one kind (chart series types, alert presenters, transports...).
-- Features register implementations by name and the host looks them up, so adding a new kind
-- of thing never means editing the code that uses it.
local Registry = {}
Registry.__index = Registry

function Stockist.NewRegistry(kind)
    return setmetatable({ kind = kind, items = {}, order = {} }, Registry)
end

function Registry:Register(name, impl)
    if self.items[name] then
        error(("%s '%s' is already registered"):format(self.kind, name), 2)
    end
    self.items[name] = impl
    self.order[#self.order + 1] = name
    return impl
end

function Registry:Get(name)
    return self.items[name]
end

function Registry:Require(name)
    local impl = self.items[name]
    if not impl then
        error(("unknown %s '%s'"):format(self.kind, tostring(name)), 2)
    end
    return impl
end

--- Names in registration order.
function Registry:List()
    local out = {}
    for i, name in ipairs(self.order) do out[i] = name end
    return out
end
