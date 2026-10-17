local B, P, U, C, V = BattlegroundDossier, BattlegroundDossier.Personal, BattlegroundDossier.UI, BattlegroundDossier.Controls, BattlegroundDossier.ViewData
local passed = 0
local function test(label, fn)
    local ok, err = pcall(fn); assert(ok, label .. ": " .. tostring(err)); passed = passed + 1; print("PASS personal/polish " .. label)
end
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function fixture(index, outcome)
    return { id = "personal-" .. index, world = GetWorldName(), localCharacterId = "personal-main", localCharacter = "Local^Mx",
        finishedAt = 1800000000 + index * 60, map = "Arena", mode = BATTLEGROUND_GAME_TYPE_DOMINATION, modeName = "Domination",
        teamCount = 2, teamCapacity = 4, outcome = outcome or "Win", objectiveLabel = "Flags / objectives captured",
        teams = { [1] = { name = "Allies", result = outcome or "Win" }, [2] = { name = "Opponents", result = "Loss" } },
        players = { { isLocal = true, character = "Local^Mx", account = "@local", kills = index, deaths = 2, assists = 3,
            damage = index * 100, healing = index * 1000, score = index * 10, objective = index, damageTaken = index * 200 },
            { character = "Other^Fx", account = "@opponent", kills = 999, deaths = 999, damage = 999999999, healing = 999999999 } } }
end
local function reset(count)
    C:CancelNumeric(); B.Match:Stop(); B.Match.session = nil; engine.characterId = "personal-main"
    B.Storage:Initialize({}); for i = 1, count or 0 do B.db.matches[i] = fixture(i) end
    U:Initialize(); U.personalCharacter, U.personalSort, U.personalDescending, U.personalPage, U.personalReturn = nil, nil, nil, nil, nil
    U.profile, U.expanded = nil, nil
end
local function currentRows(limit)
    local _, aliases, current = P.Index(); return P.Rows(current, limit or 0, aliases)
end
local function click(text)
    for _, button in ipairs(U.canvas.pools.button or {}) do
        if not button:IsHidden() and button:GetLabelControl():GetText() == text then button.handlers.OnClicked(button); return end
    end
    error("Missing button " .. text)
end
local function editFor(key, store)
    for _, edit in ipairs(U.canvas.pools.number or {}) do
        if not edit:IsHidden() and edit.settingKey == key and (not store or edit.settingStore == store) then return edit end
    end
    error("Missing editor " .. key)
end
local function enter(edit, text, event)
    edit:TakeFocus(); edit:SetText(text); edit.handlers[event or "OnEnter"](edit)
