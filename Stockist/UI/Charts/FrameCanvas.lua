local ADDON_NAME, Stockist = ...

-- Canvas implementation backed by WoW frames. Lines, rectangles and text are pooled: every redraw
-- reuses last time's objects and hides the unused ones, so redraws do not allocate.
-- Canvas interface: begin(w, h), finish(), line(x1,y1,x2,y2,color,width), rect(x,y,w,h,color),
-- text(x,y,str,color,anchor). Coordinates are pixels from the frame's bottom-left, y up.
local FrameCanvas = {}
FrameCanvas.__index = FrameCanvas
Stockist.Charts.FrameCanvas = FrameCanvas

local function createLine(frame)
    return frame:CreateLine(nil, "ARTWORK", nil, 2)
end
local function createRect(frame)
    return frame:CreateTexture(nil, "ARTWORK", nil, 1)
end
local function createText(frame)
    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetJustifyH("LEFT")
    return fs
end

local CREATORS = { line = createLine, rect = createRect, text = createText }

function FrameCanvas.New(frame)
    return setmetatable({
        frame = frame,
        pools = { line = {}, rect = {}, text = {} },
        used = { line = 0, rect = 0, text = 0 },
    }, FrameCanvas)
end

local function acquire(self, kind)
    local used = self.used[kind] + 1
    self.used[kind] = used
    local pool = self.pools[kind]
    local obj = pool[used]
    if not obj then
        obj = CREATORS[kind](self.frame)
        pool[used] = obj
    end
    obj:Show()
    return obj
end

function FrameCanvas:begin()
    self.used.line, self.used.rect, self.used.text = 0, 0, 0
end

function FrameCanvas:finish()
    for kind, pool in pairs(self.pools) do
        for i = self.used[kind] + 1, #pool do pool[i]:Hide() end
    end
end

function FrameCanvas:line(x1, y1, x2, y2, color, width)
    local l = acquire(self, "line")
    l:SetThickness(width or 1)
    l:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    l:SetStartPoint("BOTTOMLEFT", self.frame, x1, y1)
    l:SetEndPoint("BOTTOMLEFT", self.frame, x2, y2)
end

function FrameCanvas:rect(x, y, w, h, color)
    local r = acquire(self, "rect")
    r:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    r:ClearAllPoints()
    r:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", x, y)
    r:SetSize(math.max(w, 0.01), math.max(h, 0.01))
end

--- `anchor` says which point of the text sits at (x, y): "RIGHT" = right edge, vertically centred.
function FrameCanvas:text(x, y, str, color, anchor)
    local fs = acquire(self, "text")
    fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    fs:SetText(str)
    fs:ClearAllPoints()
    fs:SetPoint(anchor or "BOTTOMLEFT", self.frame, "BOTTOMLEFT", x, y)
end
