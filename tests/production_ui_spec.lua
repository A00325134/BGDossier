-- Native-template routing is simulated here; physical ESO keyboard input and
-- rasterized fonts remain explicit in-game acceptance gates.
local B, U, C = BattlegroundDossier, BattlegroundDossier.UI, BattlegroundDossier.Controls
local passed = 0
local function test(label, fn)
    local ok, err = pcall(fn); assert(ok, label .. ": " .. tostring(err)); passed = passed + 1; print("PASS production UI " .. label)
end
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function setup()
    if WINDOW_MANAGER.focus then WINDOW_MANAGER.focus:LoseFocus() end
    C:CancelNumeric(); B.Match:Stop(); B.Match.session = nil; engine.characterId = "production-ui"
    GuiRoot:SetDimensions(1920, 1080); B.Storage:Initialize({}); B.LiveSession:Initialize(); U:Initialize(); U:Open("SETTINGS")
end
local function editor(key, store)
    for _, c in ipairs(U.canvas.pools.number or {}) do
        if not c:IsHidden() and c.settingKey == key and (not store or c.settingStore == store) then return c end
    end
    error("No editor " .. key)
end
local function clickEdit(c) c.handlers.OnMouseDown(c) end
local function key(command, text) assert(WINDOW_MANAGER:SimulateEditKey(command, text), command .. " did not reach a focused editable control") end
local function click(text)
    for _, button in ipairs(U.canvas.pools.button or {}) do
        if not button:IsHidden() and button:GetLabelControl():GetText() == text then button.handlers.OnClicked(button); return end
    end
    error("No button " .. text)
end
local function fixture()
    return { id = "production-ui", map = "Arena", world = GetWorldName(), localCharacter = "Local^Mx", localCharacterId = engine.characterId,
        modeName = "Domination", mode = BATTLEGROUND_GAME_TYPE_DOMINATION, outcome = "Win", finishedAt = 1800000000,
        localTeam = 1, teamCount = 2, teamCapacity = 4, objectiveLabel = "Flags captured", rounds = {},
        teams = { [1] = { name = "Allies", result = "Win", score = 500 }, [2] = { name = "Opponents", result = "Loss", score = 200 } },
        players = { { character = "Local^Mx", account = "@local", isLocal = true, team = 1, classId = 1, kills = 5, deaths = 2, assists = 9, damage = 45000, healing = 80000, score = 100, abilities = {}, medals = {} },
            { character = "A Very Long Character Name With Accents Éire^Fx", account = "@opponent", team = 2, classId = 2, kills = 3, deaths = 4, assists = 2, damage = 40000, abilities = {}, medals = {} } } }
