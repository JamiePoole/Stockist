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
-- Scroll bar maths (pure)
---------------------------------------------------------------------------------------------------

local MIN_THUMB = 16

local function thumbHeight(total, visible, track)
    return math.max(MIN_THUMB, math.floor(track * visible / total + 0.5))
end

--- The thumb of a scroll bar: its distance from the top of the track and its height, in pixels. Nil when
--- everything fits and no bar is needed.
function Picker.Thumb(total, visible, offset, track)
    if total <= visible then return nil end
    local height = thumbHeight(total, visible, track)
    local range = track - height
    local top = math.floor(range * offset / (total - visible) + 0.5)
    return math.max(0, math.min(range, top)), height
end

--- The list offset after the thumb is dragged `dy` pixels down from where it was grabbed (`startOffset`).
function Picker.OffsetForDrag(total, visible, track, startOffset, dy)
    if total <= visible then return 0 end
    local range = track - thumbHeight(total, visible, track)
    if range <= 0 then return 0 end
    local offset = startOffset + dy / range * (total - visible)
    return math.max(0, math.min(total - visible, math.floor(offset + 0.5)))
end

---------------------------------------------------------------------------------------------------
-- Popup (game side)
---------------------------------------------------------------------------------------------------

-- One popup serves two entry points, and only one is open at a time:
--   * the item name in a chart header: the popup has its own search box;
--   * a search box that lives elsewhere (the workspace title bar, see Picker.Attach): the popup shows only
--     the results, under that box.
local ui -- built on first use
local state = { rows = {}, selectable = {}, cursor = 1, offset = 0, onPick = nil, edit = nil, external = false }

local GAP = 4        -- space between the item name and the popup
local SCROLL_W = 6
local TRACK_H = ROWS * ROW_HEIGHT

local function listTop() return state.external and 8 or 50 end

--- Place the result list (and the scroll bar track beside it) for the current mode.
local function layout()
    local top = listTop()
    ui.popup:SetHeight(top + TRACK_H + 8)
    ui.list:ClearAllPoints()
    ui.list:SetPoint("TOPLEFT", ui.popup, "TOPLEFT", 4, -top)
    ui.list:SetPoint("TOPRIGHT", ui.popup, "TOPRIGHT", ui.scrollVisible and -(SCROLL_W + 10) or -4, -top)
    ui.list:SetHeight(TRACK_H)
    ui.track:ClearAllPoints()
    ui.track:SetPoint("TOPRIGHT", ui.popup, "TOPRIGHT", -5, -top)
    ui.track:SetSize(SCROLL_W, TRACK_H)
end

local function close()
    if not (ui and ui.popup:IsShown()) then return end
    local edit, external = state.edit, state.external
    ui.popup:Hide()
    ui.catcher:Hide()
    state.onPick = nil
    state.edit = nil
    if edit then
        edit:ClearFocus()
        if external then edit:SetText("") end
    end
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

