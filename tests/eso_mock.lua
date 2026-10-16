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
    "DL_BACKGROUND", "TEXT_ALIGN_LEFT", "TEXT_ALIGN_RIGHT", "TEXT_ALIGN_CENTER", "TEXT_ALIGN_TOP", "TEXT_WRAP_MODE_ELLIPSIS", "TEXT_WRAP_MODE_TRUNCATE" }
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
local Control = {}; Control.__index = Control
local setters = { "SetAnchorFill", "SetCenterColor", "SetEdgeColor", "SetEdgeTexture", "SetFont", "SetColor",
    "SetNormalFontColor", "SetMouseOverFontColor", "SetPressedFontColor", "SetMouseEnabled", "SetMaxInputChars",
    "SetClampedToScreen", "SetMovable", "SetScale", "SetResizeToFitDescendents", "SetDrawLayer", "SetVerticalAlignment", "SetHorizontalAlignment", "SetMaxLineCount", "SetWrapMode", "SetTexture" }
for _, method in ipairs(setters) do Control[method] = function() end end
function Control:SetAnchor(...) self.anchor = { ... } end
function Control:ClearAnchors() self.anchor = nil end
function Control:SetDimensions(w, h) self.width, self.height = w, h end
function Control:SetHeight(h) self.height = h end
function Control:SetText(t) self.text = t end
function Control:GetText() return self.text or "" end
function Control:GetTextHeight() return math.max(24, math.ceil(#(self.text or "") / math.max(1, (self.width or 100) / 9)) * 24) end
function Control:SetHidden(v) self.hidden = v end
function Control:IsHidden() return self.hidden end
function Control:SetHandler(event, fn) self.handlers[event] = fn end
function Control:GetLeft() return 100 end
function Control:GetTop() return 100 end
function Control:LoseFocus() end
function Control:SetVerticalScroll(v) self.offset = v end
function Control:GetVerticalScroll() return self.offset or 0 end
function Control:GetNamedChild(name)
    if not self.children[name] then self.children[name] = setmetatable({ handlers = {}, children = {} }, Control) end
    return self.children[name]
end
local function new() return setmetatable({ handlers = {}, children = {} }, Control) end
WINDOW_MANAGER = {}
function WINDOW_MANAGER:CreateControl() return new() end
function WINDOW_MANAGER:CreateTopLevelWindow() return new() end
function WINDOW_MANAGER:CreateControlFromVirtual() return new() end
GuiRoot, InformationTooltip = new(), new()
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
