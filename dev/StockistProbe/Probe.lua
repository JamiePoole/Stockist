-- Stockist capability probe.
-- Usage: /stkprobe        run every test, print a summary, write StockistProbeDB
--        /stkprobe ah     (stand at the Auction House) re-check the AH API list only
-- Results land in WTF\Account\<ACCOUNT>\SavedVariables\StockistProbe.lua after /reload or logout.

local PREFIX = "STKPROBE"
local CHANNEL_NAME = "StockistProbe"

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")

local run -- current run record

local function say(msg) print("|cff33ff99StockistProbe|r " .. msg) end

local function resultName(r)
    if type(r) ~= "number" then return tostring(r) end
    local enum = Enum and Enum.SendAddonMessageResult
    if enum then
        for k, v in pairs(enum) do
            if v == r then return k .. "(" .. r .. ")" end
        end
    end
    return tostring(r)
end

local function trySend(chatType, target)
    local ok, a = pcall(C_ChatInfo.SendAddonMessage, PREFIX, "probe:" .. chatType, chatType, target)
    if not ok then return "ERROR: " .. tostring(a) end
    return resultName(a)
end

local AH_APIS = {
    "ReplicateItems", "GetNumReplicateItems", "GetReplicateItemInfo",
    "SendBrowseQuery", "GetBrowseResults", "HasFullBrowseResults",
    "SendSearchQuery", "GetNumCommoditySearchResults", "GetCommoditySearchResultInfo",
    "GetCommoditySearchResultsQuantity", "GetItemKeyInfo", "MakeItemKey",
}

local function probeAH()
    local out = { apiPresent = {}, apiMissing = {} }
    if not C_AuctionHouse then
        out.noNamespace = true
        return out
    end
    for _, name in ipairs(AH_APIS) do
        if type(C_AuctionHouse[name]) == "function" then
            out.apiPresent[#out.apiPresent + 1] = name
        else
            out.apiMissing[#out.apiMissing + 1] = name
        end
    end
    return out
end

local function finish()
    StockistProbeDB.lastRun = run
    say("done. Results saved (type /reload to flush to disk).")
    say("sends: ")
    for _, line in ipairs(run.sendLog) do say("  " .. line) end
    say("received echoes: " .. (#run.received > 0 and table.concat(run.received, ", ") or "none"))
end

local function runAll()
    local build, buildNum, date, toc = GetBuildInfo()
    run = {
        time = date,
        version = build, build = buildNum, toc = toc,
        player = UnitName("player"),
        sendLog = {}, received = {}, channelNotices = {},
        ah = probeAH(),
    }

    run.prefixRegistered = tostring(C_ChatInfo.RegisterAddonMessagePrefix(PREFIX))

    local me = UnitName("player")
    local tests = {
        { "PARTY" }, { "RAID" }, { "INSTANCE_CHAT" }, { "GUILD" },
        { "WHISPER", me }, { "SAY" }, { "YELL" },
    }
    for _, t in ipairs(tests) do
        local r = trySend(t[1], t[2])
        run.sendLog[#run.sendLog + 1] = t[1] .. " -> " .. r
        run[t[1]] = r
    end

    -- CHANNEL needs a joined channel and a numeric id, so give the join a moment.
    local joinOk, joinErr = pcall(JoinChannelByName, CHANNEL_NAME)
    run.joinChannel = joinOk and "ok" or ("ERROR: " .. tostring(joinErr))
    C_Timer.After(3, function()
        local id, name = GetChannelName(CHANNEL_NAME)
        run.channelId = id
        if id and id > 0 then
            local r = trySend("CHANNEL", id)
            run.sendLog[#run.sendLog + 1] = "CHANNEL(" .. id .. ") -> " .. r
            run.CHANNEL = r
        else
            run.sendLog[#run.sendLog + 1] = "CHANNEL -> could not join/find channel '" .. CHANNEL_NAME .. "'"
            run.CHANNEL = "NO_CHANNEL"
        end
        -- Allow a moment for echoed CHAT_MSG_ADDON events.
        C_Timer.After(2, finish)
    end)

    say("running. Results in ~5 seconds.")
end

f:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if (...) == "StockistProbe" then
            StockistProbeDB = StockistProbeDB or {}
        end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, text, channel, sender = ...
        if prefix == PREFIX and run then
            run.received[#run.received + 1] = text .. " via " .. tostring(channel)
        end
    elseif event == "CHAT_MSG_CHANNEL_NOTICE" and run then
        run.channelNotices[#run.channelNotices + 1] = tostring((...))
    end
end)

SLASH_STOCKISTPROBE1 = "/stkprobe"
SlashCmdList["STOCKISTPROBE"] = function(arg)
    if arg == "ah" then
        local ah = probeAH()
        StockistProbeDB.ah = ah
        say("AH present: " .. table.concat(ah.apiPresent, ", "))
        say("AH missing: " .. table.concat(ah.apiMissing, ", "))
    else
        runAll()
    end
end
