local ADDON_NAME, Stockist = ...

-- Single place to read the time, so tests and the network layer can substitute it.
Stockist.Clock = {
    now = function()
        if GetServerTime then return GetServerTime() end
        return os.time()
    end,

    --- Local time minus UTC, in seconds (used to put chart day ticks on local midnight). Daylight
    --- saving can leave this an hour off, which only shifts tick positions.
    tzOffset = function()
        local timeFn = (os and os.time) or time
        local dateFn = (os and os.date) or date
        local now = timeFn()
        return now - timeFn(dateFn("!*t", now))
    end,
}
