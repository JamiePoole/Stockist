local ADDON_NAME, Stockist = ...

-- The workspace: one frame holding several panels in a layout. Panels that share a link group follow
-- the same selected item (Core/Link.lua). Closing the workspace does not stop the addon. Design:
-- docs/design/workspace.md.
--
-- A layout is a list of cells, each placed by fractions of the frame (x, y from the top-left, w, h):
--   { id = "chart", panel = "chart", x = 0.26, y = 0, w = 0.74, h = 1, link = "A" }
-- `panel` names a type in Stockist.Panels; a type that does not exist yet shows a labelled placeholder.
local Workspace = {}
Stockist.Workspace = Workspace

Workspace.LAYOUTS = {
    trader = {
        name = "Trader",
        cells = {
            { id = "watchlist", panel = "watchlist", title = "Watchlist", x = 0, y = 0, w = 0.27, h = 1, link = "A" },
            { id = "chart", panel = "chart", title = "Price chart", x = 0.27, y = 0, w = 0.73, h = 1, link = "A" },
        },
    },
}
Workspace.DEFAULT_LAYOUT = "trader"

local GAP = 6 -- pixels between cells

--- Pixel rectangles for a layout inside a frame of w x h: { id, x, y, w, h } with x, y measured from
--- the top-left corner. Cells are inset by half the gap so neighbours end up `gap` apart.
function Workspace.CellRects(layout, w, h, gap)
    gap = gap or GAP
    local out = {}
    for i, c in ipairs(layout.cells) do
        out[i] = {
            id = c.id,
            x = math.floor(c.x * w + gap / 2 + 0.5),
            y = math.floor(c.y * h + gap / 2 + 0.5),
            w = math.max(1, math.floor(c.w * w - gap + 0.5)),
            h = math.max(1, math.floor(c.h * h - gap + 0.5)),
        }
    end
    return out
end

---------------------------------------------------------------------------------------------------
-- Game side
---------------------------------------------------------------------------------------------------

local win, cells, layout

--- Stand-in for a panel type that is not built yet.
local function placeholder(parent, title)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("CENTER")
    fs:SetJustifyH("CENTER")
    fs:SetTextColor(0.6, 0.63, 0.7)
    fs:SetText(title .. "\n\nComing soon")
    return { frame = parent, SetItem = function() end, Refresh = function() end, placeholder = true }
end

local function layoutCells()
    if not (win and layout) then return end
    local w, h = win.content:GetWidth(), win.content:GetHeight()
    for i, rect in ipairs(Workspace.CellRects(layout, w, h)) do
        local cell = cells[i]
        cell.frame:ClearAllPoints()
        cell.frame:SetPoint("TOPLEFT", win.content, "TOPLEFT", rect.x, -rect.y)
        cell.frame:SetSize(rect.w, rect.h)
    end
end

local function build()
    layout = Workspace.LAYOUTS[Workspace.DEFAULT_LAYOUT]
    win = Stockist.UI.Window.Create({
        name = "StockistWorkspace", title = "Stockist", width = 1040, height = 640, minWidth = 700, minHeight = 460,
    })
    cells = {}
    for i, def in ipairs(layout.cells) do
        local frame = CreateFrame("Frame", nil, win.content)
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.09, 0.1, 0.13, 0.55)

        local panelType = Stockist.Panels:Get(def.panel)
        local panel
        if panelType then
            -- popOut: a panel that can open itself in its own window shows a button for it
            panel = panelType.create(frame, { link = def.link, popOut = true })
        else
            panel = placeholder(frame, def.title)
        end
        cells[i] = { def = def, frame = frame, panel = panel }
    end
    win.content:SetScript("OnSizeChanged", layoutCells)
end

--- Open the workspace. `itemID` (optional) is selected in the "A" link group; otherwise the group keeps
--- its item, falling back to the item we hold the most history for.
function Workspace.Show(itemID)
    if not win then build() end
    itemID = itemID or Stockist.Link.Get("A") or (Stockist.RichestItem and Stockist.RichestItem())
    if itemID then Stockist.Link.Select("A", itemID) end
    win.frame:Show()
    layoutCells()
    -- Frame sizes are only known after the first layout pass, so place the cells again right after.
    C_Timer.After(0, layoutCells)
end

function Workspace.IsShown()
    return win ~= nil and win.frame:IsShown()
end

local function open(arg)
    local id
    if arg ~= "" then
        id = Stockist.ParseItemID(arg)
        if not id then return Stockist.Print("usage: /stockist workspace [itemID or item link]") end
    end
    Workspace.Show(id)
end

Stockist.Commands:Register("workspace", {
    help = "workspace [item]   open the trader workspace (several panels at once)", run = open,
})
