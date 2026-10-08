load_support("recording_canvas")

local FILES = {
    "Core/Registry.lua", "Core/Format.lua", "Data/Indicators.lua",
    "UI/Charts/Charts.lua", "UI/Charts/Util.lua", "UI/Charts/Scale.lua", "UI/Charts/Formatters.lua",
    "UI/Charts/Theme.lua", "UI/Charts/Series/Line.lua", "UI/Charts/Series/Candle.lua",
    "UI/Charts/Series/Bar.lua", "UI/Charts/Overlays/Overlays.lua", "UI/Charts/Core.lua",
}

local function ns() return load_addon(unpack(FILES)) end

local function linePoints(n, fn)
    local pts = {}
    for i = 1, n do pts[i] = { x = i * 100, y = fn(i) } end
    return pts
end

-- Util -----------------------------------------------------------------------------------------

test("Util.Nearest finds the closest point by x", function()
    local U = ns().Charts.Util
    local pts = { { x = 10 }, { x = 20 }, { x = 40 } }
    eq(U.Nearest(pts, 0), 1)
    eq(U.Nearest(pts, 14), 1)
    eq(U.Nearest(pts, 16), 2)
    eq(U.Nearest(pts, 29), 2)
    eq(U.Nearest(pts, 31), 3)
    eq(U.Nearest(pts, 999), 3)
    is_nil(U.Nearest({}, 5))
end)

test("Util.ClipSegmentX trims a segment to the x window and interpolates y", function()
    local U = ns().Charts.Util
    local x1, y1, x2, y2 = U.ClipSegmentX(0, 0, 10, 100, 2, 8)
    eq(x1, 2); near(y1, 20); eq(x2, 8); near(y2, 80)
    is_nil(U.ClipSegmentX(0, 0, 1, 1, 5, 9))
    is_nil(U.ClipSegmentX(10, 0, 12, 1, 0, 9))
    local a = { U.ClipSegmentX(1, 5, 2, 6, 0, 9) }
    eq(a[1], 1); eq(a[4], 6)
end)

