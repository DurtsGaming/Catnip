-- The unlock-mode overlay shared by the HUD and the cooldown box, drawn like Blizzard's Edit Mode:
-- the blue nine-slice highlight over the frame, brighter while the mouse is over it (an additive
-- copy on top) with "Click To Edit" in the middle. Clicking opens its settings.
local addonName, ns = ...

local TEXTURE_KIT = "editmode-actionbar-highlight" -- Edit Mode's blue; "-selected" is its yellow
local HOVER_GLOW = 0.4 -- strength of the additive copy that brightens it on hover

-- Blizzard's EditModeSystemSelectionLayout (NineSliceLayouts.lua), copied rather than looked up by
-- name: the corners stick out 8px past the frame, as in Edit Mode.
local LAYOUT = {
    TopLeftCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = 8 },
    TopRightCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = 8 },
    BottomLeftCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = -8 },
    BottomRightCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = -8 },
    TopEdge = { atlas = "_%s-NineSlice-EdgeTop" },
    BottomEdge = { atlas = "_%s-NineSlice-EdgeBottom" },
    LeftEdge = { atlas = "!%s-NineSlice-EdgeLeft" },
    RightEdge = { atlas = "!%s-NineSlice-EdgeRight" },
    Center = { atlas = "%s-NineSlice-Center", x = -8, y = 8, x1 = 8, y1 = -8 },
}

-- Edit Mode's art on frame if this client has it, else a flat blue tint.
local function ApplyLook(frame)
    local hasAtlas = C_Texture and C_Texture.GetAtlasInfo
        and C_Texture.GetAtlasInfo(TEXTURE_KIT .. "-NineSlice-Corner") ~= nil
    if hasAtlas and NineSliceUtil and NineSliceUtil.ApplyLayout
        and pcall(NineSliceUtil.ApplyLayout, frame, LAYOUT, TEXTURE_KIT) then
        return
    end
    ns.Debug("Unlock overlay: no Edit Mode art, using a flat tint")
    local tint = frame:CreateTexture(nil, "BACKGROUND")
    tint:SetAllPoints()
    tint:SetColorTexture(0.2, 0.6, 1, 0.35)
end

-- The hover brightening: the same look again, drawn additively over the first.
local function CreateGlow(overlay)
    local glow = CreateFrame("Frame", nil, overlay)
    glow:SetAllPoints()
    ApplyLook(glow)
    for _, region in ipairs({ glow:GetRegions() }) do
        if region.SetBlendMode then
            region:SetBlendMode("ADD")
        end
    end
    glow:SetAlpha(HOVER_GLOW)
    glow:Hide()
    return glow
end

-- Edit Mode's "Click To Edit" is about 24pt; GameFontHighlightHuge2 may not exist in every client.
local LABEL_FONT = _G.GameFontHighlightHuge2 and "GameFontHighlightHuge2" or "GameFontHighlightHuge"
local CLICK_SLOP = 4 -- cursor travel (pixels) under which a press counts as a click, not a drag

-- Edit Mode's name tag: a small dark box with gold text, poking out of the frame's right edge.
local function CreateNameTag(owner, overlay, name)
    local tag = CreateFrame("Frame", nil, owner, BackdropTemplateMixin and "BackdropTemplate" or nil)
    tag:SetPoint("LEFT", overlay, "RIGHT", -12, 0)
    local text = tag:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("CENTER")
    text:SetText(name)
    tag:SetSize(text:GetStringWidth() + 20, text:GetStringHeight() + 14)
    if tag.SetBackdrop then
        tag:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        tag:SetBackdropColor(0.05, 0.04, 0.02, 0.95)
        tag:SetBackdropBorderColor(0.7, 0.6, 0.4, 1)
    end
    return tag
end

-- A hidden overlay covering parent that catches the mouse (drag registered) only while shown.
-- On hover it brightens, says "Click To Edit" and shows a tag with name; a left click that isn't a
-- drag calls onClick.
function ns.CreateUnlockOverlay(parent, name, onClick)
    local overlay = CreateFrame("Frame", nil, parent)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(parent:GetFrameLevel() + 20)
    if overlay.SetIgnoreParentAlpha then
        overlay:SetIgnoreParentAlpha(true) -- full strength whatever the widget's opacity setting
    end
    overlay:EnableMouse(true)
    overlay:RegisterForDrag("LeftButton")
    overlay:Hide()
    ApplyLook(overlay)
    local glow = CreateGlow(overlay)

    local text = CreateFrame("Frame", nil, overlay) -- above the glow, so it doesn't wash out the words
    text:SetAllPoints()
    text:SetFrameLevel(glow:GetFrameLevel() + 1)
    local label = text:CreateFontString(nil, "OVERLAY", LABEL_FONT)
    label:SetPoint("CENTER")
    label:SetText("Click To Edit")
    -- A heavier shadow than the font's own, so it reads on the bright highlight like Blizzard's.
    label:SetShadowColor(0, 0, 0, 1)
    label:SetShadowOffset(2, -2)
    local tag = CreateNameTag(text, overlay, name)

    -- Polled rather than OnEnter/OnLeave, which a child frame (a resize grip) under the mouse would end.
    local hovered
    overlay:SetScript("OnUpdate", function(self)
        local now = self:IsMouseOver()
        if now ~= hovered then
            hovered = now
            glow:SetShown(now)
            label:SetShown(now)
            tag:SetShown(now)
        end
    end)
    overlay:SetScript("OnHide", function() hovered = nil end)

    -- Told apart from a drag by how far the cursor went, so callers keep their own drag scripts.
    local downX, downY
    overlay:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            downX, downY = GetCursorPosition()
        end
    end)
    overlay:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" or not downX then
            return
        end
        local x, y = GetCursorPosition()
        local moved = math.abs(x - downX) + math.abs(y - downY)
        downX, downY = nil, nil
        if moved <= CLICK_SLOP then
            onClick()
        end
    end)
    return overlay
end
