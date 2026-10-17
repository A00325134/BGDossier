local B = BattlegroundDossier
B.Storage = {}
local S = B.Storage
function S:RepairAbilities(t)
    if type(t) ~= "table" then return {} end
    for id, a in pairs(t) do
        if type(a) ~= "table" then t[id] = nil
        else
            for _, key in ipairs({ "events", "firstSeen", "lastSeen", "damage", "healing" }) do
                if type(a[key]) ~= "number" then a[key] = nil end
            end
            if type(a.name) ~= "string" then a.name = nil end
            if type(a.category) ~= "string" then a.category = nil end
        end
    end
    return t
end
function S:RepairBests(t)
    if type(t) ~= "table" then return {} end
    for key, best in pairs(t) do
        if type(best) ~= "table" or type(best.value) ~= "number" then t[key] = nil end
    end
    return t
end
function S:Initialize(db)
    if type(db.schema) == "number" and db.schema > B.schema then
        B.Say("Saved data uses a newer schema. Recording disabled to protect history.")
        return false
    end
    db.schema = B.schema
    for _, key in ipairs({ "settings", "matches", "profiles", "stats" }) do
        if type(db[key]) ~= "table" then db[key] = {} end
    end
    for k, v in pairs(B.defaults) do if type(db.settings[k]) ~= type(v) then db.settings[k] = v end end
    db.settings.historyLimit = math.floor(math.max(10, math.min(1000, db.settings.historyLimit)))
    db.settings.profileLimit = math.floor(math.max(100, math.min(20000, db.settings.profileLimit)))
    db.settings.frequentThreshold = math.floor(math.max(2, math.min(100, db.settings.frequentThreshold)))
    db.settings.scale = math.max(0.6, math.min(1.2, db.settings.scale))
    db.sequence = tonumber(db.sequence) or 0
    for _, key in ipairs({ "total", "Win", "Loss", "Draw", "Unresolved" }) do
        if type(db.stats[key]) ~= "number" then db.stats[key] = 0 end
    end
    db.stats.bests = self:RepairBests(db.stats.bests)
    for _, m in ipairs(db.matches) do
        if type(m) == "table" and type(m.players) == "table" and type(m.teams) == "table" then
            m.rounds = type(m.rounds) == "table" and m.rounds or {}
            m.world = type(m.world) == "string" and m.world or "unknown"
            m.outcome = ({ Win = true, Loss = true, Draw = true, Unresolved = true })[m.outcome] and m.outcome or "Unresolved"
            for _, p in ipairs(m.players) do
                if type(p) == "table" then
                    p.abilities = self:RepairAbilities(p.abilities)
                    p.medals = type(p.medals) == "table" and p.medals or {}
                    for id, medal in pairs(p.medals) do
                        if type(medal) ~= "table" or type(medal.count) ~= "number" then p.medals[id] = nil end
                    end
                    for _, key in ipairs(B.metrics) do if type(p[key]) ~= "number" then p[key] = nil end end
                end
            end
        end
    end
    for id, p in pairs(db.profiles) do
        if type(p) == "table" then
            p.id = type(p.id) == "string" and p.id or tostring(id)
            for _, field in ipairs({ "characters", "classes", "matches", "abilities", "bests" }) do
                if type(p[field]) ~= "table" then p[field] = {} end
            end
            p.abilities = self:RepairAbilities(p.abilities)
            p.bests = self:RepairBests(p.bests)
            for _, field in ipairs({ "account", "latestCharacter", "confidence" }) do
                if type(p[field]) ~= "string" then p[field] = nil end
            end
            for key, character in pairs(p.characters) do if type(character) ~= "string" then p.characters[key] = nil end end
            for _, field in ipairs({ "encounters", "allies", "opponents", "unknown", "wins", "losses", "draws", "unresolved" }) do
                if type(p[field]) ~= "number" then p[field] = 0 end
            end
        end
    end
    -- Keep older/unrecognized records intact; views only accept recognizable records.
    B.db = db
    self:Prune()
    return true