end
test("bare mouse-enabled edit does not magically route keys without native focus behavior", function()
    setup(); local bare = C:New(U.body, CT_EDITBOX); bare:SetMouseEnabled(true); bare:SetKeyboardEnabled(true); bare:SetEditEnabled(true)
    eq(bare.handlers.OnMouseDown, nil); eq(WINDOW_MANAGER:SimulateEditKey("type", "500"), false)
    local e = editor("historyLimit"); eq(e.template, "ZO_DefaultEdit"); assert(e.keyboardEnabled and e.editEnabled and e.copyEnabled and e.pasteEnabled)
    clickEdit(e); eq(WINDOW_MANAGER.focus, e); eq(C.activeNumeric, e); key("type", "500"); eq(e:GetText(), "500")
end)
test("real click focus plus select-all replacement and Enter updates 200 to 500", function()
    setup(); local e = editor("historyLimit"); clickEdit(e); key("selectAll"); key("type", "500")
    eq(B.db.settings.historyLimit, 200); key("enter"); eq(B.db.settings.historyLimit, 500); eq(e:GetText(), "500"); eq(e:HasFocus(), false)
    local saved = B.db; assert(B.Storage:Initialize(saved)); U:Initialize(); U:Open("SETTINGS"); eq(editor("historyLimit"):GetText(), "500")
end)
test("Backspace Delete and cursor insertion modify native edit text before cancellation", function()
    setup(); local e = editor("historyLimit"); clickEdit(e); key("type", "500"); key("backspace"); eq(e:GetText(), "50")
    e:SetCursorPosition(0); key("delete"); eq(e:GetText(), "0"); key("type", "7"); eq(e:GetText(), "70")
    eq(B.db.settings.historyLimit, 200); key("escape"); eq(e:GetText(), "200"); eq(B.db.settings.historyLimit, 200)
end)
test("paste reaches focused editor but invalid values never commit", function()
    setup(); local e = editor("historyLimit"); clickEdit(e); key("paste", "1000"); eq(e:GetText(), "1000"); key("enter"); eq(B.db.settings.historyLimit, 1000)
    for _, text in ipairs({ "", "invalid", "-10", "1001" }) do
        clickEdit(e); key("selectAll"); key("paste", text); key("enter"); eq(B.db.settings.historyLimit, 1000); eq(e:GetText(), "1000")
    end
end)
test("every numeric field receives click typing and paste including HUD decimals", function()
    setup()
    for _, item in ipairs({ { "scale", B.db.settings, "0.9", 0.9 }, { "frequentThreshold", B.db.settings, "7", 7 },
        { "historyLimit", B.db.settings, "500", 500 }, { "profileLimit", B.db.settings, "15000", 15000 },
        { "scale", B.LiveSession.preferences, "1.25", 1.25 }, { "opacity", B.LiveSession.preferences, "0.35", 0.35 } }) do
        local e = editor(item[1], item[2]); clickEdit(e); key("selectAll"); key("paste", item[3]); key("enter"); eq(item[2][item[1]], item[4])
    end
end)
test("per-keystroke layout never saves prunes rerenders or loses keyboard focus", function()
    setup(); for i = 1, 35 do local m = fixture(); m.id = "production-" .. i; B.db.matches[i] = m end
    local e = editor("historyLimit"); local serial = C.serial; clickEdit(e); key("selectAll"); key("backspace")
    for _, digit in ipairs({ "1", "0", "0", "0" }) do
        key("type", digit); U:RefreshIfChanged(); eq(B.db.settings.historyLimit, 200); eq(#B.db.matches, 35); eq(WINDOW_MANAGER.focus, e); eq(C.serial, serial)
    end
    key("enter"); eq(B.db.settings.historyLimit, 1000); eq(#B.db.matches, 35)
    clickEdit(e); key("selectAll"); key("type", "10"); key("enter"); eq(B.db.settings.historyLimit, 10); eq(#B.db.matches, 10)
end)
test("committing by focus transfer keeps the next field alive and editable", function()
    setup(); local first, second = editor("historyLimit"), editor("profileLimit"); clickEdit(first); key("type", "500")
    local serial = C.serial; clickEdit(second); eq(B.db.settings.historyLimit, 500); eq(C.serial, serial); eq(WINDOW_MANAGER.focus, second)
    key("type", "15000"); key("enter"); eq(B.db.settings.profileLimit, 15000)
end)
test("whole value cell is clickable and has focus feedback", function()
    setup(); local e = editor("historyLimit"); local frame = e.inputPanel
    frame.handlers.OnMouseDown(frame); eq(WINDOW_MANAGER.focus, e); eq(frame.background.edgeColor[1], C.theme.gold[1])
    key("escape"); eq(frame.background.edgeColor[1], C.theme.border[1])
end)
test("text editors reserve native keyboard focus from addon toggle actions", function()
    setup(); local e = editor("historyLimit"); clickEdit(e); local hud = B.LiveSession.preferences.visible
    B.Keybindings:Toggle(); B.Keybindings:ToggleHUD(); eq(U.window:IsHidden(), false); eq(B.LiveSession.preferences.visible, hud)
    key("type", "500"); key("escape"); B.Keybindings:Toggle(); eq(U.window:IsHidden(), true)
end)
test("centered editor tracks measured text without moving plus/minus symmetry", function()
    setup(); local e = editor("profileLimit"); local b = e.bounds
    local function centered() assert(math.abs(e.anchor[4] + e.width / 2 - b.x - b.width / 2) < 0.01) end
    centered(); clickEdit(e); key("type", "20000"); centered(); key("backspace"); centered()
    local minus, plus
    for _, button in ipairs(U.canvas.pools.button) do
        if not button:IsHidden() and button.anchor[5] == b.y then
            if button:GetLabelControl():GetText() == "−" then minus = button elseif button:GetLabelControl():GetText() == "+" then plus = button end
        end
    end
    assert(minus and plus); eq(minus.width, plus.width)
    eq(b.x - minus.anchor[4] - minus.width, plus.anchor[4] - b.x - b.width)
    key("escape")
end)
test("boundary step buttons have disabled styling and pool reuse restores enabled state", function()
    setup(); local e = editor("historyLimit"); clickEdit(e); key("type", "1000"); key("enter")
    local plus
    for _, button in ipairs(U.canvas.pools.button) do if not button:IsHidden() and button:GetLabelControl():GetText() == "+" and button.anchor[5] == e.bounds.y then plus = button end end
    eq(plus.enabled, false); plus.handlers.OnClicked(plus); eq(B.db.settings.historyLimit, 1000)
    clickEdit(e); key("type", "500"); key("enter"); eq(plus.enabled, true); plus.handlers.OnClicked(plus); eq(B.db.settings.historyLimit, 550)
end)
test("cards center labels and values with full-value tips", function()
    setup(); local canvas = C:Canvas(U.body, 1110); canvas:Begin(); canvas:Cards({ { label = "Retained matches", value = "1,000" } })
    eq(canvas.pools.label[2].alignment, TEXT_ALIGN_CENTER); eq(canvas.pools.label[3].alignment, TEXT_ALIGN_CENTER)
    eq(canvas.pools.label[3].verticalAlignment, TEXT_ALIGN_CENTER); eq(canvas.pools.label[3].tip, "1,000")
end)
test("compact columns center while large totals stay right aligned with identical headings", function()
    setup(); local m = fixture(); B.Storage:Commit(m); U:OpenMatch(m); local t = U.canvas.tables[1]
    for i, col in ipairs(t.columns) do
        local expected = (col.key == "kills" or col.key == "deaths" or col.key == "assists" or col.key == "team") and TEXT_ALIGN_CENTER
            or col.numeric and TEXT_ALIGN_RIGHT or TEXT_ALIGN_LEFT
        eq(t.headers[i].caption.alignment, expected); eq(t.rowControls[1].labels[i].alignment, expected)
    end
    assert(t.columns[1].width >= 380); assert(t.contentWidth <= t.body.width)
    eq(t.headers[1].height, C.layout.buttonHeight); eq(t.rowControls[1].control.height, C.layout.rowHeight)
end)
test("table fallback tooltips retain exact raw values and long truncated text", function()
    setup(); local tableView = C:Table(U.body)
    local name = "An exceptionally long localized character name"
    tableView:Bind({ { title = "PLAYER", key = "name", width = 100 }, { title = "VALUE", key = "value", width = 100, numeric = true, text = function() return "2.4M" end } },
        { { name = name, value = 2400001 } }, {}, 224)
    assert(tableView.rowControls[1].control.tip:find(name, 1, true)); assert(tableView.rowControls[1].control.tip:find("2400001", 1, true))
end)
test("search uses native focus and preserves unfinished text during debounce renders", function()
    setup(); U:Open("PLAYERS"); clickEdit(U.searchBox); key("type", "Éire Account")
    eq(U.searchBox:GetText(), "Éire Account"); EVENT_MANAGER.updates[B.name .. "Search"]()
    eq(U.searchBox:GetText(), "Éire Account"); eq(WINDOW_MANAGER.focus, U.searchBox)
    B.Keybindings:Toggle(); eq(U.window:IsHidden(), false); key("escape"); eq(C:IsEditing(), false)
end)
test("leaving a search view cancels its pending redraw before numeric editing", function()
    setup(); U:Open("PLAYERS"); clickEdit(U.searchBox); key("type", "local")
    assert(EVENT_MANAGER.updates[B.name .. "Search"])
    U:Open("SETTINGS"); eq(EVENT_MANAGER.updates[B.name .. "Search"], nil)
    local e = editor("historyLimit"); clickEdit(e); key("type", "500"); U:RefreshIfChanged()
    eq(e:GetText(), "500"); eq(WINDOW_MANAGER.focus, e); eq(B.db.settings.historyLimit, 200)
    key("escape")
end)
test("all major views retain bounded table geometry and aligned controls at normal scales", function()
    setup(); local m = fixture(); B.Storage:Commit(m)
    for _, scale in ipairs({ 0.6, 0.85, 1.2 }) do
        B.db.settings.scale = scale; U:ApplyScale()
        for _, section in ipairs({ "MATCHES", "PLAYERS", "STATISTICS", "SETTINGS" }) do
            U:Open(section)
            if section == "STATISTICS" then
                click("BG History"); for _, role in ipairs({ "HEALER", "TANK", "DPS" }) do click(role) end
            end
            for _, t in ipairs(U.canvas.tables) do if not t.control:IsHidden() then assert(t.contentWidth <= t.body.width + 0.01) end end
        end
        U:OpenMatch(m); U:OpenDossier(m, m.players[2])
        for _, tab in ipairs({ "Overview", "Observed abilities", "History", "Scoreboard details" }) do U.dossierTab = tab; U:Render() end
        U.compareA, U.compareB, U.view, U.expanded = m.players[1], m.players[2], "comparison", nil; U:Render()
    end
end)
test("rendered scale fits root dimensions without overwriting requested scale", function()
    setup(); B.db.settings.scale = 1.2; GuiRoot:SetDimensions(1280, 720)
    EVENT_MANAGER.events[B.name .. "UIResize:" .. EVENT_SCREEN_RESIZED]()
    assert(U.window.scale * 800 <= 696.01); assert(U.window.scale * 1180 <= 1256.01); eq(B.db.settings.scale, 1.2)
    GuiRoot:SetDimensions(1920, 1080); EVENT_MANAGER.events[B.name .. "UIResize:" .. EVENT_SCREEN_RESIZED](); eq(U.window.scale, 1.2)
end)
test("HUD captions and values have separate measured vertical bounds", function()
    setup(); local live = B.LiveSession
    for _, header in ipairs({ true, false }) do
        live.preferences.header = header; live:ApplyPreferences()
        for _, section in ipairs(live.sections) do
            assert(section.label.anchor[5] + section.label.height <= section.value.anchor[5])
            assert(section.value.anchor[5] + section.value.height <= live.window.height - 6)
            eq(section.value.alignment, TEXT_ALIGN_CENTER)
        end
    end
end)
test("button hover reads native label text and never calls unsupported Button GetText", function()
    setup(); local clicked, shown
    local oldTooltip = SetTooltipText
    SetTooltipText = function(_, text) shown = text end
    local button = C:Button(U.body, "Short", 0, 0, 120, function() clicked = true end)
    eq(button.GetText, nil); eq(button:GetLabelControl():GetText(), "Short")
    local ok = pcall(function() return button:GetText() end); eq(ok, false)
    button.handlers.OnMouseEnter(button); eq(shown, nil)
    local long = "A long button label that must have a full tooltip"
    button:SetText(long); button.handlers.OnMouseEnter(button); eq(shown, long)
    button.handlers.OnMouseExit(button); button.handlers.OnClicked(button); eq(clicked, true)
    C:Tooltip(button, function() return "Explicit tooltip" end)
    button.handlers.OnMouseEnter(button); eq(shown, "Explicit tooltip")
    SetTooltipText = oldTooltip
end)
test("shared hover handler remains safe for tabs settings roles and sort headers", function()
    setup(); local m = fixture(); B.Storage:Commit(m)
    local function hover(button)
        button.handlers.OnMouseEnter(button); button.handlers.OnMouseExit(button)
    end
    local function hoverVisible()
        for _, tab in pairs(U.tabs) do hover(tab) end
        for _, button in ipairs(U.canvas.pools.button or {}) do if not button:IsHidden() then hover(button) end end
        for _, tableView in ipairs(U.canvas.tables) do
            if not tableView.control:IsHidden() then for _, header in ipairs(tableView.headers) do if not header:IsHidden() then hover(header) end end end
        end
    end
    for _, section in ipairs({ "MATCHES", "PLAYERS", "STATISTICS", "SETTINGS" }) do
        U:Open(section); hoverVisible()
        if section == "STATISTICS" then click("BG History"); hoverVisible(); click("TANK"); hoverVisible() end
    end
    U:OpenMatch(m); hoverVisible(); U:OpenDossier(m, m.players[2]); hoverVisible()
end)
test("Match History removes only PLACE and fills its space without mutating saved placement", function()
    setup(); local m = fixture(); m.placement = 2; B.Storage:Commit(m)
    U:OpenMatch(m); U:Open("MATCHES"); local t = U.canvas.tables[1]
    eq(#t.columns, 7); eq(#t.rows, 1); assert(t.columns[1].width >= 315)
    assert(math.abs(t.contentWidth - t.body.width) < 0.01)
    local visible = 0
    for _, header in ipairs(t.headers) do if not header:IsHidden() then visible = visible + 1; assert(not header.caption:GetText():find("PLACE", 1, true)) end end
    eq(visible, 7)
    for _, col in ipairs(t.columns) do assert(col.key ~= "placement") end
    for i = 8, #t.rowControls[1].labels do eq(t.rowControls[1].labels[i]:IsHidden(), true) end
    eq(m.placement, 2); eq(B.db.matches[1].placement, 2)
    t.rowControls[1].control.handlers.OnClicked(); eq(U.view, "scoreboard"); eq(U.match, m); eq(U.match.placement, 2)
end)
print(passed .. " production UI tests passed (simulated native input; physical ESO testing still required).")