test("Util.Decimate keeps the last point and bounds the count", function()
    local U = ns().Charts.Util
    local pts = linePoints(1000, function(i) return i end)
    local out = U.Decimate(pts, 100)
    eq(out[#out], pts[1000])
    eq(#out <= 101, true)
    eq(U.Decimate(pts, 5000), pts)
end)

-- Scale ----------------------------------------------------------------------------------------

test("Scale.Linear maps and inverts", function()
    local S = ns().Charts.Scale
    local s = S.Linear(0, 10, 100, 200)
    eq(s:Map(0), 100); eq(s:Map(10), 200); eq(s:Map(5), 150)
    near(s:Invert(150), 5)
    local flip = S.Linear(0, 10, 200, 100) -- y axes can run the other way
    eq(flip:Map(0), 200)
end)

test("Scale.Linear survives a zero-width domain", function()
    local s = ns().Charts.Scale.Linear(5, 5, 0, 100)
    eq(s:Map(5), 50)
end)

test("Scale.Ticks are round numbers inside the domain", function()
    local S = ns().Charts.Scale
    local ticks = S.Ticks(0, 100, 5)
    eq(table.concat(ticks, ","), "0,20,40,60,80,100")
    eq(tostring(S.Ticks(0, 100, 5)[1]), "0", "no negative zero")
    eq(table.concat(S.Ticks(-50, 50, 4), ","), "-50,0,50") -- nice step for a span of 100 is 50
    local t2 = S.Ticks(3, 47, 4)
    for _, v in ipairs(t2) do eq(v >= 3 and v <= 47, true) end
    eq(table.concat(S.Ticks(1000, 1500, 5), ","), "1000,1100,1200,1300,1400,1500")
    eq(#S.Ticks(5, 5, 4), 1)
end)

test("Scale.TimeTicks land on round boundaries and respect the timezone offset", function()
    local S = ns().Charts.Scale
    local day = 86400
    local ticks, step = S.TimeTicks(0, 7 * day, 8, 0)
    eq(step, day)
    for _, t in ipairs(ticks) do eq(t % day, 0) end
    -- local midnight in UTC+10 is 14:00 UTC the previous day
    local local10, step10 = S.TimeTicks(0, 7 * day, 8, 10 * 3600)
    eq(step10, day)
    for _, t in ipairs(local10) do eq((t + 10 * 3600) % day, 0) end
    local hourly, hstep = S.TimeTicks(0, 6 * 3600, 8, 0)
    eq(hstep <= 3600, true)
    eq(#hourly > 1, true)
end)

-- Formatters -----------------------------------------------------------------------------------

test("daily data is labelled with dates only, never a time of day", function()
    local C = ns().Charts
    local time = C.formatters:Require("time")
    local t = 1791417600 -- midnight UTC, i.e. 10:00 in UTC+10
    local daily = { span = 2 * 86400, resolution = 86400 }
    eq(time(t, daily):find(":", 1, true), nil, "axis label")
    eq(time(t, { span = 2 * 86400, resolution = 86400, long = true }):find(":", 1, true), nil, "tooltip label")
    eq(time(t, { span = 3600, resolution = 60 }):find(":", 1, true) ~= nil, true, "fine data keeps the clock time")
    eq(time(t, { span = 3600, resolution = 3600, long = true }):find(":", 1, true) ~= nil, true)
end)

test("daily charts put their ticks on UTC midnights, whatever the timezone", function()
    local C = ns().Charts
    local day = 86400
    local model = C.Build({
        x = { format = "time", resolution = day, tzOffset = 10 * 3600 },
        series = { { type = "line", points = { { x = 100 * day, y = 1 }, { x = 105 * day, y = 2 } } } },
    }, 600, 200)
    local canvas = new_recording_canvas()
    C.Draw(model, canvas)
    -- every vertical grid line (x constant) must be at a UTC midnight
    local verticals = canvas:find("line", function(o) return o.x1 == o.x2 end)
    eq(#verticals > 2, true)
    for _, l in ipairs(verticals) do
        local v = model.xs:Invert(l.x1)
        if v >= 100 * day - 1 then eq(math.abs(v / day - math.floor(v / day + 0.5)) < 1e-6, true) end
    end
end)

test("money, number and int formatters", function()
    local C = ns().Charts
    local money = C.formatters:Require("money")
    eq(money(123456), "12.35g")
    eq(money(120000), "12g")
    eq(money(5050), "50.5s")
    eq(money(37), "37c")
    eq(money(1000000), "100g")
    eq(money(-20000), "-2g")
    eq(C.formatters:Require("int")(12.6), "13")
    eq(C.formatters:Require("number")(2.50), "2.5")
    eq(C.formatters:Require("percent")(1.234), "+1.23%")
end)

-- Build / layout -------------------------------------------------------------------------------

test("Build splits panes by weight inside the padded plot", function()
    local C = ns().Charts
    local model = C.Build({
        padding = { left = 50, right = 10, top = 10, bottom = 20 },
        panes = {
            { id = "a", weight = 3, series = { { type = "line", points = linePoints(5, function(i) return i end) } } },
            { id = "b", weight = 1, series = { { type = "bar", points = linePoints(5, function(i) return i end) } } },
        },
    }, 400, 300)
    eq(model.plot.x, 50); eq(model.plot.w, 340); eq(model.plot.h, 270)
    local a, b = model.panes[1].rect, model.panes[2].rect
    near(a.h / b.h, 3, 1e-9)
    eq(a.y > b.y, true, "first pane is on top")
    near(b.y, 20, 1e-9)
    near(a.y + a.h, 290, 1e-9) -- 300 high minus the 10px top padding
    near(a.y - (b.y + b.h), 6, 1e-9) -- gap
end)

test("single-pane shorthand works", function()
    local C = ns().Charts
    local model = C.Build({ series = { { type = "line", points = linePoints(3, function(i) return i end) } } }, 200, 100)
    eq(#model.panes, 1)
    eq(model.empty, false)
end)

test("an empty chart is flagged and draws a message", function()
    local C = ns().Charts
    local model = C.Build({ series = { { type = "line", points = {} } }, emptyText = "nothing here" }, 200, 100)
    eq(model.empty, true)
    local canvas = new_recording_canvas()
    C.Draw(model, canvas)
    eq(canvas:find("text")[1].str, "nothing here")
    eq(canvas.began, 1); eq(canvas.finished, 1)
end)

test("y domain gets a margin, but bars keep their zero baseline", function()
    local C = ns().Charts
    local model = C.Build({
        panes = {
            { id = "p", series = { { type = "line", points = linePoints(3, function(i) return 100 + i * 10 end) } } },
            { id = "v", series = { { type = "bar", points = linePoints(3, function(i) return i * 50 end) } } },
        },
    }, 300, 200)
    eq(model.panes[1].ys.d0 < 110, true)
    eq(model.panes[1].ys.d1 > 130, true)
    eq(model.panes[2].ys.d0, 0)
end)

test("explicit x and y ranges override autoscale", function()
    local C = ns().Charts
    local model = C.Build({
        x = { range = { 0, 1000 } },
        panes = { { y = { range = { 0, 500 } }, series = { { type = "line", points = linePoints(3, function() return 10 end) } } } },
    }, 300, 200)
    eq(model.xs.d0, 0); eq(model.xs.d1, 1000)
    eq(model.panes[1].ys.d0, 0); eq(model.panes[1].ys.d1, 500)
end)

-- Drawing --------------------------------------------------------------------------------------

test("line series draws one segment per gap between points", function()
    local C = ns().Charts
    local model = C.Build({ minimal = true, series = { { type = "line", points = linePoints(6, function(i) return i end) } } }, 300, 100)
    local canvas = new_recording_canvas()
    C.Draw(model, canvas)
    eq(canvas:count("line"), 5)
    eq(canvas:count("text"), 0, "minimal charts have no axis labels")
end)

test("a lone point is drawn as a dot", function()
    local C = ns().Charts
    local model = C.Build({ minimal = true, series = { { type = "line", points = linePoints(1, function() return 5 end) } } }, 300, 100)
    local canvas = new_recording_canvas()
    C.Draw(model, canvas)
    eq(canvas:count("line"), 0)
    eq(canvas:count("rect"), 2) -- background + dot
end)

test("candles are coloured by direction and have a wick and a body", function()
    local C = ns().Charts
    local model = C.Build({
        minimal = true,
        series = { { type = "candle", points = {
            { x = 100, o = 10, h = 14, l = 9, c = 13 },  -- up
            { x = 200, o = 13, h = 13.5, l = 8, c = 9 }, -- down
        } } },
    }, 300, 100)
    local canvas = new_recording_canvas()
    C.Draw(model, canvas)
    eq(canvas:count("line"), 2)
    local wicks = canvas:find("line")
    local bodies = canvas:find("rect", function(o) return o.w < 100 end)
    eq(#bodies, 2)
    local function sameHue(a, b) return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] end
    eq(sameHue(bodies[1].color, model.theme.up), true, "up body")
    eq(sameHue(bodies[2].color, model.theme.down), true, "down body")
    eq(sameHue(wicks[1].color, model.theme.up), true, "up wick")
    eq(sameHue(wicks[2].color, model.theme.down), true, "down wick")
end)

test("the body is see-through and the wick solid, so the wick shows even inside the body", function()
    local C = ns().Charts
    -- opens at the high and closes at the low: the body covers the whole range, no wick sticks out
    local model = C.Build({ minimal = true, series = { { type = "candle", points = {
        { x = 100, o = 434, h = 434, l = 200, c = 200 },
        { x = 200, o = 300, h = 310, l = 290, c = 305 },
    } } } }, 300, 100)
    local canvas = new_recording_canvas()
    C.Draw(model, canvas)
    for _, b in ipairs(canvas:find("rect", function(o) return o.w < 100 end)) do
        eq(b.color[4] < 1, true, "body alpha " .. b.color[4])
    end
    for _, w in ipairs(canvas:find("line")) do
        eq(w.color[4], 1, "wick alpha")
    end
    local first = canvas:find("line")[1]
    local body = canvas:find("rect", function(o) return o.w < 100 end)[1]
    eq(first.x1, body.x + body.w / 2, "wick is down the middle of the body")
    -- the wick spans exactly the body here (open = high, close = low), so it is only visible through it
    near(math.max(first.y1, first.y2), body.y + body.h, 1e-6)
    near(math.min(first.y1, first.y2), body.y, 1e-6)
end)

test("supply bars are semi-transparent so they do not overpower the price", function()
    local C = ns().Charts
    local model = C.Build({ minimal = true, series = { { type = "bar", points = { { x = 1, y = 5 }, { x = 2, y = 9, up = false } } } } }, 200, 100)
    local canvas = new_recording_canvas()
    C.Draw(model, canvas)
    for _, b in ipairs(canvas:find("rect", function(o) return o.w < 100 end)) do
        near(b.color[4], 0.55, 1e-9)
    end
end)

test("candles are narrow: at most 16px however few there are", function()
    local C = ns().Charts
    local model = C.Build({ minimal = true, series = { { type = "candle", points = {
        { x = 0, o = 1, h = 2, l = 1, c = 2 }, { x = 3600, o = 2, h = 3, l = 2, c = 3 } } } } }, 600, 200)
    local canvas = new_recording_canvas()
    C.Draw(model, canvas)
    for _, b in ipairs(canvas:find("rect", function(o) return o.w < 100 end)) do
        eq(b.w <= 16, true, "width " .. b.w)
    end
end)

test("candles and bars at the first and last point stay inside the plot", function()
    local C = ns().Charts
    local model = C.Build({
        panes = {
            { id = "p", series = { { type = "candle", points = {
                { x = 0, o = 234, h = 234, l = 234, c = 234 },
                { x = 3600, o = 434, h = 434, l = 234, c = 234 },
            } } } },
            { id = "v", series = { { type = "bar", points = { { x = 0, y = 5 }, { x = 3600, y = 9 } } } } },
        },
    }, 640, 360)
    local canvas = new_recording_canvas()
    C.Draw(model, canvas)
    local plot = model.plot
    local shapes = canvas:find("rect", function(o) return o.w < plot.w end)
    eq(#shapes, 4, "two candle bodies and two bars")
    for _, r in ipairs(shapes) do
        eq(r.x >= plot.x - 1e-9, true, "left edge " .. r.x)
        eq(r.x + r.w <= plot.x + plot.w + 1e-9, true, "right edge " .. (r.x + r.w))
    end
end)

test("a candle with no price movement is still drawn as a visible dash", function()
    local C = ns().Charts
    local model = C.Build({ series = { { type = "candle", points = { { x = 1, o = 5, h = 5, l = 5, c = 5 },
        { x = 2, o = 5, h = 8, l = 4, c = 7 } } } } }, 300, 200)
    local canvas = new_recording_canvas()
    C.Draw(model, canvas)
    local flat = canvas:find("rect", function(o) return o.w < 100 end)[1]
    eq(flat.h >= 2, true)
end)

test("stacked panes are separated by a full-width divider", function()
    local C = ns().Charts
    local model = C.Build({
        panes = {
            { id = "a", series = { { type = "line", points = linePoints(4, function(i) return i end) } } },
            { id = "b", series = { { type = "bar", points = linePoints(4, function(i) return i end) } } },
        },
    }, 400, 300)
    local canvas = new_recording_canvas()
    C.Draw(model, canvas)
    local dividers = canvas:find("line", function(o) return o.y1 == o.y2 and o.x1 == 0 and o.x2 == 400 end)
    eq(#dividers, 1)
    local gapTop, gapBottom = model.panes[1].rect.y, model.panes[2].rect.y + model.panes[2].rect.h
    eq(dividers[1].y1 < gapTop and dividers[1].y1 > gapBottom, true, "sits in the gap between the panes")
end)

test("a single candle is centred in the plot", function()
    local C = ns().Charts
    local model = C.Build({ series = { { type = "candle", points = { { x = 500, o = 1, h = 3, l = 1, c = 2 } } } } }, 300, 200)
    local canvas = new_recording_canvas()
    C.Draw(model, canvas)
    local body = canvas:find("rect", function(o) return o.w < 100 end)[1]
    near(body.x + body.w / 2, model.plot.x + model.plot.w / 2, 1)
end)

test("bars rise from zero and use up/down colours when given", function()
    local C = ns().Charts
    local model = C.Build({
        minimal = true,
        series = { { type = "bar", points = { { x = 1, y = 5, up = true }, { x = 2, y = 10, up = false } } } },
    }, 200, 100)
    local canvas = new_recording_canvas()
    C.Draw(model, canvas)
    local bars = canvas:find("rect", function(o) return o.w < 100 end)
    eq(#bars, 2)
    near(bars[1].y, bars[2].y) -- same baseline
    eq(bars[2].h > bars[1].h, true)
    eq(bars[1].color[1], model.theme.up[1])
    eq(bars[2].color[1], model.theme.down[1])
end)

test("axis labels are drawn for non-minimal charts", function()
    local C = ns().Charts
    local model = C.Build({
        x = { format = "number" },
        axis = { format = "money" },
        series = { { type = "line", points = linePoints(10, function(i) return i * 10000 end) } },
    }, 400, 200)
    local canvas = new_recording_canvas()
    C.Draw(model, canvas)
    eq(canvas:count("text") > 3, true)
    local right = canvas:find("text", function(o) return o.anchor == "RIGHT" end)
    eq(#right > 0, true, "y labels are right-anchored at the axis")
    eq(right[1].str:match("g$") ~= nil, true, "money format")
end)

test("a pane title is drawn in its corner so stacked axes are not confused", function()
    local C = ns().Charts
    local model = C.Build({
        panes = {
            { id = "p", title = "Price", axis = { format = "money" },
              series = { { type = "line", points = linePoints(5, function(i) return i * 100 end) } } },
            { id = "v", title = "Listed", axis = { format = "int" },
              series = { { type = "bar", points = linePoints(5, function(i) return i end) } } },
        },
    }, 400, 300)
    local canvas = new_recording_canvas()
    C.Draw(model, canvas)
    local titles = canvas:find("text", function(o) return o.anchor == "TOPLEFT" end)
    eq(#titles, 2)
    eq(titles[1].str, "Price"); eq(titles[2].str, "Listed")
    eq(titles[1].y > titles[2].y, true, "top pane's title is higher")
end)

test("a line wider than the x window is clipped, not drawn off the plot", function()
    local C = ns().Charts
    local model = C.Build({
        minimal = true,
        x = { range = { 250, 450 } },
        series = { { type = "line", points = linePoints(6, function(i) return i * 10 end) } },
    }, 200, 100)
    local canvas = new_recording_canvas()
    C.Draw(model, canvas)
    for _, l in ipairs(canvas:find("line")) do
        eq(l.x1 >= -1e-9 and l.x2 <= 200 + 1e-9, true)
    end
end)

-- Overlays -------------------------------------------------------------------------------------

test("sma overlay becomes a derived line in the same pane", function()
    local C = ns().Charts
    local model = C.Build({
        panes = { {
            series = { { type = "line", id = "price", points = linePoints(10, function(i) return i end) } },
            overlays = { { type = "sma", of = "price", period = 3 } },
        } },
    }, 300, 100)
    local entries = model.panes[1].entries
    eq(#entries, 2)
    eq(entries[2].derived, true)
    eq(#entries[2].spec.points, 8) -- 10 values, first 2 undefined
    near(entries[2].spec.points[1].y, 2) -- mean of 1,2,3
end)

test("bollinger overlay adds two bands and an overlay can read a series from another pane", function()
    local C = ns().Charts
    local model = C.Build({
        panes = {
            { id = "p", series = { { type = "line", id = "price", points = linePoints(12, function(i) return 100 + (i % 3) end) } } },
            { id = "v", series = { { type = "bar", points = linePoints(12, function() return 5 end) } },
              overlays = { { type = "bollinger", of = "price", period = 5 } } },
        },
    }, 300, 200)
    eq(#model.panes[2].entries, 3) -- bar + upper + lower
end)

test("hline overlay spans the source's x range", function()
    local C = ns().Charts
    local model = C.Build({
        panes = { {
            series = { { type = "line", points = linePoints(4, function(i) return i end) } },
            overlays = { { type = "hline", value = 2.5 } },
        } },
    }, 300, 100)
    local pts = model.panes[1].entries[2].spec.points
    eq(pts[1].x, 100); eq(pts[2].x, 400); eq(pts[1].y, 2.5)
end)

test("an overlay with an unknown source is skipped with a warning, not an error", function()
    local C = ns().Charts
    local model = C.Build({
        panes = { {
            series = { { type = "line", id = "a", points = linePoints(4, function(i) return i end) } },
            overlays = { { type = "sma", of = "missing", period = 2 } },
        } },
    }, 300, 100)
    eq(#model.panes[1].entries, 1)
    eq(#model.warnings, 1)
end)

-- Extensibility --------------------------------------------------------------------------------

test("a new series type can be added without touching the engine", function()
    local S = ns()
    local C = S.Charts
    C.series:Register("dots", {
        extent = function(spec) return C.Util.Extent(spec.points, "y", "y") end,
        draw = function(spec, ctx)
            for _, p in ipairs(spec.points) do
                ctx.canvas:rect(ctx.xs:Map(p.x), ctx.ys:Map(p.y), 3, 3, ctx.color)
            end
        end,
    })
    local model = C.Build({ minimal = true, series = { { type = "dots", points = linePoints(4, function(i) return i end) } } }, 200, 100)
    local canvas = new_recording_canvas()
    C.Draw(model, canvas)
    eq(canvas:count("rect"), 5) -- background + 4 dots
end)

test("unknown series or overlay types fail loudly", function()
    local C = ns().Charts
    throws(function() C.Build({ series = { { type = "nope", points = {} } } }, 100, 100) end, "unknown chart series 'nope'")
    throws(function()
        C.Build({ panes = { { series = { { type = "line", id = "a", points = linePoints(2, function() return 1 end) } },
            overlays = { { type = "nope", of = "a" } } } } }, 100, 100)
    end, "unknown chart overlay 'nope'")
end)

-- Hover ----------------------------------------------------------------------------------------

test("hover snaps to the nearest point and lists its values", function()
    local C = ns().Charts
    local model = C.Build({
        axis = { format = "int" }, x = { format = "number" },
        series = { { type = "line", label = "price", points = linePoints(5, function(i) return i * 10 end) } },
    }, 400, 200)
    local canvas = new_recording_canvas()
    local px = model.xs:Map(300) + 2 -- just right of the third point
    local hit = C.Hover(model, canvas, px, 100)
    eq(hit.x, 300)
    eq(hit.rows[2].text, "price: 30")
    eq(canvas:count("line"), 2) -- vertical + horizontal crosshair
    eq(canvas:count("text") >= 2, true)
end)

test("hover outside the plot clears the layer and returns nil", function()
    local C = ns().Charts
    local model = C.Build({ series = { { type = "line", points = linePoints(5, function(i) return i end) } } }, 400, 200)
    local canvas = new_recording_canvas()
    is_nil(C.Hover(model, canvas, 1, 1))
    eq(#canvas.ops, 0)
    eq(canvas.began, 1); eq(canvas.finished, 1)
    is_nil(C.Hover(model, canvas, nil, nil))
end)

test("hovering a candle shows how many scans it summarises", function()
    local C = ns().Charts
    local model = C.Build({
        axis = { format = "money" }, x = { format = "number" },
        series = { { type = "candle", points = {
            { x = 100, o = 10000, h = 14000, l = 9000, c = 13000, n = 4 },
            { x = 200, o = 13000, h = 13500, l = 8000, c = 9000, n = 1 },
        } } },
    }, 400, 300)
    local canvas = new_recording_canvas()
    local many = C.Hover(model, canvas, model.xs:Map(100), 150)
    eq(many.rows[#many.rows].text, "4 scans")
    local one = C.Hover(model, canvas, model.xs:Map(200), 150)
    eq(one.rows[#one.rows].text, "1 scan", "singular")
    eq(#one.rows, 6, "header + open/high/low/close + scans")
end)

test("a candle without a scan count shows no scans row", function()
    local C = ns().Charts
    local model = C.Build({ x = { format = "number" }, series = { { type = "candle", points = {
        { x = 100, o = 10, h = 14, l = 9, c = 13 }, { x = 200, o = 13, h = 14, l = 9, c = 10 } } } } }, 300, 200)
    local hit = C.Hover(model, new_recording_canvas(), model.xs:Map(100), 100)
    eq(#hit.rows, 5)
end)

test("hover tooltip stays inside the chart", function()
    local C = ns().Charts
    local model = C.Build({
        axis = { format = "money" }, x = { format = "number" },
        series = { { type = "candle", points = {
            { x = 100, o = 10000, h = 14000, l = 9000, c = 13000 },
            { x = 200, o = 13000, h = 13500, l = 8000, c = 9000 },
        } } },
    }, 300, 200)
    local canvas = new_recording_canvas()
    local hit = C.Hover(model, canvas, model.xs:Map(200), 100)
    eq(hit.box.x >= 0 and hit.box.x + hit.box.w <= 300, true)
    eq(hit.box.y >= 0 and hit.box.y + hit.box.h <= 200, true)
    eq(#hit.rows, 5) -- header + open/high/low/close
end)
