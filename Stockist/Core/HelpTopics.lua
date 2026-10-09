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

R("popout", "Pop out", "Opens this panel in its own window.",
    "The chart stays here too. A popped-out window is handy when you want to keep one item in view while "
    .. "you look at something else.")

R("watchlist-row", "Tracked item", "Click to show this item in the chart. To stop tracking it, select it and use the button below the list.",
    "Each row shows the cheapest price now, how far it has moved in the last 24 hours (green is up, red is down) "
    .. "and a small line of the last 7 days. The line is green if the price ended higher than it started.")

R("watchlist-track", "Track this item", "Adds the item shown in the chart to your watchlist, or removes it.",
    "Tracked items are kept in this list and their price history is stored for longer, so you can see "
    .. "slow trends. Items you do not track are cleaned up after a while.")

R("change-scope", "Change over this time range", "How much the price has moved over the range you picked: 24 hours, 7 days or 30 days.",
    "Green is up, red is down. It changes with the 1D / 1W / 1M buttons, so it always describes the chart "
    .. "you are looking at. With less history than the range it says how long it really covers. A dim dash "
    .. "means there is not enough history for that range yet; it fills in by itself as scans build up.")

R("change-recent", "Recent change", "How far the latest price is from its average over the last couple of hours.",
    "Green is up, red is down. Comparing with an average, not just the previous scan, stops one odd "
    .. "listing from making the number jump around. It appears once there are a few scans to average. "
    .. "Handy for an item you are not watching: it shows whether it is moving right now.")

R("ticker-item", "Tracked item", "Click to show this item in the chart. Hover the strip to pause it.",
    "The strip scrolls through the items you track, each with its price and how far it moved in the last 24 hours "
    .. "(green is up, red is down). Drop an item on it to start tracking it.")

R("movers-row", "Mover", "Click to show this item in the chart.",
    "The biggest risers and fallers across every item we hold prices for, by how far the price moved over "
    .. "the last 24 hours (or as far back as we have, when that is less; the grey label says how far).")

R("movers-tracked", "Watchlist only", "Narrows the lists to the items on your watchlist.",
    "Off, the lists cover the whole market, including items you have never looked at. On, they show "
    .. "only how your own watchlist items are moving.")

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
