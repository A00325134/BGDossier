-- Mocked engine: verifies logic/control construction, not actual ESO layout or event timing.
clock, timestamp = 0, 1800000000
function GetTimeStamp() return timestamp end
function GetFrameTimeMilliseconds() return clock end
function GetUnitName() return "Local^Mx" end
function GetWorldName() return "NA Megaserver" end
function GetAPIVersion() return 101051 end
function ZO_CreateStringId(name, text) _G[name] = text end
function GetDateStringFromTimestamp(t) return tostring(t) end
function d(s) end
function GetString(_, mode) return "Mode " .. tostring(mode) end
zo_strlower = string.lower
local globals = { "BATTLEGROUND_STATE_NONE", "BATTLEGROUND_STATE_STARTING", "BATTLEGROUND_STATE_PREROUND",
    "BATTLEGROUND_STATE_RUNNING", "BATTLEGROUND_STATE_POSTROUND", "BATTLEGROUND_STATE_FINISHED",
    "BATTLEGROUND_RESULT_INVALID", "BATTLEGROUND_RESULT_WIN", "BATTLEGROUND_RESULT_LOSS", "BATTLEGROUND_RESULT_TIE",
    "BATTLEGROUND_GAME_TYPE_DEATHMATCH", "BATTLEGROUND_GAME_TYPE_MURDERBALL", "BATTLEGROUND_GAME_TYPE_CAPTURE_THE_FLAG",
    "BATTLEGROUND_GAME_TYPE_KING_OF_THE_HILL", "BATTLEGROUND_GAME_TYPE_DOMINATION", "BATTLEGROUND_GAME_TYPE_CRAZY_KING",
    "COMBAT_UNIT_TYPE_PLAYER", "COMBAT_UNIT_TYPE_OTHER", "COMBAT_UNIT_TYPE_GROUP", "COMBAT_UNIT_TYPE_PLAYER_PET",
    "ACTION_RESULT_DAMAGE", "ACTION_RESULT_CRITICAL_DAMAGE", "ACTION_RESULT_DOT_TICK", "ACTION_RESULT_DOT_TICK_CRITICAL",
    "ACTION_RESULT_HEAL", "ACTION_RESULT_CRITICAL_HEAL", "ACTION_RESULT_HOT_TICK", "ACTION_RESULT_HOT_TICK_CRITICAL",
    "ACTION_RESULT_BLOCKED_DAMAGE", "ACTION_RESULT_DAMAGE_SHIELDED", "EVENT_COMBAT_EVENT", "EVENT_PLAYER_COMBAT_STATE",
    "EVENT_ADD_ON_LOADED", "EVENT_BATTLEGROUND_STATE_CHANGED", "EVENT_BATTLEGROUND_SCOREBOARD_UPDATED", "EVENT_PLAYER_ACTIVATED",
    "EVENT_PLAYER_DEACTIVATED", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "CENTER", "TOP", "BOTTOM",
    "CT_CONTROL", "CT_LABEL", "CT_BUTTON", "CT_BACKDROP", "CT_EDITBOX", "CT_TEXTURE", "GENDER_MALE",
    "DL_BACKGROUND", "DT_LOW", "EVENT_ALLIANCE_POINT_UPDATE", "EVENT_SCREEN_RESIZED", "EVENT_BATTLEGROUND_LEADERBOARD_DATA_RECEIVED",
    "CURT_ALLIANCE_POINTS", "CURRENCY_LOCATION_CHARACTER", "CURRENCY_CHANGE_REASON_PLAYER_INIT", "CURRENCY_CHANGE_REASON_BANK_WITHDRAWAL",
    "CURRENCY_CHANGE_REASON_BANK_DEPOSIT", "CURRENCY_CHANGE_REASON_GUILD_BANK_WITHDRAWAL", "CURRENCY_CHANGE_REASON_GUILD_BANK_DEPOSIT",
    "BATTLEGROUND_LEADERBOARD_TYPE_COMPETITIVE", "LEADERBOARD_DATA_READY", "LEADERBOARD_DATA_RESPONSE_PENDING",
    "TEXT_ALIGN_LEFT", "TEXT_ALIGN_RIGHT", "TEXT_ALIGN_CENTER", "TEXT_ALIGN_TOP", "TEXT_WRAP_MODE_ELLIPSIS", "TEXT_WRAP_MODE_TRUNCATE" }
