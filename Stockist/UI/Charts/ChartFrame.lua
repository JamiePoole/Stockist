local ADDON_NAME, Stockist = ...

local Charts = Stockist.Charts

-- A chart you can parent anywhere. Redraws when the config or size changes, and shows a crosshair
-- and tooltip while the mouse is over it.
--   local chart = Charts.Create(parent, config)
--   chart.frame:SetPoint(...) -- position it like any frame
--   chart:SetConfig(newConfig) -- replace what is drawn
local Chart = {}
Chart.__index = Chart

function Charts.Create(parent, config)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetClipsChildren(true)

    local hoverLayer = CreateFrame("Frame", nil, frame)
    hoverLayer:SetAllPoints()
    hoverLayer:SetFrameLevel(frame:GetFrameLevel() + 5)

    local chart = setmetatable({
        frame = frame,
        config = config,
        main = Charts.FrameCanvas.New(frame),
        hover = Charts.FrameCanvas.New(hoverLayer),
        dirty = true,
    }, Chart)

    frame:EnableMouse(true)
    frame:SetScript("OnSizeChanged", function() chart.dirty = true end)
    frame:SetScript("OnLeave", function()
        chart.lastX, chart.lastY = nil, nil
        if chart.model then Charts.Hover(chart.model, chart.hover, nil, nil) end
    end)
    frame:SetScript("OnUpdate", function() chart:OnUpdate() end)
    return chart
end

function Chart:SetConfig(config)
    self.config = config
    self.dirty = true
end

function Chart:Refresh()
    self.dirty = true
end

function Chart:CursorPosition()
    if not self.frame:IsMouseOver() then return nil end
    local scale = self.frame:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    return cx / scale - self.frame:GetLeft(), cy / scale - self.frame:GetBottom()
end

function Chart:OnUpdate()
    if self.dirty then
        local w, h = self.frame:GetSize()
        if w < 2 or h < 2 then return end
        self.dirty = false
        self.model = Charts.Build(self.config, w, h)
        Charts.Draw(self.model, self.main)
        self.lastX, self.lastY = nil, nil -- force the hover layer to repaint over the new drawing
    end
    if not self.model then return end
    local x, y = self:CursorPosition()
    if x ~= self.lastX or y ~= self.lastY then
        self.lastX, self.lastY = x, y
        Charts.Hover(self.model, self.hover, x, y)
    end
end
