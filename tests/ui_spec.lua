-- Presentation regression tests. These do not certify native font rendering or live ESO layout.
local B, U, V, C = BattlegroundDossier, BattlegroundDossier.UI, BattlegroundDossier.ViewData, BattlegroundDossier.Controls
local passed = 0
local function test(label, fn)
    local ok, err = pcall(fn); assert(ok, label .. ": " .. tostring(err)); passed = passed + 1; print("PASS UI " .. label)
end
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function match(id, outcome, teams, capacity)
    local m = { id = id, world = "NA Megaserver", map = "Arena " .. id, mapId = 42, modeName = "Deathmatch", outcome = outcome or "Win",
        finishedAt = 1800000000, teamCount = teams or 3, teamCapacity = capacity or 6, localTeam = 1, placement = 1, teams = {}, players = {}, rounds = {} }
    for team = 1, m.teamCount do m.teams[team] = { name = "Team " .. team, result = team == 1 and "Win" or "Loss", score = 500 - team * 50 } end
    for i = 1, m.teamCount * m.teamCapacity do
        m.players[i] = { character = "Character " .. i, account = "@account" .. i, team = (i - 1) % m.teamCount + 1,
            isLocal = i == 1, classId = 1, kills = i, deaths = i == 1 and 0 or 2, assists = 4, damage = i * 1000,
            healing = i % 2 == 0 and i * 100 or nil, score = i * 10, previousEncounters = i % 3 == 0 and 3 or 0,
            abilities = { [20805] = { name = "Molten Whip", category = "Class abilities", events = 9, damage = 31901, firstSeen = 1800000001, lastSeen = 1800000010 },
                [40001] = { name = "Burning", category = "Other observed effects", events = 9, damage = 7300 } }, medals = {} }
    end
    m.participantCount = #m.players; return m
end
local fixture
local function reset()
    B.Storage:Initialize({}); fixture = match("current"); B.Storage:Commit(fixture)
    -- Model a saved snapshot whose preceding encounters have already been pruned.
    for i, p in ipairs(fixture.players) do p.previousEncounters = i % 3 == 0 and 3 or 0 end
    U:Initialize(); U.filters = { result = "All results", mode = "All modes", format = "All formats" }
    U.search, U.page, U.teamFilter = "", 1, "All players"; U.profile, U.expanded = nil, nil
    U:OpenMatch(fixture)
