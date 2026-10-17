local A = BGSessionTracker
local C = A.Core

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

function A:CancelResultRetry()
    EVENT_MANAGER:UnregisterForUpdate(self.name .. "Result")
    self.retryingResult = false
end

function A:ReadFinalResult()
    local match = self.session.match
    if not self.worldActive or not IsActiveWorldBattleground() or not match
        or not match.eligible or match.counted
        or GetCurrentBattlegroundId() ~= match.battlegroundId
        or GetCurrentBattlegroundState() ~= BATTLEGROUND_STATE_FINISHED then return false end

    local team = GetUnitBattlegroundTeam("player")
    if team == nil or team == BATTLEGROUND_TEAM_INVALID then return false end
    local localIndex = GetScoreboardLocalPlayerEntryIndex()
    if not C.IsCount(localIndex) or localIndex < 1 then return false end
    local _, _, scoreboardTeam, isLocal = GetScoreboardEntryInfo(localIndex)
    if not isLocal or scoreboardTeam ~= team then return false end

    local count = GetBattlegroundNumTeams(match.battlegroundId)
    if count ~= 2 and count ~= 3 then return false end
    local foundLocal, seen = false, {}
    for i = 1, count do
        local candidate = GetBattlegroundTeamByIndex(match.battlegroundId, i)
        if candidate == nil or candidate == BATTLEGROUND_TEAM_INVALID or seen[candidate] then return false end
        seen[candidate] = true
        if candidate == team then foundLocal = true end
        local result = GetBattlegroundResultForTeam(candidate)
        if result ~= BATTLEGROUND_RESULT_WIN and result ~= BATTLEGROUND_RESULT_LOSS
            and result ~= BATTLEGROUND_RESULT_TIE then return false end
    end
    if not foundLocal then return false end
    local result = GetBattlegroundResultForTeam(team)
    local outcome
    if result == BATTLEGROUND_RESULT_WIN then outcome = "win"
    elseif result == BATTLEGROUND_RESULT_LOSS then outcome = "loss"
    elseif result == BATTLEGROUND_RESULT_TIE then outcome = "draw" end
    if C.RecordResult(self.session, match, outcome) then
        self:CancelResultRetry()
        self:RefreshUI()
        self:RequestRank()
        return true
    end
    return false
end

function A:ObserveBattleground()
    if not self.worldActive then return end
    local state = GetCurrentBattlegroundState()
    if not IsActiveWorldBattleground() or state == BATTLEGROUND_STATE_NONE then
        local match = self.session.match
        if match and match.finishedSeen and not match.counted and match.eligible then
            self:Print("The last Battleground result was unavailable; no win or loss was recorded.")
        end
        self.session.match = nil
        self:CancelResultRetry()
        return
    end
    local id = GetCurrentBattlegroundId()
    if not C.IsCount(id) or id == 0 then return end
    local match = self.session.match
    if not match or match.battlegroundId ~= id then
        match = { battlegroundId = id, eligible = false }
        self.session.match = match
    end
    if state == BATTLEGROUND_STATE_STARTING or state == BATTLEGROUND_STATE_PREROUND
        or state == BATTLEGROUND_STATE_RUNNING or state == BATTLEGROUND_STATE_POSTROUND then
        -- Keep the same latch across rounds, zone events, and explicit reloads.
        match.eligible = true
        return
    end
    if state ~= BATTLEGROUND_STATE_FINISHED or match.counted or not match.eligible then return end
    match.finishedSeen = true
    if self:ReadFinalResult() or self.retryingResult then return end
    self.retryingResult = true
    local attempts = 0
    EVENT_MANAGER:RegisterForUpdate(self.name .. "Result", 500, function()
        attempts = attempts + 1
        if not self:ReadFinalResult() and attempts >= 20 then self:CancelResultRetry() end
    end)
end

function A:SelectLeaderboard()
    local competitive = BATTLEGROUND_LEADERBOARD_TYPE_COMPETITIVE
    if competitive and ShouldShowLeaderboardForBattlegroundLeaderboardType(competitive) then
        return competitive
    end
    -- Never substitute an unrelated legacy leaderboard for Competitive rank.
    return nil
