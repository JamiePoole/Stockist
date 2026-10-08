-- A Canvas that records draw calls instead of drawing, for chart tests.
function new_recording_canvas()
    local c = { ops = {}, began = 0, finished = 0 }
    function c:begin(w, h) self.began = self.began + 1; self.ops = {}; self.w, self.h = w, h end
    function c:finish() self.finished = self.finished + 1 end
    function c:line(x1, y1, x2, y2, color, width)
        self.ops[#self.ops + 1] = { op = "line", x1 = x1, y1 = y1, x2 = x2, y2 = y2, color = color, width = width }
    end
    function c:rect(x, y, w, h, color)
        self.ops[#self.ops + 1] = { op = "rect", x = x, y = y, w = w, h = h, color = color }
    end
    function c:text(x, y, str, color, anchor)
        self.ops[#self.ops + 1] = { op = "text", x = x, y = y, str = str, color = color, anchor = anchor }
    end
    function c:count(op)
        local n = 0
        for _, o in ipairs(self.ops) do if o.op == op then n = n + 1 end end
        return n
    end
    function c:find(op, pred)
        local out = {}
        for _, o in ipairs(self.ops) do if o.op == op and (not pred or pred(o)) then out[#out + 1] = o end end
        return out
    end
    return c
end
