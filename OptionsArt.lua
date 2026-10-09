-- The settings window's look (used by Options.lua): the window itself and the panels its sections
-- sit in, made to match WoW Forever's Professions frame.
--
-- First choice is Blizzard's own art, found with /catnip art on the Professions frame (2026-10-02):
-- the window is PortraitFrameTemplate (UI-Frame-Metal border with title bar, portrait ring and
-- close button) over the Profession-Background-Overview background; panels are cut from the
-- Profession-overview-card-generic-Cooking card (its corners, edges and fade, without its
-- illustration). If the template or atlases are missing, our own drawn version (ui_* textures,
-- colours sampled from a screenshot of the same frame) stands in.
local addonName, ns = ...

local art = {}
ns.OptionsArt = art

art.PORTRAIT = 72 -- room the portrait takes in the top-left corner

local function RGB(r, g, b, a) return { r / 255, g / 255, b / 255, a or 1 } end
local MUTED = RGB(163, 154, 138)
art.GROUND = RGB(12, 10, 8) -- behind the panels; must match GROUND in tools/make_textures.py
local HEADER_GLOW = RGB(22, 19, 15) -- the drawn tab row fades from the ground to this at its bottom
local PANEL_TOP = RGB(22, 18, 15) -- a drawn panel's fill fades from this at the top...
local PANEL_BOTTOM = RGB(41, 32, 25) -- ...to this at the bottom
local TAB_TOP = RGB(16, 13, 10) -- an unselected drawn tab, darker
local TAB_BOTTOM = RGB(28, 22, 17)
local SHADOW = 0.45 -- strength of a drawn panel's inner shadow along its top and left
local SHADOW_SIZE = 10
local DIM = 0.65 -- an unselected tab cut from the card, darkened

local BORDER = 8 -- the drawn frame's bevel (ui_frame)
local TITLE_HEIGHT = 28 -- the drawn title bar with its gold underline (ui_title)
local HEADER_HEIGHT = 28 -- the drawn tab row under the title bar

local BACKGROUND_ATLAS = "Profession-Background-Overview"
local CARD_ATLAS = "Profession-overview-card-generic-Cooking"
local CARD_CORNER = 16 -- card pixels kept as they are at each corner
local CARD_STRIP = 16 -- width of the plain strip (left of the illustration) stretched across the middle

