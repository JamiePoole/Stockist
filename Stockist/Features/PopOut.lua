local ADDON_NAME, Stockist = ...

-- Pop-outs: any registered panel type in its own window, any number of times. Each window holds its own panel,
-- is independent of the workspace and of other pop-outs, and remembers its position and size.
--   Stockist.PopOut.Open("watchlist")                          a new pop-out (or a free closed one)
--   Stockist.PopOut.Open("chart", { itemID = 2589 })           options go to the panel's Apply
--   Stockist.PopOut.Show("chart", { itemID = 2589 })           the one shared window (for /stockist chart)
-- A panel type opts in by registering a `popout` table of sizes next to its `create`:
--   Stockist.Panels:Register("watchlist", { title = ..., create = ..., popout = { width, height, minWidth, minHeight } })
-- A panel may define Apply(opts) (called with the options each time its window is opened), Title() (the
-- window title, updated through its onTitle callback) and Drop(itemID) or Pick(itemID) (for items dropped on
-- the window). Windows are never destroyed, only hidden and reused: a hidden panel does no work, because
-- panels refresh only while visible.
local PopOut = { slots = {}, built = 0 }
Stockist.PopOut = PopOut

local MAX_PER_TYPE = 12 -- if every one is open, the last is reused
local STAGGER = 28      -- each new window opens this many pixels down and right of the one before

--- The first chart window keeps the name it always had, so its saved position survives.
local function windowName(typeName, index)
    if typeName == "chart" and index == 1 then return "StockistChartWindow" end
    return ("StockistPopout_%s_%d"):format(typeName, index)
end

local function updateTitle(slot)
    local panel, def = slot.panel, slot.def
    local text = panel.Title and panel:Title() or def.title
    slot.win.title:SetText("Stockist - " .. text)
end

local function build(typeName, def, index)
    local sizes = def.popout or {}
    local name = windowName(typeName, index)
    local win = Stockist.UI.Window.Create({
        name = name, title = "Stockist - " .. def.title,
        width = sizes.width or 520, height = sizes.height or 400,
        minWidth = sizes.minWidth or 320, minHeight = sizes.minHeight or 200,
    })
    -- A window that has never been opened gets a slightly different spot from the others, so they do not stack.
    local saved = Stockist.settings and Stockist.settings.windows and Stockist.settings.windows[name]
    if not saved and PopOut.built > 0 then
        win.frame:ClearAllPoints()
        win.frame:SetPoint("CENTER", UIParent, "CENTER", STAGGER * PopOut.built, -STAGGER * PopOut.built)
    end
    PopOut.built = PopOut.built + 1

    -- No pop-out button inside a pop-out, and no link group until a panel asks for one.
    local panel = def.create(win.content, { popOut = false })
    local slot = { win = win, panel = panel, def = def, index = index, type = typeName }
    panel.onTitle = function() updateTitle(slot) end

    local function drop(itemID)
        local take = panel.Drop or panel.Pick
        if take then take(panel, itemID) end
    end
    Stockist.ItemPicker.AcceptDrops(win.frame, drop)
    Stockist.ItemPicker.AcceptDrops(win.bar, drop)
    return slot
end

local function present(slot, opts)
    if slot.panel.Apply then slot.panel:Apply(opts or {}) end
    updateTitle(slot)
    slot.win.frame:Show()
    -- Sizes are only known after the first layout pass, so give the panel one more chance to fit itself.
    C_Timer.After(0, function()
        if slot.win.frame:IsShown() and slot.panel.LayoutChart then slot.panel:LayoutChart() end
    end)
    return slot
end

local function definition(typeName)
    local def = Stockist.Panels:Get(typeName)
    if not def then error(("no panel type '%s' to pop out"):format(tostring(typeName)), 3) end
    return def
end

--- Open a pop-out of a panel type in a new window, or in one that was closed earlier. Returns the slot
--- ({ win, panel, index, type }).
function PopOut.Open(typeName, opts)
    local def = definition(typeName)
    local list = PopOut.slots[typeName]
    if not list then list = {}; PopOut.slots[typeName] = list end
    local slot
    for i = 1, MAX_PER_TYPE do
        local existing = list[i]
        if not existing then
            slot = build(typeName, def, i)
            list[i] = slot
            break
        elseif not existing.win.frame:IsShown() then
            slot = existing
            break
        end
    end
    return present(slot or list[MAX_PER_TYPE], opts)
end

--- The shared window of a panel type (the first one): opened if needed and pointed at `opts`. This is what
--- /stockist chart uses, so it replaces what its window shows instead of piling up windows.
function PopOut.Show(typeName, opts)
    local def = definition(typeName)
    local list = PopOut.slots[typeName]
    if not list then list = {}; PopOut.slots[typeName] = list end
    list[1] = list[1] or build(typeName, def, 1)
    return present(list[1], opts)
end

--- The slot at `index` (default 1) of a panel type, or nil if it was never opened.
function PopOut.Slot(typeName, index)
    local list = PopOut.slots[typeName]
    return list and list[index or 1] or nil
end

--- How many windows of a panel type are open right now.
function PopOut.OpenCount(typeName)
    local n = 0
    for _, slot in ipairs(PopOut.slots[typeName] or {}) do
        if slot.win.frame:IsShown() then n = n + 1 end
    end
    return n
end
