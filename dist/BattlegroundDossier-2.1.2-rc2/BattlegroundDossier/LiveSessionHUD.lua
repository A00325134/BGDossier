local A = BattlegroundDossier.LiveSession
local C = BattlegroundDossier.LiveCore
local WIDTH = 448

local function Label(parent, text, font, x, y, width, r, g, b)
    local label = WINDOW_MANAGER:CreateControl(nil, parent, CT_LABEL)
    label:SetFont(font)
    label:SetAnchor(TOPLEFT, parent, TOPLEFT, x, y)
    label:SetWidth(width)
    label:SetHeight(label:GetFontHeight()); label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    label:SetMaxLineCount(1); label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    label:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    label:SetColor(r, g, b, 1)
    label:SetText(text)
    label:SetMouseEnabled(false)
    return label
end

local function Rectangle(parent, x, y, width, height, r, g, b, alpha)
    local control = WINDOW_MANAGER:CreateControl(nil, parent, CT_BACKDROP)
    control:SetAnchor(TOPLEFT, parent, TOPLEFT, x, y)
    control:SetDimensions(width, height)
    control:SetCenterColor(r, g, b, alpha)
    control:SetEdgeColor(0, 0, 0, 0)
    control:SetMouseEnabled(false)
    return control
end

function A:PositionUI()
    local p, window = self.preferences, self.window
    local scale = p.scale
    local width, height = GuiRoot:GetWidth(), GuiRoot:GetHeight()
    local x = C.IsNumber(p.x) and p.x or (width - WIDTH * scale) / 2
    local y = C.IsNumber(p.y) and p.y or height * 0.18
    x = C.Clamp(x, 0, math.max(0, width - WIDTH * scale), 0)
    y = C.Clamp(y, 0, math.max(0, height - window:GetHeight() * scale), 0)
    window:ClearAnchors()
    -- Store positions in unscaled GuiRoot units; the anchor offset is scaled
    -- by this control's scale, so compensate when applying it.
    window:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, x / scale, y / scale)
end

function A:ApplyVisibility()
    if not self:IsReady() or not self.fragment then return end
    local p = self.preferences
    -- Manual visibility is the master switch; mode only restricts where it can
    -- appear. Instance presence includes pregame and the final scoreboard.
    local outside = p.visibilityMode == "battlegroundsOnly"
        and BattlegroundDossier.API:Call("IsActiveWorldBattleground") ~= true
    self.fragment:SetHiddenForReason("preference", not p.visible or outside)
end

function A:ApplyPreferences()
    if not self.window then return end
    local p = self.preferences
    local offset = p.header and 24 or 6
    local labelHeight = math.max(18, self.sections[1].label:GetFontHeight())
    local valueHeight = math.max(28, self.valueFontHeight or self.sections[1].value:GetFontHeight())
    local valueOffset = offset + labelHeight + 2
    local height = math.max(p.header and 78 or 60, valueOffset + valueHeight + 6)
    self.window:SetScale(p.scale)
    self.window:SetDimensions(WIDTH, height)
    self.background:SetDimensions(WIDTH, height)
    self.background:SetCenterColor(0.035, 0.032, 0.028, p.opacity)
    self.bottomBorder:ClearAnchors()
    self.bottomBorder:SetAnchor(BOTTOMLEFT, self.window, BOTTOMLEFT, 0, 0)
    self.leftBorder:SetHeight(height)
    self.rightBorder:SetHeight(height)
    self.header:SetHidden(not p.header)
    for i, section in ipairs(self.sections) do
        local x = 8 + (i - 1) * 108
        section.label:ClearAnchors()
        section.label:SetAnchor(TOPLEFT, self.window, TOPLEFT, x, offset)
        section.label:SetHeight(labelHeight)
        section.value:ClearAnchors()
        section.value:SetAnchor(TOPLEFT, self.window, TOPLEFT, x, valueOffset)
        section.value:SetHeight(valueHeight)
    end
    for _, separator in ipairs(self.separators) do separator:SetHeight(height - 20) end
    self.window:SetMovable(not p.locked)
    self.window:SetMouseEnabled(not p.locked and not IsUnitInCombat("player"))
    self:ApplyVisibility()
    self:PositionUI()
end

