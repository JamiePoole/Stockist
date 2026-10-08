local ADDON_NAME, Stockist = ...

-- Single place to read the time, so tests and the network layer can substitute it.
Stockist.Clock = {
    now = function()
        if GetServerTime then return GetServerTime() end
        return os.time()
    end,
}
