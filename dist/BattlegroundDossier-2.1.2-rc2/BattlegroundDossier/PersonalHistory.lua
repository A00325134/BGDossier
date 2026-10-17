-- Retained personal snapshots, never inferred builds or reconstructed lifetime totals.
local B, V = BattlegroundDossier, BattlegroundDossier.ViewData
B.Personal = { roles = { "HEALER", "TANK", "DPS" }, ranges = { 10, 25, 50, 0 } }
local P = B.Personal
function P.ValidRole(role) return role == "HEALER" or role == "TANK" or role == "DPS" end
function P.Number(value) return type(value) == "number" and value == value and value >= 0 and value < math.huge end
function P.Player(m)
    if m.localIdentityAmbiguous then return nil end
    local found
    for _, player in ipairs(m.players or {}) do
        if player.isLocal then if found then return nil end; found = player end
    end
    if found then return found end
    -- Legacy snapshots may lack isLocal. Match only the explicitly saved local
    -- character, uniquely; an account alone cannot distinguish its characters.
    local name = B.Normalize(m.localCharacter)
    if not name then return nil end
    for _, player in ipairs(m.players or {}) do
        if B.Normalize(player.character) == name then if found then return nil end; found = player end
    end
    return found
end
function P.Owner(m)
    local player = P.Player(m)
    local rawName = B.Normalize(m.localCharacter) and m.localCharacter or player and player.character
    local name, world = B.Normalize(rawName), m.world or "unknown"
    local id = m.localCharacterId
    if (type(id) == "string" and id ~= "") or type(id) == "number" then
        return world .. ":id:" .. tostring(id), rawName, world, name
    end
    if name then return world .. ":name:" .. name, rawName, world, name end
end
function P.Current()
    local m = { localCharacterId = B.API:Call("GetCurrentCharacterId"), localCharacter = GetUnitName("player"), world = GetWorldName() }
    return P.Owner(m)
