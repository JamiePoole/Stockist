local ADDON_NAME, Stockist = ...

-- Pure maths over arrays of numbers. Every series function returns an array the same length as
-- its input, with nil where the indicator is not yet defined, plus `.n` = input length.
local Indicators = {}
Stockist.Indicators = Indicators

--- Closing prices from an array of candles.
function Indicators.Closes(candles)
    local out = { n = #candles }
    for i, c in ipairs(candles) do out[i] = c.c end
    return out
end

function Indicators.SMA(values, period)
    local count = values.n or #values
    local out = { n = count }
    local sum = 0
    for i = 1, count do
        sum = sum + values[i]
        if i > period then sum = sum - values[i - period] end
        if i >= period then out[i] = sum / period end
    end
    return out
end

--- Exponential moving average, seeded with the SMA of the first `period` values.
function Indicators.EMA(values, period)
    local count = values.n or #values
    local out = { n = count }
    if count < period then return out end
    local k = 2 / (period + 1)
    local seed = 0
    for i = 1, period do seed = seed + values[i] end
    out[period] = seed / period
    for i = period + 1, count do
        out[i] = values[i] * k + out[i - 1] * (1 - k)
    end
    return out
end

--- Bollinger bands: SMA +/- k population standard deviations. Returns { mid, upper, lower }.
function Indicators.Bollinger(values, period, k)
    local count = values.n or #values
    local mid = Indicators.SMA(values, period)
    local upper, lower = { n = count }, { n = count }
    for i = period, count do
        local mean = mid[i]
        local acc = 0
        for j = i - period + 1, i do
            local d = values[j] - mean
            acc = acc + d * d
        end
        local sd = math.sqrt(acc / period)
        upper[i] = mean + k * sd
        lower[i] = mean - k * sd
    end
    return { mid = mid, upper = upper, lower = lower }
end

--- Relative strength index with Wilder smoothing. First value appears at index period + 1.
function Indicators.RSI(values, period)
    local count = values.n or #values
    local out = { n = count }
    if count <= period then return out end

    local function rsiOf(gain, loss)
        if loss == 0 then return gain == 0 and 50 or 100 end
        return 100 - 100 / (1 + gain / loss)
    end

    local gain, loss = 0, 0
    for i = 2, period + 1 do
        local change = values[i] - values[i - 1]
        if change > 0 then gain = gain + change else loss = loss - change end
    end
    gain, loss = gain / period, loss / period
    out[period + 1] = rsiOf(gain, loss)

    for i = period + 2, count do
        local change = values[i] - values[i - 1]
        local g = change > 0 and change or 0
        local l = change < 0 and -change or 0
        gain = (gain * (period - 1) + g) / period
        loss = (loss * (period - 1) + l) / period
        out[i] = rsiOf(gain, loss)
    end
    return out
end

--- Percentage move from `from` to `to`. nil when `from` is zero or missing.
function Indicators.PercentChange(from, to)
    if not from or from == 0 or not to then return nil end
    return (to - from) / from * 100
end

--- Where `value` sits within `values`: percent of values that are <= value (0-100).
function Indicators.Percentile(values, value)
    local count = values.n or #values
    if count == 0 then return nil end
    local below = 0
    for i = 1, count do
        if values[i] <= value then below = below + 1 end
    end
    return below / count * 100
end