for i, name in ipairs(globals) do _G[name] = i end
for i, suffix in ipairs({ "KILL", "DEATH", "ASSISTS", "DAMAGE_DONE", "HEALING_DONE", "SCORE", "DAMAGE_TAKEN",
    "DAMAGE_SHIELDS_GRANTED", "BUFFS_GRANTED", "DEBUFFS_GRANTED", "FLAG_CAPTURED", "FLAG_CARRIED_TIME",
    "CAPTURE_DEFENSE_POINTS", "CAPTURE_KILLED_ATTACKER", "CAPTURE_KILLED_DEFENDER", "DAMAGED_FLAG_CARRIER",
    "HEALED_FLAG_CARRIER", "HEALING_DEFENDERS", "KILLED_FLAG_CARRIER", "KILL_STREAK" }) do _G["SCORE_TRACKER_TYPE_" .. suffix] = i end
EVENT_MANAGER = { events = {}, updates = {} }
function EVENT_MANAGER:RegisterForEvent(name, event, fn) self.events[name .. ":" .. event] = fn end
function EVENT_MANAGER:UnregisterForEvent(name, event) self.events[name .. ":" .. event] = nil end
function EVENT_MANAGER:RegisterForUpdate(name, interval, fn) self.updates[name] = fn end
function EVENT_MANAGER:UnregisterForUpdate(name) self.updates[name] = nil end
SLASH_COMMANDS = {}
SCENE_MANAGER = {}
function SCENE_MANAGER:RegisterTopLevel(control) self.control = control end
function SCENE_MANAGER:ShowTopLevel(control) control:SetHidden(false) end
function SCENE_MANAGER:HideTopLevel(control) control:SetHidden(true) end
ZO_SavedVars = {}
function ZO_SavedVars:NewAccountWide() return {} end
-- Controls deliberately reject unknown methods to catch typos in Lua UI paths.
local Control = {}
Control.__index = function(control, method)
    -- ButtonControl supports SetText but no GetText in ESO. Only its label
    -- supports text reads. A shared permissive mock hid the hover regression.
    if rawget(control, "kind") == CT_BUTTON and method == "GetText" then return nil end
    return Control[method]
end
local setters = { "SetAnchorFill", "SetCenterColor", "SetEdgeColor", "SetEdgeTexture", "SetFont", "SetColor",
    "SetNormalFontColor", "SetMouseOverFontColor", "SetPressedFontColor", "SetMouseEnabled", "SetMaxInputChars",
    "SetClampedToScreen", "SetMovable", "SetScale", "SetResizeToFitDescendents", "SetDrawTier", "SetDrawLayer", "SetVerticalAlignment", "SetHorizontalAlignment", "SetMaxLineCount", "SetWrapMode", "SetTexture", "SetSelectAllOnFocus", "SetNormalOffset", "SetPressedOffset", "SetDisabledFontColor", "SetSelectionColor", "SetMultiLine", "SetNewLineEnabled" }
for _, method in ipairs(setters) do Control[method] = function() end end
function Control:SetAnchor(...) self.anchor = { ... } end
function Control:ClearAnchors() self.anchor = nil end
function Control:SetDimensions(w, h) self.width, self.height = w, h end
function Control:SetWidth(w) self.width = w end
function Control:GetWidth() return self.width or 1920 end
function Control:GetHeight() return self.height or 1080 end
function Control:SetScale(value) self.scale = value end
function Control:SetMouseEnabled(value) self.mouseEnabled = value end
function Control:SetMovable(value) self.movable = value end
function Control:SetCenterColor(...) self.centerColor = { ... } end
function Control:SetEdgeColor(...) self.edgeColor = { ... } end
function Control:SetHeight(h) self.height = h end
function Control:SetText(t, suppress)
    if self.kind == CT_BUTTON then self:GetLabelControl():SetText(t, suppress) end
    local changed = self.text ~= t; self.text = t
    if changed and not suppress and self.handlers.OnTextChanged then self.handlers.OnTextChanged(self) end
