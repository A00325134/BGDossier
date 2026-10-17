local B, L, C = BattlegroundDossier, BattlegroundDossier.LiveSession, BattlegroundDossier.LiveCore
local passed = 0
local function test(label, fn)
    local ok, err = pcall(fn); assert(ok, label .. ": " .. tostring(err)); passed = passed + 1; print("PASS merge " .. label)
end
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function setup(sizes, capacity)
    B.Match:Stop(); B.Match.session = nil
    for _, suffix in ipairs({ "RankQuery", "RankResponse", "RankExpiry" }) do EVENT_MANAGER:UnregisterForUpdate(L.name .. suffix) end
    B.Storage:Initialize({}); clock, timestamp = 0, 1800000000
    engine.active, engine.map, engine.round, engine.multi, engine.state = true, 42, 1, false, BATTLEGROUND_STATE_RUNNING
    engine.characterId, engine.wallet, engine.combat, engine.capacity = "merge-main", 1000, false, capacity or 4
    engine.missingStats, engine.missingDamage, engine.zoneName = nil, nil, nil
    engine.showLeaderboard, engine.rank, engine.rankSeconds, engine.rankQueries = true, 42, 86400, 0
    engine.rankReadyState = nil
    engine.teams, engine.results, engine.scores, engine.roster = {}, {}, {}, { {} }
    local index = 0
    for team, size in ipairs(sizes or { 4, 4 }) do
        engine.teams[team], engine.results[team], engine.scores[team] = team, team == 1 and BATTLEGROUND_RESULT_WIN or BATTLEGROUND_RESULT_LOSS, 500 - team * 50
        for _ = 1, size do
            index = index + 1
            engine.roster[1][index] = { character = "Player " .. index, account = "@merge" .. index, team = team, isLocal = index == 1, value = index }
        end
    end
    L:Initialize(); B.UI:Initialize(); B.InitializeCommands(); B.db.settings.autoOpen = false; B.Match:Initialize()
end
local function finish()
    engine.state = BATTLEGROUND_STATE_FINISHED; B.Match:State(BATTLEGROUND_STATE_RUNNING, engine.state)
    clock, timestamp = clock + 30000, timestamp + 30; B.Match:TryCapture()
end
local function click(text)
    for _, button in ipairs(B.UI.canvas.pools.button or {}) do
        if not button:IsHidden() and button:GetLabelControl():GetText() == text then button.handlers.OnClicked(button); return end
    end
    error("Button not found: " .. text)
end
local function ap(total, difference, reason)
    engine.wallet = total
    EVENT_MANAGER.events[L.name .. ":" .. EVENT_ALLIANCE_POINT_UPDATE](EVENT_ALLIANCE_POINT_UPDATE, total, false, difference, reason or 9001)
