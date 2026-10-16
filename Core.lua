BattlegroundDossier = { name = "BattlegroundDossier", version = "1.2.0", schema = 1 }
local B = BattlegroundDossier
B.MAX_ABILITIES = 80
B.MAX_CHARACTERS = 24
B.MAX_REFS = 200
B.metrics = { "kills", "deaths", "assists", "damage", "healing", "score", "objective" }
B.defaults = { historyLimit = 200, profileLimit = 10000, autoOpen = true, notifications = true,
    observeCombat = true, frequentThreshold = 5, scale = 0.85, debug = false }

function B.Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = B.Copy(v) end
    return out
end
function B.Count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end
function B.Now() return GetTimeStamp() end
function B.Normalize(name)
    if type(name) ~= "string" then return nil end
    -- Only ESO grammatical suffixes and presentation markup are removed. No fuzzy matching.
    name = name:gsub("|c%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%^%a+", "")
    name = name:match("^%s*(.-)%s*$")
    if name == "" then return nil end
    return zo_strlower and zo_strlower(name) or string.lower(name)
end
function B.Identity(p, world)
    if p.identityConfidence == "unresolved" then return nil, "unresolved" end
    local account = B.Normalize(p.account)
    local character = B.Normalize(p.character)
    if account and account:sub(1, 1) == "@" then return (world or "unknown") .. ":a:" .. account, "account" end
    if character then return (world or "unknown") .. ":c:" .. character, "character" end
end
function B.ParticipantKey(p, world)
    return p.participantId or B.Identity(p, world)
end
function B.Say(text) if d then d("|cC5A56ABattleground Dossier|r: " .. tostring(text)) end end
function B.Debug(text) if B.db and B.db.settings.debug then B.Say(text) end end
function B.Value(n) if type(n) ~= "number" then return "—" end; return tostring(n) end
function B.Ratio(p)
    if type(p.kills) == "number" and type(p.deaths) == "number" and p.deaths > 0 then return p.kills / p.deaths end
end
function B.Difference(a, b, key)
    local x, y = a and a[key], b and b[key]
    if type(x) == "number" and type(y) == "number" then return x - y end
end
function B.Date(t)
    if type(t) ~= "number" then return "Unknown date" end
    return GetDateStringFromTimestamp and GetDateStringFromTimestamp(t) or tostring(t)
end
function B.DateTime(t)
    if type(t) ~= "number" then return "Unknown date" end
    local hour, minute = math.floor(t / 3600) % 24, math.floor(t / 60) % 60
    return B.Date(t) .. string.format(" • %02d:%02d UTC", hour, minute)
end
function B.Result(value)
    if value == nil then return "Unresolved" end
    if value == BATTLEGROUND_RESULT_WIN then return "Win" end
    if value == BATTLEGROUND_RESULT_LOSS then return "Loss" end
    if value == BATTLEGROUND_RESULT_TIE then return "Draw" end
    return "Unresolved"
end
function B.TeamRelation(match, p)
    if p.teamUncertain or match.localTeamUncertain or not match.localTeam or not p.team or not match.teams
        or not match.teams[match.localTeam] or not match.teams[p.team] then return "unknown" end
    return p.team == match.localTeam and "ally" or "opponent"
end
-- A team result is a result against another team, never an individual duel result.
function B.Against(match, p)
    if B.TeamRelation(match, p) ~= "opponent" then return "Unresolved" end
    local mine, theirs = match.teams[match.localTeam], match.teams[p.team]
    if not mine or not theirs then return "Unresolved" end
    if mine.result == "Win" and theirs.result == "Loss" then return "Win" end
    if mine.result == "Loss" and theirs.result == "Win" then return "Loss" end
    if mine.result == "Draw" and theirs.result == "Draw" then return "Draw" end
    -- Two losing teams in a three-team match have no verified head-to-head result.
    return "Unresolved"
end
function B.Compare(a, b)
    local rows = {}
    for _, key in ipairs(B.metrics) do rows[#rows + 1] = { key = key, a = a[key], b = b[key], difference = B.Difference(a, b, key) } end
    local ra, rb = B.Ratio(a), B.Ratio(b)
    rows[#rows + 1] = { key = "K/D", a = ra, b = rb, difference = ra and rb and ra - rb }
    return rows
end
