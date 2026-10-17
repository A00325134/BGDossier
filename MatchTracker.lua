local B = BattlegroundDossier
B.Match = {}
local M = B.Match
function M:Initialize()
    B.Combat:Initialize()
    EVENT_MANAGER:RegisterForEvent(B.name, EVENT_BATTLEGROUND_STATE_CHANGED, function(_, previous, current) self:State(previous, current) end)
    EVENT_MANAGER:RegisterForEvent(B.name, EVENT_BATTLEGROUND_SCOREBOARD_UPDATED, function() self:Roster(); if self.pending then self:TryCapture() end end)
    EVENT_MANAGER:RegisterForEvent(B.name, EVENT_PLAYER_ACTIVATED, function()
        self:Activated()
        if B.LiveSession and B.LiveSession:IsReady() then B.LiveSession:RequestRank() end
    end)
    EVENT_MANAGER:RegisterForEvent(B.name, EVENT_PLAYER_DEACTIVATED, function() self:Leaving() end)
    self:Activated()
end
function M:Stop()
    EVENT_MANAGER:UnregisterForUpdate(B.name .. "Final")
    EVENT_MANAGER:UnregisterForUpdate(B.name .. "Recognition")
    self.pending = nil
    B.Combat:SetActive(false)
end
function M:Activated()
    -- Reuse the existing activation owner: login/reload and every zone/loading
    -- transition refresh the HUD without polling or another event subscription.
    if B.LiveSession then B.LiveSession:ApplyVisibility() end
    if not B.API:Call("IsActiveWorldBattleground") then
        self:Flush("left Battleground")
        self:Stop(); self.session = nil; B.db.active = nil
        return
    end
    self:EnsureSession()
    if self.session then self.session.captureFailed = nil end
    local state = B.API:Call("GetCurrentBattlegroundState")
    if B.LiveSession then B.LiveSession:OnMatchObserved(self.session, state) end
    if state == BATTLEGROUND_STATE_FINISHED then self:Finish() else self:Roster(); B.Combat:SetActive(state == BATTLEGROUND_STATE_RUNNING) end
end
function M:EnsureSession(force)
    local map = B.API:Call("GetCurrentBattlegroundId")
    if not map or map <= 0 then return end
    local world = B.API:Call("GetWorldName") or "unknown"
    local saved = B.db.active
    if not force and type(saved) == "table" and saved.mapId == map and saved.world == world
        and type(saved.id) == "string" and type(saved.startedAt) == "number" and B.Now() - saved.startedAt < 21600 then
        self.session = saved
        saved.observations = type(saved.observations) == "table" and saved.observations or {}
        for id, abilities in pairs(saved.observations) do saved.observations[id] = B.Storage:RepairAbilities(abilities) end
        saved.seenRoster = type(saved.seenRoster) == "table" and saved.seenRoster or {}
    else
        self:Flush("starting a different or expired session")
        self:Stop()
        self.session = B.Storage:NewSession(map, world)
        B.Debug("New match session " .. self.session.id)
    end
    return self.session
end
function M:State(previous, current)
    if current == BATTLEGROUND_STATE_NONE then
        self:Flush("match data cleared")
        self:Stop(); self.session = nil; B.db.active = nil; return
    end
    if not B.API:Call("IsActiveWorldBattleground") then return end
    local force = previous == BATTLEGROUND_STATE_FINISHED and current ~= BATTLEGROUND_STATE_FINISHED
    if force then self:Flush("new match started") end
    self:EnsureSession(force)
    if B.LiveSession then B.LiveSession:OnMatchObserved(self.session, current) end
    B.Debug("State " .. tostring(previous) .. " -> " .. tostring(current))
    if current == BATTLEGROUND_STATE_FINISHED then self:Finish()
    else
        -- POSTROUND never commits. Observations span rounds within the same session.
        self:Roster()
        B.Combat:SetActive(current == BATTLEGROUND_STATE_RUNNING)
        if current == BATTLEGROUND_STATE_RUNNING then
            EVENT_MANAGER:UnregisterForUpdate(B.name .. "Recognition")
            EVENT_MANAGER:RegisterForUpdate(B.name .. "Recognition", 4000, function()
                EVENT_MANAGER:UnregisterForUpdate(B.name .. "Recognition"); self:Roster(); self:Notify()
            end)
        end
    end
