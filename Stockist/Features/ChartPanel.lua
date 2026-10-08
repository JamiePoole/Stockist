local ADDON_NAME, Stockist = ...

-- The price chart as a panel: item header (name, price, change), scope and indicator buttons, the chart,
-- and the tutorial legend. It fills whatever frame it is given and keeps its own state, so any number of
-- them can exist at once, in a window or in the workspace. The config logic is in Features/PriceChart.lua.
local Format = Stockist.Format
local PriceChart = Stockist.PriceChart

local ChartPanel = {}
ChartPanel.__index = ChartPanel
Stockist.ChartPanel = ChartPanel

local LEGEND_GAP = 12 -- empty space between the chart and the legend below it
local HEADER_MARGIN = 10 -- clear space kept between the header text and the buttons
local UNDERLINE_REST, UNDERLINE_HOVER = 0.35, 0.95 -- the underline that marks the item name as clickable

--- A switch button: coloured while on (and usable), plain while off, greyed text when it cannot be used.
local function paintToggle(btn, on, enabled)
    Stockist.UI.Button.SetActive(btn, on and enabled)
    if not enabled then btn:GetFontString():SetTextColor(0.5, 0.5, 0.5) end
end

local function button(parent, text, width, helpKey, extra)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 20)
    b:SetText(text)
    Stockist.UI.Tooltip.Attach(b, helpKey, extra)
    return b
end

local function showItemTooltip(owner, itemID)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(itemID)
    else
        GameTooltip:SetHyperlink("item:" .. itemID)
    end
    GameTooltip:AddLine("Click to pick another item", 0.55, 0.62, 0.75)
    GameTooltip:Show()
end

