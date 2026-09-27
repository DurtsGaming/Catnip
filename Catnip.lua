local addonName, ns = ...

ns.MEDIA = "Interface\\AddOns\\" .. addonName .. "\\media\\"
ns.RESOURCE_SIZE = 100

-- In combat, Midnight hands addons "secret" values we can display but not compare or do math on.
function ns.IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

local hud = CreateFrame("Frame", "CatnipHUD", UIParent)
hud:SetSize(200, 200) -- positioned and scaled by Layout.lua
ns.hud = hud

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name)
    if name == addonName then
        print("|cff33ff99Catnip|r loaded. Interface: " .. select(4, GetBuildInfo()))
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
