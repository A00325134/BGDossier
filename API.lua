-- Adapter verified against esoui/esoui live ESOUIDocumentation.txt, API 101051.
-- Optional calls return nil rather than manufacturing a zero statistic.
local B = BattlegroundDossier
B.API = {}
local A = B.API
function A:Call(name, ...)
    local fn = _G[name]
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
    if not self.errors then self.errors = {} end
    if not self.errors[name] then B.Debug("API unavailable: " .. name); self.errors[name] = true end
end
A.scoreTypes = {
    kills = "KILL", deaths = "DEATH", assists = "ASSISTS", damage = "DAMAGE_DONE", healing = "HEALING_DONE", score = "SCORE",
    damageTaken = "DAMAGE_TAKEN", shieldsGranted = "DAMAGE_SHIELDS_GRANTED", buffsGranted = "BUFFS_GRANTED",
    debuffsGranted = "DEBUFFS_GRANTED", flagsCaptured = "FLAG_CAPTURED", flagCarriedTime = "FLAG_CARRIED_TIME",
    captureDefensePoints = "CAPTURE_DEFENSE_POINTS", killedAttacker = "CAPTURE_KILLED_ATTACKER",
    killedDefender = "CAPTURE_KILLED_DEFENDER", damagedFlagCarrier = "DAMAGED_FLAG_CARRIER",
    healedFlagCarrier = "HEALED_FLAG_CARRIER", healingDefenders = "HEALING_DEFENDERS",
    killedFlagCarrier = "KILLED_FLAG_CARRIER", killStreak = "KILL_STREAK",
}
function A:ObjectiveType(mode)
    if mode == BATTLEGROUND_GAME_TYPE_DEATHMATCH then return "damageTaken", "Damage taken (native Deathmatch objective column)" end
    if mode == BATTLEGROUND_GAME_TYPE_MURDERBALL then return "flagCarriedTime", "Ball carry time (seconds)" end
    if mode == BATTLEGROUND_GAME_TYPE_CAPTURE_THE_FLAG or mode == BATTLEGROUND_GAME_TYPE_KING_OF_THE_HILL
        or mode == BATTLEGROUND_GAME_TYPE_DOMINATION or mode == BATTLEGROUND_GAME_TYPE_CRAZY_KING then
        return "flagsCaptured", "Flags / objectives captured"
    end
end
function A:ModeName(mode)
    if mode and GetString then
        local ok, result = pcall(GetString, "SI_BATTLEGROUNDGAMETYPE", mode)
        if ok and type(result) == "string" and result ~= "" then return result end
    end
    return "Unknown mode"
end
function A:TeamName(team)
    local name = self:Call("GetBattlegroundTeamName", team)
    return B.Normalize(name) and name or ("Team " .. tostring(team))
end
function A:AbilityCategory(abilityId)
    -- Resolve only client-known progression metadata. Proc/tick IDs often have none.
    local hasProgression, progression = self:Call("GetAbilityProgressionXPInfoFromAbilityId", abilityId)
    if hasProgression and progression then
        local skillType = self:Call("GetSkillAbilityIndicesFromProgressionIndex", progression)
        if skillType and skillType == SKILL_TYPE_CLASS then return "Class abilities" end
        if skillType and skillType == SKILL_TYPE_WEAPON then return "Weapon abilities" end
        if skillType and (skillType == SKILL_TYPE_GUILD or skillType == SKILL_TYPE_WORLD) then return "Guild / world abilities" end
    end
    return "Other observed effects"
end
function A:Roster(round)
    local rows = {}
    local count = self:Call("GetNumScoreboardEntries", round)
    if type(count) ~= "number" or count < 0 or count > 100 then return rows, nil end
    for i = 1, count do
        local character, account, team, isLocal = self:Call("GetScoreboardEntryInfo", i, round)
        -- Every exposed slot is a match participant, even before identity/statistics arrive.
        rows[#rows + 1] = { index = i, character = type(character) == "string" and character or nil,
            account = type(account) == "string" and account or nil, team = team,
            isLocal = isLocal == true, roundIndex = round, classId = self:Call("GetScoreboardEntryClassId", i, round) }
    end
    return rows, count