--- Create a chart panel filling `parent`. `opts` (optional): itemID, timeframe ("1D"/"1W"/"1M"),
--- indicators ({ sma = bool, bollinger = bool }), link (a link group name: the panel then follows
--- that group's selected item, see Core/Link.lua), popOut (add a pop-out icon button, rightmost in the
--- header, that opens the item in its own window).
function ChartPanel.Create(parent, opts)
    opts = opts or {}
    local self = setmetatable({
        link = opts.link,
        state = {
            itemID = opts.itemID or Stockist.Link.Get(opts.link),
            timeframe = opts.timeframe or "1D",
            indicators = opts.indicators or { sma = true, bollinger = false },
        },
        available = {}, -- indicator availability for the chart on screen, set by Refresh
        tfButtons = {},
        toggleButtons = {},
    }, ChartPanel)

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    self.frame = frame

    -- Header, left to right: item name (hover for its tooltip), price, 24h change and age.
    self.nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.nameText:SetPoint("TOPLEFT", 2, -4)
    self.nameText:SetJustifyH("LEFT")
    self.nameText:SetWordWrap(false) -- too long for the room: cut off with "..." (LayoutHeader sets the width)
    self.nameHit = CreateFrame("Frame", nil, frame)
    self.nameHit:SetPoint("TOPLEFT", self.nameText, "TOPLEFT")
    self.nameHit:EnableMouse(true)
    -- A thin underline says "this is clickable"; it brightens under the mouse.
    self.nameUnderline = self.nameHit:CreateTexture(nil, "OVERLAY")
    self.nameUnderline:SetHeight(1)
    self.nameUnderline:SetPoint("BOTTOMLEFT", 0, -1)
    self.nameUnderline:SetPoint("BOTTOMRIGHT", 0, -1)
    self.nameUnderline:SetColorTexture(0.6, 0.8, 1, UNDERLINE_REST)
    self.nameHit:SetScript("OnEnter", function(hit)
        self.nameUnderline:SetColorTexture(0.6, 0.8, 1, UNDERLINE_HOVER)
        if self.state.itemID and self.statusKind ~= "notfound" then showItemTooltip(hit, self.state.itemID) end
    end)
    self.nameHit:SetScript("OnLeave", function()
        self.nameUnderline:SetColorTexture(0.6, 0.8, 1, UNDERLINE_REST)
        GameTooltip:Hide()
    end)
    -- Clicking the name opens the item picker under it.
    self.nameHit:SetScript("OnMouseUp", function(hit)
        GameTooltip:Hide()
        Stockist.ItemPicker.Show(hit, function(itemID) self:Pick(itemID) end)
    end)

    self.priceText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.priceText:SetPoint("LEFT", self.nameText, "RIGHT", 12, 0)
    -- The move since the previous scan sits right beside the price; hover it for what it means.
    self.scanText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.scanText:SetPoint("LEFT", self.priceText, "RIGHT", 8, 0)
    self.scanHit = CreateFrame("Frame", nil, frame)
    self.scanHit:SetAllPoints(self.scanText)
    self.scanHit:EnableMouse(true)
    Stockist.UI.Tooltip.Attach(self.scanHit, "change-scan")
    self.metaText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.metaText:SetPoint("LEFT", self.scanText, "RIGHT", 12, 0)

    -- Controls, right to left: pop out | time scope buttons | divider | chart overlays.
    local prev
    local gap = -2
    local used = 0 -- width taken by the buttons, from the right edge: the header text must stay clear of it
    if opts.popOut then
        local pop = Stockist.UI.IconButton.Create(frame, { icon = "popout", width = 24, height = 20 })
        pop:SetPoint("TOPRIGHT", 0, 0)
        pop:SetScript("OnClick", function() self:PopOut() end)
        Stockist.UI.Tooltip.Attach(pop, "popout")
        self.popOutButton = pop
        prev, gap, used = pop, -8, 24
    end
    for i = #PriceChart.TIMEFRAMES, 1, -1 do
        local tf = PriceChart.TIMEFRAMES[i]
        local b = button(frame, tf.key, 40, "timeframe-" .. tf.key)
        if prev then b:SetPoint("RIGHT", prev, "LEFT", gap, 0) else b:SetPoint("TOPRIGHT", 0, 0) end
        used = used + (prev and -gap or 0) + 40
        gap = -2
        b:SetScript("OnClick", function()
            if self.state.timeframe == tf.key then return end -- already the active scope
            self.state.timeframe = tf.key
            self:Refresh()
        end)
        self.tfButtons[tf.key] = b
        prev = b
    end
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.18)
    divider:SetSize(1, 18)
    divider:SetPoint("RIGHT", prev, "LEFT", -7, 0)
    prev = divider
    used = used + 7 + 1
    for _, def in ipairs({ { "bollinger", "BB", "bollinger" }, { "sma", "SMA", "sma" } }) do
        local key = def[1]
        local whyDisabled = function()
            local a = self.available[key]
            if a and not a.ok then
                return ("Not available in this view yet: it needs at least %d points and this view has %d."):format(a.need, a.have)
            end
        end
        local b = button(frame, def[2], 40, def[3], whyDisabled)
        b:SetPoint("RIGHT", prev, "LEFT", -7, 0)
        used = used + 7 + 40
        b:SetScript("OnClick", function(btn)
            if not Stockist.UI.Tooltip.IsAvailable(btn) then return end
            self.state.indicators[key] = not self.state.indicators[key]
            self:Refresh()
        end)
        self.toggleButtons[key] = b
        prev = b
    end

    self.controlsWidth = used
    self.metaChoices = { "" }
    self.chart = Stockist.Charts.Create(frame, { series = {} })

    -- Legend: the key on the left, "what to look for" (blue) on the right. The text carries its own
    -- colours, so the font strings are plain white by default. Both columns hang from the same line just
    -- under the chart, so their headings are level. Each runs from `leftAnchor` (offset leftX) to
    -- `rightAnchor` (offset rightX) along the chart's bottom edge.
    local function legendColumn(leftAnchor, leftX, rightAnchor, rightX)
        local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", self.chart.frame, leftAnchor, leftX, -LEGEND_GAP)
        fs:SetPoint("TOPRIGHT", self.chart.frame, rightAnchor, rightX, -LEGEND_GAP)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetTextColor(1, 1, 1)
        fs:SetWordWrap(true)
        return fs
    end
    self.legendKey = legendColumn("BOTTOMLEFT", 2, "BOTTOM", -10)
    self.legendTips = legendColumn("BOTTOM", 10, "BOTTOMRIGHT", -2)
    -- Shown instead of the chart when there is nothing to chart (see PriceChart.Status).
    self.message = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.message:SetPoint("LEFT", frame, "LEFT", 40, 0)
    self.message:SetPoint("RIGHT", frame, "RIGHT", -40, 0)
    self.message:SetJustifyH("CENTER")
    self.message:SetWordWrap(true)
    self.message:SetTextColor(0.7, 0.72, 0.78)
    self.message:Hide()

    -- The legend's height depends on its width, so make room for it again whenever the panel resizes.
    frame:SetScript("OnSizeChanged", function()
        self:LayoutHeader()
        if self.state.itemID then self:LayoutChart() end
    end)

    -- Item names arrive from the server a moment after the first request.
    -- A load that fails means the item does not exist, which turns the panel into "Item not found".
    local loader = CreateFrame("Frame")
    loader:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    loader:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    loader:SetScript("OnEvent", function(_, event, itemID, success)
        if event == "ITEM_DATA_LOAD_RESULT" then Stockist.ItemInfo.NoteLoadResult(itemID, success) end
        if frame:IsVisible() and itemID == self.state.itemID then self:Refresh() end
    end)

    Stockist.Events:On("SCAN_COMPLETE", function()
        if frame:IsVisible() then self:Refresh() end
    end, self)
    Stockist.Events:On("TUTORIAL_CHANGED", function()
        if frame:IsVisible() then self:Refresh() end
    end, self)

    Stockist.Events:On("LINK_SELECTED", function(group, itemID)
        if self.link and group == self.link and itemID ~= self.state.itemID then self:SetItem(itemID) end
    end, self)

    self:Refresh()
    return self
