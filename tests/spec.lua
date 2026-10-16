local B = BattlegroundDossier
local passed = 0
local function test(label, fn)
    local ok, err = pcall(fn)
    if not ok then error(label .. ": " .. tostring(err)) end
    passed = passed + 1; print("PASS " .. label)
end
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function player(character, account, team, isLocal) return { character = character, account = account, team = team, isLocal = isLocal } end
local function reset()
    B.Storage:Initialize({})
    B.Combat:Initialize(); B.Match:Stop(); B.Match.session = nil
    engine.active, engine.map, engine.round, engine.multi, engine.state = true, 42, 1, false, BATTLEGROUND_STATE_RUNNING
    engine.missingStats, engine.missingDamage = nil, nil
    engine.teams = { 1, 2 }
    engine.results = { [1] = BATTLEGROUND_RESULT_WIN, [2] = BATTLEGROUND_RESULT_LOSS }
    engine.scores = { [1] = 500, [2] = 300 }
    engine.roster = { { player("Local^Mx", "@local", 1, true), player("Enemy^Fx", "@enemy", 2, false) } }
    clock = 0; timestamp = 1800000000
end
local function snapshot(id)
    B.Match:EnsureSession()
    engine.state = BATTLEGROUND_STATE_FINISHED
    B.Match.session.finishedAt = timestamp
    local m, reason = B.API:Snapshot(B.Match.session); assert(m, reason)
    if id then m.id = id end
    return m