end
function A:Snapshot(session)
    if self:Call("GetCurrentBattlegroundState") ~= BATTLEGROUND_STATE_FINISHED then return nil, "not finished" end
    if self:Call("GetCurrentBattlegroundId") ~= session.mapId then return nil, "Battleground identity changed" end
    local round = self:Call("GetCurrentBattlegroundRoundIndex")
    if type(round) ~= "number" or round < 1 then return nil, "round unavailable" end
    local hasRounds = self:Call("DoesBattlegroundHaveRounds", session.mapId) == true
    local mode = self:Call("GetCurrentBattlegroundGameType", round)
    local m = { id = session.id, world = session.world, mapId = session.mapId, startedAt = session.startedAt,
        finishedAt = session.finishedAt, localCharacter = session.localCharacter, localCharacterId = session.localCharacterId,
        liveHUDSessionId = session.liveHUDSessionId, roundIndex = round, hasRounds = hasRounds,
        mode = mode, modeName = self:ModeName(mode), map = self:Call("GetBattlegroundName", session.mapId),
        teams = {}, players = {}, rounds = {}, apiVersion = self:Call("GetAPIVersion"),
        competitive = self:Call("DoesCurrentBattlegroundImpactMMR"), teamCapacity = self:Call("GetBattlegroundTeamSize", session.mapId) }
    if self:Call("IsActiveWorldBattleground") and self:Call("GetCurrentBattlegroundId") == session.mapId then
        local zone = self:Call("GetUnitZone", "player")
        if type(zone) == "string" and B.Normalize(zone) then m.zoneName = zone end
    end
    -- Union round rosters so early leavers are not lost when they are absent from the last round.
    -- The cumulative function is called with each entry's own round/index, as in the native UI.
    local rosterByIdentity, roundRosters, characterAccounts, accountNames, ambiguousCharacters = {}, {}, {}, {}, {}
    local roundIndexes = {}
    for r = hasRounds and 1 or round, math.min(round, 20) do roundIndexes[#roundIndexes + 1] = r end
    if round > 20 then roundIndexes[#roundIndexes + 1] = round; m.roundHistoryTruncated = hasRounds end
    local diagnostics = { scoreboardEntries = 0, finalRoundCaptured = 0, exposedRoundEntries = 0, roundEntries = {} }
    m.diagnostics = diagnostics
    for _, r in ipairs(roundIndexes) do
        local rows, exposed = self:Roster(r)
        roundRosters[r] = rows
        diagnostics.roundEntries[r] = exposed
        diagnostics.exposedRoundEntries = diagnostics.exposedRoundEntries + (exposed or 0)
        if r == round then diagnostics.scoreboardEntries, diagnostics.finalRoundCaptured = exposed or 0, #rows end
        local characterCounts = {}
        for _, p in ipairs(rows) do
            local character = B.Normalize(p.character)
            local id, confidence = B.Identity(p, m.world)
            if character then
                characterCounts[character] = (characterCounts[character] or 0) + 1
                if characterCounts[character] > 1 then ambiguousCharacters[character] = true end
                if confidence == "account" then
                    characterAccounts[character] = characterAccounts[character] or {}
                    characterAccounts[character][id] = true; accountNames[id] = p.account
                end
            end
        end
    end
    for _, r in ipairs(roundIndexes) do
        local identities = {}
        for _, p in ipairs(roundRosters[r]) do
            local character = B.Normalize(p.character)
            local id, confidence = B.Identity(p, m.world)
            local candidates = character and characterAccounts[character]
            -- Exact unique character/account association within these authoritative round rosters only.
            -- Historical character-only profiles are never merged or rewritten.
            if confidence == "character" and candidates and B.Count(candidates) == 1 and not ambiguousCharacters[character] then
                for accountId in pairs(candidates) do p.account = accountNames[accountId]; p.accountSource = "exact-round-character" end
                id, confidence = B.Identity(p, m.world)
            end
            p.identityConfidence = confidence or "unresolved"
            identities[id or false] = (identities[id or false] or 0) + 1
        end
        for _, p in ipairs(roundRosters[r]) do
            local id = B.Identity(p, m.world)
            if not id or identities[id] > 1 then
                -- Preserve colliding slots without attributing observations or lifetime profiles.
                p.identityConfidence, p.identityAmbiguous = "unresolved", id ~= nil
                id = session.id .. ":slot:" .. r .. ":" .. p.index
            end
            p.participantId = id
            local old = rosterByIdentity[id]
            if old and old.team ~= p.team then p.teamUncertain = true end
            if old and old.teamUncertain then p.teamUncertain = true end
            rosterByIdentity[id] = p
        end
    end
    local keys = {}; for id in pairs(rosterByIdentity) do keys[#keys + 1] = id end; table.sort(keys)
    for _, id in ipairs(keys) do m.players[#m.players + 1] = rosterByIdentity[id] end
    if #m.players == 0 then return nil, "empty scoreboard" end
    local teamCount = self:Call("GetBattlegroundNumTeams", session.mapId)
    local configuredTeams = type(teamCount) == "number" and teamCount >= 2 and teamCount <= 10
    m.teamCount = configuredTeams and teamCount or nil
    for i = 1, configuredTeams and teamCount or 0 do
        local team = self:Call("GetBattlegroundTeamByIndex", session.mapId, i)
        if team then m.teams[team] = { name = self:TeamName(team), result = B.Result(self:Call("GetBattlegroundResultForTeam", team)),
            score = hasRounds and self:Call("GetCurrentBattlegroundRoundsWonByTeam", team)
                or self:Call("GetCurrentBattlegroundScore", round, team) } end
    end
    local objectiveKey, objectiveLabel = self:ObjectiveType(mode)
    m.objectiveLabel = objectiveLabel
    local scoreFn = hasRounds and "GetBattlegroundCumulativeScoreForScoreboardEntryByType" or "GetScoreboardEntryScoreByType"
    local seen = {}
    for _, p in ipairs(m.players) do
        local entryRound = p.roundIndex
        if not m.teams[p.team] then
            if type(p.team) == "number" and p.team > 0 then
                -- A roster-reported team remains usable even if team enumeration is delayed.
                m.teams[p.team] = { name = self:TeamName(p.team), result = B.Result(self:Call("GetBattlegroundResultForTeam", p.team)),
                    score = hasRounds and self:Call("GetCurrentBattlegroundRoundsWonByTeam", p.team) or self:Call("GetCurrentBattlegroundScore", round, p.team) }
                m.teamConfigurationMismatch = true
            else p.reportedTeam, p.team = p.team, nil end
        end
        local identity = B.Identity(p, m.world)
        if identity then seen[identity] = true end
        if p.isLocal then
            if p.teamUncertain then m.localTeamUncertain = true end
            if m.localPlayerId then m.localIdentityAmbiguous, m.localTeam = true, nil
            else m.localTeam, m.localPlayerId = p.team, p.participantId end
        end
        for key, suffix in pairs(self.scoreTypes) do
            local constant = _G["SCORE_TRACKER_TYPE_" .. suffix]
            if constant ~= nil then
                local v = self:Call(scoreFn, p.index, constant, entryRound)
                if type(v) == "number" and v >= 0 then p[key] = v end
            end
        end
        -- A mixed-mode multi-round aggregate has no meaningful single objective unit.
        if not hasRounds and objectiveKey then p.objective = p[objectiveKey] end
        p.medals = {}
        if hasRounds and type(GenerateCumulativeMedalInfoForScoreboardEntry) == "function" then
            local ok = pcall(GenerateCumulativeMedalInfoForScoreboardEntry, p.index, entryRound)
            if ok then
                local last
                for _ = 1, 100 do
                    local id = self:Call("GetNextBattlegroundCumulativeMedalId", last)
                    if not id or id == last then break end
                    local count = self:Call("GetBattlegroundCumulativeNumEarnedMedalsById", id)
                    if type(count) == "number" and count > 0 then p.medals[id] = { name = self:Call("GetMedalName", id), count = count } end
                    last = id
                end
            end
        elseif not hasRounds then
            local n = self:Call("GetBattlegroundNumUsedMedals", session.mapId) or 0
            for medal = 1, math.min(n, 100) do
                local id = self:Call("GetBattlegroundMedalIdByIndex", session.mapId, medal)
                if id then
                    local count = self:Call("GetScoreboardEntryNumEarnedMedalsById", p.index, id, entryRound)
                    if type(count) == "number" and count > 0 then
                        p.medals[id] = { name = self:Call("GetMedalName", id), count = count }
                    end
                end
            end
        end
        p.livesRemaining = self:Call("GetScoreboardEntryNumLivesRemaining", p.index, entryRound)
        p.abilities = self:ObservedAbilities(session, identity)
        p.scoreboardSlot, p.index = p.index, nil
    end
    if m.localIdentityAmbiguous then m.localTeam = nil end
    m.outcome = m.teams[m.localTeam] and m.teams[m.localTeam].result or "Unresolved"
    m.participantCount = #m.players
    m.scoreLabel = hasRounds and "Rounds won" or "Team score"
    m.winningTeams = {}
    local rank, localScore, scoresAvailable = 1, m.teams[m.localTeam] and m.teams[m.localTeam].score, configuredTeams
    for team, t in pairs(m.teams) do
        if t.result == "Win" then m.winningTeams[#m.winningTeams + 1] = team end
        if type(t.score) ~= "number" then scoresAvailable = false end
        if type(localScore) == "number" and type(t.score) == "number" and t.score > localScore then rank = rank + 1 end
    end
    if type(localScore) == "number" and scoresAvailable then m.placement = rank end
    for r = 1, math.min(round, 20) do
        local row = { mode = self:Call("GetCurrentBattlegroundGameType", r), scores = {} }
        for team in pairs(m.teams) do row.scores[team] = self:Call("GetCurrentBattlegroundScore", r, team) end
        m.rounds[r] = row
    end
    for id in pairs(session.seenRoster or {}) do if not seen[id] then m.rosterMayBeIncomplete = true end end
    self:Diagnose(m)
    return m
end
function A:ObservedAbilities(session, identity)
    if not identity then return {} end
    local abilities = B.Copy(session.observations[identity] or {})
    for alias in pairs((session.observationAliases or {})[identity] or {}) do
        for id, a in pairs(session.observations[alias] or {}) do
            if not abilities[id] then
                if B.Count(abilities) < B.MAX_ABILITIES then abilities[id] = B.Copy(a) end
            else
                local combined = abilities[id]
                for _, field in ipairs({ "events", "damage", "healing" }) do if type(a[field]) == "number" then combined[field] = (combined[field] or 0) + a[field] end end
                if a.firstSeen then combined.firstSeen = math.min(combined.firstSeen or a.firstSeen, a.firstSeen) end
                if a.lastSeen then combined.lastSeen = math.max(combined.lastSeen or a.lastSeen, a.lastSeen) end
            end
        end
    end
    return abilities
end
function A:Diagnose(m)
    local d = m.diagnostics or {}; m.diagnostics = d
    d.participants, d.accountIdentities, d.characterIdentities, d.unresolvedIdentities, d.unknownTeams, d.missingStatistics, d.retainedParticipants, d.earlierStatistics, d.uncertainRelationships = #m.players, 0, 0, 0, 0, 0, 0, 0, 0
    m.actualTeamSizes, m.finalTeamSizes = {}, {}
    for team in pairs(m.teams) do m.actualTeamSizes[team], m.finalTeamSizes[team] = 0, 0 end
    for _, p in ipairs(m.players) do
        local _, confidence = B.Identity(p, m.world)
        local key = confidence == "account" and "accountIdentities" or confidence == "character" and "characterIdentities" or "unresolvedIdentities"
        d[key] = d[key] + 1
        if p.team and m.teams[p.team] then
            m.actualTeamSizes[p.team] = m.actualTeamSizes[p.team] + 1
            if p.roundIndex == m.roundIndex and not p.notInLatestScoreboard then m.finalTeamSizes[p.team] = m.finalTeamSizes[p.team] + 1 end
        else d.unknownTeams = d.unknownTeams + 1 end
        if p.teamUncertain then d.uncertainRelationships = d.uncertainRelationships + 1 end
        if p.statisticsFromEarlierRead then d.earlierStatistics = d.earlierStatistics + 1 end
        if p.roundIndex ~= m.roundIndex or p.notInLatestScoreboard then d.retainedParticipants = d.retainedParticipants + 1 end
        if p.kills == nil or p.deaths == nil or p.assists == nil or p.score == nil then d.missingStatistics = d.missingStatistics + 1 end
    end
    local resultsMissing = not m.teamCount or B.Count(m.teams) ~= m.teamCount or not m.localTeam or m.teamConfigurationMismatch
    for _, t in pairs(m.teams) do if t.result == "Unresolved" then resultsMissing = true end end
    m.snapshotIncomplete = m.rosterMayBeIncomplete or d.unresolvedIdentities > 0 or d.unknownTeams > 0 or d.missingStatistics > 0
        or d.finalRoundCaptured ~= d.scoreboardEntries or resultsMissing or m.verificationInterrupted or d.earlierStatistics > 0
        or d.uncertainRelationships > 0 or m.localTeamUncertain or m.roundHistoryTruncated or m.captureTruncated or false
    m.captureStatus = m.snapshotIncomplete and "Partial" or "Verified window"
end
function A:Fingerprint(m)
    local rows = {}
    for _, p in ipairs(m.players) do
        local parts = { "identity=" .. (B.ParticipantKey(p, m.world) or "unresolved"), "team=" .. tostring(p.team), "class=" .. tostring(p.classId), "local=" .. tostring(p.isLocal) }
        for _, key in ipairs(B.metrics) do parts[#parts + 1] = key .. "=" .. tostring(p[key]) end
        for key in pairs(self.scoreTypes) do parts[#parts + 1] = key .. "=" .. tostring(p[key]) end
        parts[#parts + 1] = "lives=" .. tostring(p.livesRemaining)
        for id, medal in pairs(p.medals or {}) do parts[#parts + 1] = "medal:" .. id .. "=" .. medal.count end
        table.sort(parts, function(a, b) return tostring(a) < tostring(b) end)
        rows[#rows + 1] = table.concat(parts, "/")
    end
    table.sort(rows)
    local teams = {}; for id, t in pairs(m.teams) do teams[#teams + 1] = tostring(id) .. ":" .. t.result .. ":" .. tostring(t.score) end
    table.sort(teams)
    return table.concat(teams, "|") .. "#" .. table.concat(rows, "|")
end
