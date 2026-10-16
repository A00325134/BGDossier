local B = BattlegroundDossier
B.Players = {}
local P = B.Players
function P:Get(player, world)
    local id = B.Identity(player, world)
    local p = id and B.db.profiles[id]
    if type(p) == "table" then return p end
end
function P:Classification(p)
    if not p or (p.encounters or 0) <= 1 then return "First Encounter" end
    local threshold = B.db.settings.frequentThreshold
    if (p.opponents or 0) >= threshold then return "Frequent Opponent" end
    if (p.allies or 0) >= threshold then return "Frequent Teammate" end
    return "Familiar Player"
end
function P:Record(m, profiles)
    profiles = profiles or B.db.profiles
    local processed = {}
    for _, player in ipairs(m.players) do
        local id, confidence = B.Identity(player, m.world)
        if id and not player.isLocal and not processed[id] then
            processed[id] = true
            local p = profiles[id]
            if type(p) ~= "table" then p = nil end
            player.previousEncounters = p and p.encounters or 0
            if not p and B.Count(profiles) < B.db.settings.profileLimit then
                p = { id = id, confidence = confidence, account = confidence == "account" and player.account or nil, characters = {}, classes = {},
                    encounters = 0, allies = 0, opponents = 0, unknown = 0, wins = 0, losses = 0,
                    draws = 0, unresolved = 0, firstSeen = m.finishedAt, matches = {}, abilities = {}, bests = {} }
                profiles[id] = p
            end
            if p then
                local when = tonumber(m.finishedAt) or B.Now()
                p.confidence = confidence
                if confidence == "account" then p.account = player.account end
                p.encounters = (p.encounters or 0) + 1
                if not tonumber(p.lastSeen) or when >= tonumber(p.lastSeen) then p.latestCharacter = player.character end
                p.lastSeen = math.max(tonumber(p.lastSeen) or when, when)
                p.firstSeen = math.min(tonumber(p.firstSeen) or when, when)
                local rel = B.TeamRelation(m, player)
                local key = rel == "ally" and "allies" or rel == "opponent" and "opponents" or "unknown"
                p[key] = (p[key] or 0) + 1
                if rel == "opponent" then
                    local outcome = B.Against(m, player)
                    local field = ({ Win = "wins", Loss = "losses", Draw = "draws", Unresolved = "unresolved" })[outcome]
                    p[field] = (p[field] or 0) + 1
                end
                local character = B.Normalize(player.character)
                if character and (p.characters[character] or B.Count(p.characters) < B.MAX_CHARACTERS) then
                    p.characters[character] = player.character
                end
                if player.classId then p.classes[player.classId] = true end
                p.matches[#p.matches + 1] = m.id
                while #p.matches > B.MAX_REFS do table.remove(p.matches, 1) end
                for _, metric in ipairs(B.metrics) do
                    local v = player[metric]
                    if type(v) == "number" and (not p.bests[metric] or v > p.bests[metric].value) then
                        p.bests[metric] = { value = v, matchId = m.id, timestamp = m.finishedAt }
                    end
                end
                for abilityId, ability in pairs(player.abilities or {}) do
                    local old = p.abilities[abilityId]
                    if old then
                        old.events = (old.events or 0) + (ability.events or 0)
                        if ability.lastSeen then old.lastSeen = math.max(old.lastSeen or ability.lastSeen, ability.lastSeen) end
                        if ability.firstSeen then old.firstSeen = math.min(old.firstSeen or ability.firstSeen, ability.firstSeen) end
                        if type(ability.damage) == "number" then old.damage = (old.damage or 0) + ability.damage end
                        if type(ability.healing) == "number" then old.healing = (old.healing or 0) + ability.healing end
                    elseif B.Count(p.abilities) < B.MAX_ABILITIES then p.abilities[abilityId] = B.Copy(ability) end
                end
            else m.profileLimitReached = true end
        end
    end
end