end

function A:ScheduleRankExpiry()
    EVENT_MANAGER:UnregisterForUpdate(self.name .. "RankExpiry")
    if not self.rankType then return end
    local seconds, nextStart = GetBattlegroundLeaderboardsSchedule(self.rankType)
    if not C.IsNumber(seconds) or seconds <= 0 then seconds = nextStart end
    if C.IsNumber(seconds) and seconds > 0 then
        EVENT_MANAGER:RegisterForUpdate(self.name .. "RankExpiry", math.ceil(seconds * 1000) + 1000, function()
            EVENT_MANAGER:UnregisterForUpdate(self.name .. "RankExpiry")
            self.rank = nil
            self:RefreshUI()
            self:RequestRank()
        end)
    end
end

function A:ReadRank()
    self.rank = nil
    if self.rankType and self:SelectLeaderboard() == self.rankType then
        local seconds = GetBattlegroundLeaderboardsSchedule(self.rankType)
        local rank = GetBattlegroundLeaderboardLocalPlayerInfo(self.rankType)
        if C.IsNumber(seconds) and seconds > 0 and C.IsCount(rank) and rank > 0 then self.rank = rank end
    end
    self:ScheduleRankExpiry()
    self:RefreshUI()
end

function A:RequestRank()
    self.rankType = self:SelectLeaderboard()
    if not self.rankType then
        self.rank = nil
        self:RefreshUI()
        return
    end
    local now = GetFrameTimeMilliseconds()
    local wait = self.lastRankQuery and 60000 - (now - self.lastRankQuery) or 0
    if wait > 0 then
        if not self.rankQueryQueued then
            self.rankQueryQueued = true
            EVENT_MANAGER:RegisterForUpdate(self.name .. "RankQuery", math.ceil(wait), function()
                EVENT_MANAGER:UnregisterForUpdate(self.name .. "RankQuery")
                self.rankQueryQueued = false
                self:RequestRank()
            end)
        end
        return
    end
    self.lastRankQuery = now
    -- Bound pending data lifetime. No rank is persisted between UI loads.
    self.rank = nil
    self:RefreshUI()
    local ready = QueryBattlegroundLeaderboardData(self.rankType)
    if ready == LEADERBOARD_DATA_READY then self:ReadRank() end
end

function A:RegisterTracking()
    local function register(event, handler)
        EVENT_MANAGER:RegisterForEvent(self.name, event, handler)
    end
    register(EVENT_ALLIANCE_POINT_UPDATE, function(_, total, _, difference, reason)
        self:OnAP(total, difference, reason)
    end)
    register(EVENT_PLAYER_ACTIVATED, function()
        self.worldActive = true
        self:ObserveBattleground()
        self:RequestRank()
    end)
    register(EVENT_PLAYER_DEACTIVATED, function()
        -- Never inspect a departing world's cached scoreboard.
        self.worldActive = false
        self:CancelResultRetry()
    end)
    register(EVENT_BATTLEGROUND_STATE_CHANGED, function(_, previous, current)
        -- Also support consecutive matches on the same map without an outside
        -- world activation. Map IDs identify a template, not a match instance.
        if previous == BATTLEGROUND_STATE_FINISHED and
            (current == BATTLEGROUND_STATE_STARTING or current == BATTLEGROUND_STATE_PREROUND
                or current == BATTLEGROUND_STATE_RUNNING) then
            self.session.match = nil
        end
        self:ObserveBattleground()
    end)
    register(EVENT_BATTLEGROUND_SCOREBOARD_UPDATED, function()
        -- Late scoreboards may arrive after the bounded retry window.
        self:ReadFinalResult()
    end)
    register(EVENT_BATTLEGROUND_LEADERBOARD_DATA_RECEIVED, function(_, leaderboardType)
        if leaderboardType == self.rankType then self:ReadRank() end
    end)
end
