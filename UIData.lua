-- Presentation-only projections. None of these helpers mutate recorded matches/profiles.
local B = BattlegroundDossier
B.ViewData = {}
local V = B.ViewData
function V.Name(p)
    for _, key in ipairs({ "character", "account", "latestCharacter" }) do if B.Normalize(p[key]) then return p[key] end end
    return p.identityConfidence == "unresolved" and "Unresolved participant" or "Unknown player"
end
function V.MapName(m) return m.zoneName or m.map or "Unknown Battleground" end
function V.Account(p)
    local account = B.Normalize(p.account)
    return account and account:sub(1, 1) == "@" and p.account or "Account unavailable"
end
function V.ProfileName(p)
    local account = B.Normalize(p.account)
    if account and account:sub(1, 1) == "@" then return p.account end
    return B.Normalize(p.latestCharacter) and p.latestCharacter or "Unknown player"
end
function V.Class(p) return B.API:Call("GetClassName", GENDER_MALE, p.classId or 0) or "Unknown" end
function V.Precise(v)
    if type(v) ~= "number" then return "—" end
    local sign = v < 0 and "−" or ""
    local absolute = v % 1 ~= 0 and math.floor(math.abs(v) * 100 + 0.5) / 100 or math.abs(v)
    local digits = tostring(math.floor(absolute))
    local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    if v % 1 ~= 0 then grouped = grouped .. string.format("%.2f", absolute % 1):sub(2) end
    return sign .. grouped
