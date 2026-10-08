local ADDON_NAME, Stockist = ...

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON_NAME then
        StockistDB = StockistDB or {}
        print(("|cff33ff99Stockist|r v%s loaded."):format(Stockist.VERSION))
    end
end)
