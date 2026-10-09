local ADDON_NAME, Stockist = ...

-- The ticker: a thin strip that scrolls your tracked items past, each with its price and its move, like the
-- tape on a trading screen. With only a few items tracked it is topped up with the biggest movers on the
-- market, so there is always something moving past. It is built to be small enough to leave on screen on its own (pop it out). Hover
-- to pause it; click an item to show it in the chart (the panel's link group). Drop an item on it to track it.
-- When everything fits it stands still instead of scrolling. Segments and scrolling maths are pure.
local Format = Stockist.Format

local Ticker = {}
Ticker.__index = Ticker
Stockist.Ticker = Ticker

Ticker.HELP_KEYS = { "ticker-item" }

local SPEED = 38        -- pixels per second
local GAP = 36          -- space between one item and the next
local EDGE = 8          -- left margin when the tape stands still
local BUTTON_ROOM = 32  -- kept clear on the right for the pop-out button
local MOVERS = 20       -- the number of biggest movers added to a short list
local FILL_TO = 6       -- fewer tracked items than this and the tape is topped up with market movers

---------------------------------------------------------------------------------------------------
-- Pure part
---------------------------------------------------------------------------------------------------

--- The items to show, in the order of `rows`: { id, name, price } for each one that has a price.
--- Reuses the watchlist's rows, so both lists agree.
function Ticker.Segments(rows)
    local out = {}
    for _, row in ipairs(rows) do
        if row.price then out[#out + 1] = { id = row.id, name = row.name, price = row.price } end
    end
    return out
end

--- The biggest movers among `rows` (any items with prices): the `limit` with the largest move, up or down,
--- by their 24h move or, lacking that, their recent move. Items that have not moved at all, or have no
--- move to measure, are left out. Shown in name order, like a tracked list.
function Ticker.MoverSegments(rows, limit)
    local scored = {}
    for _, row in ipairs(rows) do
        local move = row.change or row.recent
        if row.price and move and move ~= 0 then scored[#scored + 1] = { row = row, size = math.abs(move) } end
    end
    table.sort(scored, function(a, b)
        if a.size ~= b.size then return a.size > b.size end
        return a.row.id < b.row.id
    end)
    local picked = {}
    for i = 1, math.min(limit, #scored) do picked[#picked + 1] = scored[i].row end
    table.sort(picked, function(a, b)
        local x, y = a.name:lower(), b.name:lower()
        if x ~= y then return x < y end
        return a.id < b.id
    end)
    return Ticker.Segments(picked)
end

--- The move to show for an item: over the last 24 hours (or as far back as we hold, if that is at least
--- half a day, labelled with how far), otherwise the recent move, labelled "recent". Returns percent and
--- the label to show beside it (nil for a plain 24h move); nil when there is nothing to measure.
function Ticker.Move(store, itemID, now)
    local parts = Stockist.PriceChart.HeaderParts(store, itemID, now, "1D")
    if not parts then return nil end
    if parts.change then
        return parts.change, parts.changeLabel ~= "24h" and parts.changeLabel or nil
    end
    if parts.recent then return parts.recent, "recent" end
    return nil
end

--- Whether the tape has to scroll: it does when its items are wider than the room.
function Ticker.NeedsScroll(contentWidth, viewWidth)
    return contentWidth > viewWidth
end

--- The tape's offset after `dt` seconds. The tape is the items twice over, side by side, so when the first
--- copy has gone by the second sits exactly where it was and the jump is not visible. `loop` is the width of
--- one copy. The offset runs from 0 down to -loop.
function Ticker.Advance(offset, dt, speed, loop)
    if loop <= 0 then return 0 end
    offset = offset - speed * dt
    while offset <= -loop do offset = offset + loop end
    return offset
end

---------------------------------------------------------------------------------------------------
-- Panel (game side)
---------------------------------------------------------------------------------------------------

local function sortName(id)
    return Stockist.ItemInfo.Name(id) or ("item:" .. id)
end

--- One tape item as text: "Linen Cloth  1g 20s  +3.10%", with a grey label after the move when it does not
--- cover a full 24 hours ("+3.10% 9h", "+0.80% recent"). A heading is just its words.
local function segmentText(seg)
    if seg.heading then return Format.Colored(seg.heading, 0.6, 0.8, 1) end
    local text = Stockist.ItemInfo.ColoredName(seg.id) .. "  " .. Format.MoneyDisplay(seg.price)
    if seg.move then
        text = text .. "  " .. Format.Change(seg.move)
        if seg.moveLabel then text = text .. " " .. Format.Colored(seg.moveLabel, 0.6, 0.63, 0.68) end
    end
    return text
end

--- Create a ticker filling `parent`. `opts`: link (the group to select into), popOut (add a pop-out button).
function Ticker.Create(parent, opts)
    opts = opts or {}
    local self = setmetatable({ link = opts.link, offset = 0, items = {}, loop = 0, copies = {} }, Ticker)

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:EnableMouse(true)
    self.frame = frame

    if opts.popOut then
        local pop = Stockist.UI.IconButton.Create(frame, { icon = "popout", width = 24, height = 20 })
        pop:SetPoint("RIGHT", -4, 0)
        pop:SetScript("OnClick", function() self:PopOut() end)
        Stockist.UI.Tooltip.Attach(pop, "popout")
        self.popOutButton = pop
    end

    -- The window the tape moves through: everything outside it is clipped.
    self.view = CreateFrame("Frame", nil, frame)
    self.view:SetClipsChildren(true)
    self.view:SetPoint("TOPLEFT", 0, 0)
    self.view:SetPoint("BOTTOMRIGHT", opts.popOut and -BUTTON_ROOM or 0, 0)

    self.tape = CreateFrame("Frame", nil, self.view)
    self.tape:SetHeight(1)

    self.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.empty:SetPoint("LEFT", EDGE, 0)
    self.empty:SetTextColor(0.7, 0.72, 0.78)
    self.empty:SetText("No prices yet: open the Auction House for a first scan, then tracked items (or the biggest movers) scroll past here.")

    local function refresh()
        if frame:IsVisible() then self:Refresh() else self.stale = true end
    end
    frame:HookScript("OnShow", function()
        if self.stale then self.stale = false; self:Refresh() end
    end)
    frame:SetScript("OnSizeChanged", refresh)
    Stockist.Events:On("TRACKED_CHANGED", refresh, self)
    Stockist.Events:On("SCAN_COMPLETE", refresh, self)
    local loader = CreateFrame("Frame")
    loader:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    loader:SetScript("OnEvent", refresh)

    frame:SetScript("OnUpdate", function(_, dt) self:Tick(dt) end)

    -- An item dropped on the strip is tracked and shown in the chart.
    Stockist.ItemPicker.AcceptDrops(frame, function(itemID) self:Drop(itemID) end,
        { hint = true, text = "Drop to track this item" })

    self:Refresh()
    return self
end

local function buildItem(self, index)
    local btn = CreateFrame("Button", nil, self.tape)
    btn:RegisterForClicks("LeftButtonUp")
    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.label:SetPoint("LEFT", 0, 0)
    btn:SetScript("OnClick", function(b)
        if b.itemID then self:Select(b.itemID) end
    end)
    btn:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        local _, short = Stockist.Help.Lines("ticker-item")
        GameTooltip:AddLine(b.itemID and Stockist.ItemInfo.ColoredName(b.itemID) or "", 1, 1, 1)
        if short then GameTooltip:AddLine(short, 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.copies[index] = btn
    return btn
end

--- Rebuild the tape from the tracked items. Keeps the scroll position, so a new price does not restart it.
function Ticker:Refresh()
    if not (Stockist.store and Stockist.tracked) then return end
    local now = Stockist.Clock.now()
    local ids = Stockist.tracked:List()
    self.items = Ticker.Segments(Stockist.Watchlist.Rows(Stockist.store, ids, now, sortName, true))
    if #self.items < FILL_TO then
        -- Too few of your own to fill the strip: follow them with what is moving most across the market,
        -- under a heading saying so (items you already track are not repeated).
        local mine = {}
        for _, id in ipairs(ids) do mine[id] = true end
        local others = {}
        for _, id in ipairs(Stockist.store:Items()) do
            if not mine[id] then others[#others + 1] = id end
        end
        local movers = Ticker.MoverSegments(Stockist.Watchlist.Rows(Stockist.store, others, now, sortName, true), MOVERS)
        if #movers > 0 then
            self.items[#self.items + 1] = { heading = "Market movers" }
            for _, seg in ipairs(movers) do self.items[#self.items + 1] = seg end
        end
    end
    for _, seg in ipairs(self.items) do
        if seg.id then seg.move, seg.moveLabel = Ticker.Move(Stockist.store, seg.id, now) end
    end
    self.empty:SetShown(#self.items == 0)

    -- Lay one copy of the items out, measuring as we go; a second copy follows when the tape scrolls.
    local x, n = 0, #self.items
    local widths, starts = {}, {}
    for i, seg in ipairs(self.items) do
        local btn = self.copies[i] or buildItem(self, i)
        btn.itemID = seg.id -- nil for a heading
        btn.label:SetText(segmentText(seg))
        local w = btn.label:GetStringWidth()
        widths[i], starts[i] = w, x
        btn:SetSize(w + GAP, 20)
        btn:ClearAllPoints()
        btn:SetPoint("LEFT", self.tape, "LEFT", x, 0)
        btn:Show()
        x = x + w + GAP
    end
    self.loop = x
    self.scrolling = n > 0 and Ticker.NeedsScroll(x - GAP, self.view:GetWidth() - EDGE)

    -- The repeat copies (indices n+1 .. 2n) exist only while scrolling.
    for i = 1, n do
        local idx = n + i
        local btn = self.copies[idx] or buildItem(self, idx)
        if self.scrolling then
            btn.itemID = self.items[i].id
            btn.label:SetText(segmentText(self.items[i]))
            btn:SetSize(widths[i] + GAP, 20)
            btn:ClearAllPoints()
            btn:SetPoint("LEFT", self.tape, "LEFT", self.loop + starts[i], 0)
            btn:Show()
        else
            btn.itemID = nil
            btn:Hide()
        end
    end
    for i = 2 * n + 1, #self.copies do self.copies[i].itemID = nil; self.copies[i]:Hide() end
    self.tape:SetSize(self.scrolling and self.loop * 2 or math.max(1, self.loop), 20)
    if not self.scrolling then self.offset = 0 end
    self:Place()
end

--- Position the tape in its window.
function Ticker:Place()
    self.tape:ClearAllPoints()
    self.tape:SetPoint("LEFT", self.view, "LEFT", EDGE + self.offset, 0)
end

--- Called every frame: scroll unless the mouse is over the strip or there is nothing to scroll.
function Ticker:Tick(dt)
    if not self.scrolling then return end
    if self.frame:IsMouseOver() then return end
    self.offset = Ticker.Advance(self.offset, dt, SPEED, self.loop)
    self:Place()
end

--- Choose an item: show it in the chart. From a popped-out ticker that also opens the workspace if it is closed.
function Ticker:Select(itemID)
    if not self.link then return end
    Stockist.Link.Select(self.link, itemID)
    Stockist.Workspace.Reveal()
end

--- Open the ticker in a window of its own; it keeps this panel's link group.
function Ticker:PopOut()
    Stockist.PopOut.Open("ticker", { link = self.link })
end

function Ticker:Apply(opts)
    self.link = opts.link
    self:Refresh()
end

function Ticker:Title() return "Ticker" end

function Ticker:SetItem() end

--- An item was dropped on the strip: track it and show it in the chart.
function Ticker:Drop(itemID)
    if Stockist.ItemInfo.Exists(itemID) == false then return end
    if Stockist.tracked:Add(itemID) then Stockist.Events:Fire("TRACKED_CHANGED", itemID, true) end
    self:Select(itemID)
end

function Ticker:Destroy()
    Stockist.Events:OffOwner(self)
    self.frame:Hide()
end

Stockist.Panels:Register("ticker", {
    title = "Ticker", create = Ticker.Create,
    popout = { width = 640, height = 76, minWidth = 300, minHeight = 70 },
})
