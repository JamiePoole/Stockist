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

---------------------------------------------------------------------------
-- Communities (C_Club) probe. /stkprobe club
-- Looks for a community whose name contains "Stockist" and a stream named "Data",
-- then tests: focus, send (short, long, burst), receive event, history fetch.
---------------------------------------------------------------------------
local CLUB_NAME, STREAM_NAME = "Stockist", "Data"
local club -- current club test record

local CLUB_EVENTS = {
    "CLUB_MESSAGE_ADDED", "CLUB_MESSAGE_UPDATED", "CLUB_ERROR", "CLUB_STREAMS_LOADED",
    "CLUB_MESSAGE_HISTORY_RECEIVED", "CLUB_STREAM_SUBSCRIBED", "CLUB_STREAM_UNSUBSCRIBED",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
}
local isClubEvent = {}
for _, e in ipairs(CLUB_EVENTS) do
    isClubEvent[e] = true
    pcall(f.RegisterEvent, f, e) -- some names may not exist on every client
end

local CLUB_APIS = {
    "GetSubscribedClubs", "GetStreams", "FocusStream", "UnfocusStream", "SendMessage",
    "GetMessageInfo", "GetMessageRanges", "GetMessagesBefore", "GetClubInfo",
}

local function note(msg)
    club.log[#club.log + 1] = msg
    say(msg)
end

local function safe(fn, ...)
    local r = { pcall(fn, ...) }
    if not r[1] then return false, tostring(r[2]) end
    return true, unpack(r, 2)
end

local function fetchHistory()
    local c, s = club.clubId, club.streamId
    local ok, ranges = safe(C_Club.GetMessageRanges, c, s)
    club.ranges = ok and ranges and #ranges or ("ERR " .. tostring(ranges))
    if ok and ranges and #ranges > 0 then
        local newest = ranges[#ranges].newestMessageId
        local ok2, msgs = safe(C_Club.GetMessagesBefore, c, s, newest, 50)
        club.historyCount = ok2 and msgs and #msgs or ("ERR " .. tostring(msgs))
        if ok2 and msgs then
            club.historySample = {}
            for i = math.max(1, #msgs - 4), #msgs do
                local m = msgs[i]
                local content = m.content
                club.historySample[#club.historySample + 1] =
                    (type(content) == "string" and content:sub(1, 80)) or ("<" .. type(content) .. ">")
            end
        end
    end
    note("history: ranges=" .. tostring(club.ranges) .. " messages=" .. tostring(club.historyCount))
    StockistProbeDB.club = club
    say("club test done. /reload to flush to disk.")
end

local function sendTests()
    local c, s = club.clubId, club.streamId
    local stamp = date("%H:%M:%S")
    local ok, err = safe(C_Club.SendMessage, c, s, "STKPROBE short " .. stamp)
    club.sendShort = ok and "called" or err
    note("send short: " .. club.sendShort)

    C_Timer.After(2, function()
        local long = ("STKPROBE long " .. stamp .. " "):rep(1):sub(1, 30) .. ("x"):rep(370)
        local ok2, err2 = safe(C_Club.SendMessage, c, s, long)
        club.sendLong = ok2 and ("called, len " .. #long) or err2
        note("send long(" .. #long .. "): " .. club.sendLong)
    end)

    C_Timer.After(4, function()
        club.burstSent = 0
        for i = 1, 5 do
            local ok3 = safe(C_Club.SendMessage, c, s, "STKPROBE burst " .. i .. " " .. stamp)
            if ok3 then club.burstSent = club.burstSent + 1 end
        end
        note("burst of 5 called: " .. club.burstSent .. " calls ok")
    end)

    C_Timer.After(10, fetchHistory)
end

local function runClub(readOnly)
    club = { log = {}, errors = {}, received = {}, apis = {}, missing = {} }
    if not C_Club then
        note("C_Club namespace does not exist on this client.")
        StockistProbeDB.club = club
        return
    end
    for _, name in ipairs(CLUB_APIS) do
        if type(C_Club[name]) == "function" then club.apis[#club.apis + 1] = name
        else club.missing[#club.missing + 1] = name end
    end
    note("C_Club present: " .. table.concat(club.apis, ", "))
    if #club.missing > 0 then note("C_Club missing: " .. table.concat(club.missing, ", ")) end

    local ok, clubs = safe(C_Club.GetSubscribedClubs)
    if not ok then note("GetSubscribedClubs error: " .. clubs) StockistProbeDB.club = club return end
    club.clubs = {}
    for _, c in ipairs(clubs or {}) do
        club.clubs[#club.clubs + 1] = tostring(c.name) .. " (id " .. tostring(c.clubId) .. ")"
        if not club.clubId and c.name and c.name:find(CLUB_NAME, 1, true) then
            club.clubId, club.clubName = c.clubId, c.name
        end
    end
    note("subscribed clubs: " .. (#club.clubs > 0 and table.concat(club.clubs, "; ") or "none"))
    if not club.clubId then note("no community matching '" .. CLUB_NAME .. "' found.") StockistProbeDB.club = club return end

    local ok2, streams = safe(C_Club.GetStreams, club.clubId)
    club.streams = {}
    for _, s in ipairs((ok2 and streams) or {}) do
        club.streams[#club.streams + 1] = tostring(s.name) .. " (id " .. tostring(s.streamId) .. ")"
        if not club.streamId and s.name and s.name:lower() == STREAM_NAME:lower() then
            club.streamId = s.streamId
        end
    end
    note("streams: " .. (#club.streams > 0 and table.concat(club.streams, "; ") or "none"))
    if not club.streamId then note("no stream named '" .. STREAM_NAME .. "' found.") StockistProbeDB.club = club return end

    local okF, focused = safe(C_Club.FocusStream, club.clubId, club.streamId)
    club.focus = okF and tostring(focused) or focused
    note("FocusStream: " .. club.focus)
    -- give the stream a moment to load before sending
    if readOnly then
        say("read-only: reading history in 5s (type a message in the Data stream by hand now if you haven't).")
        C_Timer.After(5, fetchHistory)
    else
        C_Timer.After(5, sendTests)
    end
end

local function handleClubEvent(event, ...)
    if not club then return end
    if isClubEvent[event] then
        club.events = club.events or {}
        local packed = { ... }
        local n = select("#", ...)
        local ok, args = pcall(function() return table.concat({ tostringall(unpack(packed, 1, n)) }, ",") end)
        club.events[#club.events + 1] = event .. "(" .. (ok and args or "?") .. ")"
    end
    if event == "CLUB_MESSAGE_ADDED" then
        local c, s, messageId = ...
        if c == club.clubId and s == club.streamId then
            local ok, info = safe(C_Club.GetMessageInfo, c, s, messageId)
            local content = ok and info and info.content
            club.received[#club.received + 1] =
                (type(content) == "string" and content:sub(1, 60)) or ("<" .. type(content) .. ">")
        end
    elseif event == "CLUB_ERROR" then
        club.errors[#club.errors + 1] = table.concat({ tostringall(...) }, ",")
        say("CLUB_ERROR " .. club.errors[#club.errors])
    end
end

f:SetScript("OnEvent", function(_, event, ...)
    handleClubEvent(event, ...)
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

-- Other probe files (Craft.lua, Owned.lua) register their subcommands in this table.
StockistProbeCommands = StockistProbeCommands or {}

SLASH_STOCKISTPROBE1 = "/stkprobe"
SlashCmdList["STOCKISTPROBE"] = function(arg)
    local extra = StockistProbeCommands[arg]
    if extra then
        extra()
    elseif arg == "club" then
        runClub(false)
    elseif arg == "clubread" then
        runClub(true)
    elseif arg == "ah" then
        local ah = probeAH()
        StockistProbeDB.ah = ah
        say("AH present: " .. table.concat(ah.apiPresent, ", "))
        say("AH missing: " .. table.concat(ah.apiMissing, ", "))
    else
        runAll()
    end
end
