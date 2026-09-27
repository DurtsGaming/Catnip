-- Shared setup for Blizzard's AuraContainer widget (patch 12.1+). Blizzard's engine watches the
-- auras, even in combat when they're secret to us, and shows a button while a matching aura is up.
-- Buttons start empty and zero-sized: we size them, then add our own look (and can register our own
-- widgets, e.g. button:SetDurationCooldown(cooldown), which Blizzard then drives with the real timing).
-- After setup the buttons are forbidden objects to addon code, so never query them later.
-- Technique from the Blood in the Water addon; see docs/api-research.md.
local addonName, ns = ...

ns.HAS_AURA_CONTAINER = C_XMLUtil and C_XMLUtil.GetTemplateInfo
    and C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate") and true or false

-- Makes any art Blizzard gave the button invisible, so only what we add shows.
function ns.HideAuraButtonArt(button)
    for _, region in ipairs({ button:GetRegions() }) do
        region:SetAlpha(0)
    end
    for _, child in ipairs({ button:GetChildren() }) do
        child:SetAlpha(0)
    end
end

-- options:
--   label       name for debug output
--   unit        "player" or "target"
--   filter      "HELPFUL" or "HARMFUL" (only auras we applied are matched)
--   spellIDs    list of aura spell IDs to show (every rank, on Forever)
--   width, height, x, y   button size, and its centre's offset from the HUD centre
--   level       frame level above the HUD
--   initialize  function(button): adds our look; runs once per pooled button, out of combat
function ns.CreateAuraContainer(options)
    local spellSet = {}
    for _, spellID in ipairs(options.spellIDs) do
        spellSet[spellID] = true
    end

    local container

    -- Unit and filters can be (re)applied any time, including in combat.
    local function Apply()
        container:SetUnit(options.unit)
        container:SetAuraGroupFilterString("main", options.filter .. "|PLAYER")
        container:SetAuraGroupCandidateFilters("main", { includeSpellIDs = spellSet })
        container:SetAuraGroupMaxFrameCount("main", 1)
        container:SetAuraGroupLayout("main", { elementWidth = options.width, elementHeight = options.height })
        container:SetFlowLayoutMaximumLineSize(options.width)
        container:SetEnabled(true)
    end

    local function InitializeButton(button)
        button:SetSize(options.width, options.height) -- zero-sized buttons hide everything on them
        button:EnableMouse(false)
        options.initialize(button)
    end

    local function Create()
        container = CreateFrame("AuraContainer", nil, ns.hud, "CustomAuraContainerTemplate")
        container:SetSize(options.width, options.height)
        container:SetPoint("CENTER", ns.hud, "CENTER", options.x or 0, options.y or 0)
        container:SetFrameLevel(ns.hud:GetFrameLevel() + (options.level or 10))
        container:AddAuraGroup("main", options.filter, {
            initializeFrame = function(button)
                local ok, err = pcall(InitializeButton, button)
                if not ok then
                    ns.Debug(options.label, "button styling failed:", err)
                end
            end,
            sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.Default,
            sortDirection = AuraContainerSortDirection and AuraContainerSortDirection.Normal,
        })
        -- Without a flow layout anchor and direction the container never shows its button.
        container:SetFlowLayoutAnchorPoint("LEFT")
        container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
        Apply()
        ns.Debug(options.label, "using AuraContainer")
    end

    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    if options.unit == "target" then
        events:RegisterEvent("PLAYER_TARGET_CHANGED")
    end
    events:SetScript("OnEvent", function(_, event)
        if not container then
            if not InCombatLockdown() then -- containers can't be created in combat; retried when it ends
                Create()
            end
        elseif event == "PLAYER_TARGET_CHANGED" then
            Apply() -- as Blood in the Water does on every target change
        end
    end)
end