end
local function activeTables()
    local tables = {}; for _, t in ipairs(U.canvas.tables) do if not t.control:IsHidden() then tables[#tables + 1] = t end end; return tables
end
local function click(text)
    for _, button in ipairs(U.canvas.pools.button or {}) do
        if not button:IsHidden() and button:GetText() == text then button.handlers.OnClicked(button); return end
    end
    error("Visible button not found: " .. text)
end
test("number formatting preserves unavailable, exact and compact values", function()
    eq(V.Number(nil, true), "—"); eq(V.Precise(1250), "1,250"); eq(V.Number(45200, true), "45.2K")
    eq(V.Number(2400000, true), "2.4M"); eq(V.Precise(-1234), "−1,234"); eq(V.Precise(1.999), "2.00")
end)
test("history combines independent result, mode, format and identity filters", function()
    reset(); local second = match("second", "Loss", 2, 9); second.modeName = "Murderball"; B.Storage:Commit(second)
    local f = { result = "Loss", mode = "Murderball", format = "9v9" }
    eq(#V.History(f, "@account2"), 1); f.result = "Win"; eq(#V.History(f, "@account2"), 0)
    f = { result = "All results", mode = "All modes", format = "6v6v6" }; eq(#V.History(f, ""), 1)
end)
test("dropdown callbacks apply filters without callback loops", function()
    reset(); U:Open("MATCHES")
    for _, item in ipairs(U.dropdowns[1].combo.items) do if item.name == "Loss" then item.callback(); break end end
    eq(U.filters.result, "Loss"); eq(U.dropdowns[1].combo.selected, "Loss")
    U:ClearFilters(); eq(U.filters.result, "All results"); eq(U.search, "")
end)
test("18-player scoreboard has bounded columns and full roster access", function()
    reset(); local tables = activeTables(); eq(#U.scoreboardRows, 18); eq(#tables[1].rows, 18)
    assert(tables[1].contentWidth <= tables[1].body.width)
    assert(tables[1].body.height > tables[1].control.height)
    for _, row in ipairs(tables[1].rowControls) do eq(row.control.width, tables[1].body.width) end
end)
test("scoreboard sorting and filters handle all three teams", function()
    reset(); U.teamFilter = "My team"; U:Render(); eq(#U.scoreboardRows, 6)
    U.teamFilter = "Opposing teams"; U:Render(); eq(#U.scoreboardRows, 12)
    U.teamFilter = "team:3"; U:Render(); eq(#U.scoreboardRows, 6)
    U.teamFilter = "Familiar players"; U:Render(); eq(#U.scoreboardRows, 6)
    U.teamFilter, U.sort, U.descending = "All players", "healing", true; U:Render()
    eq(U.scoreboardRows[1].healing, 1800); eq(U.scoreboardRows[#U.scoreboardRows].healing, nil)
    activeTables()[1].headers[4].handlers.OnClicked(); eq(U.sort, "kills")
end)
test("whole-row selection opens dossier and Back preserves selected roster row", function()
    reset(); local p = activeTables()[1].rows[2]
    U.scroll:GetNamedChild("Scroll"):SetVerticalScroll(21); activeTables()[1].scroll:GetNamedChild("Scroll"):SetVerticalScroll(94)
    activeTables()[1].rowControls[2].control.handlers.OnClicked(); eq(U.view, "dossier"); eq(U.expanded, p)
    U:Back(); eq(U.view, "scoreboard"); eq(U.expanded, nil); eq(activeTables()[1].options.selected, p)
    eq(U.scroll:GetNamedChild("Scroll"):GetVerticalScroll(), 21); eq(activeTables()[1].scroll:GetNamedChild("Scroll"):GetVerticalScroll(), 94)
end)
test("dossier tabs retain all statistics and observed IDs", function()
    reset(); U:OpenDossier(fixture, fixture.players[2]); click("Observed abilities")
    eq(#U.abilityRows, 2); eq(U.abilityRows[1].id, 20805); eq(U.abilityRows[1].damage, 31901)
    local t = activeTables()[1]; assert(not t.rowControls[1].labels[1]:GetText():find("20805", 1, true))
    assert(t.rowControls[1].control.tip:find("20805", 1, true)); assert(t.rowControls[1].control.tip:find("31,901", 1, true))
    assert(t.rowControls[1].control.tip:find("First observed", 1, true))
    click("Scoreboard details"); assert(#activeTables()[1].rows >= B.Count(B.API.scoreTypes))
    click("History"); assert(#activeTables() >= 1)
end)
test("same-name ability IDs stay distinct and missing sort values stay last", function()
    local rows = V.Abilities({ [1] = { name = "Burning", damage = 20 }, [2] = { name = "Burning", damage = 50 }, [3] = { name = "Unknown" } }, "damage", true)
    eq(#rows, 3); eq(rows[1].id, 2); eq(rows[3].id, 3)
    rows = V.Abilities({ [1] = { name = "A" }, [2] = { name = "B", damage = 1 } }, "damage", false)
    eq(rows[2].id, 1)
end)
test("ability name/category/events/damage/healing headers sort", function()
    reset(); U:OpenDossier(fixture, fixture.players[2]); click("Observed abilities")
    for i, key in ipairs({ "name", "category", "events", "damage", "healing" }) do
        activeTables()[1].headers[i].handlers.OnClicked(); eq(U.abilitySorts["dossier:This match"].key, key)
    end
end)
test("long ability lists are paged without discarding any saved entry", function()
    reset(); local p = fixture.players[2]; p.abilities = {}
    for i = 1, 205 do p.abilities[i] = { name = "Observed " .. i, damage = i, events = i } end
    U:OpenDossier(fixture, p); click("Observed abilities")
    eq(#U.abilityRows, 205); eq(#activeTables()[1].rows, 80); eq(activeTables()[1].rows[1].id, 205)
    click("Next abilities ›"); eq(activeTables()[1].rows[1].id, 125)
    click("Next abilities ›"); eq(#activeTables()[1].rows, 45); eq(activeTables()[1].rows[45].id, 1)
    eq(B.Count(p.abilities), 205); assert(#activeTables()[1].rowControls <= 80)
end)
test("historical aggregation keeps every distinct ID and excludes current/future matches", function()
    reset(); local old = match("old"); old.finishedAt = fixture.finishedAt - 10
    old.players[2].abilities = {}; for i = 1, 100 do old.players[2].abilities[i] = { name = "Previous", events = 1, damage = 2 } end
    local future = match("future"); future.finishedAt = fixture.finishedAt + 10; future.players[2].abilities = { [99999] = { events = 1 } }
    B.Storage:Commit(old); B.Storage:Commit(future)
    local result = V.PreviousAbilities(fixture, fixture.players[2]); eq(B.Count(result), 100); eq(result[20805], nil); eq(result[99999], nil)
end)
test("history query, page and scroll survive contextual navigation", function()
    reset(); U:Open("MATCHES"); U.search, U.page = "account", 1; U.scroll:GetNamedChild("Scroll"):SetVerticalScroll(73)
    U:OpenMatch(fixture); U:OpenDossier(fixture, fixture.players[2]); U:Open("STATISTICS"); U:Open("MATCHES")
    eq(U.search, "account"); eq(U.scroll:GetNamedChild("Scroll"):GetVerticalScroll(), 73)
    eq(U.view, "history"); eq(U.tabs.MATCHES.selected, true)
end)
test("search debounce and clear controls stay in sync", function()
    reset(); U:Open("PLAYERS"); U.searchBox:SetText("@account2"); U.searchBox.handlers.OnTextChanged(U.searchBox)
    assert(EVENT_MANAGER.updates[B.name .. "Search"]); EVENT_MANAGER.updates[B.name .. "Search"]()
    eq(U.search, "@account2"); eq(#activeTables()[1].rows, 1)
    U:ClearFilters(); eq(U.searchBox:GetText(), "")
end)
test("comparison uses saved values and preserves unavailable differences", function()
    reset(); U:OpenDossier(fixture, fixture.players[2]); click("Compare with me")
    eq(U.view, "comparison"); local rows = activeTables()[1].rows
    for _, r in ipairs(rows) do if r.key == "healing" then eq(r.difference, nil) end end
    click("Swap A / B"); eq(U.compareA, fixture.players[1]); click("Clear comparison"); eq(U.view, "scoreboard")
end)
test("statistics never manufactures a trend before a second period exists", function()
    reset(); local groups = V.Trends(); eq(groups[1].count, 1); eq(groups[2].count, 0)
    U:Open("STATISTICS"); local tables = activeTables(); local trends = tables[#tables]
    for _, row in ipairs(trends.rows) do eq(row.b, nil); eq(row.difference, nil) end
end)
test("presentation changes do not mutate saved matches/profiles/stats", function()
    reset(); local matches, profiles, stats = B.Copy(B.db.matches), B.Copy(B.db.profiles), B.Copy(B.db.stats)
    U:OpenDossier(fixture, fixture.players[2])
    for _, tab in ipairs({ "Overview", "Observed abilities", "History", "Scoreboard details" }) do U.dossierTab = tab; U:Render() end
    U:Open("PLAYERS"); U.profile = B.Players:Get(fixture.players[2], fixture.world); U.dossierTab = "Observed abilities"; U:Render()
    U.profileAbilityScope = "Latest match"; U:Render(); U:Open("STATISTICS"); U:Open("SETTINGS")
    for _, tableView in ipairs(U.canvas.tables) do
        if tableView.body.width then assert(tableView.contentWidth <= tableView.body.width, "Table columns exceed content width") end
    end
    assert(equal(matches, B.db.matches)); assert(equal(profiles, B.db.profiles)); assert(equal(stats, B.db.stats))
    eq(B.db.schema, 1)
end)
test("pooled controls stabilize across repeated renders and clear old tooltips", function()
    reset(); U:Render(); local count = C.serial; for _ = 1, 12 do U:Render(true) end; eq(C.serial, count)
    U:Open("SETTINGS"); U:OpenMatch(fixture)
    local t = activeTables()[1]; assert(t.rowControls[1].control.tip:find("Character", 1, true))
end)
test("icons use exact IDs with neutral fallback and no category guesses", function()
    reset(); local requested; local oldIcon = GetAbilityIcon
    GetAbilityIcon = function(id) requested = id; return id == 42 and "/verified-icon.dds" or "" end
    U.iconCache = {}; eq(U:AbilityIcon(42), "/verified-icon.dds"); eq(requested, 42); eq(U:AbilityIcon(43), nil)
    eq(V.Category("Unknown set proc"), "Other / Effect")
    GetAbilityIcon = oldIcon
end)
test("empty datasets and missing optional values render across every view", function()
    reset(); B.db.matches, B.db.profiles, B.db.stats = {}, {}, {}
    for _, section in ipairs({ "MATCHES", "PLAYERS", "STATISTICS", "SETTINGS" }) do U:Open(section) end
    local m = match("missing", "Draw", 2, 4); m.players[2].kills, m.players[2].damage, m.players[2].abilities, m.players[2].account = nil, nil, nil, nil
    U:OpenMatch(m); U:OpenDossier(m, m.players[2]); click("Observed abilities"); eq(#U.abilityRows, 0)
end)
test("position, presentation defaults and scale survive reinitialization", function()
    reset(); B.db.settings.position = { x = 120, y = 60 }; B.db.settings.scale = 0.9
    B.db.settings.presentation.defaultTab = "PLAYERS"; B.db.settings.presentation.compactNumbers = false
    local saved = B.db; assert(B.Storage:Initialize(saved)); U:Initialize()
    eq(U.section, "PLAYERS"); eq(U.window.anchor[4], 120); eq(U.window.anchor[5], 60); eq(U:Number(45000), "45,000"); eq(B.db.settings.scale, 0.9)
end)
test("visible-data refresh detects new saved matches and skips combat", function()
    reset(); local before = U.seenTotal; B.Storage:Commit(match("new")); local old = IsUnitInCombat
    IsUnitInCombat = function() return true end; U:RefreshIfChanged(); eq(U.seenTotal, before)
    IsUnitInCombat = function() return false end; U:RefreshIfChanged(); eq(U.seenTotal, B.db.stats.total); IsUnitInCombat = old
    local stamp = U.seenSettings; B.db.settings.debug = not B.db.settings.debug; U:RefreshIfChanged(); assert(U.seenSettings ~= stamp)
end)
test("settings reset requires confirmation and preserves preferences", function()
    reset(); U:Open("SETTINGS"); local settings = B.db.settings
    click("Arm history reset"); eq(#B.db.matches, 1); click("Cancel"); eq(#B.db.matches, 1)
    click("Arm history reset"); click("Confirm deletion"); eq(#B.db.matches, 0); eq(B.db.settings, settings)
end)
print(passed .. " UI tests passed (mocked layout and controls; no visual ESO validation).")
