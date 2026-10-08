local ADDON_NAME, Stockist = ...

-- Pop-outs: a panel from the workspace in a window of its own, so it can be used without a workspace (a
-- watchlist or a chart on its own). One pop-out per panel type: popping out again reuses and updates the same
-- window instead of spawning another. The window holds its own panel, independent of the workspace, and
-- remembers its position and size.
--   Stockist.PopOut.Open("watchlist")
--   Stockist.PopOut.Open("chart", { itemID = 2589 })     options go to the panel's Apply
-- A panel type opts in by registering a `popout` table of sizes next to its `create`:
--   Stockist.Panels:Register("watchlist", { title = ..., create = ..., popout = { width, height, minWidth, minHeight } })
-- A panel may define Apply(opts) (called with the options each time the window is opened), Title() (the window
-- title, updated through its onTitle callback) and Drop(itemID) or Pick(itemID) (for items dropped on the
-- window). The window is created once and then only hidden and shown; a hidden panel does no work because
-- panels refresh only while visible.
local PopOut = { slots = {}, built = 0 }
Stockist.PopOut = PopOut

local STAGGER = 28 -- each pop-out of a different type opens this far down and right of the one before

--- The chart window keeps the name it always had, so its saved position survives.
local function windowName(typeName)
    if typeName == "chart" then return "StockistChartWindow" end
    return "StockistPopout_" .. typeName
end

local function updateTitle(slot)
    local panel, def = slot.panel, slot.def
    local text = panel.Title and panel:Title() or def.title
    slot.win.title:SetText("Stockist - " .. text)
end

local function build(typeName, def)
    local sizes = def.popout or {}
    local name = windowName(typeName)
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
    local slot = { win = win, panel = panel, def = def, type = typeName }
    panel.onTitle = function() updateTitle(slot) end

    local function drop(itemID)
        local take = panel.Drop or panel.Pick
        if take then take(panel, itemID) end
    end
    Stockist.ItemPicker.AcceptDrops(win.frame, drop)
    Stockist.ItemPicker.AcceptDrops(win.bar, drop)
    return slot
end

--- Open the pop-out of a panel type, pointing it at `opts`. Returns the slot ({ win, panel, type }).
function PopOut.Open(typeName, opts)
    local def = Stockist.Panels:Get(typeName)
    if not def then error(("no panel type '%s' to pop out"):format(tostring(typeName)), 2) end
    local slot = PopOut.slots[typeName]
    if not slot then
        slot = build(typeName, def)
        PopOut.slots[typeName] = slot
    end
    if slot.panel.Apply then slot.panel:Apply(opts or {}) end
    updateTitle(slot)
    slot.win.frame:Show()
    slot.win.frame:Raise() -- also when it was already open, perhaps buried under other windows
    -- Sizes are only known after the first layout pass, so give the panel one more chance to fit itself.
    C_Timer.After(0, function()
        if slot.win.frame:IsShown() and slot.panel.LayoutChart then slot.panel:LayoutChart() end
    end)
    return slot
end

--- The pop-out of a panel type, or nil if it was never opened.
function PopOut.Slot(typeName)
    return PopOut.slots[typeName]
end

function PopOut.IsOpen(typeName)
    local slot = PopOut.slots[typeName]
    return slot ~= nil and slot.win.frame:IsShown()
end
