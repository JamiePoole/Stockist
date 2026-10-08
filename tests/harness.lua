-- Minimal test harness. Loaded by tests/run.py, which sets ADDON_DIR and TESTS_DIR first.
local passed, failures = 0, {}
local currentFile = "?"

function set_current_file(name) currentFile = name end

function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failures[#failures + 1] = currentFile .. " :: " .. name .. "\n    " .. tostring(err)
    end
end

function eq(actual, expected, label)
    if actual ~= expected then
        error((label and (label .. ": ") or "") .. "expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

function near(actual, expected, eps)
    eps = eps or 1e-9
    if type(actual) ~= "number" or math.abs(actual - expected) > eps then
        error("expected ~" .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

function is_nil(actual, label)
    if actual ~= nil then
        error((label and (label .. ": ") or "") .. "expected nil, got " .. tostring(actual), 2)
    end
end

function throws(fn, pattern)
    local ok, err = pcall(fn)
    if ok then error("expected an error, but none was raised", 2) end
    if pattern and not tostring(err):find(pattern, 1, true) then
        error("error did not contain '" .. pattern .. "': " .. tostring(err), 2)
    end
end

--- A fresh addon namespace with the given addon files loaded into it, in order.
function load_addon(...)
    local ns = {}
    for _, rel in ipairs({ ... }) do
        local chunk, err = loadfile(ADDON_DIR .. "/" .. rel)
        if not chunk then error(err, 2) end
        chunk("Stockist", ns)
    end
    return ns
end

--- Load a test-support file (tests/support/<name>.lua) into the global environment.
function load_support(name)
    dofile(TESTS_DIR .. "/support/" .. name .. ".lua")
end

function report()
    return passed, #failures, table.concat(failures, "\n")
end