local function AtlasInfo(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
end

-- The portrait: the druid class icon (brown claw marks), as the Character panel shows it (file
-- 625999, uncropped under the round mask; found with /catnip art, 2026-10-02).
local PORTRAIT_ICON = 625999 -- Interface\Icons\ClassIcon_Druid

-- Slicing ----------------------------------------------------------------------------------------

-- Draws a source image around frame in nine pieces: the four `corner`-pixel corners as they are,
-- the edges stretched, and the middle stretched or left out. uv(x0, x1, y0, y1) turns a rectangle
-- in source pixels (w x h) into tex coords. Options:
--   centre      draw the middle
--   stripFrom/stripTo  source columns the top and bottom edges and the middle are sampled from
--               (default the whole middle)
--   openBottom  draw the bottom row from the source's middle rows, so there is no bottom edge
--               (a tab that joins the panel below)
-- Returns the textures.
local function Slices(frame, file, uv, w, h, corner, layer, options)
    options = options or {}
    local textures = {}
    local function Piece(x0, x1, y0, y1)
        local texture = frame:CreateTexture(nil, layer)
        texture:SetTexture(file)
        texture:SetTexCoord(uv(x0, x1, y0, y1))
        textures[#textures + 1] = texture
        return texture
    end
    local c = corner
    local sx0, sx1 = options.stripFrom or c, options.stripTo or (w - c)
    local by0 = options.openBottom and math.floor(h / 2) or (h - c) -- the bottom row's source rows
    local topLeft = Piece(0, c, 0, c)
    local topRight = Piece(w - c, w, 0, c)
    local bottomLeft = Piece(0, c, by0, by0 + c)
    local bottomRight = Piece(w - c, w, by0, by0 + c)
    for _, spec in ipairs({ { topLeft, "TOPLEFT" }, { topRight, "TOPRIGHT" },
        { bottomLeft, "BOTTOMLEFT" }, { bottomRight, "BOTTOMRIGHT" } }) do
        spec[1]:SetSize(c, c)
        spec[1]:SetPoint(spec[2])
    end
    local function Between(texture, fromTexture, fromPoint, toTexture, toPoint)
        texture:SetPoint("TOPLEFT", fromTexture, fromPoint)
        texture:SetPoint("BOTTOMRIGHT", toTexture, toPoint)
    end
    Between(Piece(sx0, sx1, 0, c), topLeft, "TOPRIGHT", topRight, "BOTTOMLEFT")
    Between(Piece(sx0, sx1, by0, by0 + c), bottomLeft, "TOPRIGHT", bottomRight, "BOTTOMLEFT")
    Between(Piece(0, c, c, h - c), topLeft, "BOTTOMLEFT", bottomLeft, "TOPRIGHT")
    Between(Piece(w - c, w, c, h - c), topRight, "BOTTOMLEFT", bottomRight, "TOPRIGHT")
    if options.centre then
        Between(Piece(sx0, sx1, c, h - c), topLeft, "BOTTOMRIGHT", bottomRight, "TOPLEFT")
    end
    return textures
end

-- One of our square ui_* nine-slice textures, middle left out.
local function OwnSlices(frame, file, size, corner, layer)
    return Slices(frame, file, function(x0, x1, y0, y1)
        return x0 / size, x1 / size, y0 / size, y1 / size
    end, size, size, corner, layer)
end

-- A vertical gradient over `texture`'s area: ui_fade (opaque at the top, clear at the bottom)
-- tinted `colour`, over whatever is drawn beneath.
local function Fade(texture, colour)
    texture:SetTexture(ns.MEDIA .. "ui_fade")
    texture:SetVertexColor(unpack(colour))
end

-- Panels -----------------------------------------------------------------------------------------

local card = AtlasInfo(CARD_ATLAS)
local cardFile = card and (card.file or card.filename)

-- The card's corners and edges with a plain strip of it stretched across the middle.
local function CardPanel(frame, corner, openBottom)
    local left, right, top, bottom = card.leftTexCoord, card.rightTexCoord, card.topTexCoord, card.bottomTexCoord
    local w, h = card.width, card.height
    local textures = Slices(frame, cardFile, function(x0, x1, y0, y1)
        return left + (right - left) * x0 / w, left + (right - left) * x1 / w,
            top + (bottom - top) * y0 / h, top + (bottom - top) * y1 / h
    end, w, h, corner, "BACKGROUND", {
        centre = true, stripFrom = CARD_CORNER, stripTo = CARD_CORNER + CARD_STRIP, openBottom = openBottom,
    })
    return function(selected)
        local shade = selected and 1 or DIM
        for _, texture in ipairs(textures) do
            texture:SetVertexColor(shade, shade, shade)
        end
    end
end

-- Our drawn panel: a fill fading from `top` to `bottom` colour, an inner shadow along the top and
-- left, and the ui_panel edge with cut corners.
local function DrawnPanel(frame)
    local base = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
    base:SetPoint("TOPLEFT", 1, -1)
    base:SetPoint("BOTTOMRIGHT", -1, 1)
    local fade = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    fade:SetAllPoints(base)
    local shadeTop = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    shadeTop:SetPoint("TOPLEFT", 2, -2)
    shadeTop:SetPoint("TOPRIGHT", -2, -2)
    shadeTop:SetHeight(SHADOW_SIZE)
    Fade(shadeTop, { 0, 0, 0, SHADOW })
    local shadeLeft = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    shadeLeft:SetPoint("TOPLEFT", 2, -2)
    shadeLeft:SetPoint("BOTTOMLEFT", 2, 2)
    shadeLeft:SetWidth(SHADOW_SIZE)
    Fade(shadeLeft, { 0, 0, 0, SHADOW })
    shadeLeft:SetTexCoord(0, 0, 1, 0, 0, 1, 1, 1) -- turned so it fades left to right
    OwnSlices(frame, ns.MEDIA .. "ui_panel", 32, 8, "BORDER")
    return function(selected)
        base:SetColorTexture(unpack(selected and PANEL_BOTTOM or TAB_BOTTOM))
        Fade(fade, selected and PANEL_TOP or TAB_TOP)
    end
end

-- Gives frame a panel's look; `corner` (card pixels kept at each corner, default 16) can be smaller
-- for short frames. Returns SetSelected(bool): unselected (for tabs) is darker.
function art.Panel(frame, corner)
    local setSelected = (card and cardFile) and CardPanel(frame, corner or CARD_CORNER) or DrawnPanel(frame)
    setSelected(true)
    return setSelected
end

-- How far a panel's visible top edge sits inside its frame: the card has a dark margin around its
-- painted border (6px above, 5px at the sides, measured in-game 2026-10-02); our drawn panel's edge
-- is at the frame.
art.EDGE_INSET = (card and cardFile) and 6 or 0

-- A bookmark tab (ui_tab: rounded top, no bottom edge, colours sampled where a tab meets the card).
-- Returns SetSelected(selected, cover): unselected is darker; the bottom `cover` pixels (the part
-- reaching over a panel's edge) are plain fill, so the tab's side lines stop at the panel's edge.
local TAB_FOOT = RGB(27, 22, 17) -- ui_tab's bottom fill; must match TAB_FILL_BOTTOM in tools/make_textures.py
function art.Tab(frame)
    local textures = Slices(frame, ns.MEDIA .. "ui_tab", function(x0, x1, y0, y1)
        return x0 / 64, x1 / 64, y0 / 64, y1 / 64
    end, 64, 64, 8, "BACKGROUND", { centre = true })
    local bottomLeft, bottomRight = textures[3], textures[4] -- see Slices' order
    local foot = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    foot:SetPoint("BOTTOMLEFT")
    foot:SetPoint("BOTTOMRIGHT")
    foot:SetColorTexture(unpack(TAB_FOOT))
    return function(selected, cover)
        cover = cover or 0
        bottomLeft:ClearAllPoints()
        bottomLeft:SetPoint("BOTTOMLEFT", 0, cover) -- the edges and middle hang off the corners
        bottomRight:ClearAllPoints()
        bottomRight:SetPoint("BOTTOMRIGHT", 0, cover)
        foot:SetHeight(math.max(cover, 1))
        foot:SetShown(cover > 0)
        local shade = selected and 1 or DIM
        for _, texture in ipairs(textures) do
            texture:SetVertexColor(shade, shade, shade)
        end
    end
end

-- A button in the bookmark tabs' look, rounded all round: ui_tab's top corners and edge, mirrored
-- for the bottom, with a thin band from just under them stretched over the sides and middle (so the
-- fill is even, not the tab's gradient). Returns SetSelected(selected): unselected is darker.
function art.RoundTab(frame)
    local file, size, c = ns.MEDIA .. "ui_tab", 64, 8
    local band0, band1 = c, c + 2
    local textures = {}
    local function Piece(x0, x1, y0, y1, flip)
        local texture = frame:CreateTexture(nil, "BACKGROUND")
        texture:SetTexture(file)
        if flip then
            y0, y1 = y1, y0
        end
        texture:SetTexCoord(x0 / size, x1 / size, y0 / size, y1 / size)
        textures[#textures + 1] = texture
        return texture
    end
    local topLeft, topRight = Piece(0, c, 0, c), Piece(size - c, size, 0, c)
    local bottomLeft, bottomRight = Piece(0, c, 0, c, true), Piece(size - c, size, 0, c, true)
    for _, spec in ipairs({ { topLeft, "TOPLEFT" }, { topRight, "TOPRIGHT" },
        { bottomLeft, "BOTTOMLEFT" }, { bottomRight, "BOTTOMRIGHT" } }) do
        spec[1]:SetSize(c, c)
        spec[1]:SetPoint(spec[2])
    end
    local function Between(texture, fromTexture, fromPoint, toTexture, toPoint)
        texture:SetPoint("TOPLEFT", fromTexture, fromPoint)
        texture:SetPoint("BOTTOMRIGHT", toTexture, toPoint)
    end
    Between(Piece(c, size - c, 0, c), topLeft, "TOPRIGHT", topRight, "BOTTOMLEFT")
    Between(Piece(c, size - c, 0, c, true), bottomLeft, "TOPRIGHT", bottomRight, "BOTTOMLEFT")
    Between(Piece(0, c, band0, band1), topLeft, "BOTTOMLEFT", bottomLeft, "TOPRIGHT")
    Between(Piece(size - c, size, band0, band1), topRight, "BOTTOMLEFT", bottomRight, "TOPRIGHT")
    Between(Piece(c, size - c, band0, band1), topLeft, "BOTTOMRIGHT", bottomRight, "TOPLEFT")
    return function(selected)
        local shade = selected and 1 or DIM
        for _, texture in ipairs(textures) do
            texture:SetVertexColor(shade, shade, shade)
        end
    end
end

-- Side tabs --------------------------------------------------------------------------------------

-- Blizzard's side tabs (the Character and Professions windows' tabs down the right edge, found with
-- /catnip art): a 55x60 bronze frame with cut corners, the icon masked to its shape, a yellow
-- outline when selected and a white one on mouseover.
art.SIDE_TAB_WIDTH, art.SIDE_TAB_HEIGHT = 55, 60
local SIDE_TAB_ICON = 50
local SIDE_TAB_FILL = RGB(27, 22, 17) -- a tab without an icon: the panels' colour

-- Gives `button` (SIDE_TAB_WIDTH x SIDE_TAB_HEIGHT) a side tab's look, showing `iconFile`: a file
-- ID or path, or a function returning one (called each time the tab shows until it does, for icons
-- looked up from game data that may not be loaded yet, with `fallbackFile` shown meanwhile); nil
-- for a plain fill. Returns SetSelected(bool).
function art.SideTab(button, iconFile, fallbackFile)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(SIDE_TAB_ICON, SIDE_TAB_ICON)
    icon:SetPoint("CENTER")
    icon:SetTexCoord(0.031, 0.969, 0.031, 0.969) -- as Blizzard's side tabs crop theirs
    icon:SetColorTexture(unpack(SIDE_TAB_FILL))
    local function ShowIcon()
        local file = iconFile
        if type(file) == "function" then
            file = file()
        end
        if file then
            icon:SetTexture(file)
            button:SetScript("OnShow", nil)
        elseif fallbackFile then
            icon:SetTexture(fallbackFile)
        end
    end
    if iconFile then
        button:SetScript("OnShow", ShowIcon)
        ShowIcon()
    end
    if AtlasInfo("common-sidetab") then
        local background = button:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetAtlas("common-sidetab")
        if AtlasInfo("common-sidetab-mask") then
            local mask = button:CreateMaskTexture()
            mask:SetAllPoints()
            mask:SetAtlas("common-sidetab-mask")
            icon:AddMaskTexture(mask)
        end
        local highlight = button:CreateTexture(nil, "HIGHLIGHT") -- shown by the game on mouseover
        highlight:SetAllPoints()
        highlight:SetAtlas("common-sidetab-hover")
        local selected = button:CreateTexture(nil, "OVERLAY")
        selected:SetAllPoints()
        selected:SetAtlas("common-sidetab-selected")
        return function(isSelected)
            selected:SetShown(isSelected)
        end
    end
    -- Drawn stand-in: a bronze box, yellow when selected, white on mouseover.
    local border = button:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.15)
    return function(isSelected)
        border:SetColorTexture(unpack(isSelected and { 1, 0.82, 0, 1 } or RGB(125, 102, 52)))
    end
end

-- Window -----------------------------------------------------------------------------------------

-- Blizzard's portrait frame, titled, with the druid portrait and the Professions background.
-- Returns nil if this client lacks the template.
local function BlizzardWindow(name, titleText)
    local ok, window = pcall(CreateFrame, "Frame", name, UIParent, "PortraitFrameTemplate")
    if not ok or not window.NineSlice then
        ns.Debug("Settings window: no PortraitFrameTemplate, drawing our own frame")
        return nil
    end
    if window.SetTitle then
        window:SetTitle(titleText)
    end
    local portrait = window.PortraitContainer and window.PortraitContainer.portrait or window.portrait
    if portrait then
        portrait:SetTexture(PORTRAIT_ICON)
    end
    -- Drawn above the scrolling pages, which slide under them (portrait under the ring, as built).
    window.overlays = {}
    for _, key in ipairs({ "PortraitContainer", "NineSlice", "TitleContainer", "CloseButton" }) do
        if window[key] then
            window.overlays[#window.overlays + 1] = window[key]
        end
    end
    window.contentTop = 24 -- below the title bar
    if AtlasInfo(BACKGROUND_ATLAS) then
        local background = window:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(window.Bg or window)
        background:SetAtlas(BACKGROUND_ATLAS)
        if window.Bg then
            window.Bg:Hide() -- the plain grey background it would otherwise draw over ours
        end
    end
    return window
end

-- Our drawn version of the same: ui_frame bevel, ui_title strip, fading tab row, portrait in
-- ui_portrait_ring, Blizzard's red close button.
local function DrawnWindow(name, titleText)
    local window = CreateFrame("Frame", name, UIParent)

    local ground = window:CreateTexture(nil, "BACKGROUND") -- inset to stay inside the cut corners
    ground:SetPoint("TOPLEFT", 6, -6)
    ground:SetPoint("BOTTOMRIGHT", -6, 6)
    ground:SetColorTexture(unpack(art.GROUND))
    OwnSlices(window, ns.MEDIA .. "ui_frame", 64, 16, "BORDER")

    local titleBar = window:CreateTexture(nil, "ARTWORK")
    titleBar:SetPoint("TOPLEFT", BORDER, -BORDER)
    titleBar:SetPoint("TOPRIGHT", -BORDER, -BORDER)
    titleBar:SetHeight(TITLE_HEIGHT)
    titleBar:SetTexture(ns.MEDIA .. "ui_title")
    titleBar:SetTexCoord(0, 1, 0, TITLE_HEIGHT / 32)

    local header = window:CreateTexture(nil, "ARTWORK")
    header:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT")
    header:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT")
    header:SetHeight(HEADER_HEIGHT)
    header:SetColorTexture(unpack(HEADER_GLOW))
    local headerFade = window:CreateTexture(nil, "ARTWORK", nil, 1)
    headerFade:SetAllPoints(header)
    Fade(headerFade, art.GROUND)

    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("CENTER", titleBar, "CENTER", 0, 4) -- centred on the brown strip, above the underline
    title:SetText(titleText)

    local portrait = CreateFrame("Frame", nil, window)
    portrait:SetSize(art.PORTRAIT, art.PORTRAIT)
    portrait:SetPoint("CENTER", window, "TOPLEFT", 32, -34)
    portrait:SetFrameLevel(window:GetFrameLevel() + 10)
    local icon = portrait:CreateTexture(nil, "ARTWORK")
    icon:SetSize(art.PORTRAIT - 12, art.PORTRAIT - 12) -- tucked under the ring's dark inner edge
    icon:SetPoint("CENTER")
    icon:SetTexture(PORTRAIT_ICON)
    local ring = portrait:CreateTexture(nil, "OVERLAY")
    ring:SetAllPoints()
    ring:SetTexture(ns.MEDIA .. "ui_portrait_ring")
    local mask = portrait:CreateMaskTexture()
    mask:SetTexture(ns.MEDIA .. "circle_hard", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)

    local ok, close = pcall(CreateFrame, "Button", nil, window, "UIPanelCloseButton")
    if not ok then
        close = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
        close:SetText("X")
    end
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -5, -6)
    close:SetScript("OnClick", function()
        window:Hide()
    end)
    window.overlays = { portrait, close } -- drawn above the scrolling pages
    window.contentTop = BORDER + TITLE_HEIGHT -- below the title bar
    return window
end

-- The settings window: a frame on UIParent named `name` with its title, portrait, close button
-- and background drawn. Positioning, size and contents are up to the caller. window.contentTop is
-- how far down the title bar ends; window.overlays are the frames (border, portrait, title, close
-- button) to raise above the contents, in order.
function art.CreateWindow(name, titleText)
    local GetMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = GetMetadata and GetMetadata(addonName, "Version")
    if version then
        titleText = string.format("%s  |cff%02x%02x%02x%s|r", titleText,
            MUTED[1] * 255, MUTED[2] * 255, MUTED[3] * 255, version)
    end
    return BlizzardWindow(name, titleText) or DrawnWindow(name, titleText)
end