end
function M:Roster()
    if not self.session or self.session.finalized then return end
    B.Combat:RefreshRoster(self.session, B.API:Roster(B.API:Call("GetCurrentBattlegroundRoundIndex")))
end
function M:Notify()
    if not self.session or self.session.notified or not B.db.settings.notifications then return end
    local familiar, seen = 0, {}
    for _, p in ipairs(B.Combat.roster) do
        local id = B.Identity(p, self.session.world)
        if id and not seen[id] and not p.isLocal and B.Players:Get(p, self.session.world) then familiar = familiar + 1; seen[id] = true end
    end
    if familiar > 0 then B.Say(familiar .. " Familiar Players Detected"); self.session.notified = true end
end
function M:Finish()
    if not self.session or self.session.finalized or self.session.captureFailed or self.pending then return end
    if B.Storage:HasMatch(self.session.id) then self.session.finalized, self.session.pendingSnapshot = true, nil; self:Stop(); return end
    B.Combat:SetActive(false)
    self.session.finishedAt = self.session.finishedAt or B.Now()
    self.session.verifyStartedAt = self.session.verifyStartedAt or B.Now()
    local elapsed = math.max(0, math.min(30000, (B.Now() - self.session.verifyStartedAt) * 1000))
    self.pending = { started = GetFrameTimeMilliseconds() - elapsed, samples = 0 }
    EVENT_MANAGER:RegisterForUpdate(B.name .. "Final", 1000, function() self:TryCapture() end)
    self:TryCapture()
end
function M:TryCapture()
    local pending, session = self.pending, self.session
    if not pending or not session then return end
    if B.API:Call("GetCurrentBattlegroundState") ~= BATTLEGROUND_STATE_FINISHED then self:Flush("final scoreboard no longer available"); self:Stop(); return end
    local now = GetFrameTimeMilliseconds()
    local snapshot, reason = B.API:Snapshot(session)
    if snapshot then
        self:Remember(snapshot)
        local fingerprint = B.API:Fingerprint(snapshot)
        if fingerprint ~= pending.fingerprint then
            pending.fingerprint, pending.stableSince, pending.samples = fingerprint, now, 1
        else pending.samples = pending.samples + 1 end
    else
        pending.fingerprint, pending.samples = nil, 0
        if pending.lastReason ~= reason then B.Debug("Waiting for final scoreboard: " .. tostring(reason)); pending.lastReason = reason end
    end
    if now - pending.started >= 30000 then
        local interrupted = not snapshot or not pending.stableSince or now - pending.stableSince < 3000
        if not self:Flush(interrupted and "verification ended with unsettled data" or nil, true) then
            self:Stop(); session.captureFailed = true
            B.Say(session.pendingSnapshot and "Final scoreboard retained, but saving failed. Enable /bgd debug on for details; reload to retry."
                or "No final scoreboard entries were available within 30 seconds; match was not saved.")
        end
    end
