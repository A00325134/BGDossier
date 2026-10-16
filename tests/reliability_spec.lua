local B, V = BattlegroundDossier, BattlegroundDossier.ViewData
local passed = 0
local function test(label, fn)
    local ok, err = pcall(fn); assert(ok, label .. ": " .. tostring(err)); passed = passed + 1; print("PASS reliability " .. label)
end
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function setup(sizes, capacity)
    B.Match:Stop(); B.Match.session = nil; B.Storage:Initialize({}); B.db.settings.autoOpen = false
    clock, timestamp = 0, 1800000000
    engine.active, engine.state, engine.map, engine.round, engine.multi, engine.capacity = true, BATTLEGROUND_STATE_RUNNING, 42, 1, false, capacity or 4
    engine.missingStats, engine.missingDamage, engine.zoneName = nil, nil, nil
    engine.teams, engine.results, engine.scores, engine.roster = {}, {}, {}, { {} }
    local index = 0
    for team, size in ipairs(sizes or { 4, 4 }) do
        engine.teams[team], engine.results[team], engine.scores[team] = team, team == 1 and BATTLEGROUND_RESULT_WIN or BATTLEGROUND_RESULT_LOSS, 500 - team * 50
        for _ = 1, size do
            index = index + 1
            engine.roster[1][index] = { character = "Player " .. index, account = "@player" .. index, team = team, isLocal = index == 1, value = 10 }
        end
    end
    B.Match:EnsureSession(); B.Match:Roster()
end
local function finish()
    engine.state = BATTLEGROUND_STATE_FINISHED; B.Match:Finish()
end
local function advance(ms)
    clock, timestamp = clock + ms, timestamp + math.floor(ms / 1000)
    if B.Match.pending then B.Match:TryCapture() end
