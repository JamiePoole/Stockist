local ADDON_NAME, Stockist = ...

-- The movers panel: what is rising and what is falling, two short lists, biggest first. By default it looks
-- at every item we hold prices for, so it shows the market, not just what you watch; a switch narrows it to
-- your watchlist. The move is the one the ticker uses (24h, or as far back as we hold if that is at least half
-- a day, labelled; else the recent move). Click an item to show it in the chart. Compute is pure.
local Format = Stockist.Format

local Movers = {}
Movers.__index = Movers
Stockist.Movers = Movers

Movers.HELP_KEYS = { "movers-row", "movers-tracked" }

local ROW_HEIGHT = 20
local SECTION_HEIGHT = 18
local HEADER_HEIGHT = 26
local MAX_PER_SECTION = 10
local MIN_MOVE = 0.005 -- a move smaller than this rounds to nothing and is not listed
local MIN_LIST_ROWS = 2   -- the guide never takes the room of the last two rows of each list

---------------------------------------------------------------------------------------------------
-- Pure part
---------------------------------------------------------------------------------------------------

--- The biggest risers and fallers among `ids`: { risers = rows, fallers = rows }, each at most `limit` rows
--- of { id, name, price, move, label }, the largest move first. Items without a price or a measurable
--- move, and moves that round to nothing, are left out.
function Movers.Compute(store, ids, now, nameOf, limit)
    local up, down = {}, {}
    for _, id in ipairs(ids) do
        local last = store:Latest(id)
        if last then
            local move, label = Stockist.Ticker.Move(store, id, now)
            if move and math.abs(move) >= MIN_MOVE then
                local row = { id = id, name = nameOf(id), price = last.price, move = move, label = label }
                if move > 0 then up[#up + 1] = row else down[#down + 1] = row end
            end
        end
    end
    table.sort(up, function(a, b)
        if a.move ~= b.move then return a.move > b.move end
        return a.id < b.id
    end)
    table.sort(down, function(a, b)
        if a.move ~= b.move then return a.move < b.move end
        return a.id < b.id
    end)
    local function head(list)
        local out = {}
        for i = 1, math.min(limit, #list) do out[i] = list[i] end
        return out
    end
    return { risers = head(up), fallers = head(down) }
end

--- How many rows each of the two lists gets in a panel `height` pixels tall, with `reserved` pixels kept at the
--- foot for the guide.
function Movers.Capacity(height, reserved)
    local room = height - (reserved or 0) - HEADER_HEIGHT - 2 * SECTION_HEIGHT - 6
    return math.max(1, math.min(MAX_PER_SECTION, math.floor(room / 2 / ROW_HEIGHT)))
end

--- The most height the guide may take: what is left once each list keeps MIN_LIST_ROWS rows.
function Movers.GuideRoom(height)
    return height - HEADER_HEIGHT - 2 * SECTION_HEIGHT - 6 - 2 * MIN_LIST_ROWS * ROW_HEIGHT
end

---------------------------------------------------------------------------------------------------
-- Panel (game side)
---------------------------------------------------------------------------------------------------

local function sortName(id)
    return Stockist.ItemInfo.Name(id) or ("item:" .. id)
end

local function buildRow(self, parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp")
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(1, 1, 1, 0.06)
    row.hover:Hide()

    row.moveText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.moveText:SetPoint("RIGHT", -8, 0)
    row.priceText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.priceText:SetPoint("RIGHT", row.moveText, "LEFT", -8, 0)
    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.nameText:SetPoint("LEFT", 8, 0)
    row.nameText:SetPoint("RIGHT", row.priceText, "LEFT", -6, 0)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWordWrap(false)

    row:SetScript("OnEnter", function(r)
        r.hover:Show()
        if r.itemID then
            Stockist.UI.Tooltip.Frame():SetOwner(r, "ANCHOR_RIGHT")
            local _, short = Stockist.Help.Lines("movers-row")
            Stockist.UI.Tooltip.Frame():AddLine(Stockist.ItemInfo.ColoredName(r.itemID), 1, 1, 1)
            if short then Stockist.UI.Tooltip.Frame():AddLine(short, 0.8, 0.8, 0.8, true) end
            Stockist.UI.Tooltip.Frame():Show()
        end
    end)
    row:SetScript("OnLeave", function(r)
        r.hover:Hide()
        Stockist.UI.Tooltip.Frame():Hide()
    end)
    row:SetScript("OnClick", function(r)
        if Stockist.ItemPicker.ClickIsDrop() then return end -- an item on the cursor is not a click on the row
        if r.itemID then self:Select(r.itemID) end
    end)
    return row
end

--- Create a movers panel filling `parent`. `opts`: link (the group to select into), popOut (add a pop-out button).
function Movers.Create(parent, opts)
    opts = opts or {}
    local self = setmetatable({ link = opts.link, onlyTracked = false, rise = {}, fall = {} }, Movers)

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    self.frame = frame

    self.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.title:SetPoint("TOPLEFT", 8, -5)
    self.title:SetText("Movers")

    local prev
    if opts.popOut then
        local pop = Stockist.UI.IconButton.Create(frame, { icon = "popout", width = 24, height = 20 })
        pop:SetPoint("TOPRIGHT", -4, -2)
        pop:SetScript("OnClick", function() self:PopOut() end)
        Stockist.UI.Tooltip.Attach(pop, "popout")
        self.popOutButton = pop
        prev = pop
    end
    -- A switch: while on, only the items on your watchlist are considered.
    self.trackedButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    self.trackedButton:SetSize(86, 20)
    self.trackedButton:SetText("Watchlist")
    if prev then self.trackedButton:SetPoint("RIGHT", prev, "LEFT", -6, 0)
    else self.trackedButton:SetPoint("TOPRIGHT", -4, -2) end
    self.trackedButton:SetScript("OnClick", function()
        self.onlyTracked = not self.onlyTracked
        self:Refresh()
    end)
    Stockist.UI.Tooltip.Attach(self.trackedButton, "movers-tracked")

    self.guide = Stockist.UI.Guide.Create(frame, "movers")

    self.riseHead = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.riseHead:SetTextColor(0.2, 0.78, 0.45)
    self.riseHead:SetText("Rising")
    self.fallHead = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.fallHead:SetTextColor(0.92, 0.3, 0.3)
    self.fallHead:SetText("Falling")

    self.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.empty:SetPoint("TOPLEFT", 14, -HEADER_HEIGHT - 12)
    self.empty:SetPoint("TOPRIGHT", -14, -HEADER_HEIGHT - 12)
    self.empty:SetJustifyH("LEFT")
    self.empty:SetJustifyV("TOP")
    self.empty:SetWordWrap(true)
    self.empty:SetTextColor(0.7, 0.72, 0.78)

    -- A panel that is not on screen skips redrawing, but remembers it missed something and catches up when shown.
    local function refresh()
        if frame:IsVisible() then self:Refresh() else self.stale = true end
    end
    frame:HookScript("OnShow", function()
        if self.stale then self.stale = false; self:Refresh() end
    end)
    frame:SetScript("OnSizeChanged", refresh)
    Stockist.Events:On("SCAN_COMPLETE", refresh, self)
    Stockist.Events:On("TRACKED_CHANGED", refresh, self)
    Stockist.Events:On("TUTORIAL_CHANGED", refresh, self)
    local loader = CreateFrame("Frame")
    loader:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    loader:SetScript("OnEvent", refresh)

    self:Refresh()
    return self
end

--- Fill one list's rows: `rows` are the data, `widgets` the pooled row buttons, `top` the y of its first row.
local function paintList(self, widgets, rows, top, capacity)
    for slot = 1, math.max(capacity, #widgets) do
        local data = slot <= capacity and rows[slot] or nil
        local row = widgets[slot]
        if data and not row then
            row = buildRow(self, self.frame)
            widgets[slot] = row
        end
        if row then
            if data then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -(top + (slot - 1) * ROW_HEIGHT))
                row:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 0, -(top + (slot - 1) * ROW_HEIGHT))
                row.itemID = data.id
                row.nameText:SetText(Stockist.ItemInfo.ColoredName(data.id))
                row.priceText:SetText(Format.MoneyDisplay(data.price))
                local move = Format.Change(data.move)
                if data.label then move = move .. " " .. Format.Colored(data.label, 0.6, 0.63, 0.68) end
                row.moveText:SetText(move)
                row:Show()
            else
                row.itemID = nil
                row:Hide()
            end
        end
    end
end

function Movers:Refresh()
    if not (Stockist.store and Stockist.tracked) then return end
    local now = Stockist.Clock.now()
    local height = self.frame:GetHeight()
    local reserved = self.guide:Fit(Movers.GuideRoom(height)) -- the guide, in tutorial mode, if there is room
    local capacity = Movers.Capacity(height, reserved)
    local ids = self.onlyTracked and Stockist.tracked:List() or Stockist.store:Items()
    local data = Movers.Compute(Stockist.store, ids, now, sortName, capacity)

    Stockist.UI.Button.SetActive(self.trackedButton, self.onlyTracked)
    local none = #data.risers == 0 and #data.fallers == 0
    self.empty:SetShown(none)
    self.empty:SetText(self.onlyTracked
        and "None of your watchlist items has moved yet. Switch the watchlist filter off to see the whole market."
        or "No moves to show yet. They appear once a few scans have been taken.")
    self.riseHead:SetShown(not none)
    self.fallHead:SetShown(not none)

    local riseTop = HEADER_HEIGHT + SECTION_HEIGHT
    local fallHeadY = riseTop + capacity * ROW_HEIGHT + 6
    self.riseHead:ClearAllPoints()
    self.riseHead:SetPoint("TOPLEFT", 8, -HEADER_HEIGHT - 2)
    self.fallHead:ClearAllPoints()
    self.fallHead:SetPoint("TOPLEFT", 8, -fallHeadY)
    paintList(self, self.rise, data.risers, riseTop, capacity)
    paintList(self, self.fall, data.fallers, fallHeadY + SECTION_HEIGHT - 2, capacity)

    local shown = {}
    for _, list in ipairs({ data.risers, data.fallers }) do
        for _, row in ipairs(list) do shown[#shown + 1] = row.id end
    end
    Stockist.ItemInfo.RetryUntilNamed(self, shown, function()
        if self.frame:IsVisible() then self:Refresh() end
    end)
end

--- Choose an item: show it in the chart. From a popped-out panel that also opens the workspace if it is closed.
function Movers:Select(itemID)
    if not self.link then return end
    Stockist.Link.Select(self.link, itemID)
    Stockist.Workspace.Reveal()
end

--- Open the panel in a window of its own; it keeps this panel's link group.
function Movers:PopOut()
    Stockist.PopOut.Open("movers", { link = self.link, onlyTracked = self.onlyTracked })
end

function Movers:Apply(opts)
    self.link = opts.link
    if opts.onlyTracked ~= nil then self.onlyTracked = opts.onlyTracked end
    self:Refresh()
end

function Movers:Title() return "Movers" end

function Movers:SetItem() end

function Movers:Destroy()
    Stockist.Events:OffOwner(self)
    self.frame:Hide()
end

Stockist.Panels:Register("movers", {
    title = "Movers", create = Movers.Create,
    popout = { width = 300, height = 400, minWidth = 230, minHeight = 190 },
})
