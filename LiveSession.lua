local B = BattlegroundDossier
local C = B.LiveCore
B.LiveSession = { name = B.name .. "Live" }
local A = B.LiveSession

function A:Print(message) B.Say(message) end
function A:IsReady()
    return not self.disabledReason and B.db ~= nil and self.session ~= nil and self.root == B.db.liveHUD and self.saved ~= nil
end
function A:CharacterKey()
    local characterId = B.API:Call("GetCurrentCharacterId")
    local character = characterId and tostring(characterId) or B.Normalize(GetUnitName("player")) or "unknown"
    return (GetWorldName() or "unknown") .. ":" .. character
end
function A:NewSession()
    self.saved.sequence = (C.IsCount(self.saved.sequence) and self.saved.sequence or 0) + 1
    local session = C.NewSession(GetTimeStamp())
    session.token = self.characterKey .. ":" .. self.saved.sequence
    session.unresolved = 0
    return session
end
function A:Initialize()
    self.disabledReason = nil
    local root = B.db.liveHUD
    if type(root) ~= "table" then root = { version = 1, characters = {} }; B.db.liveHUD = root end
    if root.version ~= nil and root.version ~= 1 then
        self.disabledReason = "Live HUD data uses an unsupported version; it has been preserved."
        self:Print(self.disabledReason); return
    end
    root.version = 1
    if type(root.characters) ~= "table" then root.characters = {} end
    self.root, self.characterKey = root, self:CharacterKey()
    local record = root.characters[self.characterKey]
    if type(record) ~= "table" then
        record = {}
        if B.Count(root.characters) < 128 then root.characters[self.characterKey] = record
        else self:Print("Live HUD character storage is full; this character's HUD settings will not persist.") end
    end
    self.saved = record
    local p = type(record.preferences) == "table" and record.preferences or {}
    p.scale, p.opacity = C.Clamp(p.scale, 0.65, 1.75, 1), C.Clamp(p.opacity, 0, 1, 0.82)
    p.visible, p.locked, p.header = p.visible ~= false, p.locked ~= false, p.header ~= false
    -- Additive preference: old installs keep their existing manual visibility.
    if p.visibilityMode ~= "battlegroundsOnly" then p.visibilityMode = "always" end
    if not C.IsNumber(p.x) then p.x = nil end
    if not C.IsNumber(p.y) then p.y = nil end
    record.preferences, self.preferences = p, p
    local restored = C.CanResume(record.session, GetTimeStamp()) and type(record.session.token) == "string"
    record.session = restored and record.session or self:NewSession()
    self.session = record.session
    self.session.reloadAt = nil
    self.session.lastAP = self:ReadAPBalance()
    self.session.unresolved = C.IsCount(self.session.unresolved) and self.session.unresolved or 0
    for _, suffix in ipairs({ "RankQuery", "RankResponse", "RankExpiry" }) do EVENT_MANAGER:UnregisterForUpdate(self.name .. suffix) end
    self.apWarning, self.rank, self.rankType, self.lastRankQuery, self.rankQueryQueued = false, nil, nil, nil, false
    self.rankState, self.rankAttempts = "unknown", 0
    if not self.reloadHookInstalled then
        ZO_PreHook("ReloadUI", function()
            if self:IsReady() then self.session.reloadAt = GetTimeStamp() end
        end)
        self.reloadHookInstalled = true
    end
    self:CreateUI()
    self:RegisterCommands()
    -- Match and activation events remain owned by Dossier's MatchTracker.
    EVENT_MANAGER:RegisterForEvent(self.name, EVENT_ALLIANCE_POINT_UPDATE, function(_, total, _, difference, reason)
        if self:IsReady() then self:OnAP(total, difference, reason) end
    end)
    EVENT_MANAGER:RegisterForEvent(self.name, EVENT_BATTLEGROUND_LEADERBOARD_DATA_RECEIVED, function(_, leaderboardType)
        if self:IsReady() and leaderboardType == self.rankType then self:ReadRank() end
    end)
    B.Debug(restored and "Live session restored after UI reload." or "New live HUD session started.")
end
function A:OnMatchObserved(match, state)
    if not self:IsReady() or not match or match.finalized then return end
    if state == BATTLEGROUND_STATE_STARTING or state == BATTLEGROUND_STATE_PREROUND
        or state == BATTLEGROUND_STATE_RUNNING or state == BATTLEGROUND_STATE_POSTROUND then
        match.liveHUDSessionId = self.session.token
    end
end
function A:StageMatch(match)
    if not self:IsReady() or match.liveHUDSessionId ~= self.session.token or self.session.lastMatchId == match.id then return nil end
    local currentId = B.API:Call("GetCurrentCharacterId")
    if match.localCharacterId and currentId and tostring(match.localCharacterId) ~= tostring(currentId) then return nil end
    if not match.localCharacterId and B.Normalize(match.localCharacter) ~= B.Normalize(GetUnitName("player")) then return nil end
    local staged = B.Copy(self.session)
    local outcome = ({ Win = "win", Loss = "loss", Draw = "draw" })[match.outcome]
    if not C.RecordResult(staged, { eligible = true }, outcome) then staged.unresolved = (staged.unresolved or 0) + 1 end
    staged.lastMatchId = match.id
    return staged