end
function S:Valid(m)
    if type(m) ~= "table" or type(m.id) ~= "string" or type(m.players) ~= "table" or type(m.teams) ~= "table" then return false end
    for _, p in ipairs(m.players) do
        if type(p) ~= "table" then return false end
        if p.character ~= nil and type(p.character) ~= "string" then return false end
        if p.account ~= nil and type(p.account) ~= "string" then return false end
    end
    for id, t in pairs(m.teams) do
        if type(id) ~= "number" or type(t) ~= "table" or type(t.name) ~= "string" or type(t.result) ~= "string" then return false end
    end
    for _, r in ipairs(m.rounds or {}) do if type(r) ~= "table" or type(r.scores) ~= "table" then return false end end
    return true
end
function S:Prune()
    while #B.db.matches > B.db.settings.historyLimit do table.remove(B.db.matches, 1) end
    local ids = {}
    for _, m in ipairs(B.db.matches) do if self:Valid(m) then ids[m.id] = true end end
    for _, p in pairs(B.db.profiles) do
        if type(p) == "table" and type(p.matches) == "table" then
            local refs = {}; for _, id in ipairs(p.matches) do if ids[id] then refs[#refs + 1] = id end end
            p.matches = refs
        end
    end
end
function S:NewSession(map, world)
    B.db.sequence = B.db.sequence + 1
    local now = B.Now()
    local s = { id = world .. ":" .. tostring(now) .. ":" .. B.db.sequence, mapId = map, world = world,
        startedAt = now, observations = {}, seenRoster = {}, localCharacter = GetUnitName("player"), localCharacterId = B.API:Call("GetCurrentCharacterId") }
    B.db.active = s
    return s
end
function S:HasMatch(id)
    if B.db.lastSavedId == id then return true end
    for _, old in ipairs(B.db.matches) do if type(old) == "table" and old.id == id then return true end end
    return false
end
function S:Commit(m)
    if not self:Valid(m) or #m.players == 0 or self:HasMatch(m.id) then return false end
    -- Stage touched profiles and totals first. A derivation error cannot partially increment history.
    local profiles = {}; for id, profile in pairs(B.db.profiles) do profiles[id] = profile end
    for _, player in ipairs(m.players) do
        local id = B.Identity(player, m.world)
        if id and not player.isLocal and profiles[id] == B.db.profiles[id] and type(profiles[id]) == "table" then profiles[id] = B.Copy(profiles[id]) end
    end
    local stats = B.Copy(B.db.stats)
    local staged = B.Copy(m)
    local liveSession
    local ok, err = pcall(function()
        B.Players:Record(staged, profiles)
        if B.LiveSession then liveSession = B.LiveSession:StageMatch(m) end
        stats.total = (stats.total or 0) + 1
        local outcome = m.outcome or "Unresolved"
        stats[outcome] = (stats[outcome] or 0) + 1
        stats.bests = stats.bests or {}
        for _, p in ipairs(m.players) do
            if p.isLocal and not m.localIdentityAmbiguous then
                for _, key in ipairs(B.metrics) do
                    if type(p[key]) == "number" and (not stats.bests[key] or p[key] > stats.bests[key].value) then
                        stats.bests[key] = { value = p[key], matchId = m.id, timestamp = m.finishedAt }
                    end
                end
            end
        end
    end)
    if not ok then B.Debug("Save aborted without changing history: " .. tostring(err)); return false end
    m.players, m.profileLimitReached = staged.players, staged.profileLimitReached
    B.db.profiles, B.db.stats = profiles, stats
    B.db.matches[#B.db.matches + 1] = m
    B.db.lastSavedId = m.id
    if liveSession then B.LiveSession:PublishMatch(liveSession) end
    self:Prune()
    if liveSession then B.LiveSession:RefreshAfterMatch() end
    return true
end
function S:Reset()
    B.db.matches, B.db.profiles, B.db.stats = {}, {}, {}
    -- Preserve active/lastSavedId so resetting at the final scoreboard cannot recapture it.
    B.Say("Recorded history and player aggregates cleared. Settings retained.")
end