end
test("single initialization preserves independent HUD and analysis windows", function()
    setup(); assert(L:IsReady()); assert(L.window ~= B.UI.window); eq(L.window.width, 448); eq(L.window.height, 78)
    eq(L.window:IsHidden(), false); B.UI:SetVisible(false); eq(L.window:IsHidden(), false)
    B.UI:Toggle(); eq(L.window:IsHidden(), false); eq(B.UI.window:IsHidden(), false)
    B.Keybindings:ToggleHUD(); eq(L.window:IsHidden(), true); eq(B.UI.window:IsHidden(), false)
    B.Keybindings:ToggleHUD(); eq(L.window:IsHidden(), false)
end)
for _, format in ipairs({ { "4v4", { 4, 4 }, 4 }, { "understaffed 3v3", { 3, 3 }, 4 }, { "6v6v6", { 6, 6, 6 }, 6 }, { "9v9", { 9, 9 }, 9 } }) do
    test(format[1] .. " updates scoreboard, profiles and live session once", function()
        setup(format[2], format[3]); finish()
        local n = 0; for _, size in ipairs(format[2]) do n = n + size end
        eq(#B.db.matches, 1); eq(#B.db.matches[1].players, n); eq(B.Count(B.db.profiles), n - 1)
        eq(L.session.wins, 1); eq(L.session.losses, 0); eq(C.WinRate(L.session), "100.0%")
        B.Match:State(BATTLEGROUND_STATE_FINISHED, BATTLEGROUND_STATE_FINISHED); B.Match:TryCapture()
        eq(L.session.wins, 1); eq(B.db.stats.total, 1); eq(B.Storage:Commit(B.db.matches[1]), false)
        for _, p in pairs(B.db.profiles) do eq(p.encounters, 1) end
    end)
end
test("win loss draw and unresolved calculations retain the tracker denominator", function()
    setup()
    for _, outcome in ipairs({ BATTLEGROUND_RESULT_WIN, BATTLEGROUND_RESULT_LOSS, BATTLEGROUND_RESULT_TIE, BATTLEGROUND_RESULT_INVALID }) do
        if #B.db.matches > 0 then engine.state = BATTLEGROUND_STATE_STARTING; B.Match:State(BATTLEGROUND_STATE_FINISHED, engine.state) end
        engine.results[1] = outcome; finish()
    end
    eq(L.session.wins, 1); eq(L.session.losses, 1); eq(L.session.draws, 1); eq(L.session.unresolved, 1)
    eq(C.WinRate(L.session), "50.0%"); eq(C.Completed(L.session), 3); eq(B.db.stats.total, 4)
end)
test("AP events count verified gains, ignore duplicates/spending/transfers and rebase", function()
    setup(); B.UI:SetVisible(false)
    ap(1100, 100); eq(L.session.ap, 100); ap(1100, 100); eq(L.session.ap, 100)
    ap(700, -400); eq(L.session.ap, 100); ap(720, 20); eq(L.session.ap, 120)
    ap(820, 100, CURRENCY_CHANGE_REASON_BANK_WITHDRAWAL); eq(L.session.ap, 120)
    ap(850, 30); eq(L.session.ap, 150)
    ap(1900, 5); eq(L.session.ap, 150); assert(L.apWarning)
    ap(1910, 10); eq(L.session.ap, 160); eq(L.sections[4].value:GetText(), "+160")
end)
test("Competitive rank remains independent, throttled, cached only within this UI load", function()
    setup(); L:RequestRank(); eq(L.rank, 42); eq(engine.rankQueries, 1)
    L:RequestRank(); L:RequestRank(); eq(engine.rankQueries, 1); assert(L.rankQueryQueued)
    engine.rank = 7; clock = clock + 60000
    EVENT_MANAGER.updates[L.name .. "RankQuery"](); eq(engine.rankQueries, 2); eq(L.rank, 7)
    engine.rank = 0
    EVENT_MANAGER.events[L.name .. ":" .. EVENT_BATTLEGROUND_LEADERBOARD_DATA_RECEIVED](0, L.rankType)
    eq(L.rank, nil); eq(L.sections[3].value:GetText(), "Unranked")
    engine.showLeaderboard = false; L:RequestRank(); eq(L.rankType, nil); eq(L.rank, nil)
end)
test("rank season expiry clears the old position and requests fresh data", function()
    setup(); L:RequestRank(); local callback = EVENT_MANAGER.updates[L.name .. "RankExpiry"]; assert(callback)
    engine.rank, engine.rankSeconds, engine.nextRankStart = 0, 0, 30; clock = clock + 60000; callback()
    eq(L.rank, nil); assert(EVENT_MANAGER.updates[L.name .. "RankExpiry"])
end)
test("HUD layout, lock, alpha, scale, position and combat mouse rules remain functional", function()
    setup(); SLASH_COMMANDS["/bglock"](); eq(L.preferences.locked, false); eq(L.window.mouseEnabled, true)
    SLASH_COMMANDS["/bgtracker"]("scale 1.25"); eq(L.window.scale, 1.25)
    SLASH_COMMANDS["/bgtracker"]("opacity 0.35"); eq(L.background.centerColor[4], 0.35)
    SLASH_COMMANDS["/bgtracker"]("header off"); eq(L.window.height, 60); eq(L.header:IsHidden(), true)
    L.window.handlers.OnMoveStop(L.window); eq(L.preferences.x, 100); eq(L.preferences.y, 100)
    EVENT_MANAGER.events[L.name .. ":" .. EVENT_PLAYER_COMBAT_STATE](0, true); eq(L.window.mouseEnabled, false)
    EVENT_MANAGER.events[L.name .. ":" .. EVENT_PLAYER_COMBAT_STATE](0, false); eq(L.window.mouseEnabled, true)
    SLASH_COMMANDS["/bgtracker"]("position reset"); eq(L.preferences.x, nil); eq(L.preferences.y, nil)
    SLASH_COMMANDS["/bgtracker"]("hide"); eq(L.window:IsHidden(), true); SLASH_COMMANDS["/bgtracker"]("show"); eq(L.window:IsHidden(), false)
end)
test("HUD settings controls share the existing page and protect resets", function()
    setup(); finish(); ap(1100, 100); B.UI:Open("SETTINGS")
    click("Arm session reset"); eq(L.session.wins, 1); click("Cancel session reset"); eq(L.session.wins, 1)
    click("Arm session reset"); click("Confirm session reset")
    eq(L.session.wins, 0); eq(L.session.ap, 0); eq(#B.db.matches, 1); eq(B.db.stats.total, 1)
    assert(L.session.lastMatchId); eq(L:StageMatch(B.db.matches[1]), nil)
    click("Reset HUD position"); eq(L.preferences.x, nil)
end)
test("slash resets require confirmation, expire, and preserve Dossier history", function()
    setup(); finish(); SLASH_COMMANDS["/bgreset"](""); eq(L.session.wins, 1)
    clock = clock + 16000; SLASH_COMMANDS["/bgreset"]("confirm"); eq(L.session.wins, 1)
    SLASH_COMMANDS["/bgreset"]("confirm"); eq(L.session.wins, 0); eq(#B.db.matches, 1)
    ap(1050, 50); eq(L.session.ap, 50)
    SLASH_COMMANDS["/bgd"]("reset"); SLASH_COMMANDS["/bgd"]("reset confirm"); eq(#B.db.matches, 0); eq(L.session.ap, 50)
end)
test("reset during an unfinished match permits its later single result", function()
    setup(); L:ResetSession(); finish(); eq(L.session.wins, 1); eq(#B.db.matches, 1)
end)
test("reset while the final snapshot is pending does not lose eligibility", function()
    setup(); engine.state = BATTLEGROUND_STATE_FINISHED; B.Match:State(BATTLEGROUND_STATE_RUNNING, engine.state)
    L:ResetSession(); B.Match:Leaving(); eq(L.session.wins, 1); eq(#B.db.matches, 1)
end)
test("deliberate reload restores session once and rebases AP without inferring outage gains", function()
    setup(); finish(); ap(1100, 100); L.preferences.scale = 1.2; L.preferences.visible = false
    ReloadUI(); timestamp = timestamp + 1; engine.wallet = 1500; L:Initialize()
    eq(L.session.wins, 1); eq(L.session.ap, 100); eq(L.session.lastAP, 1500); eq(L.session.reloadAt, nil)
    eq(L.preferences.scale, 1.2); eq(L.preferences.visible, false)
    B.Match:Activated(); eq(L.session.wins, 1)
    ap(1510, 10); eq(L.session.ap, 110)
    L:Initialize(); eq(L.session.wins, 0); eq(L.session.ap, 0); eq(L.preferences.scale, 1.2)
end)
test("session reload marker expires and rank is not restored from SavedVariables", function()
    setup(); finish(); L:RequestRank(); eq(L.rank, 42); ReloadUI(); timestamp = timestamp + 121
    L:Initialize(); eq(L.session.wins, 0); eq(L.rank, nil); eq(L.sections[3].value:GetText(), "Unavailable")
end)
test("character settings are isolated; old history survives changing characters", function()
    setup(); L.preferences.opacity = 0.42; finish(); local originalKey = L.characterKey
    engine.characterId = "merge-alt"; L:Initialize(); eq(L.preferences.opacity, 0.82); eq(L.session.wins, 0)
    eq(#B.db.matches, 1); assert(B.db.liveHUD.characters[originalKey]); eq(B.Count(B.db.profiles), 7)
    engine.characterId = "merge-main"; L:Initialize(); eq(L.preferences.opacity, 0.42)
end)
test("failed shared derivation publishes neither history nor HUD result", function()
    setup(); local stage = L.StageMatch; L.StageMatch = function() error("simulated HUD staging failure") end
    finish(); eq(#B.db.matches, 0); eq(L.session.wins, 0); eq(B.Count(B.db.profiles), 0)
    L.StageMatch = stage; assert(B.Match:Flush("retry")); eq(#B.db.matches, 1); eq(L.session.wins, 1)
end)
test("future live storage version is preserved without disabling Dossier", function()
    setup(); local root = { version = 99, characters = { sentinel = { keep = true } } }; B.db.liveHUD = root
    L:Initialize(); eq(L:IsReady(), false); eq(B.db.liveHUD, root); assert(root.characters.sentinel.keep)
    B.UI:Open("SETTINGS"); B.UI:Open("MATCHES")
end)
test("a new login at FINISHED preserves history without crediting an old session", function()
    setup(); engine.state = BATTLEGROUND_STATE_FINISHED; B.Match:State(BATTLEGROUND_STATE_RUNNING, engine.state)
    L:Initialize(); B.Match:Leaving()
    eq(#B.db.matches, 1); eq(L.session.wins, 0); eq(B.db.stats.total, 1)
end)

test("pending results from another character cannot credit the new character HUD", function()
    setup(); engine.state = BATTLEGROUND_STATE_FINISHED; B.Match:State(BATTLEGROUND_STATE_RUNNING, engine.state)
    engine.characterId = "merge-alt"; L:Initialize(); B.Match:Leaving()
    eq(#B.db.matches, 1); eq(L.session.wins, 0); eq(B.db.stats.total, 1)
end)

test("all original non-earnings AP reasons remain excluded", function()
    setup()
    for _, reason in ipairs({ CURRENCY_CHANGE_REASON_PLAYER_INIT, CURRENCY_CHANGE_REASON_BANK_WITHDRAWAL,
        CURRENCY_CHANGE_REASON_BANK_DEPOSIT, CURRENCY_CHANGE_REASON_GUILD_BANK_WITHDRAWAL, CURRENCY_CHANGE_REASON_GUILD_BANK_DEPOSIT }) do
        ap(engine.wallet + 100, 100, reason); eq(L.session.ap, 0)
    end
    ap(engine.wallet + 15, 15); eq(L.session.ap, 15)
end)

test("post-match pending query retains a clearly labelled cached rank without opening leaderboards", function()
    setup(); B.UI:SetVisible(false); L:RequestRank(); eq(L.rank, 42)
    engine.rankReadyState = LEADERBOARD_DATA_RESPONSE_PENDING; engine.rank = 0
    finish(); eq(L.rank, 42); eq(L.sections[3].value:GetText(), "#42")
    eq(L.sections[3].label:GetText(), "BG RANK*"); eq(engine.rankQueries, 1)
    clock = 60000; EVENT_MANAGER.updates[L.name .. "RankQuery"]()
    eq(engine.rankQueries, 2); eq(L.rank, 42); assert(EVENT_MANAGER.updates[L.name .. "RankResponse"])
    engine.rank = 35
    EVENT_MANAGER.events[L.name .. ":" .. EVENT_BATTLEGROUND_LEADERBOARD_DATA_RECEIVED](0, L.rankType)
    eq(L.rank, 35); eq(L.sections[3].label:GetText(), "BG RANK")
    eq(EVENT_MANAGER.updates[L.name .. "RankResponse"], nil); eq(B.UI.window:IsHidden(), true)
end)

test("a first asynchronous rank response shows loading until confirmed", function()
    setup(); engine.rankReadyState = LEADERBOARD_DATA_RESPONSE_PENDING; engine.rank = 0
    L:RequestRank(); eq(L:RankText(), "Loading..."); eq(L.rankState, "pending")
    engine.rank = 12
    EVENT_MANAGER.events[L.name .. ":" .. EVENT_BATTLEGROUND_LEADERBOARD_DATA_RECEIVED](0, L.rankType)
    eq(L:RankText(), "#12"); eq(L.rankState, "ready")
end)

test("pending rank requests retry automatically and stop after three unanswered attempts", function()
    setup(); engine.rankReadyState = LEADERBOARD_DATA_RESPONSE_PENDING
    L:RequestRank(); eq(engine.rankQueries, 1)
    for attempt = 2, 3 do
        clock = clock + 60000; EVENT_MANAGER.updates[L.name .. "RankResponse"]()
        eq(engine.rankQueries, attempt); eq(L.rankState, "pending")
    end
    clock = clock + 60000; EVENT_MANAGER.updates[L.name .. "RankResponse"]()
    eq(L:RankText(), "Unavailable"); eq(engine.rankQueries, 3)
    eq(EVENT_MANAGER.updates[L.name .. "RankResponse"], nil); eq(EVENT_MANAGER.updates[L.name .. "RankQuery"], nil)
    engine.rank = 9
    EVENT_MANAGER.events[L.name .. ":" .. EVENT_BATTLEGROUND_LEADERBOARD_DATA_RECEIVED](0, L.rankType)
    eq(L:RankText(), "#9")
end)

test("a successful retry recovers rank without native leaderboard interaction", function()
    setup(); engine.rankReadyState = LEADERBOARD_DATA_RESPONSE_PENDING; L:RequestRank()
    engine.rankReadyState, engine.rank = LEADERBOARD_DATA_READY, 8
    clock = clock + 60000; EVENT_MANAGER.updates[L.name .. "RankResponse"]()
    eq(engine.rankQueries, 2); eq(L.rank, 8); eq(L.rankState, "ready")
    eq(EVENT_MANAGER.updates[L.name .. "RankResponse"], nil)
end)

test("a confirmed zero rank replaces the cached rank with Unranked", function()
    setup(); L:RequestRank(); engine.rankReadyState = LEADERBOARD_DATA_RESPONSE_PENDING
    clock = clock + 60000; L:RequestRank(); eq(L.rank, 42)
    engine.rank = 0
    EVENT_MANAGER.events[L.name .. ":" .. EVENT_BATTLEGROUND_LEADERBOARD_DATA_RECEIVED](0, L.rankType)
    eq(L.rank, nil); eq(L:RankText(), "Unranked"); eq(L.rankState, "ready")
end)

test("valid positive rank does not depend on populated schedule metadata", function()
    setup(); engine.rankSeconds, engine.nextRankStart = 0, 0; L:RequestRank()
    eq(L.rank, 42); eq(L.rankState, "ready")
end)

test("missing rank metadata is unavailable rather than a confirmed unranked result", function()
    setup(); engine.rank, engine.rankSeconds, engine.nextRankStart = 0, 0, 0; L:RequestRank()
    eq(L:RankText(), "Loading..."); assert(EVENT_MANAGER.updates[L.name .. "RankResponse"])
end)

test("unrelated leaderboard data cannot replace rank and disappearing boards cancel timers", function()
    setup(); engine.rankReadyState = LEADERBOARD_DATA_RESPONSE_PENDING; L:RequestRank()
    EVENT_MANAGER.events[L.name .. ":" .. EVENT_BATTLEGROUND_LEADERBOARD_DATA_RECEIVED](0, -99)
    eq(L.rankState, "pending")
    engine.showLeaderboard = false; L:RequestRank(); eq(L:RankText(), "Unavailable")
    for _, suffix in ipairs({ "RankQuery", "RankResponse", "RankExpiry" }) do eq(EVENT_MANAGER.updates[L.name .. suffix], nil) end
end)

test("visibility mode upgrades preserve existing shown and hidden preferences", function()
    setup(); engine.active = false; L.preferences.visibilityMode = nil; L.preferences.visible = true
    L:Initialize(); eq(L.preferences.visibilityMode, "always"); eq(L.window:IsHidden(), false)
    L.preferences.visibilityMode, L.preferences.visible = nil, false
    L:Initialize(); eq(L.preferences.visibilityMode, "always"); eq(L.preferences.visible, false); eq(L.window:IsHidden(), true)
    L.preferences.visibilityMode = "invalid"; L:Initialize(); eq(L.preferences.visibilityMode, "always")
end)

test("settings visibility segments apply immediately only to the small HUD", function()
    setup(); engine.active = false; B.UI:Open("SETTINGS")
    click("Battlegrounds Only"); eq(L.preferences.visibilityMode, "battlegroundsOnly"); eq(L.window:IsHidden(), true)
    eq(B.UI.window:IsHidden(), false); eq(L.preferences.visible, true)
    click("Always Visible"); eq(L.window:IsHidden(), false); eq(B.UI.window:IsHidden(), false)
end)

test("Battleground visibility includes every match phase through the postgame period", function()
    setup(); L.preferences.visibilityMode = "battlegroundsOnly"
    for _, state in ipairs({ BATTLEGROUND_STATE_STARTING, BATTLEGROUND_STATE_PREROUND, BATTLEGROUND_STATE_RUNNING, BATTLEGROUND_STATE_POSTROUND, BATTLEGROUND_STATE_FINISHED }) do
        engine.state = state; L:ApplyVisibility(); eq(L.window:IsHidden(), false)
    end
    engine.active = false; L:ApplyVisibility(); eq(L.window:IsHidden(), true)
end)

test("existing activation callback refreshes HUD on entry exit and repeated loading screens", function()
    setup(); L.preferences.visibilityMode = "battlegroundsOnly"
    local activated = EVENT_MANAGER.events[B.name .. ":" .. EVENT_PLAYER_ACTIVATED]
    for _, active in ipairs({ false, true, true, false, false, true }) do
        engine.active = active; activated(0, false); eq(L.window:IsHidden(), not active)
    end
    eq(EVENT_MANAGER.events[L.name .. ":" .. EVENT_PLAYER_ACTIVATED], nil)
end)

test("manual toggles stay a master switch and never bypass the location filter", function()
    setup(); L.preferences.visibilityMode = "battlegroundsOnly"; L:ApplyVisibility()
    B.Keybindings:ToggleHUD(); eq(L.preferences.visible, false); eq(L.window:IsHidden(), true)
    engine.active = false; B.Match:Activated(); engine.active = true; B.Match:Activated(); eq(L.window:IsHidden(), true)
    SLASH_COMMANDS["/bgtracker"]("show"); eq(L.window:IsHidden(), false)
    engine.active = false; B.Match:Activated(); eq(L.window:IsHidden(), true)
    SLASH_COMMANDS["/bgtracker"]("hide"); SLASH_COMMANDS["/bgtracker"]("show"); eq(L.window:IsHidden(), true)
    L.preferences.visibilityMode = "always"; L:ApplyVisibility(); eq(L.window:IsHidden(), false)
end)

test("visibility mode persists across reload login and per-character preference switches", function()
    setup(); L.preferences.visibilityMode = "battlegroundsOnly"; L.preferences.x, L.preferences.scale = 321, 1.25
    engine.active = false; ReloadUI(); L:Initialize()
    eq(L.preferences.visibilityMode, "battlegroundsOnly"); eq(L.window:IsHidden(), true); eq(L.preferences.x, 321); eq(L.preferences.scale, 1.25)
    engine.active = true; L:Initialize(); eq(L.window:IsHidden(), false)
    engine.characterId = "visibility-alt"; L:Initialize(); eq(L.preferences.visibilityMode, "always")
    engine.characterId = "merge-main"; L:Initialize(); eq(L.preferences.visibilityMode, "battlegroundsOnly")
end)

test("hidden HUD continues AP rank and finalized match tracking without resetting data", function()
    setup(); L.preferences.visibilityMode = "battlegroundsOnly"; engine.active = false; L:ApplyVisibility(); eq(L.window:IsHidden(), true)
    ap(1100, 100); L:RequestRank(); eq(L.session.ap, 100); eq(L.rank, 42)
    engine.active = true; B.Match:Activated(); SLASH_COMMANDS["/bgtracker"]("hide"); finish()
    eq(L.window:IsHidden(), true); eq(L.session.wins, 1); eq(#B.db.matches, 1); eq(B.db.stats.total, 1)
    eq(B.Count(B.db.profiles), 7); eq(L.session.ap, 100)
end)

test("visibility refreshes register no polling timers or repeated listeners", function()
    setup(); L.preferences.visibilityMode = "battlegroundsOnly"
    local events, updates = B.Count(EVENT_MANAGER.events), B.Count(EVENT_MANAGER.updates)
    for _ = 1, 100 do L:ApplyVisibility() end
    eq(B.Count(EVENT_MANAGER.events), events); eq(B.Count(EVENT_MANAGER.updates), updates)
end)

test("one authoritative match event owner and one AP/leaderboard listener", function()
    setup(); assert(EVENT_MANAGER.events[B.name .. ":" .. EVENT_BATTLEGROUND_STATE_CHANGED])
    eq(EVENT_MANAGER.events[L.name .. ":" .. EVENT_BATTLEGROUND_STATE_CHANGED], nil)
    eq(EVENT_MANAGER.events[L.name .. ":" .. EVENT_BATTLEGROUND_SCOREBOARD_UPDATED], nil)
    eq(EVENT_MANAGER.events[L.name .. ":" .. EVENT_PLAYER_ACTIVATED], nil)
    eq(EVENT_MANAGER.updates[L.name .. "Result"], nil)
    assert(EVENT_MANAGER.events[L.name .. ":" .. EVENT_ALLIANCE_POINT_UPDATE])
    assert(EVENT_MANAGER.events[L.name .. ":" .. EVENT_BATTLEGROUND_LEADERBOARD_DATA_RECEIVED])
end)
print(passed .. " merged-addon tests passed (mock ESO; no live merged-addon gameplay validation).")