end
function M:Remember(snapshot)
    local previous = self.session.pendingSnapshot
    if previous and previous.id == snapshot.id then
        local current = {}
        local characters, counts, slots = {}, {}, {}
        for _, p in ipairs(snapshot.players) do
            current[B.ParticipantKey(p, snapshot.world)] = p
            local character = B.Normalize(p.character)
            if character then characters[character] = p; counts[character] = (counts[character] or 0) + 1 end
            slots[tostring(p.roundIndex) .. ":" .. tostring(p.scoreboardSlot)] = true
        end
        for _, old in ipairs(previous.players) do
            local id = B.ParticipantKey(old, snapshot.world)
            local p = id and current[id]
            local character = B.Normalize(old.character)
            if not p and character and counts[character] == 1 then
                local candidate = characters[character]
                local oldIdentity, oldConfidence = B.Identity(old, snapshot.world)
                local newIdentity, newConfidence = B.Identity(candidate, snapshot.world)
                if oldIdentity and newIdentity and (oldConfidence == "character" and newConfidence == "account" or oldConfidence == "account" and newConfidence == "character") then
                    p = candidate
                    if oldConfidence == "account" then
                        p.account, p.identityConfidence, p.participantId = old.account, "account", old.participantId
                        p.accountSource = "exact-earlier-scoreboard-character"
                    end
                    local accountId = oldConfidence == "account" and oldIdentity or newIdentity
                    local characterId = oldConfidence == "character" and oldIdentity or newIdentity
                    self.session.observationAliases = self.session.observationAliases or {}
                    self.session.observationAliases[accountId] = self.session.observationAliases[accountId] or {}
                    self.session.observationAliases[accountId][characterId] = true
                    p.abilities = B.API:ObservedAbilities(self.session, accountId)
                end
            end
            if p then
                -- Preserve earlier known values only when a later read makes them unavailable.
                for key in pairs(B.API.scoreTypes) do if p[key] == nil then p[key] = old[key]; if old[key] ~= nil then p.statisticsFromEarlierRead = true end end end
            elseif id and (B.Identity(old, snapshot.world) or not slots[tostring(old.roundIndex) .. ":" .. tostring(old.scoreboardSlot)]) then
                -- Bound retained earlier reads; never truncate the current authoritative roster.
                if #snapshot.players < 2100 then
                    local retained = B.Copy(old); retained.notInLatestScoreboard = true
                    snapshot.players[#snapshot.players + 1] = retained
                else snapshot.captureTruncated = true end
            end
        end
    end
    local priorMax = previous and previous.diagnostics and (previous.diagnostics.maximumExposedEntries or previous.diagnostics.scoreboardEntries) or 0
    snapshot.diagnostics.maximumExposedEntries = math.max(priorMax or 0, snapshot.diagnostics.scoreboardEntries or 0)
    if previous and previous.captureTruncated then snapshot.captureTruncated = true end
    if #snapshot.players < snapshot.diagnostics.maximumExposedEntries then snapshot.rosterMayBeIncomplete = true end
    snapshot.participantCount = #snapshot.players
    B.API:Diagnose(snapshot)
    self.session.pendingSnapshot = snapshot
end
function M:Leaving()
    if not self.session or self.session.finalized then return end
    -- Deactivation also happens on reload. Only FINISHED can create/flush a candidate.
    if B.API:Call("GetCurrentBattlegroundState") == BATTLEGROUND_STATE_FINISHED then
        self:Finish()
        if self.pending then
            local snapshot = B.API:Snapshot(self.session); if snapshot then self:Remember(snapshot) end
        end
    end
    self:Flush("leaving or reloading before verification completed")
end
function M:Flush(reason, allowOpen)
    local session = self.session or B.db.active
    if not session or session.finalized then return false end
    local snapshot = session.pendingSnapshot
    if not snapshot or snapshot.id ~= session.id or not B.Storage:Valid(snapshot) or #snapshot.players == 0 then return false end
    if reason then snapshot.verificationInterrupted, snapshot.captureNote = true, reason end
    B.API:Diagnose(snapshot)
    local saved = B.Storage:Commit(snapshot)
    if saved or B.Storage:HasMatch(snapshot.id) then
        session.finalized, session.pendingSnapshot = true, nil
        self:Stop()
        if saved then
            local d = snapshot.diagnostics
            B.Debug(string.format("Scoreboard entries: %d | Final round captured: %d | Participants saved: %d | Account identities: %d | Character-only: %d | Unresolved: %d | Retained earlier: %d",
                d.scoreboardEntries or 0, d.finalRoundCaptured or 0, #snapshot.players, d.accountIdentities, d.characterIdentities, d.unresolvedIdentities, d.retainedParticipants))
            if snapshot.snapshotIncomplete then B.Debug("Capture warning: partial snapshot; " .. (snapshot.captureNote or "identity, team, statistics or roster data unavailable")) end
            if d.finalRoundCaptured ~= d.scoreboardEntries or #snapshot.players < (d.scoreboardEntries or 0) then B.Debug("Capture warning: exposed/captured participant count mismatch") end
            if (not reason or allowOpen) and B.db.settings.autoOpen and not B.API:Call("IsUnitInCombat", "player") then B.UI:OpenMatch(snapshot) end
        end
        return true
    end
    return false
end
