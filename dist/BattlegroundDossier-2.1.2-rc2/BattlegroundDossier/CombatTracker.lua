local B = BattlegroundDossier
B.Combat = { byName = {}, counts = {}, roster = {} }
local C = B.Combat
function C:Initialize()
    self.results = {}
    for _, name in ipairs({ "ACTION_RESULT_DAMAGE", "ACTION_RESULT_CRITICAL_DAMAGE", "ACTION_RESULT_DOT_TICK",
        "ACTION_RESULT_DOT_TICK_CRITICAL", "ACTION_RESULT_BLOCKED_DAMAGE",
        "ACTION_RESULT_HEAL", "ACTION_RESULT_CRITICAL_HEAL", "ACTION_RESULT_HOT_TICK", "ACTION_RESULT_HOT_TICK_CRITICAL" }) do
        if _G[name] then
            self.results[_G[name]] = (name:find("HEAL") or name:find("HOT")) and "healing" or "damage"
        end
    end
end
function C:RefreshRoster(session, rows)
    if not session then return end
    self.byName, self.roster = {}, rows
    local aliases = {}
    for _, p in ipairs(rows) do
        local id = B.Identity(p, session.world)
        if id then
            session.seenRoster[id] = true
            for _, name in ipairs({ p.character or "", p.account or "" }) do
                local normalized = B.Normalize(name)
                if normalized then
                    aliases[normalized] = aliases[normalized] or {}
                    aliases[normalized][id] = true
                end
            end
        end
    end
    for name, ids in pairs(aliases) do
        if B.Count(ids) == 1 then for id in pairs(ids) do self.byName[name] = id end end
    end
    -- Drop name cache on roster changes: a previously unique name can become ambiguous.
    self.sourceCache, self.sourceCacheCount, self.counts = {}, 0, {}
    for id, abilities in pairs(session.observations) do self.counts[id] = B.Count(abilities) end
end
function C:SetActive(active)
    EVENT_MANAGER:UnregisterForEvent(B.name .. "Combat", EVENT_COMBAT_EVENT)
    if not active or not B.db.settings.observeCombat then return end
    EVENT_MANAGER:RegisterForEvent(B.name .. "Combat", EVENT_COMBAT_EVENT, function(_, ...) self:OnEvent(...) end)
end
function C:OnEvent(result, isError, abilityName, abilityGraphic, slotType, sourceName, sourceType,
    targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId, overflow)
    local session = B.Match.session
    if not session or session.finalized or not self.results[result] or isError or not B.db.settings.observeCombat then return end
    if sourceType ~= COMBAT_UNIT_TYPE_PLAYER and sourceType ~= COMBAT_UNIT_TYPE_OTHER and sourceType ~= COMBAT_UNIT_TYPE_GROUP then return end
    if type(abilityId) ~= "number" or abilityId <= 0 or type(sourceName) ~= "string" or sourceName == "" then return end
    local id = self.sourceCache[sourceName]
    if id == nil then
        id = self.byName[B.Normalize(sourceName)] or false
        -- Bound unmatched-name cache; no raw-event storage.
        if self.sourceCacheCount < 256 then self.sourceCache[sourceName] = id; self.sourceCacheCount = self.sourceCacheCount + 1 end
    end
    if not id then return end
    self:Observe(session, id, abilityId, abilityName, self.results[result], hitValue)
end
function C:Observe(session, id, abilityId, name, kind, value)
    local abilities = session.observations[id]
    if not abilities then
        if B.Count(session.observations) >= 100 then return end
        abilities = {}; session.observations[id] = abilities
    end
    local a = abilities[abilityId]
    if not a then
        if (self.counts[id] or 0) >= B.MAX_ABILITIES then return end
        a = { name = name, firstSeen = B.Now(), lastSeen = B.Now(), events = 0, category = B.API:AbilityCategory(abilityId) }
        abilities[abilityId] = a
        self.counts[id] = (self.counts[id] or 0) + 1
    end
    a.events, a.lastSeen = a.events + 1, B.Now()
    if (kind == "damage" or kind == "healing") and type(value) == "number" and value >= 0 then
        a[kind] = (a[kind] or 0) + value
    end
end