end
local function advance(ms) clock = clock + ms; if B.Match.pending then B.Match:TryCapture() end end
test("empty SavedVariables initialize safely", function() reset(); eq(B.db.settings.historyLimit, 200); eq(#B.db.matches, 0) end)
test("future schema protected", function() eq(B.Storage:Initialize({ schema = 99 }), false) end)
test("missing fields recover without deleting old history", function()
    local db = { matches = { { id = "legacy", players = {}, teams = {} } }, settings = { scale = "bad" } }
    assert(B.Storage:Initialize(db)); eq(#db.matches, 1); eq(db.settings.scale, 0.85); eq(db.matches[1].outcome, "Unresolved")
end)
test("account identity stable across characters and scoped to world", function()
    local a = B.Identity(player("One", "@ACCOUNT"), "NA")
    eq(a, B.Identity(player("Two", "@account"), "NA")); assert(a ~= B.Identity(player("One", "@account"), "EU"))
end)
test("character fallback never merges similar names or an account", function()
    local a, confidence = B.Identity(player("Enemy^Fx"), "NA"); eq(confidence, "character")
    eq(a, B.Identity(player("Enemy"), "NA")); assert(a ~= B.Identity(player("Enemy!"), "NA"))
    assert(a ~= B.Identity(player("Enemy", "@enemy"), "NA")); eq(B.Identity({}), nil)
end)
test("authoritative win/loss/tie and invalid results", function()
    eq(B.Result(BATTLEGROUND_RESULT_WIN), "Win"); eq(B.Result(BATTLEGROUND_RESULT_LOSS), "Loss")
    eq(B.Result(BATTLEGROUND_RESULT_TIE), "Draw"); eq(B.Result(nil), "Unresolved")
end)
test("final scoreboard snapshot and missing damage", function()
    reset(); engine.missingDamage = true
    local m = snapshot(); eq(m.outcome, "Win"); eq(m.teamCount, 2); eq(m.participantCount, 2)
    eq(m.players[1].damage, nil); eq(m.placement, 1)
end)
test("empty scoreboard refused; missing statistics preserved as partial", function()
    reset(); B.Match:EnsureSession(); engine.state = BATTLEGROUND_STATE_FINISHED
    engine.missingStats = true; local m = B.API:Snapshot(B.Match.session); eq(#m.players, 2); assert(m.snapshotIncomplete); eq(m.players[1].damage, nil)
    engine.roster = { {} }; eq(B.API:Snapshot(B.Match.session), nil)
end)
test("absent local player and pending results preserve partial roster", function()
    reset(); B.Match:EnsureSession(); engine.state = BATTLEGROUND_STATE_FINISHED
    engine.results[2] = BATTLEGROUND_RESULT_INVALID; assert(B.API:Snapshot(B.Match.session).snapshotIncomplete)
    engine.results[2] = BATTLEGROUND_RESULT_LOSS; engine.roster[1][1].isLocal = false
    local m = B.API:Snapshot(B.Match.session); eq(#m.players, 2); eq(m.outcome, "Unresolved"); assert(m.snapshotIncomplete)
end)
test("deduplication changes aggregates exactly once", function()
    reset(); local m = snapshot(); assert(B.Storage:Commit(m)); eq(B.Storage:Commit(m), false)
    eq(#B.db.matches, 1); eq(B.db.stats.total, 1)
    local p = B.Players:Get(player("Enemy", "@enemy"), m.world); eq(p.encounters, 1); eq(p.wins, 1)
end)
test("encounter aggregation distinguishes allies and opponents", function()
    reset(); local m = snapshot("first"); B.Storage:Commit(m)
    local nextMatch = B.Copy(m); nextMatch.id = "second"
    for _, p in ipairs(nextMatch.players) do if not p.isLocal then p.team = 1 end end
    B.Storage:Commit(nextMatch)
    local profile = B.Players:Get(player("Enemy", "@enemy"), m.world)
    eq(profile.encounters, 2); eq(profile.opponents, 1); eq(profile.allies, 1); eq(profile.wins, 1)
end)
test("three-team losses do not become invented head-to-head losses", function()
    reset(); engine.teams = { 1, 2, 3 }; engine.results[1] = BATTLEGROUND_RESULT_LOSS
    engine.results[2], engine.results[3] = BATTLEGROUND_RESULT_LOSS, BATTLEGROUND_RESULT_WIN
    local m = snapshot(); eq(m.teamCount, 3); eq(B.Against(m, { team = 2 }), "Unresolved"); eq(B.Against(m, { team = 3 }), "Loss")
end)
test("true tie preserved", function()
    reset(); engine.results[1], engine.results[2] = BATTLEGROUND_RESULT_TIE, BATTLEGROUND_RESULT_TIE
    local m = snapshot(); eq(m.outcome, "Draw"); eq(B.Against(m, { team = 2 }), "Draw")
end)
test("pruning details retains lifetime totals and valid references", function()
    reset(); B.db.settings.historyLimit = 10
    local base = snapshot()
    for i = 1, 15 do local m = B.Copy(base); m.id = "match" .. i; assert(B.Storage:Commit(m)) end
    eq(#B.db.matches, 10); eq(B.db.stats.total, 15)
    local p = B.Players:Get(player("Enemy", "@enemy"), base.world); eq(p.encounters, 15); eq(#p.matches, 10)
end)
test("comparison and zero-death K/D preserve unavailable", function()
    eq(B.Difference({ damage = 100 }, { damage = 60 }, "damage"), 40)
    eq(B.Difference({ damage = 100 }, {}, "damage"), nil)
    eq(B.Ratio({ kills = 5, deaths = 0 }), nil); eq(B.Ratio({ kills = 5, deaths = 2 }), 2.5)
    eq(#B.Compare({}, {}), 8)
end)
test("combat aggregation records events, not casts", function()
    reset(); B.Match:EnsureSession(); B.Match:Roster()
    for i = 1, 3 do B.Combat:OnEvent(ACTION_RESULT_DOT_TICK, false, "Flame", 0, 0, "Enemy", COMBAT_UNIT_TYPE_OTHER, "Local", COMBAT_UNIT_TYPE_PLAYER, 100, 0, 0, false, 12, 13, 900, 0) end
    local id = B.Identity(player("Enemy", "@enemy"), B.Match.session.world)
    eq(B.Match.session.observations[id][900].events, 3); eq(B.Match.session.observations[id][900].damage, 300)
end)
test("ambiguous, pet, unknown and error combat sources discarded", function()
    reset(); B.Match:EnsureSession()
    engine.roster[1][3] = player("Enemy", "@other", 2)
    B.Match:Roster(); eq(B.Combat.byName["enemy"], nil)
    local function event(source, sourceType, isError)
        B.Combat:OnEvent(ACTION_RESULT_DAMAGE, isError, "Flame", 0, 0, source, sourceType, "Local", COMBAT_UNIT_TYPE_PLAYER, 50, 0, 0, false, 1, 2, 900, 0)
    end
    event("Enemy", COMBAT_UNIT_TYPE_OTHER, false); event("@enemy", COMBAT_UNIT_TYPE_PLAYER_PET, false)
    event("Unknown", COMBAT_UNIT_TYPE_OTHER, false); event("@enemy", COMBAT_UNIT_TYPE_OTHER, true)
    eq(B.Count(B.Match.session.observations), 0)
end)
test("ability storage is bounded", function()
    reset(); B.Match:EnsureSession(); B.Match:Roster()
    local id = B.Identity(player("Enemy", "@enemy"), B.Match.session.world)
    for i = 1, 100 do B.Combat:Observe(B.Match.session, id, i, "Ability", "damage", 1) end
    eq(B.Count(B.Match.session.observations[id]), B.MAX_ABILITIES)
end)
test("round boundaries never save a match", function()
    reset(); engine.multi = true; B.Match:State(BATTLEGROUND_STATE_RUNNING, BATTLEGROUND_STATE_POSTROUND)
    eq(#B.db.matches, 0); eq(B.Match.pending, nil)
end)
test("multi-round union retains earlier leavers and uses cumulative API", function()
    reset(); engine.multi, engine.round, engine.cumulativeCalls = true, 2, 0
    engine.roster[2] = { engine.roster[1][1] }
    local m = snapshot(); eq(#m.players, 2); assert(engine.cumulativeCalls > 0)
    for _, p in ipairs(m.players) do eq(p.objective, nil) end
end)
test("delayed scoreboard stabilizes before a single save", function()
    reset(); B.db.settings.autoOpen = false; B.Match:EnsureSession()
    local roster = engine.roster; engine.roster = { {} }; engine.state = BATTLEGROUND_STATE_FINISHED; B.Match:Finish()
    advance(2000); eq(#B.db.matches, 0); engine.roster = roster
    advance(1000); advance(1000); eq(#B.db.matches, 0); advance(1000); advance(1000)
    eq(#B.db.matches, 0); advance(24000)
    eq(#B.db.matches, 1); B.Match:Finish(); advance(10000); eq(#B.db.matches, 1)
end)
test("scoreboard changes reset stability window", function()
    reset(); B.db.settings.autoOpen = false; B.Match:EnsureSession(); engine.state = BATTLEGROUND_STATE_FINISHED; B.Match:Finish()
    advance(1000); engine.roster[1][2].value = 25; advance(1000); advance(1000); eq(#B.db.matches, 0)
    advance(2000); eq(#B.db.matches, 0); advance(25000); eq(#B.db.matches, 1)
end)
test("bounded retries stop without saving incomplete data", function()
    reset(); B.Match:EnsureSession(); engine.roster = { {} }; engine.state = BATTLEGROUND_STATE_FINISHED; B.Match:Finish()
    advance(30000); eq(B.Match.pending, nil); eq(#B.db.matches, 0)
end)
test("reload final scoreboard reuses persistent session and deduplicates", function()
    reset(); local m = snapshot(); B.Storage:Commit(m); local id = B.Match.session.id
    B.Match.session = nil; B.Match:EnsureSession(); eq(B.Match.session.id, id)
    B.db.settings.autoOpen = false; B.Match:Finish(); advance(1000); advance(1000); advance(1000)
    eq(#B.db.matches, 1); eq(B.db.stats.total, 1)
end)
test("early exit discards unfinished session", function()
    reset(); B.Match:EnsureSession(); engine.active = false; B.Match:Activated()
    eq(B.db.active, nil); eq(#B.db.matches, 0)
end)
test("new match on same map receives a new identity", function()
    reset(); B.Match:EnsureSession(); local id = B.Match.session.id
    B.Match:State(BATTLEGROUND_STATE_FINISHED, BATTLEGROUND_STATE_STARTING); assert(B.Match.session.id ~= id)
end)
test("profile cap does not delete existing lifetime data", function()
    reset(); local m = snapshot(); B.db.settings.profileLimit = 0; B.Storage:Commit(m)
    eq(B.Count(B.db.profiles), 0); eq(#B.db.matches, 1); assert(m.profileLimitReached)
end)
test("native UI construction and all views render against mocked controls", function()
    reset(); local m = snapshot(); B.Storage:Commit(m); B.UI:Initialize()
    B.UI:Open("MATCHES"); B.UI:OpenMatch(m)
    B.UI.expanded = m.players[1]; B.UI:Render()
    B.UI.compareA, B.UI.compareB = m.players[1], m.players[2]; B.UI:Render()
    B.UI:Open("PLAYERS"); for _, p in pairs(B.db.profiles) do B.UI.profile = p; break end; B.UI:Render()
    B.UI:Open("STATISTICS"); B.UI:Open("SETTINGS"); B.UI:CycleFilter()
end)
test("slash commands and reset confirmation", function()
    reset(); local m = snapshot(); B.Storage:Commit(m); B.InitializeCommands()
    SLASH_COMMANDS["/bgd"]("reset confirm"); eq(#B.db.matches, 1)
    SLASH_COMMANDS["/bgd"]("debug on"); eq(B.db.settings.debug, true)
    SLASH_COMMANDS["/bgd"]("reset"); clock = clock + 31000; SLASH_COMMANDS["/bgd"]("reset confirm"); eq(#B.db.matches, 1)
    SLASH_COMMANDS["/bgd"]("reset"); SLASH_COMMANDS["/bgd"]("reset confirm"); eq(#B.db.matches, 0)
end)
test("entry point registers addon initialization", function()
    local callback = EVENT_MANAGER.events[B.name .. ":" .. EVENT_ADD_ON_LOADED]; assert(callback)
    callback(EVENT_ADD_ON_LOADED, B.name); assert(SLASH_COMMANDS["/bgd"])
end)
test("18-player dynamic scoreboard renders every participant", function()
    reset(); engine.teams = { 1, 2, 3 }; engine.results[3], engine.scores[3] = BATTLEGROUND_RESULT_LOSS, 200
    engine.roster[1] = {}
    for i = 1, 18 do engine.roster[1][i] = player("Player" .. i, "@account" .. i, (i - 1) % 3 + 1, i == 1) end
    local m = snapshot(); eq(m.participantCount, 18); eq(m.teamCount, 3)
    B.Storage:Commit(m); B.UI:OpenMatch(m)
    B.UI.teamFilter = "My team"; B.UI:Render(); B.UI.teamFilter = "All players"
end)
test("colliding identities retain exposed slots without silent merging", function()
    reset(); B.Match:EnsureSession(); engine.state = BATTLEGROUND_STATE_FINISHED
    engine.roster[1][3] = B.Copy(engine.roster[1][2]); local m = B.API:Snapshot(B.Match.session)
    eq(#m.players, 3); eq(m.diagnostics.unresolvedIdentities, 2); assert(m.snapshotIncomplete)
end)
test("unexpected saved fields recover and malformed records remain preserved", function()
    local db = { stats = { total = "broken", bests = { damage = true } }, profiles = {
        bad = false, known = { characters = { bad = true }, abilities = { [1] = false, [2] = {} }, bests = { score = false } } },
        matches = { { id = "malformed", players = { false }, teams = {} } } }
    assert(B.Storage:Initialize(db)); eq(db.stats.total, 0); eq(#db.matches, 1); eq(B.Storage:Valid(db.matches[1]), false)
    B.UI:Open("PLAYERS"); B.UI:Open("STATISTICS")
    B.Match:EnsureSession(); B.db.active.startedAt = "broken"; B.Match:EnsureSession(); assert(type(B.Match.session.startedAt) == "number")
end)
print(tostring(passed) .. " tests passed (mock ESO; no live-game validation).")
