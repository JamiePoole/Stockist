local ADDON_NAME, Stockist = ...

-- The status bar: one line saying how fresh the price data is and what the addon is doing about it.
--   Prices updated 12m ago  ·  next scan in 3:20  ·  321 items (6 tracked)
-- The age is coloured by freshness (green, amber, red), so "is this still current?" is answered at a glance.
-- When the Auction House is open and a scan is allowed, a "Scan now" button appears. The words are built by
-- the pure Parts; the panel only draws them and keeps them current.
local Format = Stockist.Format

local StatusBar = {}
StatusBar.__index = StatusBar
Stockist.StatusBar = StatusBar

StatusBar.HELP_KEYS = { "status-bar" }

-- How old a price reading may be and still count as fresh, or as merely stale. Scans cannot come faster than
-- every 15 minutes, so "fresh" allows two missed ones.
StatusBar.FRESH_SEC = 30 * 60
StatusBar.STALE_SEC = 3 * 3600

local GREEN, AMBER, RED, GREY = { 0.2, 0.78, 0.45 }, { 1, 0.75, 0.25 }, { 0.92, 0.3, 0.3 }, { 0.6, 0.63, 0.68 }
local SEPARATOR = Format.Colored("  " .. "-" .. "  ", 0.4, 0.43, 0.48)
local TICK = 1 -- seconds between redraws while visible

---------------------------------------------------------------------------------------------------
-- Pure part
---------------------------------------------------------------------------------------------------

--- How fresh a reading is: "fresh", "stale" or "old" (older than STALE_SEC), or "none" with no scan yet.
function StatusBar.Freshness(age)
    if not age then return "none" end
    if age <= StatusBar.FRESH_SEC then return "fresh" end
    if age <= StatusBar.STALE_SEC then return "stale" end
    return "old"
end

local function countdown(seconds)
    seconds = math.ceil(seconds)
    if seconds >= 3600 then return ("%dh"):format(math.floor(seconds / 3600)) end
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