end
local function saved() return B.db.matches[#B.db.matches] end
for _, scenario in ipairs({ { "4v4", { 4, 4 }, 4, 8 }, { "understaffed 3v3 in 4v4", { 3, 3 }, 4, 6 },
    { "6v6v6", { 6, 6, 6 }, 6, 18 }, { "9v9", { 9, 9 }, 9, 18 }, { "uneven 3v2", { 3, 2 }, 4, 5 } }) do
    test(scenario[1] .. " preserves every final roster participant", function()
        setup(scenario[2], scenario[3]); finish(); advance(30000)
        eq(#B.db.matches, 1); eq(#saved().players, scenario[4]); eq(saved().diagnostics.scoreboardEntries, scenario[4])
        eq(saved().diagnostics.finalRoundCaptured, scenario[4]); eq(B.Count(B.db.profiles), scenario[4] - 1)
        local seen = {}; for _, p in ipairs(saved().players) do assert(not seen[p.participantId]); seen[p.participantId] = true end
        eq(V.Format(saved()), scenario[3] == 4 and "4v4" or scenario[3] == 6 and "6v6v6" or "9v9")
        local sizes = {}; for _, n in ipairs(scenario[2]) do sizes[#sizes + 1] = tostring(n) end
        eq(V.PlayedFormat(saved()), table.concat(sizes, "v"))
    end)
end
test("zero statistics and absent combat observations are valid", function()
    setup({ 1, 1 }); engine.roster[1][2].value = 0; finish(); advance(30000)
    local p; for _, row in ipairs(saved().players) do if not row.isLocal then p = row end end
    eq(p.kills, 0); eq(p.damage, 0); eq(B.Count(p.abilities), 0); eq(#saved().players, 2)
end)
test("missing account uses exact character fallback without merging similar names", function()
    setup({ 1, 2 }); engine.roster[1][2].account, engine.roster[1][2].character = "", "Astra"
    engine.roster[1][3].account, engine.roster[1][3].character = nil, "Astral"
    finish(); advance(30000); eq(#saved().players, 3); eq(saved().diagnostics.characterIdentities, 2)
    local a, b = B.Players:Get({ character = "Astra" }, saved().world), B.Players:Get({ character = "Astral" }, saved().world)
    assert(a and b and a.id ~= b.id); eq(a.encounters, 1); eq(V.ProfileName(a), "Astra")
end)
test("unnamed slots and absent statistics survive as unresolved participants", function()
    setup({ 1, 1 }); engine.roster[1][2].account, engine.roster[1][2].character = nil, nil; engine.missingStats = true
    finish(); advance(30000); eq(#saved().players, 2); eq(saved().diagnostics.unresolvedIdentities, 1)
    assert(saved().snapshotIncomplete); eq(B.Count(B.db.profiles), 0)
    local unresolved; for _, p in ipairs(saved().players) do if not p.isLocal then unresolved = p end end
    eq(V.Name(unresolved), "Unresolved participant"); eq(unresolved.damage, nil)
end)
test("unknown team never becomes an opponent or a team loss", function()
    setup({ 1, 1 }); engine.roster[1][2].team = 0; finish(); advance(30000)
    local profile = B.Players:Get({ account = "@player2" }, saved().world)
    eq(profile.unknown, 1); eq(profile.opponents, 0); eq(profile.wins, 0); eq(profile.losses, 0)
    local p; for _, row in ipairs(saved().players) do if not row.isLocal then p = row end end
    eq(B.TeamRelation(saved(), p), "unknown"); eq(B.Against(saved(), p), "Unresolved")
    eq(V.TeamSummary(saved(), p, "damage"), nil)
    B.UI:OpenMatch(saved()); B.UI:OpenDossier(saved(), p)
end)
test("players arriving after the old three-second window are included once", function()
    setup({ 3, 3 }); local last = table.remove(engine.roster[1]); finish(); advance(5000); eq(#B.db.matches, 0)
    advance(15000); engine.roster[1][#engine.roster[1] + 1] = last; B.Match:TryCapture(); advance(10000)
    eq(#saved().players, 6); eq(B.db.stats.total, 1)
    B.Match:Finish(); B.Match:TryCapture(); eq(B.db.stats.total, 1)
end)
test("final verification retains a player who disappears from a later read", function()
    setup({ 1, 2 }); finish(); advance(5000); table.remove(engine.roster[1]); advance(25000)
    eq(#saved().players, 3); eq(saved().diagnostics.scoreboardEntries, 2); eq(saved().diagnostics.retainedParticipants, 1)
    local p = B.Players:Get({ account = "@player3" }, saved().world); eq(p.encounters, 1)
end)
test("leaving after FINISHED flushes a marked candidate rather than losing the match", function()
    setup({ 3, 3 }); finish(); advance(1000); B.Match:Leaving()
    eq(#saved().players, 6); assert(saved().snapshotIncomplete); eq(B.db.stats.total, 1)
    B.Match:Leaving(); eq(B.db.stats.total, 1)
end)
test("reload resumes the persisted final candidate and remaining deadline", function()
    setup({ 3, 3 }); finish(); advance(17000)
    local id = B.Match.session.id; local db = B.Copy(B.db)
    B.Match:Stop(); B.Match.session = nil; B.Storage:Initialize(db); B.Match:Activated()
    eq(B.Match.session.id, id); advance(13000); eq(#B.db.matches, 1); eq(#saved().players, 6)
    B.Match.session = nil; B.Match:Activated(); eq(B.db.stats.total, 1)
end)
test("multi-round cumulative union includes early leavers and late substitutes once", function()
    setup({ 1, 2 }); local localPlayer, leaver, substitute = engine.roster[1][1], engine.roster[1][2], engine.roster[1][3]
    engine.roster[1] = { localPlayer, leaver }; engine.roster[2] = { localPlayer, substitute }
    engine.multi, engine.round = true, 2
    B.Match:State(BATTLEGROUND_STATE_RUNNING, BATTLEGROUND_STATE_POSTROUND); eq(#B.db.matches, 0)
    finish(); advance(30000); eq(#saved().players, 3); eq(saved().diagnostics.scoreboardEntries, 2)
    eq(saved().diagnostics.retainedParticipants, 1); eq(B.db.stats.total, 1)
end)
test("same character gaining an account within round rosters does not duplicate participation", function()
    setup({ 1, 1 }); local localPlayer, enemy = engine.roster[1][1], B.Copy(engine.roster[1][2])
    engine.roster[1][2].account = nil; engine.roster[2] = { localPlayer, enemy }; engine.multi, engine.round = true, 2
    finish(); advance(30000); eq(#saved().players, 2); eq(B.Count(B.db.profiles), 1)
    eq(B.Players:Get(enemy, saved().world).encounters, 1)
end)
test("late account resolution preserves observations without doubling events", function()
    setup({ 1, 1 }); local enemy = engine.roster[1][2]; enemy.account = nil
    local charId = B.Identity(enemy, B.Match.session.world)
    B.Match.session.observations[charId] = { [99] = { name = "Effect", events = 3, damage = 30, firstSeen = timestamp, lastSeen = timestamp } }
    finish(); advance(5000); enemy.account = "@player2"
    local accountId = B.Identity(enemy, B.Match.session.world)
    B.Match.session.observations[accountId] = { [99] = { name = "Effect", events = 2, damage = 20, firstSeen = timestamp, lastSeen = timestamp } }
    advance(1000); advance(1000); advance(23000)
    eq(#saved().players, 2)
    local p; for _, row in ipairs(saved().players) do if not row.isLocal then p = row end end
    eq(p.abilities[99].events, 5); eq(p.abilities[99].damage, 50)
    eq(B.Players:Get(enemy, saved().world).abilities[99].events, 5)
end)
test("profile derivation failure rolls back encounters, totals and history together", function()
    setup({ 1, 1 }); finish()
    local record = B.Players.Record
    B.Players.Record = function(self, m, profiles) record(self, m, profiles); error("simulated derivation failure") end
    advance(30000); eq(#B.db.matches, 0); eq(B.Count(B.db.profiles), 0); eq(B.db.stats.total, 0)
    B.Players.Record = record
    assert(B.Match:Flush("retry after repaired derivation")); eq(B.db.stats.total, 1); eq(B.Count(B.db.profiles), 1)
    eq(B.Players:Get({ account = "@player2" }, saved().world).encounters, 1)
end)
test("missing healing remains unavailable in lifetime observations", function()
    setup({ 1, 1 }); local base = B.API:Snapshot(B.Match.session); eq(base, nil)
    finish(); advance(30000); local m = B.Copy(saved()); m.id = "second"
    for _, p in ipairs(m.players) do if not p.isLocal then p.abilities = { [99] = { name = "Effect", events = 1, damage = 5 } } end end
    B.Storage:Commit(m); local second = B.Copy(m); second.id = "third"; B.Storage:Commit(second)
    local p = B.Players:Get({ account = "@player2" }, m.world); eq(p.abilities[99].healing, nil); eq(p.abilities[99].damage, 10)
end)
test("clean zone display retains original Battleground identifier and name", function()
    setup({ 1, 1 }); engine.zoneName = "Castle Courtyard"; finish(); advance(30000)
    eq(V.MapName(saved()), "Castle Courtyard"); eq(saved().map, "Test Arena"); eq(saved().mapId, 42)
    engine.zoneName = nil; eq(V.MapName({ map = "Castle Courtyard 1 point DOM R" }), "Castle Courtyard 1 point DOM R")
end)
test("debug completeness diagnostic reflects actual identities and counts once", function()
    setup({ 1, 2 }); engine.roster[1][2].account = ""; B.db.settings.debug = true
    local output, previous = {}, d; d = function(text) output[#output + 1] = text end
    finish(); advance(30000); d = previous
    local summaries = 0
    for _, text in ipairs(output) do if text:find("Scoreboard entries:", 1, true) then
        summaries = summaries + 1; assert(text:find("Participants saved: 3", 1, true)); assert(text:find("Account identities: 2", 1, true)); assert(text:find("Character-only: 1", 1, true))
    end end
    eq(summaries, 1)
end)
test("keybinding delegates to existing toggle and safely reports native assignments", function()
    local toggled, toggle = 0, B.UI.Toggle; B.UI.Toggle = function() toggled = toggled + 1 end
    B.Keybindings:Toggle(); B.Keybindings:Toggle(); eq(toggled, 2); B.UI.Toggle = toggle
    local old = { GetActionIndicesFromName, GetActionBindingInfo, GetMaxBindingsPerAction, GetKeyName }
    GetActionIndicesFromName = function(action) eq(action, "BGD_TOGGLE"); return 1, 2, 3 end
    GetMaxBindingsPerAction = function() return 2 end
    GetActionBindingInfo = function(_, _, _, slot) if slot == 1 then return 10, 20, 0, 0, 0 else return 0, 0, 0, 0, 0 end end
    GetKeyName = function(code) return code == 10 and "D" or "Ctrl" end
    eq(B.Keybindings:Assigned(), "Ctrl + D")
    GetActionBindingInfo = function() return 0, 0, 0, 0, 0 end; eq(B.Keybindings:Assigned(), "Unassigned")
    GetActionIndicesFromName = function() return nil end; eq(B.Keybindings:Assigned(), nil)
    GetActionIndicesFromName, GetActionBindingInfo, GetMaxBindingsPerAction, GetKeyName = old[1], old[2], old[3], old[4]
end)
test("existing schema-one history, profiles, counters and abilities remain accessible", function()
    setup({ 1, 1 }); finish(); advance(30000)
    local legacy = B.Copy(B.db); local m = legacy.matches[1]
    m.diagnostics, m.actualTeamSizes, m.finalTeamSizes, m.captureStatus, m.snapshotIncomplete = nil, nil, nil, nil, nil
    for _, p in ipairs(m.players) do p.participantId, p.identityConfidence, p.scoreboardSlot = nil, nil, nil end
    local id, encounters, damage = m.id, B.Players:Get({ account = "@player2" }, m.world).encounters, m.players[1].damage
    assert(B.Storage:Initialize(legacy)); eq(B.db.schema, 1); eq(#B.db.matches, 1); eq(B.db.matches[1].id, id)
    eq(B.db.matches[1].players[1].damage, damage); eq(B.Players:Get({ account = "@player2" }, m.world).encounters, encounters)
    eq(B.Storage:Commit(m), false); eq(B.db.stats.total, 1); B.UI:OpenMatch(m); B.UI:Open("PLAYERS")
end)
test("a changed team across rounds leaves relationship unresolved, not an invented win", function()
    setup({ 1, 1 }); local localPlayer, enemy = engine.roster[1][1], B.Copy(engine.roster[1][2])
    enemy.team = 1; engine.roster[2] = { localPlayer, enemy }; engine.multi, engine.round = true, 2
    finish(); advance(30000)
    local p = B.Players:Get(enemy, saved().world); eq(p.unknown, 1); eq(p.wins, 0); eq(p.allies, 0)
    eq(V.PlayedFormat(saved()), "2v0"); assert(saved().snapshotIncomplete)
end)
test("pending team results can resolve late without dropping any participants", function()
    setup({ 3, 3 }); engine.results[1], engine.results[2] = BATTLEGROUND_RESULT_INVALID, BATTLEGROUND_RESULT_INVALID
    finish(); advance(20000); eq(#B.db.matches, 0)
    engine.results[1], engine.results[2] = BATTLEGROUND_RESULT_WIN, BATTLEGROUND_RESULT_LOSS
    advance(1000); advance(9000); eq(#saved().players, 6); eq(saved().outcome, "Win")
end)
test("clearing the live scoreboard flushes the persisted candidate once", function()
    setup({ 3, 3 }); finish(); advance(1000); engine.state, engine.active = BATTLEGROUND_STATE_NONE, false
    B.Match:State(BATTLEGROUND_STATE_FINISHED, BATTLEGROUND_STATE_NONE)
    eq(#saved().players, 6); eq(B.db.stats.total, 1); assert(saved().verificationInterrupted)
    B.Match:Activated(); eq(B.db.stats.total, 1)
end)
test("authoritative late corrections replace earlier numeric values", function()
    setup({ 1, 1 }); finish(); advance(20000); engine.roster[1][2].value = 3; advance(1000); advance(9000)
    local enemy; for _, p in ipairs(saved().players) do if not p.isLocal then enemy = p end end
    eq(enemy.kills, 3 * SCORE_TRACKER_TYPE_KILL); eq(enemy.damage, 3 * SCORE_TRACKER_TYPE_DAMAGE_DONE)
end)
print(passed .. " reliability/keybinding tests passed (mock ESO).")
