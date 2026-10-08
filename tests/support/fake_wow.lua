-- A permissive stand-in for WoW's frame API, so game-facing code can run in the unit tests.
--
-- Every object accepts any method call and does nothing, except the few methods whose state the tests
-- read: text, shown, enabled, scripts, and a handful of getters that must return numbers. Nothing here
-- checks that the real client has a method, so it catches nil errors and logic mistakes, not API typos;
-- the real client is still the final test.
Fake = {}

local timers = {}

local function trackedMethods()
    return {
        SetText = function(self, t) self.text = t end,
        GetText = function(self) return self.text end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        SetShown = function(self, v) self.shown = v and true or false end,
        IsShown = function(self) return self.shown end,
        IsVisible = function(self) return self.shown end,
        SetEnabled = function(self, v) self.enabled = v and true or false end,
        Enable = function(self) self.enabled = true end,
        Disable = function(self) self.enabled = false end,
        IsEnabled = function(self) return self.enabled end,
        SetAlpha = function(self, a) self.alpha = a end,
        SetScript = function(self, name, fn) self.scripts[name] = fn end,
        GetScript = function(self, name) return self.scripts[name] end,
        HookScript = function(self, name, fn)
            self.hooks[name] = self.hooks[name] or {}
            table.insert(self.hooks[name], fn)
        end,
        RegisterEvent = function(self, e) self.events[e] = true end,
        UnregisterEvent = function(self, e) self.events[e] = nil end,
        SetFrameLevel = function(self, n) self.level = n end,
        GetFrameLevel = function(self) return self.level or 5 end,
        GetWidth = function() return 640 end,
        GetHeight = function() return 360 end,
        GetSize = function() return 640, 360 end,
        GetStringWidth = function(self) return 6 * #(self.text or "") end,
        GetStringHeight = function(self)
            local _, lines = (self.text or ""):gsub("\n", "")
            return 12 * (lines + 1)
        end,
        GetEffectiveScale = function() return 1 end,
        GetLeft = function() return 0 end,
        GetBottom = function() return 0 end,
        GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
        IsMouseOver = function() return false end,
        GetFontString = function(self)
            self.fontString = self.fontString or Fake.new("FontString", self)
            return self.fontString
        end,
        CreateFontString = function(self) return Fake.new("FontString", self) end,
        CreateTexture = function(self) return Fake.new("Texture", self) end,
        CreateLine = function(self) return Fake.new("Line", self) end,
    }
end

local METHODS = trackedMethods()

function Fake.new(kind, parent)
    local o = {
        kind = kind, parent = parent, shown = true, enabled = true,
        scripts = {}, hooks = {}, events = {}, calls = {},
    }
    return setmetatable(o, {
        __index = function(_, key)
            local m = METHODS[key]
            if m then return m end
            -- WoW method names are capitalised; a lowercase key is a plain field that was never set
            if type(key) ~= "string" or not key:match("^%u") then return nil end
            -- any other method: remember it was called and do nothing
            return function(self, ...)
                self.calls[#self.calls + 1] = key
                return nil
            end
        end,
    })
end

--- Run a script handler (and hooks) the way the client would, e.g. Fake.fire(button, "OnClick").
function Fake.fire(obj, name, ...)
    local fn = obj.scripts[name]
    if fn then fn(obj, ...) end
    for _, hook in ipairs(obj.hooks[name] or {}) do hook(obj, ...) end
end

function Fake.called(obj, method)
    for _, c in ipairs(obj.calls) do if c == method then return true end end
    return false
end

--- Run everything queued with C_Timer.After.
function Fake.flush()
    local guard = 0
    while #timers > 0 and guard < 1000 do
        local fn = table.remove(timers, 1)
        fn()
        guard = guard + 1
    end
end

--- Install the globals the addon's UI code expects. Call before loading the addon files.
function Fake.install()
    timers = {}
    UIParent = Fake.new("Frame")
    GameTooltip = Fake.new("Frame")
    UISpecialFrames = {}
    tinsert = table.insert
    GetCursorPosition = function() return 0, 0 end
    Fake.frames = {} -- every frame created through CreateFrame, in order
    CreateFrame = function(kind, name, parent)
        local o = Fake.new(kind, parent)
        if name then _G[name] = o end
        Fake.frames[#Fake.frames + 1] = o
        return o
    end
    C_Timer = {
        After = function(_, fn) timers[#timers + 1] = fn end,
        NewTicker = function(_, fn)
            local t = Fake.new("Ticker")
            t.fn = fn
            return t
        end,
    }
end

--- Remove the globals again, so other specs see a plain Lua environment.
function Fake.uninstall()
    for _, name in ipairs({ "UIParent", "GameTooltip", "UISpecialFrames", "tinsert", "GetCursorPosition",
        "CreateFrame", "C_Timer", "StockistChartWindow" }) do
        _G[name] = nil
    end
end