end
function Control:GetText() return self.text or "" end
function Control:GetTextHeight() return math.max(24, math.ceil(#(self.text or "") / math.max(1, (self.width or 100) / 9)) * 24) end
function Control:SetHidden(v) self.hidden = v end
function Control:IsHidden() return self.hidden end
function Control:SetHandler(event, fn) self.handlers[event] = fn end
function Control:GetLeft() return 100 end
function Control:GetTop() return 100 end
function Control:SetFont(font)
    self.font = font
    if self.kind == CT_BUTTON then self:GetLabelControl():SetFont(font) end
end
function Control:GetFontHeight() return self.font == "ZoFontHeader3" and 30 or self.font == "ZoFontGameSmall" and 18 or self.font == "ZoFontWinH2" and 28 or 24 end
function Control:GetStringWidth(text) return #(tostring(text):gsub("|c%x%x%x%x%x%x", ""):gsub("|r", "")) * (self.font == "ZoFontHeader3" and 15 or 9) end
function Control:SetHorizontalAlignment(value) self.alignment = value end
function Control:SetVerticalAlignment(value) self.verticalAlignment = value end
function Control:SetEnabled(value) self.enabled = value end
function Control:SetKeyboardEnabled(value) self.keyboardEnabled = value end
function Control:SetEditEnabled(value) self.editEnabled = value end
function Control:SetPasteEnabled(value) self.pasteEnabled = value end
function Control:SetCopyEnabled(value) self.copyEnabled = value end
function Control:SetSelectAllOnFocus(value) self.selectAllOnFocus = value end
function Control:HasFocus() return self.focused == true end
function Control:SelectAll() self.selectionStart, self.selectionEnd = 0, #self:GetText() end
function Control:SetCursorPosition(value) self.cursor = value; self.selectionStart, self.selectionEnd = nil, nil end
function Control:TakeFocus()
    if WINDOW_MANAGER.focus == self then return end
    if WINDOW_MANAGER.focus then WINDOW_MANAGER.focus:LoseFocus() end
    WINDOW_MANAGER.focus = self
    self.focused = true
    self.cursor = #self:GetText()
    if self.selectAllOnFocus then self:SelectAll() end
    if self.handlers.OnFocusGained then self.handlers.OnFocusGained(self) end
end
function Control:LoseFocus()
    if not self.focused then return end
    self.focused = false
    if WINDOW_MANAGER.focus == self then WINDOW_MANAGER.focus = nil end
    if self.handlers.OnFocusLost then self.handlers.OnFocusLost(self) end
end
function Control:SetVerticalScroll(v) self.offset = v end
function Control:GetVerticalScroll() return self.offset or 0 end
function Control:GetNamedChild(name)
    if not self.children[name] then self.children[name] = setmetatable({ handlers = {}, children = {} }, Control) end
    return self.children[name]
end
local function new() return setmetatable({ handlers = {}, children = {} }, Control) end
WINDOW_MANAGER = {}
function WINDOW_MANAGER:CreateControl(name, parent, kind)
    local c = new(); c.kind, c.parent = kind, parent; return c
end
function Control:GetLabelControl()
    local label = self:GetNamedChild("Label"); label.kind = CT_LABEL; return label
end
function WINDOW_MANAGER:CreateTopLevelWindow() return new() end
function WINDOW_MANAGER:CreateControlFromVirtual(name, parent, template)
    local c = new(); c.template, c.parent = template, parent
    if template == "ZO_DefaultEdit" then
        c.kind = CT_EDITBOX; c.mouseEnabled = true
        -- This is the critical behavior provided by ESO's native XML template.
        c:SetHandler("OnMouseDown", function(control) control:TakeFocus() end)
    end
    return c
end
-- Simulated routing only: cannot certify physical key behavior in ESO.
function WINDOW_MANAGER:SimulateEditKey(command, text)
    local c = self.focus
    if not c or c.kind ~= CT_EDITBOX or not c.keyboardEnabled or not c.editEnabled then return false end
    if command == "selectAll" then c:SelectAll(); return true end
    if command == "enter" then c.handlers.OnEnter(c); return true end
    if command == "escape" then c.handlers.OnEscape(c); return true end
    if command == "paste" and not c.pasteEnabled then return false end
    local value, first, last = c:GetText(), c.selectionStart, c.selectionEnd
    first, last = first or c.cursor or #value, last or c.cursor or #value
    if command == "backspace" then
        if first == last then first = math.max(0, first - 1) end; text = ""
    elseif command == "delete" then
        if first == last then last = math.min(#value, last + 1) end; text = ""
    elseif command ~= "type" and command ~= "paste" then return false end
    c:SetText(value:sub(1, first) .. (text or "") .. value:sub(last + 1))
    c:SetCursorPosition(first + #(text or "")); return true
end
GuiRoot, InformationTooltip = new(), new()
HUD_SCENE, HUD_UI_SCENE = { fragments = {} }, { fragments = {} }
function HUD_SCENE:AddFragment(fragment) self.fragments[#self.fragments + 1] = fragment end
function HUD_UI_SCENE:AddFragment(fragment) self.fragments[#self.fragments + 1] = fragment end
ZO_HUDFadeSceneFragment = {}
function ZO_HUDFadeSceneFragment:New(control)
    return { control = control, SetHiddenForReason = function(self, reason, hidden) self[reason] = hidden; self.control:SetHidden(hidden) end }
end
reloadHooks = {}
function ZO_PreHook(name, callback) assert(name == "ReloadUI"); reloadHooks[#reloadHooks + 1] = callback end
function ReloadUI() for _, hook in ipairs(reloadHooks) do hook() end end
function InitializeTooltip() end
function SetTooltipText() end
function ClearTooltip() end
function ZO_ComboBox_ObjectFromContainer(container)
    if not container.combo then
        local combo = { items = {} }
        function combo:SetSortsItems() end
        function combo:SetFont() end
        function combo:ClearItems() self.items = {} end
        function combo:CreateItemEntry(label, callback) return { name = label, callback = callback } end
        function combo:AddItem(item) self.items[#self.items + 1] = item end
        function combo:SetSelectedItem(label) self.selected = label end
        container.combo = combo
    end
    return container.combo
end

engine = { active = true, map = 42, round = 1, multi = false, state = BATTLEGROUND_STATE_RUNNING,
    teams = { 1, 2 }, results = { [1] = BATTLEGROUND_RESULT_WIN, [2] = BATTLEGROUND_RESULT_LOSS },
    scores = { [1] = 500, [2] = 300 }, roster = {} }
function IsActiveWorldBattleground() return engine.active end
function GetCurrentBattlegroundId() return engine.map end
function GetCurrentBattlegroundState() return engine.state end
function GetCurrentBattlegroundRoundIndex() return engine.round end
function DoesBattlegroundHaveRounds() return engine.multi end
function GetCurrentBattlegroundGameType() return BATTLEGROUND_GAME_TYPE_DEATHMATCH end
function GetBattlegroundName() return "Test Arena" end
function GetBattlegroundTeamName(id) return "Team " .. id end
function GetBattlegroundNumTeams() return #engine.teams end
function GetBattlegroundTeamByIndex(_, i) return engine.teams[i] end
function GetBattlegroundResultForTeam(id) return engine.results[id] end
function GetCurrentBattlegroundScore(_, team) return engine.scores[team] end
function GetCurrentBattlegroundRoundsWonByTeam(team) return engine.scores[team] end
function DoesCurrentBattlegroundImpactMMR() return true end
function GetBattlegroundTeamSize() return engine.capacity or 4 end
function GetUnitZone() return engine.zoneName end
function GetNumScoreboardEntries(round) return #(engine.roster[round or engine.round] or {}) end
function GetScoreboardEntryInfo(i, round)
    local p = engine.roster[round or engine.round][i]
    return p.character, p.account, p.team, p.isLocal
end
function GetScoreboardEntryClassId() return 1 end
function GetScoreboardEntryScoreByType(i, scoreType, round)
    if engine.missingStats then return nil end
    if engine.missingDamage and scoreType == SCORE_TRACKER_TYPE_DAMAGE_DONE then return nil end
    local p = engine.roster[round or engine.round][i]
    return (p.value or 10) * scoreType
end
function GetBattlegroundCumulativeScoreForScoreboardEntryByType(i, scoreType, round)
    engine.cumulativeCalls = (engine.cumulativeCalls or 0) + 1
    return GetScoreboardEntryScoreByType(i, scoreType, round)
end
function GetBattlegroundNumUsedMedals() return 0 end
function GetClassName(_, id) return "Class " .. id end
function GetCurrentCharacterId() return engine.characterId or "character-1" end
function GetCurrencyAmount(currency, location)
    assert(currency == CURT_ALLIANCE_POINTS and location == CURRENCY_LOCATION_CHARACTER)
    return engine.wallet or 0
end
function ShouldShowLeaderboardForBattlegroundLeaderboardType() return engine.showLeaderboard == true end
function GetBattlegroundLeaderboardsSchedule() return engine.rankSeconds or 86400, engine.nextRankStart or 86400 end
function GetBattlegroundLeaderboardLocalPlayerInfo() return engine.rank or 0, 0 end
function QueryBattlegroundLeaderboardData() engine.rankQueries = (engine.rankQueries or 0) + 1; return engine.rankReadyState or LEADERBOARD_DATA_READY end
function IsUnitInCombat() return engine.combat == true end