end
function V.PlayedFormat(m)
    local counts, ids = {}, {}
    for id in pairs(m.teams or {}) do ids[#ids + 1] = id; counts[id] = 0 end
    table.sort(ids)
    local unknown = 0
    for _, p in ipairs(m.players or {}) do
        if not p.notInLatestScoreboard and (not m.hasRounds or not p.roundIndex or p.roundIndex == m.roundIndex) then
            if counts[p.team] then counts[p.team] = counts[p.team] + 1 else unknown = unknown + 1 end
        end
    end
    if #ids < 2 or unknown > 0 then return "Unresolved team sizes" end
    local sizes = {}; for _, id in ipairs(ids) do sizes[#sizes + 1] = tostring(counts[id]) end
    return table.concat(sizes, "v")
end
function V.FormatDescription(m)
    local queued, actual = V.Format(m), V.PlayedFormat(m)
    local label = m.competitive == true and "Competitive " or type(m.teamCapacity) == "number" and m.teamCapacity >= 6 and "Big Team Battle " or ""
    return label .. queued .. " • Final roster " .. actual
end
function V.Number(v, compact)
    if type(v) ~= "number" then return "—" end
    if compact then
        local absolute = math.abs(v)
        if absolute >= 1000000 then return string.format("%.1fM", v / 1000000) end
        if absolute >= 10000 then return string.format("%.1fK", v / 1000) end
    end
    return V.Precise(v)
end
function V.Format(m)
    local sizes = {}
    if type(m.teamCount) == "number" and m.teamCount >= 2 and m.teamCount <= 10 and m.teamCapacity then
        for _ = 1, m.teamCount do sizes[#sizes + 1] = tostring(m.teamCapacity) end
        return table.concat(sizes, "v")
    end
    return tostring(m.teamCount or "?") .. " teams"
end
function V.LocalPlayer(m)
    if m.localIdentityAmbiguous then return nil end
    for _, p in ipairs(m.players or {}) do if p.isLocal then return p end end
end
function V.Search(p, query)
    query = B.Normalize(query) or ""
    if query == "" then return true end
    for _, key in ipairs({ "character", "account", "latestCharacter" }) do
        if (B.Normalize(p[key]) or ""):find(query, 1, true) then return true end
    end
    for _, alias in pairs(p.characters or {}) do if (B.Normalize(alias) or ""):find(query, 1, true) then return true end end
    return false
end
function V.Sort(rows, key, descending)
    table.sort(rows, function(a, b)
        local x, y = a[key], b[key]
        if x == nil or y == nil then if x ~= y then return x ~= nil end
        elseif type(x) == type(y) and x ~= y then
            if type(x) == "string" then x, y = B.Normalize(x) or "", B.Normalize(y) or "" end
            if x ~= y then if descending then return x > y else return x < y end end
        end
        return tostring(a._key or a.id or a.account or a.character or "") < tostring(b._key or b.id or b.account or b.character or "")
    end)
    return rows
end
function V.History(filters, query)
    local rows = {}
    for i = #B.db.matches, 1, -1 do
        local m = B.db.matches[i]
        if B.Storage:Valid(m) then
            local accepted = (filters.result == "All results" or filters.result == m.outcome)
                and (filters.mode == "All modes" or filters.mode == (m.modeName or "Unknown mode"))
                and (filters.format == "All formats" or filters.format == V.Format(m)
                    or filters.format == "Competitive" and m.competitive == true
                    or filters.format == "Big Team Battles" and type(m.teamCapacity) == "number" and m.teamCapacity >= 6)
            local found = query == "" or query == nil
            if not found then for _, p in ipairs(m.players) do if V.Search(p, query) then found = true; break end end end
            if accepted and found then rows[#rows + 1] = m end
        end
    end
    return rows
end
function V.Category(raw)
    return ({ ["Class abilities"] = "Class", ["Weapon abilities"] = "Weapon", ["Guild / world abilities"] = "Guild / World",
        ["Guild abilities"] = "Guild", ["World abilities"] = "World", ["Other observed effects"] = "Other / Effect" })[raw] or "Other / Effect"
end
function V.Abilities(abilities, key, descending)
    local rows = {}
    for id, a in pairs(abilities or {}) do
        if type(a) == "table" then rows[#rows + 1] = { _key = tostring(id), id = id, name = a.name or "Unknown ability",
            category = V.Category(a.category), rawCategory = a.category, events = a.events, damage = a.damage,
            healing = a.healing, firstSeen = a.firstSeen, lastSeen = a.lastSeen } end
    end
    return V.Sort(rows, key or "damage", descending ~= false)
end
function V.PreviousAbilities(m, p)
    local result = {}
    local identity = B.Identity(p, m.world)
    if not identity then return result end
    for _, old in ipairs(B.db.matches) do
        if B.Storage:Valid(old) and old.id ~= m.id and (old.finishedAt or 0) <= (m.finishedAt or 0) then
            for _, peer in ipairs(old.players) do
                if B.Identity(peer, old.world) == identity then
                    for id, a in pairs(peer.abilities or {}) do
                        if type(a) == "table" then
                            if not result[id] then result[id] = B.Copy(a)
                            else
                                local total = result[id]
                                for _, field in ipairs({ "events", "damage", "healing" }) do
                                    if type(a[field]) == "number" then total[field] = (total[field] or 0) + a[field] end
                                end
                                if a.firstSeen then total.firstSeen = math.min(total.firstSeen or a.firstSeen, a.firstSeen) end
                                if a.lastSeen then total.lastSeen = math.max(total.lastSeen or a.lastSeen, a.lastSeen) end
                            end
                        end
                    end
                end
            end
        end
    end
    return result
end
function V.TeamSummary(m, p, key)
    if B.TeamRelation(m, p) == "unknown" then return nil, nil end
    local sum, count = 0, 0
    for _, peer in ipairs(m.players or {}) do
        if not peer.teamUncertain and peer.team == p.team and type(peer[key]) == "number" then sum, count = sum + peer[key], count + 1 end
    end
    return count > 0 and sum / count or nil, type(p[key]) == "number" and sum > 0 and p[key] / sum * 100 or nil
end
function V.Trends()
    local groups = { { count = 0, sums = {}, counts = {} }, { count = 0, sums = {}, counts = {} } }
    local n = 0
    for i = #B.db.matches, 1, -1 do
        local m = B.db.matches[i]
        if B.Storage:Valid(m) then
            n = n + 1; if n > 20 then break end
            local g, p = groups[n <= 10 and 1 or 2], V.LocalPlayer(m)
            g.count = g.count + 1
            for _, key in ipairs(B.metrics) do
                if p and type(p[key]) == "number" then g.sums[key] = (g.sums[key] or 0) + p[key]; g.counts[key] = (g.counts[key] or 0) + 1 end
            end
        end
    end
    return groups
end
