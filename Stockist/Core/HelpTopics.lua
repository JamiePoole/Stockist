local ADDON_NAME, Stockist = ...

-- The wording for every help topic. Keep detail text in plain language: assume the reader has
-- never seen a trading chart.
local R = Stockist.Help.Register

R("timeframe-1D", "Today", "Midnight to midnight, one candle per hour.",
    "Use this to see what the price did today. The right-hand side is the rest of the day, still to come.")
R("timeframe-1W", "This week", "Monday to Sunday, one candle per hour.",
    "A good default: long enough to see a trend, detailed enough to spot a spike.")
R("timeframe-1M", "This month", "The 1st to the last day of the month, one candle per day.",
    "Each candle is a whole day, so you see the bigger picture and slow trends.")
R("sma", "Moving average (SMA)", "The average of the last few points (up to 7), drawn as a smooth line.",
    "SMA stands for Simple Moving Average. It smooths out the ups and downs so you can see the "
    .. "direction. When the price is above this line, the recent trend is up; below it, down. "
    .. "A price far from the line has moved a lot faster than usual.")

R("bollinger", "Bollinger bands (BB)", "A channel around the average that widens when prices are jumpy.",
    "The two lines show how far the price normally strays from its average. Touching the lower "
    .. "line can mean unusually cheap (a possible buy); touching the upper line, unusually "
    .. "expensive (a possible sell). Narrow bands mean a calm market; wide bands, a volatile one.")

R("tutorial", "Tutorial tips", "Turns the longer explanations on or off.",
    "When on, buttons and the chart show plain-language descriptions of what each thing means. "
    .. "Turn it off once you know your way around.")

R("legend", "Reading the chart",
    "Candle: thick part = first to last price, thin line = lowest to highest. Green = price rose, red = fell. "
    .. "Bars below = how many are listed for sale.",
    "A candle with a single reading is just a flat dash. It grows as more scans land in the same hour.")