--- Draw the visible slice of rows and the scroll bar. The mouse wheel scrolls without moving the highlight.
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

    -- A scroll bar shows only when there is more than fits: it is the hint that the list scrolls.
    local top, height = Picker.Thumb(#state.rows, ROWS, state.offset, TRACK_H)
    local needed = top ~= nil
    if needed ~= ui.scrollVisible then
        ui.scrollVisible = needed
        layout()
    end
    ui.track:SetShown(needed)
    ui.thumb:SetShown(needed)
    if needed then
        ui.thumb:ClearAllPoints()
        ui.thumb:SetPoint("TOPRIGHT", ui.track, "TOPRIGHT", 0, -top)
        ui.thumb:SetSize(SCROLL_W, height)
    end
end

local function refresh()
    state.rows = Picker.Entries(Picker.Source(), state.edit:GetText())
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

--- Keyboard handling shared by the popup's own search box and one attached from outside. Each box only
--- acts while it is the one the popup is serving.
local function bindEdit(edit)
    edit:SetScript("OnTextChanged", function(self)
        if not (ui and ui.popup:IsShown() and state.edit == self) then return end
        state.cursor, state.offset = 1, 0
        refresh()
    end)
    edit:SetScript("OnEnterPressed", function(self)
        if state.edit ~= self then return end
        local pos = state.selectable[state.cursor]
        local row = pos and state.rows[pos]
        if row then pick(row.id) end
    end)
    edit:SetScript("OnEscapePressed", function(self)
        if state.edit == self then close() else self:ClearFocus() end
    end)
    if edit.SetAltArrowKeyMode then edit:SetAltArrowKeyMode(false) end
    edit:SetScript("OnArrowPressed", function(self, key)
        if state.edit ~= self then return end
        if key == "UP" then move(-1) elseif key == "DOWN" then move(1) end
    end)
end

local function cursorY()
    local _, y = GetCursorPosition()
    return y / ui.popup:GetEffectiveScale()
end

local function build()
    ui = { scrollVisible = false }
    -- A transparent layer over the whole screen: a click anywhere outside the popup closes it.
    ui.catcher = CreateFrame("Button", nil, UIParent)
    ui.catcher:SetAllPoints(UIParent)
    ui.catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    ui.catcher:RegisterForClicks("AnyUp")
    ui.catcher:SetScript("OnClick", close)

    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    ui.popup = popup
    popup:SetWidth(WIDTH)
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

    -- The popup's own search box, used when it was opened from an item name.
    local edit = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
    ui.edit = edit
    edit:SetAutoFocus(false)
    edit:SetSize(WIDTH - 24, 20)
    edit:SetPoint("TOPLEFT", 14, -8)
    bindEdit(edit)

    ui.hint = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.hint:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", -2, -2)
    ui.hint:SetText("Type a name, or paste an item link")

    ui.list = CreateFrame("Frame", nil, popup)

    ui.empty = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.empty:SetPoint("TOPLEFT", ui.list, "TOPLEFT", 8, -8)
    ui.empty:SetPoint("TOPRIGHT", ui.list, "TOPRIGHT", -8, -8)
    ui.empty:SetJustifyH("LEFT")
    ui.empty:SetWordWrap(true)
    ui.empty:SetTextColor(0.7, 0.72, 0.78)
    ui.empty:SetText("Nothing matches. Names are only known for items the game has loaded: paste an item link or type its ID.")

    ui.rows = {}
    for slot = 1, ROWS do
        local row = CreateFrame("Button", nil, ui.list)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", ui.list, "TOPLEFT", 0, -(slot - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", ui.list, "TOPRIGHT", 0, -(slot - 1) * ROW_HEIGHT)
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

    -- The scroll bar: a thin track with a thumb that can be dragged. It only appears when the list is longer
    -- than the window, which is also the hint that it scrolls.
    ui.track = CreateFrame("Frame", nil, popup)
    local trackBg = ui.track:CreateTexture(nil, "BACKGROUND")
    trackBg:SetAllPoints()
    trackBg:SetColorTexture(1, 1, 1, 0.07)
    ui.thumb = CreateFrame("Button", nil, popup)
    ui.thumb:SetFrameLevel(ui.track:GetFrameLevel() + 2)
    local thumbBg = ui.thumb:CreateTexture(nil, "ARTWORK")
    thumbBg:SetAllPoints()
    thumbBg:SetColorTexture(0.55, 0.65, 0.85, 0.65)
    local drag
    ui.thumb:SetScript("OnMouseDown", function() drag = { y = cursorY(), offset = state.offset } end)
    ui.thumb:SetScript("OnMouseUp", function() drag = nil end)
    ui.thumb:SetScript("OnUpdate", function()
        if not drag then return end
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then drag = nil return end
        state.offset = Picker.OffsetForDrag(#state.rows, ROWS, TRACK_H, drag.offset, drag.y - cursorY())
        redraw()
    end)
    ui.track:Hide()
    ui.thumb:Hide()

    -- Item names arrive from the server a moment after they are first asked for.
    local loader = CreateFrame("Frame")
    loader:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    loader:SetScript("OnEvent", function() if popup:IsShown() then redraw() end end)

    popup:Hide()
    ui.catcher:Hide()
end

--- Open the picker under `anchor`. `onPick(itemID)` runs when an item is chosen. `opts.edit` is a search
--- box that already exists elsewhere: the popup then shows only the results, under it. Anything already
--- open (from the other entry point too) is closed first, so there is only ever one.
function Picker.Show(anchor, onPick, opts)
    if not ui then build() end
    close()
    opts = opts or {}
    state.onPick = onPick
    state.external = opts.edit ~= nil
    state.edit = opts.edit or ui.edit
    state.cursor, state.offset = 1, 0
    ui.edit:SetShown(not state.external)
    ui.hint:SetShown(not state.external)
    ui.popup:ClearAllPoints()
    ui.popup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, state.external and -2 or -GAP)
    ui.catcher:Show()
    ui.popup:Show()
    state.edit:SetText("")
    layout()
    refresh()
    state.edit:SetFocus()
end

--- Let a search box that lives elsewhere (a window's title bar, say) drive the picker: focusing it opens the
--- results under it, typing filters them, and choosing an item calls `onPick(itemID)`.
function Picker.Attach(edit, onPick)
    bindEdit(edit)
    edit:SetScript("OnEditFocusGained", function(self)
        if state.edit == self and Picker.IsShown() then return end
        Picker.Show(self, onPick, { edit = self })
    end)
end

function Picker.Hide() close() end

function Picker.IsShown() return ui ~= nil and ui.popup:IsShown() end

--- Test hook: the widgets and the current rows.
function Picker._debug() return ui, state end