end
function A:PublishMatch(staged)
    -- Pointer publication only; no UI/API calls in the storage transaction.
    self.saved.session, self.session = staged, staged
end
function A:RefreshAfterMatch()
    local ok, err = pcall(function() self:RefreshUI(); self:RequestRank() end)
    if not ok then B.Debug("Live HUD refresh deferred: " .. tostring(err)) end
end
function A:ResetSession()
    local previousToken, lastMatchId = self.session.token, self.session.lastMatchId
    local session = self:NewSession()
    session.lastMatchId, session.lastAP = lastMatchId, self:ReadAPBalance()
    self.saved.session, self.session = session, session
    local active = B.Match.session
    if active and not active.finalized and active.liveHUDSessionId == previousToken then
        active.liveHUDSessionId = session.token
        if active.pendingSnapshot then active.pendingSnapshot.liveHUDSessionId = session.token end
    end
    self.apWarning, self.resetUntil = false, nil
    self:RefreshUI(); self:Print("Live session statistics reset. Match history is unchanged.")
end
function A:ConfirmReset(argument)
    local now = GetFrameTimeMilliseconds()
    if self.resetUntil and now <= self.resetUntil and (argument == "" or argument == "confirm") then self:ResetSession()
    else
        self.resetUntil = now + 15000
        self:Print("Reset live session statistics? Type /bgreset again within 15 seconds to confirm.")
    end
end
function A:Toggle()
    if not self:IsReady() then B.Say(self.disabledReason or "Live HUD is not initialized."); return end
    self.preferences.visible = not self.preferences.visible; self:ApplyPreferences()
end
function A:PrintStats()
    local s = self.session
    self:Print(string.format("%d wins / %d losses / %d draws | %d completed | %s win rate | Competitive rank %s | +%s AP (%d exact). Session age: %d minutes. Unresolved results: %d.",
        s.wins, s.losses, s.draws, C.Completed(s), C.WinRate(s), self:RankText(), C.FormatAP(s.ap), s.ap,
        math.max(0, math.floor((GetTimeStamp() - s.startedAt) / 60)), s.unresolved or 0))
end
function A:RegisterCommands()
    SLASH_COMMANDS["/bgtracker"] = function(argument)
        local command, value = string.match(string.lower(argument or ""), "^%s*(%S*)%s*(.-)%s*$")
        local p = self.preferences
        if command == "" then self:Toggle(); return
        elseif command == "show" then p.visible = true
        elseif command == "hide" then p.visible = false
        elseif command == "scale" then
            local number = tonumber(value)
            if not C.IsNumber(number) or number < 0.65 or number > 1.75 then self:Print("Usage: /bgtracker scale 0.65-1.75"); return end
            p.scale = number
        elseif command == "opacity" then
            local number = tonumber(value)
            if not C.IsNumber(number) or number < 0 or number > 1 then self:Print("Usage: /bgtracker opacity 0-1"); return end
            p.opacity = number
        elseif command == "header" and (value == "on" or value == "off") then p.header = value == "on"
        elseif command == "position" and value == "reset" then p.x, p.y = nil, nil
        else self:Print("/bgtracker [show|hide|scale 0.65-1.75|opacity 0-1|header on/off|position reset] | /bglock | /bgstats | /bgreset"); return end
        self:ApplyPreferences()
    end
    SLASH_COMMANDS["/bgreset"] = function(argument) self:ConfirmReset(string.lower(string.match(argument or "", "^%s*(.-)%s*$"))) end
    SLASH_COMMANDS["/bglock"] = function()
        self.preferences.locked = not self.preferences.locked; self:ApplyPreferences()
        self:Print(self.preferences.locked and "HUD locked." or "HUD unlocked. Enable cursor mode to drag; mouse interaction is disabled in combat.")
    end
    SLASH_COMMANDS["/bgstats"] = function() self:PrintStats() end
end

function A:ReadAPBalance()
    -- GetAlliancePoints() is absent from the 101051 API/source. Use the
    -- documented currency API for the character's AP wallet instead.
    return GetCurrencyAmount(CURT_ALLIANCE_POINTS, CURRENCY_LOCATION_CHARACTER)
end

function A:OnAP(total, difference, reason)
    local excluded = reason == CURRENCY_CHANGE_REASON_PLAYER_INIT
        or reason == CURRENCY_CHANGE_REASON_BANK_WITHDRAWAL
        or reason == CURRENCY_CHANGE_REASON_BANK_DEPOSIT
        or reason == CURRENCY_CHANGE_REASON_GUILD_BANK_WITHDRAWAL
        or reason == CURRENCY_CHANGE_REASON_GUILD_BANK_DEPOSIT
    local changed, issue = C.ApplyAP(self.session, total, difference, reason, excluded)
    if issue and not self.apWarning then
        self.apWarning = true
        self:Print("An AP update could not be verified; it was skipped. Session AP includes verified gains only.")
    end
    if changed then self:RefreshUI() end