end

--- Open this panel's item in its own window (the panel stays where it is).
function ChartPanel:PopOut()
    if self.state.itemID then Stockist.PriceChart.Show(self.state.itemID) end
end

--- The player chose an item (from the picker): select it for the whole link group, or just here if unlinked.
function ChartPanel:Pick(itemID)
    if self.link then
        Stockist.Link.Select(self.link, itemID)
        if self.state.itemID ~= itemID then self:SetItem(itemID) end
    else
        self:SetItem(itemID)
    end
end

function ChartPanel:SetItem(itemID)
    self.state.itemID = itemID
    self:Refresh()
end

function ChartPanel:GetItem()
    return self.state.itemID
end

--- Size the chart to leave room for the legend (tutorial mode) under it, whose height follows its text.
function ChartPanel:LayoutChart()
    if self.statusKind then return end -- a message is showing instead of the chart and legend
    local tutorial = Stockist.Help.TutorialEnabled()
    self.legendKey:SetShown(tutorial)
    self.legendTips:SetShown(tutorial)
    local legendHeight = 0
    if tutorial then
        -- Before the first layout pass the width is 0 and the measured height is not meaningful.
        local known = self.legendKey:GetWidth() > 1
        legendHeight = known and math.max(self.legendKey:GetStringHeight(), self.legendTips:GetStringHeight()) or 110
    end
    local chartFrame = self.chart.frame
    chartFrame:ClearAllPoints()
    chartFrame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -28)
    chartFrame:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0, tutorial and (legendHeight + LEGEND_GAP) or 0)
end

--- Fit the header (name, price, move since the last scan, and the "24h / updated" text) into the room left
--- of the buttons. What gives way first: the "updated ..." text, then the 24h move, then the item name,
--- which is cut off with "..." (hover it for the full name). The price and the scan move are never cut.
--- A message such as "no data yet" outranks the name. Runs again whenever the text or the size changes.
function ChartPanel:LayoutHeader()
    local width = self.frame:GetWidth()
    local natural = self.nameText:GetStringWidth()
    local price, scan = self.priceText:GetStringWidth(), self.scanText:GetStringWidth()
    local fixed = (price > 0 and (12 + price) or 0) + (scan > 0 and ((price > 0 and 8 or 12) + scan) or 0) -- with their gaps
    local room = width - self.controlsWidth - HEADER_MARGIN
    local choices = self.metaChoices

    -- Empty pieces take no room: each piece hangs from the last one that has text, so the gaps between the
    -- pieces that are shown are exactly the ones counted below.
    self.priceText:ClearAllPoints()
    self.priceText:SetPoint("LEFT", self.nameText, "RIGHT", 12, 0)
    self.scanText:ClearAllPoints()
    self.scanText:SetPoint("LEFT", price > 0 and self.priceText or self.nameText, "RIGHT", price > 0 and 8 or 12, 0)
    self.metaText:ClearAllPoints()
    self.metaText:SetPoint("LEFT", scan > 0 and self.scanText or (price > 0 and self.priceText or self.nameText),
        "RIGHT", 12, 0)

    local chosen, meta = choices[1], 0
    if width > 1 then
        chosen = nil
        for _, text in ipairs(choices) do
            self.metaText:SetText(text)
            local w = text ~= "" and (12 + self.metaText:GetStringWidth()) or 0
            if natural + fixed + w <= room then chosen, meta = text, w break end
        end
        if not chosen then
            -- Nothing fits next to the whole name: keep a message, drop the rest, and shorten the name.
            chosen = self.metaKeep and choices[1] or ""
            self.metaText:SetText(chosen)
            meta = chosen ~= "" and (12 + self.metaText:GetStringWidth()) or 0
        end
    end
    self.metaText:SetText(chosen)

    local nameWidth = natural + 1
    if width > 1 and natural + fixed + meta > room then
        nameWidth = room - fixed - meta
    end
    self.nameText:SetWidth(math.max(1, nameWidth))
    self.nameHit:SetSize(math.max(1, math.min(natural, nameWidth)), math.max(1, self.nameText:GetStringHeight()))
