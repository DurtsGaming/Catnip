-- Snapping for Catnip's frames in Blizzard's Edit Mode. LibEditMode doesn't snap (a TODO in the
-- library), so this copies Blizzard's rules (EditModeMagnetismManager, Blizzard_EditMode's
-- EditModeUtil.lua): while Edit Mode's Snap option is on, a dropped frame within 8 pixels of the
-- screen's edges or centre, a grid line (while the grid shows), or the facing edge of a neighbouring
-- Edit Mode frame jumps to it. Corners line up with that neighbour too. It only reads Blizzard's
-- frames and never calls Edit Mode's code, so nothing of Blizzard's is tainted.
local addonName, ns = ...

local RANGE = 8 -- pixels; Blizzard's magnetismRange

-- A region's sides (left, right, bottom, top) in UIParent units, or nil if it has no size.
local function Sides(region)
    local left, bottom, width, height = region:GetRect()
    if not left or width <= 0 or height <= 0 then
        return nil
    end
    local k = region:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return left * k, (left + width) * k, bottom * k, (bottom + height) * k
end

-- The boxes another frame can snap to: Blizzard's Edit Mode frames (their selection boxes) and
-- other LibEditMode frames, Catnip's included. `selections` is LibEditMode's frame -> selection map.
local function Neighbours(frame, selections)
    local boxes = {}
    local function Add(region)
        if region and region:IsVisible() then
            local l, r, b, t = Sides(region)
            if l then
                boxes[#boxes + 1] = { l, r, b, t }
            end
        end
    end
    for _, system in ipairs(EditModeManagerFrame.registeredSystemFrames or {}) do
        if system ~= frame then
            Add(system.Selection or system)
        end
    end
    for other, selection in pairs(selections or {}) do
        if other ~= frame then
            Add(selection)
        end
    end
    return boxes
end

-- How far (x, y, in UIParent units) the frame should move to snap, then where it snaps to: the x of a
-- vertical line and the y of a horizontal one, or nil. 0, 0 when nothing is in range or Snap is off.
function ns.EditModeSnapOffset(frame, selections)
    local manager = EditModeManagerFrame
    if not manager or manager.snapEnabled == false then
        return 0, 0
    end
    local l, r, b, t = Sides(frame)
    if not l then
        return 0, 0
    end
    local range = RANGE / UIParent:GetEffectiveScale()
    local cx, cy = (l + r) / 2, (b + t) / 2
    local width, height = UIParent:GetSize()
    local bestX, bestY
    local lineX, lineY = {}, {} -- move -> the line it snaps to

    local function Closer(best, source, target, lines)
        local move = target - source
        if math.abs(move) <= range and (not best or math.abs(move) < math.abs(best)) then
            lines[move] = target
            return move
        end
        return best
    end
    local function CloserX(best, source, target) return Closer(best, source, target, lineX) end
    local function CloserY(best, source, target) return Closer(best, source, target, lineY) end

    -- Screen edges and centre lines.
    for _, source in ipairs({ l, r, cx }) do
        bestX = CloserX(bestX, source, width / 2)
    end
    bestX = CloserX(CloserX(bestX, l, 0), r, width)
    for _, source in ipairs({ b, t, cy }) do
        bestY = CloserY(bestY, source, height / 2)
    end
    bestY = CloserY(CloserY(bestY, b, 0), t, height)

    -- Grid lines, every gridSpacing from the grid's centre.
    local grid = manager.Grid
    local spacing = grid and grid:IsVisible() and grid.gridSpacing
    if spacing and spacing > 0 then
        local gl, gr, gb, gt = Sides(grid)
        if gl then
            spacing = spacing * grid:GetEffectiveScale() / UIParent:GetEffectiveScale()
            local gx, gy = (gl + gr) / 2, (gb + gt) / 2
            for _, source in ipairs({ l, r, cx }) do
                bestX = CloserX(bestX, source, gx + math.floor((source - gx) / spacing + 0.5) * spacing)
            end
            for _, source in ipairs({ b, t, cy }) do
                bestY = CloserY(bestY, source, gy + math.floor((source - gy) / spacing + 0.5) * spacing)
            end
        end
    end

    -- Neighbours: side by side (overlapping vertically) the facing edges meet, and the tops or
    -- bottoms line up when close; stacked (overlapping horizontally) likewise with left and right.
    for _, box in ipairs(Neighbours(frame, selections)) do
        local nl, nr, nb, nt = box[1], box[2], box[3], box[4]
        if t >= nb - range and b <= nt + range then
            bestX = CloserX(CloserX(bestX, l, nr), r, nl)
            if math.abs(l - nr) <= range or math.abs(r - nl) <= range then
                bestY = CloserY(CloserY(bestY, t, nt), b, nb)
            end
        end
        if r >= nl - range and l <= nr + range then
            bestY = CloserY(CloserY(bestY, b, nt), t, nb)
            if math.abs(b - nt) <= range or math.abs(t - nb) <= range then
                bestX = CloserX(CloserX(bestX, l, nl), r, nr)
            end
        end
    end

    return bestX or 0, bestY or 0, bestX and lineX[bestX], bestY and lineY[bestY]
end

-- Red preview lines while dragging, like Blizzard's (Blizzard_EditMode's MagnetismPreviewLineTemplate:
-- red, across the whole screen). Our own frame, so Blizzard's stays untouched.
local preview = CreateFrame("Frame", nil, UIParent)
preview:SetAllPoints(UIParent)
preview:SetFrameStrata("HIGH")
preview:Hide()

-- Blizzard's preview lines are Line objects 1.5 UI units thick, rounded to whole screen pixels.
local LINE_THICKNESS = 1.5

local function PreviewLine()
    local line = preview:CreateLine(nil, "OVERLAY")
    line:SetColorTexture(1, 0, 0)
    line:Hide()
    return line
end
local vertical, horizontal = PreviewLine(), PreviewLine()

local function SetThickness(line)
    local thickness = LINE_THICKNESS
    if PixelUtil and PixelUtil.GetNearestPixelSize then
        thickness = PixelUtil.GetNearestPixelSize(LINE_THICKNESS, line:GetEffectiveScale(), LINE_THICKNESS)
    end
    line:SetThickness(thickness)
end

-- Shows the lines for wherever `frame` would snap, every frame until StopSnapPreview.
function ns.StartSnapPreview(frame, selections)
    SetThickness(vertical)
    SetThickness(horizontal)
    preview:SetScript("OnUpdate", function()
        if InCombatLockdown() or not IsMouseButtonDown("LeftButton") then
            ns.StopSnapPreview() -- the drag ended without a drop (combat stops it)
            return
        end
        local _, _, x, y = ns.EditModeSnapOffset(frame, selections)
        vertical:SetShown(x ~= nil)
        if x then
            vertical:SetStartPoint("TOPLEFT", preview, x, 0)
            vertical:SetEndPoint("BOTTOMLEFT", preview, x, 0)
        end
        horizontal:SetShown(y ~= nil)
        if y then
            horizontal:SetStartPoint("BOTTOMLEFT", preview, 0, y)
            horizontal:SetEndPoint("BOTTOMRIGHT", preview, 0, y)
        end
    end)
    preview:Show()
end

function ns.StopSnapPreview()
    preview:SetScript("OnUpdate", nil)
    preview:Hide()
    vertical:Hide()
    horizontal:Hide()
end
