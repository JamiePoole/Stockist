local ADDON_NAME, Stockist = ...

-- The item picker: a searchable dropdown for choosing an item. Click the item name in a chart's header.
--   Stockist.ItemPicker.Show(anchorFrame, function(itemID) ... end)
-- The list has the watchlist (tracked items) first, a separator, then every other item we hold prices for.
-- Type to filter by name; paste an item link or type an item ID to open an item we have no data for yet.
-- Enter picks the highlighted row (the first one), Up/Down move it, Esc or a click outside closes.
-- Entries and Search are pure; the popup below them is the game side.
local Picker = {}
Stockist.ItemPicker = Picker

local ROWS = 12
local ROW_HEIGHT = 20
local WIDTH = 280

---------------------------------------------------------------------------------------------------
-- Pure part
---------------------------------------------------------------------------------------------------

--- What the picker chooses from: { items = ids we hold prices for, tracked = tracked ids, nameOf = function }.
function Picker.Source()
    return {
        items = Stockist.store and Stockist.store:Items() or {},
        tracked = Stockist.tracked and Stockist.tracked:List() or {},
        nameOf = function(id) return Stockist.ItemInfo.Name(id) or ("item:" .. id) end,
    }
end

local function byName(a, b)
    local x, y = a.name:lower(), b.name:lower()
    if x ~= y then return x < y end
    return a.id < b.id
end