end

--- Replace the chart with a message: the item does not exist ("404"), or it exists but has no prices.
function ChartPanel:ShowStatus(status)
    local state = self.state
    self.statusKind = status.kind
    self.metaKeep = false
    if status.kind == "notfound" then
        self.nameText:SetText(Format.Colored("Item not found", 0.92, 0.3, 0.3))
        self.metaChoices = { "" }
    elseif status.kind == "noitem" then
        self.nameText:SetText(Format.Colored("Choose an item", 0.6, 0.8, 1)) -- click it for the picker
        self.metaChoices = { "" }
    else
        self.nameText:SetText(Stockist.ItemInfo.ColoredName(state.itemID))
        self.metaChoices = { "no data yet" }
        self.metaKeep = true -- the reason there is no chart: the name gives way before this does
    end
    self.priceText:SetText("")
    self.scanText:SetText("")
    self:LayoutHeader()

    local Tooltip = Stockist.UI.Tooltip
    for _, btn in pairs(self.tfButtons) do
        Tooltip.SetAvailable(btn, false)
        Stockist.UI.Button.SetSelected(btn, false)
    end
    for _, btn in pairs(self.toggleButtons) do
        Tooltip.SetAvailable(btn, false)
        paintToggle(btn, false, false)
    end
    self.available = {}

    self.chart.frame:Hide()
    self.legendKey:Hide()
    self.legendTips:Hide()
    self.message:SetText(status.text)
    self.message:Show()
end

--- Go back to the normal chart after a message.
function ChartPanel:HideStatus()
    if not self.statusKind then return end
    self.statusKind = nil
    self.message:Hide()
    self.chart.frame:Show()
end

--- Redraw everything from the current item, scope and indicators.
function ChartPanel:Refresh()
    local state = self.state
    if not Stockist.store then return end
    if not state.itemID then
        return self:ShowStatus({
            kind = "noitem",
            text = "No item selected. Click \"Choose an item\" above, or pick one from the watchlist.",
        })
    end
    local now = Stockist.Clock.now()
    local lastScan = Stockist.db and Stockist.db.scan and Stockist.db.scan.last
    local status = PriceChart.Status(Stockist.store, state.itemID, Stockist.ItemInfo.Exists(state.itemID), lastScan, now)
    if status.kind ~= "ok" then return self:ShowStatus(status) end
    self:HideStatus()
    local config = PriceChart.BuildConfig(Stockist.store, state.itemID, state.timeframe,
        state.indicators, now, Stockist.Clock.tzOffset())
    self.chart:SetConfig(config)
    self.available = config.indicators

    self.nameText:SetText(Stockist.ItemInfo.ColoredName(state.itemID))
    local parts = PriceChart.HeaderParts(Stockist.store, state.itemID, now)
    self.priceText:SetText(parts and Format.MoneyDisplay(parts.price) or "")
    self.scanText:SetText(parts and Format.Change(parts.scan) or "")
    self.metaChoices = parts and PriceChart.MetaChoices(parts) or { "no data yet" }
    self.metaKeep = parts == nil
    self:LayoutHeader()

    local Tooltip = Stockist.UI.Tooltip
    -- The active scope is shown as selected (blue), not disabled: it is simply the one in use.
    for key, btn in pairs(self.tfButtons) do
        Tooltip.SetAvailable(btn, true)
        Stockist.UI.Button.SetSelected(btn, key == state.timeframe)
    end
    for key, btn in pairs(self.toggleButtons) do
        local ok = self.available[key].ok
        Tooltip.SetAvailable(btn, ok) -- a disabled button keeps its tooltip, which says why
        paintToggle(btn, state.indicators[key], ok)
    end

    -- The legend under the chart is part of tutorial mode (toggled from the window header).
    local key, tips = Stockist.Help.Legend()
    self.legendKey:SetText(key or "")
    self.legendTips:SetText(tips or "")
    self:LayoutChart()
end

--- Stop listening for events (for a panel that is being thrown away).
function ChartPanel:Destroy()
    Stockist.Events:OffOwner(self)
    self.frame:Hide()
end

Stockist.Panels:Register("chart", { title = "Price chart", create = ChartPanel.Create })
