local function ns()
    return load_addon("Core/EventBus.lua", "Core/Registry.lua", "Core/Format.lua")
end

test("EventBus delivers arguments to every handler in order", function()
    local S = ns()
    local seen = {}
    S.Events:On("X", function(a, b) seen[#seen + 1] = "first:" .. a .. b end)
    S.Events:On("X", function(a, b) seen[#seen + 1] = "second:" .. a .. b end)
    S.Events:Fire("X", 1, 2)
    eq(table.concat(seen, ","), "first:12,second:12")
end)

test("EventBus Off removes only that subscription", function()
    local S = ns()
    local calls = 0
    local sub = S.Events:On("X", function() calls = calls + 100 end)
    S.Events:On("X", function() calls = calls + 1 end)
    S.Events:Off("X", sub)
    S.Events:Fire("X")
    eq(calls, 1)
end)

test("EventBus OffOwner drops all of an owner's subscriptions", function()
    local S = ns()
    local owner, calls = {}, 0
    S.Events:On("A", function() calls = calls + 1 end, owner)
    S.Events:On("B", function() calls = calls + 1 end, owner)
    S.Events:On("A", function() calls = calls + 10 end)
    S.Events:OffOwner(owner)
    S.Events:Fire("A")
    S.Events:Fire("B")
    eq(calls, 10)
end)

test("EventBus isolates a failing handler and reports it", function()
    local S = ns()
    local reported, ran = nil, false
    geterrorhandler = function() return function(e) reported = e end end
    S.Events:On("X", function() error("boom") end)
    S.Events:On("X", function() ran = true end)
    S.Events:Fire("X")
    geterrorhandler = nil
    eq(ran, true, "later handler still ran")
    eq(reported ~= nil and reported:find("boom", 1, true) ~= nil, true, "error reported")
end)

test("EventBus handler may unsubscribe itself during Fire", function()
    local S = ns()
    local calls = 0
    local sub
    sub = S.Events:On("X", function() calls = calls + 1; S.Events:Off("X", sub) end)
    S.Events:On("X", function() calls = calls + 1 end)
    S.Events:Fire("X")
    S.Events:Fire("X")
    eq(calls, 3)
end)

test("Registry registers, gets and lists in order", function()
    local S = ns()
    local r = S.NewRegistry("series")
    r:Register("line", { id = 1 })
    r:Register("candle", { id = 2 })
    eq(r:Get("line").id, 1)
    eq(table.concat(r:List(), ","), "line,candle")
    is_nil(r:Get("missing"))
end)

test("Registry rejects duplicates and Require fails on unknown", function()
    local S = ns()
    local r = S.NewRegistry("series")
    r:Register("line", {})
    throws(function() r:Register("line", {}) end, "already registered")
    throws(function() r:Require("nope") end, "unknown series 'nope'")
end)

test("Format.Money drops zero parts", function()
    local S = ns()
    eq(S.Format.Money(123456), "12g 34s 56c")
    eq(S.Format.Money(120000), "12g")
    eq(S.Format.Money(5), "5c")
    eq(S.Format.Money(0), "0c")
    eq(S.Format.Money(10050), "1g 50c")
end)

test("Format.Age and Percent", function()
    local S = ns()
    eq(S.Format.Age(30), "just now")
    eq(S.Format.Age(600), "10m ago")
    eq(S.Format.Age(7300), "2h ago")
    eq(S.Format.Age(200000), "2d ago")
    eq(S.Format.Percent(1.234), "+1.23%")
    eq(S.Format.Percent(-0.5), "-0.50%")
end)
