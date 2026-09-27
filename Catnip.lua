local addonName, ns = ...

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name)
    if name == addonName then
        print("|cff33ff99Catnip|r loaded. Interface: " .. select(4, GetBuildInfo()))
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