--- The pieces of the line as plain data, left to right: { { text, colour }... }.
---   info = { now, lastScan, wait (seconds until a scan is allowed), ahOpen, scanning, autoOn, items, tracked }
function StatusBar.Parts(info)
    local parts = {}
    local age = info.lastScan and math.max(0, info.now - info.lastScan) or nil
    local fresh = StatusBar.Freshness(age)
    if fresh == "none" then
        parts[#parts + 1] = { "No prices yet", GREY }
    else
        local colour = fresh == "fresh" and GREEN or (fresh == "stale" and AMBER or RED)
        parts[#parts + 1] = { "Prices updated " .. Format.Age(age), colour }
    end

    if info.scanning then
        parts[#parts + 1] = { "scanning...", GREEN }
    elseif info.wait and info.wait > 0 then
        parts[#parts + 1] = { "next scan in " .. countdown(info.wait), GREY }
    elseif info.ahOpen then
        parts[#parts + 1] = { "ready to scan", GREEN }
    else
        parts[#parts + 1] = { "scans when you open the Auction House", GREY }
    end

    local grouped = tostring(math.floor(info.items or 0)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    local items = grouped .. " items"
    if (info.tracked or 0) > 0 then items = items .. " (" .. info.tracked .. " tracked)" end
    parts[#parts + 1] = { items, GREY }

    if info.autoOn == false then parts[#parts + 1] = { "auto-scan off", AMBER } end
    return parts
end

--- The parts joined into one colour-coded line.
function StatusBar.Line(parts)
    local out = {}
    for i, p in ipairs(parts) do
        out[i] = Format.Colored(p[1], p[2][1], p[2][2], p[2][3])
    end
    return table.concat(out, SEPARATOR)
end

--- A "Scan now" button makes sense when the Auction House is open and nothing blocks a scan.
function StatusBar.CanScanNow(info)
    return info.ahOpen == true and not info.scanning and (info.wait or 0) <= 0
end

---------------------------------------------------------------------------------------------------
-- Panel (game side)
---------------------------------------------------------------------------------------------------

--- What the line is made from right now.
local function gather()
    local scanner = Stockist.Scanner
    local count = 0
    if Stockist.db and Stockist.store then
        for _ in pairs(Stockist.store.db.items) do count = count + 1 end
    end
    return {
        now = Stockist.Clock.now(),
        lastScan = Stockist.db and Stockist.db.scan and Stockist.db.scan.last or nil,
        wait = scanner and Stockist.db and scanner:SecondsUntilNextScan() or 0,
        ahOpen = scanner and scanner.ahOpen or false,
        scanning = scanner and scanner.inProgress or false,
        autoOn = scanner and scanner:AutoEnabled(),
        items = count,
        tracked = Stockist.tracked and Stockist.tracked:Count() or 0,
    }
end

--- Create a status bar filling `parent`. `opts`: popOut (add a pop-out button).
function StatusBar.Create(parent, opts)
    opts = opts or {}
    local self = setmetatable({ elapsed = 0, shownText = nil }, StatusBar)

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    self.frame = frame

    local right = frame
    local rightPoint, rightX = "RIGHT", -6
    if opts.popOut then
        local pop = Stockist.UI.IconButton.Create(frame, { icon = "popout", width = 24, height = 20 })
        pop:SetPoint("RIGHT", -4, 0)
        pop:SetScript("OnClick", function() self:PopOut() end)
        Stockist.UI.Tooltip.Attach(pop, "popout")
        self.popOutButton = pop
        right, rightPoint, rightX = pop, "LEFT", -6
    end

    self.scanButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    self.scanButton:SetSize(80, 20)
    self.scanButton:SetText("Scan now")
    self.scanButton:SetPoint("RIGHT", right, rightPoint, rightX, 0)
    self.scanButton:SetScript("OnClick", function() self:ScanNow() end)
    self.scanButton:Hide()

    self.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.text:SetPoint("LEFT", 8, 0)
    self.text:SetPoint("RIGHT", self.scanButton, "LEFT", -8, 0)
    self.text:SetJustifyH("LEFT")
    self.text:SetWordWrap(false)

    -- Hover the line for what it means (the colours, the countdown).
    self.hit = CreateFrame("Frame", nil, frame)
    self.hit:SetAllPoints(self.text)
    self.hit:EnableMouse(true)
    Stockist.UI.Tooltip.Attach(self.hit, "status-bar")

    local function refresh()
        if frame:IsVisible() then self:Refresh() else self.stale = true end
    end
    frame:HookScript("OnShow", function()
        if self.stale then self.stale = false; self:Refresh() end
    end)
    for _, event in ipairs({ "SCAN_STARTED", "SCAN_COMPLETE", "SCAN_FAILED", "SCAN_SKIPPED", "AH_OPENED",
        "AH_CLOSED", "TRACKED_CHANGED" }) do
        Stockist.Events:On(event, refresh, self)
    end
    -- The ages and the countdown move on their own: redraw once a second while on screen, only when the words change.
    frame:SetScript("OnUpdate", function(_, dt)
        self.elapsed = self.elapsed + dt
        if self.elapsed >= TICK then
            self.elapsed = 0
            self:Refresh()
        end
    end)

    self:Refresh()
    return self
end

function StatusBar:Refresh()
    if not (Stockist.db and Stockist.store) then return end
    local info = gather()
    local text = StatusBar.Line(StatusBar.Parts(info))
    if text ~= self.shownText then
        self.shownText = text
        self.text:SetText(text)
    end
    self.scanButton:SetShown(StatusBar.CanScanNow(info))
end

--- Start a scan now (the button only shows when one is allowed); say why in chat if it is refused after all.
function StatusBar:ScanNow()
    local ok, reason = Stockist.Scanner:Start()
    if not ok and reason then Stockist.Print("can't scan: " .. reason) end
    self:Refresh()
end

--- Open the status bar in a window of its own.
function StatusBar:PopOut()
    Stockist.PopOut.Open("status", {})
end

function StatusBar:Apply() self:Refresh() end

function StatusBar:Title() return "Status" end

function StatusBar:SetItem() end

function StatusBar:Destroy()
    Stockist.Events:OffOwner(self)
    self.frame:Hide()
end

Stockist.Panels:Register("status", {
    title = "Status", create = StatusBar.Create,
    popout = { width = 560, height = 76, minWidth = 300, minHeight = 70 },
})