end
function P.Index()
    local current, raw, world, name = P.Current()
    local aliases, characters = {}, {}
    local function observe(key, character, server, normalized, stable)
        if not key then return end
        if not characters[key] then characters[key] = { key = key, name = B.CharacterName(character), world = server } end
        if stable and normalized then
            local alias = server .. ":name:" .. normalized
            if aliases[alias] == nil then aliases[alias] = key
            elseif aliases[alias] ~= key then aliases[alias] = false end
        end
    end
    observe(current, raw, world, name, current and current:find(":id:", 1, true))
    for _, m in ipairs(B.db.matches) do
        if B.Storage:Valid(m) then
            local key, character, server, normalized = P.Owner(m)
            observe(key, character, server, normalized, m.localCharacterId ~= nil)
        end
    end
    local resolved = {}
    for key, character in pairs(characters) do
        local target = aliases[key] or key
        if not resolved[target] then resolved[target] = characters[target] or character end
    end
    local options = {}
    for key, character in pairs(resolved) do
        options[#options + 1] = { value = key, label = character.name .. " / " .. character.world .. (key == current and " (current)" or ""), name = character.name }
    end
    table.sort(options, function(a, b)
        if (a.value == current) ~= (b.value == current) then return a.value == current end
        return a.label == b.label and a.value < b.value or a.label < b.label
    end)
    return options, aliases, current
end
function P.Preferences(key)
    if not key then return nil end
    local root = B.db.settings.personalHistory
    if type(root) ~= "table" then root = { version = 1, characters = {} }; B.db.settings.personalHistory = root end
    if root.version ~= nil and root.version ~= 1 then return nil end
    root.version = 1
    if type(root.characters) ~= "table" then root.characters = {} end
    local prefs = root.characters[key]
    if type(prefs) ~= "table" then
        prefs = {}
        if B.Count(root.characters) < 128 then root.characters[key] = prefs end
    end
    if not P.ValidRole(prefs.role) then prefs.role = "HEALER" end
    if prefs.range ~= 10 and prefs.range ~= 25 and prefs.range ~= 50 and prefs.range ~= 0 then prefs.range = 25 end
    return prefs
end
function P.Rows(character, limit, aliases)
    local rows, seen = {}, {}
    for i = #B.db.matches, 1, -1 do
        local m = B.db.matches[i]
        if B.Storage:Valid(m) and not seen[m.id] then
            seen[m.id] = true
            local owner = P.Owner(m)
            owner = aliases and aliases[owner] or owner
            if owner == character then
                local p = P.Player(m) or {}
                local row = { id = m.id, match = m, player = P.Player(m), finishedAt = P.Number(m.finishedAt) and m.finishedAt or nil,
                    outcome = m.outcome or "Unresolved", modeName = m.modeName or "Unknown mode", format = V.Format(m),
                    role = P.ValidRole(m.personalRole) and m.personalRole or "Unclassified" }
                for _, key in ipairs({ "kills", "deaths", "assists", "damage", "healing", "score", "objective", "damageTaken", "shieldsGranted" }) do
                    if P.Number(p[key]) then row[key] = p[key] end
                end
                rows[#rows + 1] = row
            end
        end
    end
    table.sort(rows, function(a, b)
        local x, y = a.finishedAt or 0, b.finishedAt or 0
        return x == y and a.id > b.id or x > y
    end)
    if limit and limit > 0 then while #rows > limit do table.remove(rows) end end
    return rows
end
local function collect(bucket, key, value, row)
    if not P.Number(value) then return end
    local metric = bucket[key]
    if not metric then metric = { total = 0, count = 0 }; bucket[key] = metric end
    metric.total, metric.count = metric.total + value, metric.count + 1
    metric.average = metric.total / metric.count
    if not metric.best or value > metric.best.value then metric.best = { value = value, row = row } end
end
function P.Summary(rows)
    local s = { total = #rows, Win = 0, Loss = 0, Draw = 0, Unresolved = 0, metrics = {}, objectives = {}, modes = {},
        outcomes = { Win = {}, Loss = {} }, trend = { recent = {}, previous = {} }, sequence = {} }
    for i, row in ipairs(rows) do
        local outcome = ({ Win = true, Loss = true, Draw = true })[row.outcome] and row.outcome or "Unresolved"
        s[outcome] = s[outcome] + 1
        local modeKey = tostring(row.match.mode or row.modeName) .. ":" .. row.format
        local mode = s.modes[modeKey]
        if not mode then mode = { label = row.modeName .. " / " .. row.format, total = 0, Win = 0, Loss = 0, Draw = 0, Unresolved = 0 }; s.modes[modeKey] = mode end
        mode.total, mode[outcome] = mode.total + 1, mode[outcome] + 1
        if i <= 10 then s.sequence[#s.sequence + 1] = ({ Win = "W", Loss = "L", Draw = "D" })[outcome] or "?" end
        for _, key in ipairs({ "kills", "deaths", "assists", "damage", "healing", "score", "damageTaken", "shieldsGranted" }) do
            collect(s.metrics, key, row[key], row)
            if s.outcomes[outcome] then collect(s.outcomes[outcome], key, row[key], row) end
            if i <= 20 then collect(s.trend[i <= 10 and "recent" or "previous"], key, row[key], row) end
        end
        -- Different objective units are never summed together or substituted
        -- with personal score. Legacy values with no label stay in a separate group.
        if P.Number(row.objective) then
            local label = type(row.match.objectiveLabel) == "string" and row.match.objectiveLabel ~= "" and row.match.objectiveLabel or ("Unspecified objective / " .. row.modeName)
            collect(s.objectives, label, row.objective, row)
        end
    end
    local resolved = s.Win + s.Loss + s.Draw
    s.winRate = resolved > 0 and s.Win / resolved * 100 or nil
    local first = rows[1] and rows[1].outcome
    if first == "Win" or first == "Loss" then
        s.streak = { outcome = first, count = 0 }
        for _, row in ipairs(rows) do if row.outcome ~= first then break end; s.streak.count = s.streak.count + 1 end
    end
    -- Pairwise totals: a match lacking either K or D cannot bias the aggregate ratio.
    local kills, deaths, count = 0, 0, 0
    for _, row in ipairs(rows) do
        if P.Number(row.kills) and P.Number(row.deaths) then kills, deaths, count = kills + row.kills, deaths + row.deaths, count + 1 end
    end
    s.kd, s.kdSamples = deaths > 0 and kills / deaths or nil, count
    return s
end