end

function A:SelectLeaderboard()
    local competitive = BATTLEGROUND_LEADERBOARD_TYPE_COMPETITIVE
    if competitive and ShouldShowLeaderboardForBattlegroundLeaderboardType(competitive) then
        return competitive
    end
    -- Never substitute an unrelated legacy leaderboard for Competitive rank.
    return nil
end

-- Rank is a runtime cache, never SavedVariables. Only a ready response can
-- establish Unranked; waiting for the API is not a zero-rank result.
function A:RankText()
    if self.rank then return "#" .. self.rank end
    if self.rankState == "pending" then return "Loading..." end
    if self.rankState == "ready" then return "Unranked" end
    return "Unavailable"
end

function A:ScheduleRankExpiry()
    EVENT_MANAGER:UnregisterForUpdate(self.name .. "RankExpiry")
    if not self.rankType then return end
    local seconds, nextStart = GetBattlegroundLeaderboardsSchedule(self.rankType)
    if not C.IsNumber(seconds) or seconds <= 0 then seconds = nextStart end
    if C.IsNumber(seconds) and seconds > 0 then
        EVENT_MANAGER:RegisterForUpdate(self.name .. "RankExpiry", math.ceil(seconds * 1000) + 1000, function()
            EVENT_MANAGER:UnregisterForUpdate(self.name .. "RankExpiry")
            if not self:IsReady() then return end
            self.rank, self.rankState = nil, "unknown"
            self:RequestRank()
        end)
    end
end

function A:ReadRank()
    if not self.rankType or self:SelectLeaderboard() ~= self.rankType then return end
    local rank = GetBattlegroundLeaderboardLocalPlayerInfo(self.rankType)
    local seconds = GetBattlegroundLeaderboardsSchedule(self.rankType)
    B.Debug("Competitive rank response: rank=" .. tostring(rank) .. ", season seconds=" .. tostring(seconds))
    -- Match the native UI: a positive local rank is valid independently of
    -- schedule metadata, which may not yet be populated. A zero rank requires
    -- a known active season before it can establish Unranked.
    if C.IsCount(rank) and (rank > 0 or (C.IsNumber(seconds) and seconds > 0)) then
        self.rank = rank > 0 and rank or nil
        self.rankState, self.rankAttempts = "ready", 0
        EVENT_MANAGER:UnregisterForUpdate(self.name .. "RankResponse")
        EVENT_MANAGER:UnregisterForUpdate(self.name .. "RankQuery")
        self.rankQueryQueued = false
    end
    self:ScheduleRankExpiry()
    self:RefreshUI()
end

function A:RequestRank(isRetry)
    if not self:IsReady() then return end
    local leaderboardType = self:SelectLeaderboard()
    if leaderboardType ~= self.rankType then self.rank = nil end
    self.rankType = leaderboardType
    if not self.rankType then
        self.rank, self.rankState, self.rankQueryQueued = nil, "unavailable", false
        for _, suffix in ipairs({ "RankQuery", "RankResponse", "RankExpiry" }) do EVENT_MANAGER:UnregisterForUpdate(self.name .. suffix) end
        self:RefreshUI()
        return
    end
    if not isRetry then self.rankAttempts = 0 end
    self.rankState = "pending"
    self:RefreshUI()
    local now = GetFrameTimeMilliseconds()
    local wait = self.lastRankQuery and 60000 - (now - self.lastRankQuery) or 0
    if wait > 0 then
        if not self.rankQueryQueued then
            self.rankQueryQueued = true
            EVENT_MANAGER:RegisterForUpdate(self.name .. "RankQuery", math.ceil(wait), function()
                EVENT_MANAGER:UnregisterForUpdate(self.name .. "RankQuery")
                self.rankQueryQueued = false
                self:RequestRank(true)
            end)
        end
        return
    end
    -- Cancel any old queued callback before sending one actual query.
    EVENT_MANAGER:UnregisterForUpdate(self.name .. "RankQuery")
    self.rankQueryQueued = false
    self.lastRankQuery, self.rankAttempts = now, (self.rankAttempts or 0) + 1
    B.Debug("Competitive rank query attempt " .. self.rankAttempts)
    -- Register before querying so a synchronous ready response can cancel it.
    EVENT_MANAGER:RegisterForUpdate(self.name .. "RankResponse", 60000, function()
        EVENT_MANAGER:UnregisterForUpdate(self.name .. "RankResponse")
        if not self:IsReady() or self.rankState ~= "pending" then return end
        if self.rankAttempts < 3 then self:RequestRank(true)
        else
            self.rank, self.rankState = nil, "unavailable"
            EVENT_MANAGER:UnregisterForUpdate(self.name .. "RankQuery")
            self.rankQueryQueued = false
            B.Debug("Competitive rank refresh timed out after three attempts; waiting for activation, match save or a native data event.")
            self:RefreshUI()
        end
    end)
    local ready = QueryBattlegroundLeaderboardData(self.rankType)
    B.Debug("Competitive rank query state: " .. tostring(ready))
    if ready == LEADERBOARD_DATA_READY then self:ReadRank() end
end
