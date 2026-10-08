local ADDON_NAME, Stockist = ...

-- The watchlist panel: every tracked item with its latest price, 24h change and a small price line.
-- Clicking a row selects the item in the panel's link group, so a chart in the same group follows.
-- Right-click a row to stop tracking it. A button under the list tracks (or untracks) the item that is
-- selected in the group. Rows are built by the pure Watchlist.Rows; the panel only draws them.
local Format = Stockist.Format

local Watchlist = {}
Watchlist.__index = Watchlist
Stockist.Watchlist = Watchlist

Watchlist.HELP_KEYS = { "watchlist-row", "watchlist-track" }

local ROW_HEIGHT = 36
local SPARK_WIDTH, SPARK_HEIGHT = 64, 22
local SPARK_SPAN = 7 * 86400
local UP, DOWN, FLAT = { 0.20, 0.78, 0.45, 1 }, { 0.92, 0.30, 0.30, 1 }, { 0.6, 0.6, 0.6, 1 }
local HEADER_HEIGHT, FOOTER_HEIGHT = 22, 26

---------------------------------------------------------------------------------------------------
-- Pure part
---------------------------------------------------------------------------------------------------

--- The points of a row's price line: hourly closes over the last 7 days, or one point per scan when the
--- hourly data is too thin to draw a line.
local function sparkPoints(store, itemID, now)
    local from = now - SPARK_SPAN
    local points = {}
    for _, c in ipairs(store:GetCandles(itemID, "hourly", from, nil)) do points[#points + 1] = { x = c.t, y = c.c } end
    if #points < 2 then
        points = {}
        for _, t in ipairs(store:Ticks(itemID, from)) do points[#points + 1] = { x = t.x, y = t.y } end
    end
    return points
end

--- Chart config for a row's price line: no axes, green when the line ends higher than it starts, red when
--- lower. Fewer than two points draw nothing.
function Watchlist.SparkConfig(points)
    local colour = FLAT
    if #points >= 2 then
        local first, last = points[1].y, points[#points].y
        colour = last > first and UP or (last < first and DOWN or FLAT)
    end
    return {
        minimal = true, transparent = true, static = true, -- a glance, not a chart: no cursor or tooltip
        series = { { type = "line", id = "price", points = #points >= 2 and points or {}, color = colour, width = 1.25 } },
    }
end

--- One row per tracked item, sorted by name: { id, name, price, change, age, spark }.
--- `price`, `change` and `age` are nil for an item with no readings. `nameOf(id)` gives the sort name.
function Watchlist.Rows(store, ids, now, nameOf)
    local rows = {}
    for _, id in ipairs(ids) do
        local last = store:Latest(id)
        rows[#rows + 1] = {
            id = id,
            name = nameOf(id),
            price = last and last.price or nil,
            scan = last and store:ScanChange(id) or nil,
            change = last and store:Change(id, 86400, now) or nil,
            age = last and (now - last.ts) or nil,
            spark = last and sparkPoints(store, id, now) or {},
        }
    end
    table.sort(rows, function(a, b)
        local x, y = a.name:lower(), b.name:lower()
        if x ~= y then return x < y end
        return a.id < b.id
    end)
    return rows
end

--- How many rows fit in `height` pixels of list, and the highest scroll offset for `count` rows.
function Watchlist.Capacity(height, count)
    local fit = math.max(1, math.floor(height / ROW_HEIGHT))
    return fit, math.max(0, count - fit)
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
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.selectedBg = row:CreateTexture(nil, "BACKGROUND")
    row.selectedBg:SetAllPoints()
    row.selectedBg:SetColorTexture(0.2, 0.45, 0.9, 0.22)
    row.hoverBg = row:CreateTexture(nil, "BACKGROUND")
    row.hoverBg:SetAllPoints()
    row.hoverBg:SetColorTexture(1, 1, 1, 0.06)
    row.hoverBg:Hide()

    row.spark = Stockist.Charts.Create(row, Watchlist.SparkConfig({}))
    row.spark.frame:SetSize(SPARK_WIDTH, SPARK_HEIGHT)
    row.spark.frame:SetPoint("RIGHT", -6, 0)
    row.spark.frame:EnableMouse(false) -- clicks go to the row

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", 8, -5)
    row.name:SetPoint("TOPRIGHT", row.spark.frame, "TOPLEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.price = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.price:SetPoint("BOTTOMLEFT", 8, 5)
    row.scan = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall") -- move since the last scan, beside the price
    row.scan:SetPoint("LEFT", row.price, "RIGHT", 6, 0)
    row.change = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall") -- 24h, quieter
    row.change:SetPoint("LEFT", row.scan, "RIGHT", 6, 0)

    row:SetScript("OnEnter", function(r)
        r.hoverBg:Show()
        if r.itemID then
            GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
            local _, short = Stockist.Help.Lines("watchlist-row")
            GameTooltip:AddLine(Stockist.ItemInfo.ColoredName(r.itemID), 1, 1, 1)
            if short then GameTooltip:AddLine(short, 0.8, 0.8, 0.8, true) end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(r)
        r.hoverBg:Hide()
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(r, mouse)
        if not r.itemID then return end
        if mouse == "RightButton" then
            self:Untrack(r.itemID)
        else
            self:Select(r.itemID)
        end
    end)
    return row
end

--- Create a watchlist panel filling `parent`. `opts`: link (the link group to select into and follow).
function Watchlist.Create(parent, opts)
    opts = opts or {}
    local self = setmetatable({ link = opts.link, offset = 0, rowFrames = {}, rows = {} }, Watchlist)

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    self.frame = frame

    self.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.title:SetPoint("TOPLEFT", 8, -5)
    self.title:SetText("Watchlist")

    self.list = CreateFrame("Frame", nil, frame)
    self.list:SetPoint("TOPLEFT", 0, -HEADER_HEIGHT)
    self.list:SetPoint("BOTTOMRIGHT", 0, FOOTER_HEIGHT)
    self.list:EnableMouseWheel(true)
    self.list:SetScript("OnMouseWheel", function(_, delta) self:Scroll(-delta) end)

    self.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.empty:SetPoint("TOPLEFT", self.list, "TOPLEFT", 14, -16)
    self.empty:SetPoint("TOPRIGHT", self.list, "TOPRIGHT", -14, -16)
    self.empty:SetJustifyH("LEFT")
    self.empty:SetJustifyV("TOP")
    self.empty:SetWordWrap(true)
    self.empty:SetTextColor(0.7, 0.72, 0.78)
    self.empty:SetText("Nothing tracked yet. Open an item in the chart and press Track, or use /stockist track <item>.")

    self.trackButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    self.trackButton:SetHeight(20)
    self.trackButton:SetPoint("BOTTOMLEFT", 6, 3)
    self.trackButton:SetPoint("BOTTOMRIGHT", -6, 3)
    self.trackButton:SetScript("OnClick", function() self:ToggleSelected() end)
    Stockist.UI.Tooltip.Attach(self.trackButton, "watchlist-track")

    local function refresh() if frame:IsVisible() then self:Refresh() end end
    self.list:SetScript("OnSizeChanged", refresh) -- how many rows fit depends on the list height
    Stockist.Events:On("TRACKED_CHANGED", refresh, self)
    Stockist.Events:On("SCAN_COMPLETE", refresh, self)
    Stockist.Events:On("LINK_SELECTED", function(group)
        if group == self.link then refresh() end
    end, self)

    -- Item names arrive from the server a moment after the first request.
    local loader = CreateFrame("Frame")
    loader:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    loader:SetScript("OnEvent", refresh)

    self:Refresh()
    return self
end

--- Select an item in this panel's link group (so linked panels follow).
function Watchlist:Select(itemID)
    if self.link then Stockist.Link.Select(self.link, itemID) end
end

function Watchlist:SetItem(itemID)
    -- The watchlist is where items are picked, so it only highlights the selection; Refresh reads it from the group.
    self:Refresh()
end

function Watchlist:Untrack(itemID)
    if Stockist.tracked:Remove(itemID) then
        Stockist.Events:Fire("TRACKED_CHANGED", itemID, false)
    end
end

--- Track the selected item, or stop tracking it if it already is.
function Watchlist:ToggleSelected()
    local id = Stockist.Link.Get(self.link)
    if not id then return end
    if Stockist.tracked:Has(id) then
        self:Untrack(id)
    elseif Stockist.tracked:Add(id) then
        Stockist.Events:Fire("TRACKED_CHANGED", id, true)
    end
end

function Watchlist:Scroll(rows)
    local _, maxOffset = Watchlist.Capacity(self.list:GetHeight(), #self.rows)
    self.offset = math.max(0, math.min(maxOffset, self.offset + rows))
    self:Refresh()
end

function Watchlist:Refresh()
    if not (Stockist.store and Stockist.tracked) then return end
    local now = Stockist.Clock.now()
    self.rows = Watchlist.Rows(Stockist.store, Stockist.tracked:List(), now, sortName)
    local fit, maxOffset = Watchlist.Capacity(self.list:GetHeight(), #self.rows)
    self.offset = math.min(self.offset, maxOffset)
    local selected = Stockist.Link.Get(self.link)

    self.empty:SetShown(#self.rows == 0)
    self.title:SetText(#self.rows > 0 and ("Watchlist (%d)"):format(#self.rows) or "Watchlist")
    for slot = 1, math.max(fit, #self.rowFrames) do
        local data = slot <= fit and self.rows[self.offset + slot] or nil
        local row = self.rowFrames[slot]
        if data and not row then
            row = buildRow(self, self.list)
            self.rowFrames[slot] = row
        end
        if row then
            if data then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", self.list, "TOPLEFT", 0, -(slot - 1) * ROW_HEIGHT)
                row:SetPoint("TOPRIGHT", self.list, "TOPRIGHT", 0, -(slot - 1) * ROW_HEIGHT)
                row.itemID = data.id
                row.name:SetText(Stockist.ItemInfo.ColoredName(data.id))
                row.price:SetText(data.price and Format.MoneyDisplay(data.price) or "no data yet")
                row.scan:SetText(Format.Change(data.scan))
                row.change:SetText(data.change and (Format.Change(data.change) .. " 24h") or "")
                row.spark:SetConfig(Watchlist.SparkConfig(data.spark))
                row.selectedBg:SetShown(data.id == selected)
                row:Show()
            else
                row.itemID = nil
                row:Hide()
            end
        end
    end

    -- The button acts on the item selected in the group.
    local tracked = selected and Stockist.tracked:Has(selected)
    self.trackButton:SetText(tracked and "Stop tracking this item" or "Track this item")
    Stockist.UI.Tooltip.SetAvailable(self.trackButton, selected ~= nil)
end

function Watchlist:Destroy()
    Stockist.Events:OffOwner(self)
    self.frame:Hide()
end

Stockist.Panels:Register("watchlist", { title = "Watchlist", create = Watchlist.Create })
