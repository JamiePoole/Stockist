local ADDON_NAME, Stockist = ...

-- The wording for every help topic. Keep detail text in plain language: assume the reader has
-- never seen a trading chart.
local R = Stockist.Help.Register

R("timeframe-1D", "Last 24 hours", "A rolling 24-hour window ending now, one candle per hour.",
    "Rolling means it always ends at the present moment: this is the previous 24 hours, not "
    .. "\"today\" from midnight. The small gap on the right is room for what comes next.")
R("timeframe-1W", "Last 7 days", "A rolling 7-day window ending now, one candle per hour.",
    "Rolling, not a calendar week: it always shows the 7 days up to now, whatever day it is. "
    .. "A good default: long enough to see a trend, detailed enough to spot a spike.")
R("timeframe-1M", "Last 30 days", "A rolling 30-day window ending now, one candle per day.",
    "Rolling, not a calendar month: it always shows the 30 days up to now. Each candle is a whole "
    .. "day, so you see the bigger picture and slow trends.")
R("sma", "Moving average (SMA 7)", "The average of the last 7 candles, drawn as a smooth line.",
    "SMA stands for Simple Moving Average. It smooths out the ups and downs so you can see the "
    .. "direction. When the price is above this line, the recent trend is up; below it, down. "
    .. "A price far from the line has moved a lot faster than usual.")

R("bollinger", "Bollinger bands (BB 10)", "A channel around the 10-candle average that widens when prices are jumpy.",
    "The two lines show how far the price normally strays from its average. Touching the lower "
    .. "line can mean unusually cheap (a possible buy); touching the upper line, unusually "
    .. "expensive (a possible sell). Narrow bands mean a calm market; wide bands, a volatile one.")

R("tutorial", "Tutorial tips", "Turns the longer explanations on or off.",
    "When on, buttons and the chart show plain-language descriptions of what each thing means. "
    .. "Turn it off once you know your way around.")

-- The legend under the price chart (shown in tutorial mode): a key, and some general things to look
-- for. The tips are hints about how to read a chart, not advice about what to buy or sell.
Stockist.Help.legend = {
    keyTitle = "Reading the chart",
    key = {
        { "Thick part", "first to last price in that period" },
        { "Thin line", "lowest to highest price (a bright line through the middle if the price stayed inside the thick part)" },
        { "Green / red", "the price ended higher / lower than it started" },
        { "Dots and line", "used while history is short: one dot per scan" },
        { "Lower bars", "how many units are listed for sale" },
    },
    tipsTitle = "What to look for",
    tips = {
        "A thick candle: the price moved decisively (up if green, down if red).",
        "A long thin line: the price swung widely but came back, so the market is unsettled.",
        "Price rising while few are listed: buyers outnumber sellers. Falling while many are listed: sellers are undercutting each other.",
        "Hints, not advice: patches and events can move prices in ways no chart shows.",
    },
}