--- Items that match `query` (case-insensitive part of the name, or the exact item ID), as { id, name }
--- sorted by name. An empty query matches everything.
local function matching(ids, nameOf, query)
    local out = {}
    for _, id in ipairs(ids) do
        local name = nameOf(id)
        if query == "" or name:lower():find(query, 1, true) or tostring(id) == query then
            out[#out + 1] = { id = id, name = name }
        end
    end
    table.sort(out, byName)
    return out
end

local function normalise(text)
    return (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
end

--- The rows to show for `query`, in order:
---   { kind = "open",   id }          an item ID or link typed in that is not in the lists: open it anyway
---   { kind = "header", text }        "Watchlist", "Everything else"
---   { kind = "item",   id, name }
--- A header only appears when its section has rows.
function Picker.Entries(source, query)
    query = normalise(query)
    local rows = {}

    local tracked = {}
    for _, id in ipairs(source.tracked) do tracked[id] = true end
    local others = {}
    for _, id in ipairs(source.items) do
        if not tracked[id] then others[#others + 1] = id end
    end

    local watch = matching(source.tracked, source.nameOf, query)
    local rest = matching(others, source.nameOf, query)

    local typed = Stockist.ParseItemID and Stockist.ParseItemID(query)
    if typed then
        local listed = false
        for _, e in ipairs(watch) do if e.id == typed then listed = true end end
        for _, e in ipairs(rest) do if e.id == typed then listed = true end end
        if not listed then rows[#rows + 1] = { kind = "open", id = typed } end
    end
    if #watch > 0 then
        rows[#rows + 1] = { kind = "header", text = "Watchlist" }
        for _, e in ipairs(watch) do rows[#rows + 1] = { kind = "item", id = e.id, name = e.name } end
    end
    if #rest > 0 then
        rows[#rows + 1] = { kind = "header", text = #watch > 0 and "Everything else" or "Items with prices" }
        for _, e in ipairs(rest) do rows[#rows + 1] = { kind = "item", id = e.id, name = e.name } end
    end
    return rows
end

--- Every item (watchlist and others) whose name contains `text`, sorted by name: { { id, name }... }.
--- Used by `/stockist chart <name>`.
function Picker.Search(source, text)
    local seen, ids = {}, {}
    for _, list in ipairs({ source.tracked, source.items }) do
        for _, id in ipairs(list) do
            if not seen[id] then seen[id] = true; ids[#ids + 1] = id end
        end
    end
    return matching(ids, source.nameOf, normalise(text))
end

---------------------------------------------------------------------------------------------------
-- Popup (game side)
---------------------------------------------------------------------------------------------------

local ui -- built on first use: { catcher, popup, edit, rows = {...}, ... }
local state = { rows = {}, selectable = {}, cursor = 1, offset = 0, onPick = nil }

local function close()
    if not ui then return end
    ui.popup:Hide()
    ui.catcher:Hide()
    ui.edit:ClearFocus()
    state.onPick = nil
end

local function pick(id)
    local onPick = state.onPick
    close()
    if onPick and id then onPick(id) end
end

--- Scroll so the highlighted row is in view (the heading above the first item stays in view too).
local function ensureVisible()
    local pos = state.selectable[state.cursor]
    if not pos then return end
    if state.cursor == 1 then state.offset = 0 end
    if pos <= state.offset then state.offset = pos - 1 end
    if pos > state.offset + ROWS then state.offset = pos - ROWS end
end

--- Draw the visible slice of rows. The mouse wheel scrolls without moving the highlight.
local function redraw()
    local pos = state.selectable[state.cursor]
    state.offset = math.max(0, math.min(state.offset, math.max(0, #state.rows - ROWS)))

    for slot, widget in ipairs(ui.rows) do
        local index = state.offset + slot
        local row = state.rows[index]
        widget.row, widget.index = row, index
        if not row then
            widget:Hide()
        else
            widget:Show()
            widget.highlight:SetShown(index == pos)
            if row.kind == "header" then
                widget.label:SetText(row.text)
                widget.label:SetTextColor(0.55, 0.62, 0.75)
            elseif row.kind == "open" then
                widget.label:SetText("Open item " .. row.id)
                widget.label:SetTextColor(0.6, 0.8, 1)
            else
                widget.label:SetText(Stockist.ItemInfo.ColoredName(row.id))
                widget.label:SetTextColor(1, 1, 1)
            end
        end
    end
    ui.empty:SetShown(#state.rows == 0)
end

local function refresh()
    state.rows = Picker.Entries(Picker.Source(), ui.edit:GetText())
    state.selectable = {}
    for i, row in ipairs(state.rows) do
        if row.kind ~= "header" then state.selectable[#state.selectable + 1] = i end
    end
    state.cursor = math.max(1, math.min(state.cursor, #state.selectable))
    ensureVisible()
    redraw()
end

local function move(delta)
    if #state.selectable == 0 then return end
    state.cursor = math.max(1, math.min(#state.selectable, state.cursor + delta))
    ensureVisible()
    redraw()
end

local function build()
    ui = {}
    -- A transparent layer over the whole screen: a click anywhere outside the popup closes it.
    ui.catcher = CreateFrame("Button", nil, UIParent)
    ui.catcher:SetAllPoints(UIParent)
    ui.catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    ui.catcher:RegisterForClicks("AnyUp")
    ui.catcher:SetScript("OnClick", close)

    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    ui.popup = popup
    popup:SetSize(WIDTH, 34 + ROWS * ROW_HEIGHT + 8)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(ui.catcher:GetFrameLevel() + 5)
    popup:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    popup:SetBackdropColor(0.06, 0.07, 0.09, 0.98)
    popup:SetBackdropBorderColor(1, 1, 1, 0.25)
    popup:EnableMouse(true)
    popup:EnableMouseWheel(true)
    popup:SetScript("OnMouseWheel", function(_, delta)
        state.offset = state.offset - delta * 3
        redraw()
    end)

    local edit = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
    ui.edit = edit
    edit:SetAutoFocus(false)
    edit:SetSize(WIDTH - 24, 20)
    edit:SetPoint("TOPLEFT", 14, -8)
    edit:SetScript("OnTextChanged", function() state.cursor, state.offset = 1, 0; refresh() end)
    edit:SetScript("OnEnterPressed", function()
        local pos = state.selectable[state.cursor]
        local row = pos and state.rows[pos]
        if row then pick(row.id) end
    end)
    edit:SetScript("OnEscapePressed", close)
    if edit.SetAltArrowKeyMode then edit:SetAltArrowKeyMode(false) end
    edit:SetScript("OnArrowPressed", function(_, key)
        if key == "UP" then move(-1) elseif key == "DOWN" then move(1) end
    end)

    ui.hint = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.hint:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", -2, -2)
    ui.hint:SetText("Type a name, or paste an item link")

    ui.empty = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.empty:SetPoint("TOPLEFT", 12, -64)
    ui.empty:SetPoint("TOPRIGHT", -12, -64)
    ui.empty:SetJustifyH("LEFT")
    ui.empty:SetWordWrap(true)
    ui.empty:SetTextColor(0.7, 0.72, 0.78)
    ui.empty:SetText("Nothing matches. Names are only known for items the game has loaded: paste an item link or type its ID.")

    ui.rows = {}
    for slot = 1, ROWS do
        local row = CreateFrame("Button", nil, popup)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 4, -34 - (slot - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", -4, -34 - (slot - 1) * ROW_HEIGHT)
        row:RegisterForClicks("LeftButtonUp")
        row.highlight = row:CreateTexture(nil, "BACKGROUND")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(0.2, 0.45, 0.9, 0.28)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.label:SetPoint("LEFT", 8, 0)
        row.label:SetPoint("RIGHT", -8, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row:SetScript("OnEnter", function(r)
            for i, pos in ipairs(state.selectable) do
                if pos == r.index then state.cursor = i; redraw() break end
            end
        end)
        row:SetScript("OnClick", function(r)
            if r.row and r.row.kind ~= "header" then pick(r.row.id) end
        end)
        ui.rows[slot] = row
    end

    -- Item names arrive from the server a moment after they are first asked for.
    local loader = CreateFrame("Frame")
    loader:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    loader:SetScript("OnEvent", function() if popup:IsShown() then redraw() end end)

    popup:Hide()
    ui.catcher:Hide()
end

--- Open the picker under `anchor`. `onPick(itemID)` runs when an item is chosen. Opening it again
--- replaces the first use.
function Picker.Show(anchor, onPick)
    if not ui then build() end
    state.onPick = onPick
    state.cursor, state.offset = 1, 0
    ui.popup:ClearAllPoints()
    ui.popup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    ui.edit:SetText("")
    ui.catcher:Show()
    ui.popup:Show()
    refresh()
    ui.edit:SetFocus()
end

function Picker.Hide() close() end

function Picker.IsShown() return ui ~= nil and ui.popup:IsShown() end

--- Test hook: the widgets and the current rows.
function Picker._debug() return ui, state end