function A:RefreshUI()
    if not self.sections then return end
    local s = self.session
    self.sections[1].value:SetText(string.format("|c80bd88%d|r / |cc57c78%d|r", s.wins, s.losses))
    self.sections[2].value:SetText(C.WinRate(s))
    if s.wins > 0 then self.sections[2].value:SetColor(0.50, 0.74, 0.53, 1)
    else self.sections[2].value:SetColor(0.77, 0.75, 0.69, 1) end
    self.sections[3].label:SetText(self.rank and self.rankState == "pending" and "BG RANK*" or "BG RANK")
    self.sections[3].value:SetText(self:RankText())
    self.sections[4].value:SetText("+" .. C.FormatAP(s.ap))
    for _, section in ipairs(self.sections) do
        section.value:SetFont("ZoFontWinH2")
        if section.value:GetStringWidth(section.value:GetText()) > 96 then section.value:SetFont("ZoFontGameBold") end
    end
end

function A:CreateUI()
    local window = WINDOW_MANAGER:CreateTopLevelWindow("BattlegroundDossierLiveHUD")
    self.window = window
    window:SetHidden(true)
    window:SetClampedToScreen(true)
    window:SetDrawTier(DT_LOW)
    self.background = Rectangle(window, 0, 0, WIDTH, 78, 0.035, 0.032, 0.028, 0.82)
    Rectangle(window, 0, 0, WIDTH, 1, 0.65, 0.49, 0.27, 0.8)
    self.bottomBorder = Rectangle(window, 0, 77, WIDTH, 1, 0.65, 0.49, 0.27, 0.8)
    self.leftBorder = Rectangle(window, 0, 0, 1, 78, 0.65, 0.49, 0.27, 0.8)
    self.rightBorder = Rectangle(window, WIDTH - 1, 0, 1, 78, 0.65, 0.49, 0.27, 0.8)
    self.header = Label(window, "BG SESSION", "ZoFontGameSmall", 12, 3, WIDTH - 24, 0.65, 0.57, 0.43)
    self.sections, self.separators = {}, {}
    for i, title in ipairs({ "W/L", "WIN RATE", "BG RANK", "AP GAIN" }) do
        local x = 8 + (i - 1) * 108
        self.sections[i] = {
            label = Label(window, title, "ZoFontGameSmall", x, 24, 108, 0.65, 0.63, 0.58),
            value = Label(window, "--", "ZoFontWinH2", x, 42, 108, 0.82, 0.68, 0.40),
        }
        if i > 1 then
            self.separators[#self.separators + 1] = Rectangle(window, x, 10, 1, 58, 0.55, 0.43, 0.26, 0.35)
        end
    end
    self.valueFontHeight = self.sections[1].value:GetFontHeight()
    window:SetHandler("OnMoveStop", function(control)
        self.preferences.x = control:GetLeft()
        self.preferences.y = control:GetTop()
        self:PositionUI()
    end)
    window:SetHandler("OnMouseEnter", function(control)
        InitializeTooltip(InformationTooltip, control, BOTTOM, 0, -5)
        SetTooltipText(InformationTooltip, "BG SESSION\nDrag to move. /bglock locks the bar.\nCompetitive leaderboard position; not MMR.\nBG RANK* = cached rank while refreshing; Loading/Unavailable do not mean Unranked.\nDraws count as completed matches, excluded from win rate.\n/bgstats shows full totals; /bgtracker help shows settings.")
    end)
    window:SetHandler("OnMouseExit", function() ClearTooltip(InformationTooltip) end)
    self.fragment = ZO_HUDFadeSceneFragment:New(window, 0, 0)
    HUD_SCENE:AddFragment(self.fragment)
    HUD_UI_SCENE:AddFragment(self.fragment)
    EVENT_MANAGER:RegisterForEvent(self.name, EVENT_PLAYER_COMBAT_STATE, function(_, inCombat)
        window:SetMouseEnabled(not self.preferences.locked and not inCombat)
        if inCombat then ClearTooltip(InformationTooltip) end
    end)
    EVENT_MANAGER:RegisterForEvent(self.name, EVENT_SCREEN_RESIZED, function() self:PositionUI() end)
    self:ApplyPreferences()
    self:RefreshUI()
end