end
test("numeric validation rejects incomplete invalid and out-of-range input", function()
    for _, text in ipairs({ "", " ", "-1", "nan", "1e3", "1,000", "10K", "0", "1001", "2.5.0", "10." }) do eq(C.ValidateNumber(text, 10, 1000, 50), nil) end
    eq(C.ValidateNumber("1000", 10, 1000, 50), 1000); eq(C.ValidateNumber("10", 10, 1000, 50), 10)
    eq(C.ValidateNumber("225", 10, 1000, 50), 250); eq(C.ValidateNumber(" 0.85 ", 0.6, 1.2, 0.05), 0.85)
end)
test("retention typing never prunes until a completed commit", function()
    reset(35); U:Open("SETTINGS"); local edit = editFor("historyLimit")
    edit:TakeFocus()
    for _, text in ipairs({ "1", "10", "100", "1000" }) do edit:SetText(text); eq(B.db.settings.historyLimit, 200); eq(#B.db.matches, 35) end
    U:RefreshIfChanged(); eq(C.activeNumeric, edit)
    edit.handlers.OnEnter(edit); eq(B.db.settings.historyLimit, 1000); eq(#B.db.matches, 35)
    enter(editFor("historyLimit"), "10"); eq(#B.db.matches, 10); eq(B.db.settings.historyLimit, 10)
end)
test("Escape cancels and invalid blur reverts without pruning", function()
    reset(35); U:Open("SETTINGS")
    enter(editFor("historyLimit"), "10", "OnEscape"); eq(#B.db.matches, 35); eq(B.db.settings.historyLimit, 200)
    local edit = editFor("historyLimit"); edit:TakeFocus(); edit:SetText("1"); edit:LoseFocus()
    eq(edit:GetText(), "200"); eq(B.db.settings.historyLimit, 200); eq(#B.db.matches, 35)
end)
test("valid focus loss commits exactly once and plus/minus use the committed value", function()
    reset(); U:Open("SETTINGS"); local edit = editFor("profileLimit")
    edit:TakeFocus(); edit:SetText("15000"); edit:LoseFocus(); eq(B.db.settings.profileLimit, 15000)
    local plus
    for _, button in ipairs(U.canvas.pools.button) do if not button:IsHidden() and button:GetLabelControl():GetText() == "+" and button.anchor[5] == edit.anchor[5] - 4 then plus = button end end
    assert(plus); plus.handlers.OnClicked(); eq(B.db.settings.profileLimit, 16000); eq(editFor("profileLimit"):GetText(), "16000")
    local minus
    for _, button in ipairs(U.canvas.pools.button) do if not button:IsHidden() and button:GetLabelControl():GetText() == "−" and button.anchor[5] == edit.anchor[5] - 4 then minus = button end end
    assert(minus); minus.handlers.OnClicked(); eq(B.db.settings.profileLimit, 15000); eq(editFor("profileLimit"):GetText(), "15000")
    enter(editFor("scale", B.db.settings), "0.9"); eq(B.db.settings.scale, 0.9); eq(U.window.scale, 0.9)
end)
test("closing or changing section cancels partial numeric input safely", function()
    reset(35); U:Open("SETTINGS"); local edit = editFor("historyLimit")
    edit:TakeFocus(); edit:SetText("10"); U:SetVisible(false); eq(B.db.settings.historyLimit, 200)
    U:Open("SETTINGS"); edit = editFor("historyLimit"); edit:TakeFocus(); edit:SetText("10"); U:Open("STATISTICS")
    eq(#B.db.matches, 35); eq(B.db.settings.historyLimit, 200); eq(C.activeNumeric, nil)
end)
test("live HUD numeric settings use the same editor and independent store", function()
    reset(); B.LiveSession:Initialize(); U:Open("SETTINGS")
    local prefs = B.LiveSession.preferences
    local count = 0; for _, edit in ipairs(U.canvas.pools.number) do if not edit:IsHidden() then count = count + 1 end end; eq(count, 6)
    enter(editFor("scale", prefs), "1.25"); eq(prefs.scale, 1.25); eq(B.LiveSession.window.scale, 1.25)
    enter(editFor("opacity", prefs), "0.35"); eq(prefs.opacity, 0.35); eq(B.LiveSession.background.centerColor[4], 0.35)
    eq(B.db.settings.scale, 0.85)
end)
test("ESO name formatting is display-only and bypasses account IDs", function()
    reset(); local old, oldId = zo_strformat, SI_UNIT_NAME; local called
    SI_UNIT_NAME = 99999; zo_strformat = function(id, raw) eq(id, SI_UNIT_NAME); called = raw; return raw:gsub("%^[MF]x$", "") end
    local player = { character = "Al Drakkon^Mx", account = "@ExactAccount" }
    local id = B.Identity(player, "NA"); eq(V.Name(player), "Al Drakkon"); eq(called, "Al Drakkon^Mx")
    called = nil; eq(B.CharacterName("@Account^Mx"), "@Account^Mx"); eq(called, nil)
    eq(player.character, "Al Drakkon^Mx"); eq(B.Identity(player, "NA"), id)
    eq(V.ProfileName({ latestCharacter = "Irishnelly^Fx" }), "Irishnelly")
    zo_strformat, SI_UNIT_NAME = old, oldId
end)
test("fallback names preserve accents and arbitrary caret text and normalize searches", function()
    eq(B.CharacterName("Élenteriel^Mx"), "Élenteriel"); eq(B.CharacterName("Tienti^Fx"), "Tienti")
    eq(B.CharacterName("A^NotAMarker"), "A^NotAMarker")
    eq(B.Identity({ character = "Irishnelly^Fx" }, "NA"), B.Identity({ character = "Irishnelly" }, "NA"))
    assert(V.Search({ character = "Al Drakkon^Mx" }, "Al Drakkon"))
end)
test("cards calculate padded nonoverlapping bounds from fonts", function()
    reset(); local canvas = C:Canvas(U.body, 1110); canvas:Begin()
    canvas:Cards({ { label = "Match ability summaries", value = "100,000" }, { label = "Stored identities", value = "10,000" } }, 4)
    local panels, labels = canvas.pools.panel, canvas.pools.label
    for i = 1, 2 do
        local panel, caption, value = panels[i], labels[2 + (i - 1) * 2], labels[3 + (i - 1) * 2]
        assert(caption.anchor[5] >= panel.anchor[5] + 12)
        assert(value.anchor[5] >= caption.anchor[5] + caption.height + 4)
        assert(value.anchor[5] + value.height <= panel.anchor[5] + panel.height - 12)
    end
end)
test("adaptive scoreboard gives player names the spare width and keeps cells inside bounds", function()
    reset(1); U:OpenMatch(B.db.matches[1]); local t = U.canvas.tables[1]
    assert(t.columns[1].width >= 380); assert(t.contentWidth <= t.body.width)
    for j, col in ipairs(t.columns) do
        local cell = t.rowControls[1].labels[j]
        assert(cell.anchor[4] + cell.width <= t.body.width); eq(cell.alignment, t.headers[j].caption.alignment)
    end
    local fitted = C.LayoutColumns(t.columns, 900); local total = 0
    for _, col in ipairs(fitted) do assert(col.width > 0); total = total + col.width end
    assert(math.abs(total - 900) < 0.001)
end)
test("character filtering never uses another character on the same account", function()
    reset(2); B.db.matches[2].localCharacterId, B.db.matches[2].localCharacter = "alt", "Alt^Fx"
    B.db.matches[2].players[1].character = "Alt^Fx"
    local rows = currentRows(); eq(#rows, 1); eq(rows[1].id, "personal-1"); eq(rows[1].damage, 100)
    local s = P.Summary(rows); eq(s.metrics.damage.total, 100); eq(s.metrics.kills.total, 1)
end)
test("legacy local-name fallback is exact unique and server scoped", function()
    reset(3); B.db.matches[1].localCharacterId = nil
    B.db.matches[2].localCharacterId, B.db.matches[2].localCharacter, B.db.matches[2].players[1].character = nil, "Locally^Mx", "Locally^Mx"
    B.db.matches[3].world = "EU Megaserver"
    local rows = currentRows(); eq(#rows, 1); eq(rows[1].id, "personal-1")
    local m = fixture(7); m.players[1].isLocal = nil; eq(P.Player(m), m.players[1])
    m.players[2].character = "Local"; eq(P.Player(m), nil)
end)
test("stable character IDs associate observed renames without changing stored names", function()
    reset(2); local old = B.db.matches[1]; old.localCharacter, old.players[1].character = "Previous Name^Mx", "Previous Name^Mx"
    eq(#currentRows(), 2); eq(old.localCharacter, "Previous Name^Mx")
end)
test("ambiguous legacy names never join two distinct stable character IDs", function()
    reset(3); B.db.matches[1].localCharacterId = nil; B.db.matches[2].localCharacterId = "alt"
    local options, aliases, current = P.Index(); eq(aliases[GetWorldName() .. ":name:local"], false)
    eq(#P.Rows(current, 0, aliases), 1); eq(#options, 3)
end)
test("missing or ambiguous personal roster entries keep honest unavailable statistics", function()
    reset(2); B.db.matches[1].players[1].isLocal, B.db.matches[1].players[2].isLocal = true, true
    B.db.matches[2].localIdentityAmbiguous = true
    local rows = currentRows(); eq(#rows, 2); eq(rows[1].damage, nil); eq(rows[2].damage, nil)
    local s = P.Summary(rows); eq(s.metrics.damage, nil); eq(s.total, 2)
end)
test("last 10 25 50 and all filters select newest available records without duplicates", function()
    reset(61); B.db.matches[#B.db.matches + 1] = B.db.matches[61]
    for _, limit in ipairs({ 10, 25, 50, 0 }) do
        local rows = currentRows(limit); eq(#rows, limit == 0 and 61 or limit); eq(rows[1].id, "personal-61")
    end
    B.db.matches[1], B.db.matches[2] = B.db.matches[2], B.db.matches[1]
    eq(currentRows()[1].id, "personal-61")
end)
test("resolved win rate streaks and recent sequence use actual saved outcomes", function()
    reset(5); local outcomes = { "Unresolved", "Draw", "Loss", "Win", "Win" }
    for i, result in ipairs(outcomes) do B.db.matches[i].outcome = result end
    local s = P.Summary(currentRows()); eq(s.Win, 2); eq(s.Loss, 1); eq(s.Draw, 1); eq(s.Unresolved, 1); eq(s.winRate, 50)
    eq(s.streak.count, 2); eq(s.streak.outcome, "Win"); eq(table.concat(s.sequence), "WWLD?")
    B.db.matches[5].outcome = "Draw"; eq(P.Summary(currentRows()).streak, nil)
end)
test("missing metrics stay unavailable and zeroes contribute to sample counts", function()
    reset(3); B.db.matches[1].players[1].healing = nil; B.db.matches[2].players[1].healing = 0
    B.db.matches[3].players[1].damage = 0 / 0
    local s = P.Summary(currentRows()); eq(s.metrics.healing.count, 2); eq(s.metrics.healing.total, 3000); eq(s.metrics.healing.average, 1500)
    eq(s.metrics.damage.count, 2); eq(s.metrics.damage.total, 300)
end)
test("healer offensive and defensive summaries use only real local values", function()
    reset(2); B.db.matches[1].outcome = "Loss"
    local s = P.Summary(currentRows()); eq(s.metrics.healing.total, 3000); eq(s.metrics.damage.total, 300)
    eq(s.outcomes.Win.healing.average, 2000); eq(s.outcomes.Loss.healing.average, 1000)
    eq(s.metrics.damageTaken.total, 600); eq(s.metrics.shieldsGranted, nil); eq(s.kd, 0.75)
    eq(s.metrics.healing.best.row.id, "personal-2")
end)
test("objective totals never mix capture seconds and damage-taken units", function()
    reset(3); B.db.matches[2].objectiveLabel = "Ball carry time (seconds)"
    B.db.matches[3].objectiveLabel = "Damage taken (native Deathmatch objective column)"
    local s = P.Summary(currentRows()); eq(B.Count(s.objectives), 3)
    eq(s.objectives["Flags / objectives captured"].total, 1); eq(s.metrics.objective, nil)
end)
test("zero-death and incomplete K/D samples are never presented as infinity", function()
    reset(2); B.db.matches[1].players[1].deaths = 0; B.db.matches[2].players[1].deaths = nil
    local s = P.Summary(currentRows()); eq(s.kd, nil); eq(s.kdSamples, 1)
end)
test("personal trends require available samples in both periods", function()
    reset(11); local s = P.Summary(currentRows())
    eq(s.trend.recent.healing.count, 10); eq(s.trend.previous.healing.count, 1)
    s = P.Summary(currentRows(10)); eq(s.trend.previous.healing, nil)
end)
test("role and range persist per character without modifying snapshots or other roles", function()
    reset(2); local key = P.Current(); local prefs = P.Preferences(key); prefs.role, prefs.range = "TANK", 50
    local alt = P.Preferences(GetWorldName() .. ":id:alt"); eq(alt.role, "HEALER")
    local saved = B.db; B.Storage:Initialize(saved); eq(P.Preferences(key).role, "TANK"); eq(P.Preferences(key).range, 50)
    eq(B.db.matches[1].personalRole, nil); eq(B.db.schema, 1)
end)
test("personal preferences preserve future versions and use bounded character records", function()
    reset(); B.db.settings.personalHistory = { version = 99, sentinel = "keep" }
    eq(P.Preferences(P.Current()), nil); eq(B.db.settings.personalHistory.sentinel, "keep")
    B.db.settings.personalHistory = nil
    for i = 1, 140 do P.Preferences("character" .. i) end
    eq(B.Count(B.db.settings.personalHistory.characters), 128)
end)
test("all role views render sorted paginated personal rows with exact tooltips", function()
    reset(51); U:Open("STATISTICS"); click("BG History"); click("All retained matches")
    for _, role in ipairs({ "HEALER", "TANK", "DPS" }) do
        click(role); eq(P.Preferences(P.Current()).role, role); eq(#U.personalRows, 51); eq(#U.personalTable.rows, 40)
        assert(U.personalTable.rowControls[1].control.tip:find("healing: 51,000", 1, true))
    end
    U.personalTable.headers[8].handlers.OnClicked(); eq(U.personalSort, "damage")
    click("Next matches"); eq(#U.personalTable.rows, 11); eq(U.personalPage, 2)
    click("Last 10"); eq(#U.personalRows, 10); eq(U.personalPage, 1)
end)
test("personal match drilldown Back and role annotation preserve the selected history", function()
    reset(2); U:Open("STATISTICS"); click("BG History"); click("DPS")
    U.scroll:GetNamedChild("Scroll"):SetVerticalScroll(200)
    U.personalTable.scroll:GetNamedChild("Scroll"):SetVerticalScroll(60)
    U.personalTable.rowControls[1].control.handlers.OnClicked(); eq(U.section, "MATCHES"); eq(U.view, "scoreboard")
    click("HEALER"); eq(U.match.personalRole, "HEALER"); eq(P.Preferences(P.Current()).role, "DPS")
    U:Back(); eq(U.section, "STATISTICS"); eq(U.scroll:GetNamedChild("Scroll"):GetVerticalScroll(), 200)
    eq(U.personalTable.scroll:GetNamedChild("Scroll"):GetVerticalScroll(), 60)
    eq(U.personalRows[1].role, "HEALER"); eq(U.personalRows[2].role, "Unclassified")
    U:Open("PLAYERS"); eq(U.personalSelector.control:IsHidden(), true)
end)
test("existing records remain available and pruning only reduces retained personal detail", function()
    reset(20); local old = B.db.matches[1]; old.localCharacterId = nil; old.players[1].character = "Local^Fx"
    B.db.stats.total, B.db.stats.Win = 100, 70
    local saved = B.db; B.Storage:Initialize(saved); U:Open("STATISTICS"); click("BG History")
    eq(#U.personalRows, 20); eq(old.players[1].character, "Local^Fx"); eq(B.db.stats.total, 100)
    B.db.settings.historyLimit = 10; B.Storage:Prune(); eq(#currentRows(), 10); eq(B.db.stats.total, 100)
end)
test("empty personal history and all missing field views render without fabricated values", function()
    reset(); U:Open("STATISTICS"); click("BG History"); eq(#U.personalRows, 0)
    B.db.matches[1] = fixture(1); B.db.matches[1].players = {}; U:Render(true)
    for _, role in ipairs({ "HEALER", "TANK", "DPS" }) do click(role); eq(U.personalSummary.metrics.healing, nil) end
end)
test("date sorting toggles immediately and unknown dates stay unavailable", function()
    reset(3); B.db.matches[1].finishedAt = "old invalid timestamp"
    U:Open("STATISTICS"); click("BG History"); eq(U.personalTable.rows[1].id, "personal-3")
    U.personalTable.headers[1].handlers.OnClicked(); eq(U.personalDescending, false)
    eq(U.personalTable.rows[1].id, "personal-2"); eq(U.personalTable.rows[3].finishedAt, nil)
end)
test("personal view pools stabilize after role changes and clear empty summaries", function()
    reset(60); U:Open("STATISTICS"); click("BG History")
    for _, role in ipairs({ "HEALER", "TANK", "DPS", "HEALER" }) do click(role) end
    local count = C.serial; for _ = 1, 10 do U:Render(true) end; eq(C.serial, count)
    B.db.matches = {}; U:Render(true); eq(U.personalSummary, nil); eq(U.personalTable, nil); eq(#U.personalRows, 0)
end)
print(passed .. " personal-history/polish tests passed (mock ESO; native visual verification required).")
