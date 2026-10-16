local B, C, V = BattlegroundDossier, BattlegroundDossier.Controls, BattlegroundDossier.ViewData
B.UI = { section = "MATCHES", view = "history", sort = "score", descending = true, teamFilter = "All players",
    search = "", page = 1, filters = { result = "All results", mode = "All modes", format = "All formats" },
    states = {}, abilitySorts = {}, abilityPages = {}, abilityCache = {}, iconCache = {}, classIcons = {} }
local U, T = B.UI, C.theme
local sections = { "MATCHES", "PLAYERS", "STATISTICS", "SETTINGS" }
function U:Preferences()
    -- Additive presentation preferences; existing settings/schema and all recorded data stay intact.
    local prefs = B.db.settings.presentation
    if type(prefs) ~= "table" then prefs = {}; B.db.settings.presentation = prefs end
    if type(prefs.compactNumbers) ~= "boolean" then prefs.compactNumbers = true end
    if type(prefs.abilityIcons) ~= "boolean" then prefs.abilityIcons = true end
    local validTab = false; for _, s in ipairs(sections) do if s == prefs.defaultTab then validTab = true end end
    if not validTab then prefs.defaultTab = "MATCHES" end
    return prefs
end
function U:Initialize()
    local prefs = self:Preferences()
    self.section, self.view = prefs.defaultTab, "history"
    self.states, self.abilitySorts, self.abilityPages, self.abilityCache = {}, {}, {}, {}
    local w = WINDOW_MANAGER:CreateTopLevelWindow("BattlegroundDossierWindow"); self.window = w
    w:SetDimensions(1180, 800); w:SetClampedToScreen(true); w:SetMovable(true); w:SetMouseEnabled(true)
    w:SetHidden(true); w:SetScale(B.db.settings.scale); self:Position(); C:Backdrop(w, T.background)
    C:Label(w, "BATTLEGROUND DOSSIER", 28, 13, 850, 38, "ZoFontWinH1"):SetColor(unpack(T.gold))
    self.sectionLabel = C:Label(w, "", 30, 54, 1000, 26, "ZoFontGame")
    C:Button(w, "×", 1114, 20, 40, function() self:SetVisible(false) end)
    w:SetHandler("OnMoveStop", function(control) B.db.settings.position = { x = control:GetLeft(), y = control:GetTop() } end)
    SCENE_MANAGER:RegisterTopLevel(w, false)
    self.tabs = {}
    for i, section in ipairs(sections) do
        local target = section
        self.tabs[section] = C:Button(w, section, 24 + (i - 1) * 170, 92, 158, function() self:Open(target) end)
    end
    self.backButton = C:Button(w, "‹ Back", 884, 92, 126, function() self:Back() end)
    C:Button(w, "Latest match", 1020, 92, 136, function() self:Last() end)
    self.toolbar = C:New(w, CT_CONTROL); C:Place(self.toolbar, w, 24, 137, 1132, 72); C:Backdrop(self.toolbar)
    self.searchLabel = C:Label(self.toolbar, "SEARCH PLAYERS / ACCOUNTS", 12, 0, 280, 28, "ZoFontGame")
    self.searchBox = C:Search(self.toolbar, 12, 29, 295, function(text)
        if self.bindingSearch then return end
        self.search = B.Normalize(text) or ""; self.page = 1
        EVENT_MANAGER:UnregisterForUpdate(B.name .. "Search")
        if self.window:IsHidden() then return end
        EVENT_MANAGER:RegisterForUpdate(B.name .. "Search", 180, function()
            EVENT_MANAGER:UnregisterForUpdate(B.name .. "Search"); if not self.window:IsHidden() then self:Render(false) end
        end)
    end)
    self.dropdowns, self.dropLabels = {}, {}
    for i, width in ipairs({ 155, 238, 230 }) do
        local x = ({ 320, 487, 737 })[i]
        self.dropLabels[i] = C:Label(self.toolbar, "", x, 0, width, 28, "ZoFontGame")
        self.dropdowns[i] = C:Dropdown(self.toolbar, x, 29, width)
    end
    self.clearButton = C:Button(self.toolbar, "Clear filters", 982, 29, 138, function() self:ClearFilters() end)
    self.contextLabel = C:Label(self.toolbar, "", 12, 16, 1095, 40, "ZoFontGame")
    self.scroll = C:New(w, nil, "ZO_ScrollContainer")
    self.scroll:SetAnchor(TOPLEFT, w, TOPLEFT, 24, 220); self.scroll:SetAnchor(BOTTOMRIGHT, w, BOTTOMRIGHT, -24, -42)
    self.body = self.scroll:GetNamedChild("ScrollChild"); self.body:SetResizeToFitDescendents(false); self.body:SetDimensions(1110, 520)
    self.canvas = C:Canvas(self.body, 1110)
    self.footer = C:Label(w, "Client-visible observations • Event counts are not casts • Team results are not duels", 30, 763, 1115, 26, "ZoFontGame")
    self.footer:SetColor(unpack(T.muted))
    w:SetHandler("OnEffectivelyShown", function()
        EVENT_MANAGER:RegisterForUpdate(B.name .. "ViewRefresh", 1500, function() self:RefreshIfChanged() end)
    end)
    w:SetHandler("OnEffectivelyHidden", function()
        EVENT_MANAGER:UnregisterForUpdate(B.name .. "ViewRefresh"); EVENT_MANAGER:UnregisterForUpdate(B.name .. "Search")
        self.searchBox:LoseFocus(); ClearTooltip(InformationTooltip)
    end)
    EVENT_MANAGER:RegisterForEvent(B.name .. "UICombat", EVENT_PLAYER_COMBAT_STATE, function(_, combat) if combat then self:SetVisible(false) end end)
end
function U:Number(value) return V.Number(value, B.db.settings.presentation and B.db.settings.presentation.compactNumbers) end
function U:Position()
    self.window:ClearAnchors(); local p = B.db.settings.position
    if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" then self.window:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, p.x, p.y)
    else self.window:SetAnchor(CENTER, GuiRoot, CENTER, 0, 0) end
end
function U:SetVisible(visible)
    if visible then SCENE_MANAGER:ShowTopLevel(self.window)
    else
        self.searchBox:LoseFocus(); ClearTooltip(InformationTooltip)
        EVENT_MANAGER:UnregisterForUpdate(B.name .. "Search"); EVENT_MANAGER:UnregisterForUpdate(B.name .. "ViewRefresh")
        SCENE_MANAGER:HideTopLevel(self.window)
    end
end
function U:RefreshIfChanged()
    if self.window:IsHidden() or B.API:Call("IsUnitInCombat", "player") then return end
    if self.seenMatches ~= B.db.matches or self.seenProfiles ~= B.db.profiles or self.seenLast ~= B.db.matches[#B.db.matches] or self.seenTotal ~= B.db.stats.total or self.seenSettings ~= self:SettingsStamp() then
        self.abilityCache = {}; self:Render(true)
    end
end
function U:SettingsStamp()
    local settings, parts = B.db.settings, {}
    for _, key in ipairs({ "debug", "autoOpen", "notifications", "observeCombat", "scale", "historyLimit", "profileLimit", "frequentThreshold" }) do parts[#parts + 1] = tostring(settings[key]) end
    local prefs = settings.presentation or {}
    for _, key in ipairs({ "compactNumbers", "abilityIcons", "defaultTab" }) do parts[#parts + 1] = tostring(prefs[key]) end
    return table.concat(parts, ":")
end
function U:SaveState()
    if not self.scroll then return end
    if self.section == "MATCHES" and self.view ~= "history" or self.section == "PLAYERS" and self.profile then return end
    local tableView = self.canvas and self.canvas.tableUsed > 0 and self.canvas.tables[1]
    self.states[self.section] = { page = self.page, search = self.search, scroll = self.scroll:GetNamedChild("Scroll"):GetVerticalScroll(),
        tableScroll = tableView and tableView.scroll:GetNamedChild("Scroll"):GetVerticalScroll() or 0 }
end
function U:RestoreScroll(state)
    state = state or {}; self.scroll:GetNamedChild("Scroll"):SetVerticalScroll(state.scroll or 0)
    if self.canvas.tableUsed > 0 then self.canvas.tables[1].scroll:GetNamedChild("Scroll"):SetVerticalScroll(state.tableScroll or 0) end
end
function U:Open(section)
    self:SaveState(); self.section = section or self.section
    local state = self.states[self.section] or {}
    self.page, self.search = state.page or 1, state.search or ""
    if section == "MATCHES" then self.view, self.expanded = "history", nil end
    if section == "PLAYERS" then self.profile = nil end
    self:SetVisible(true); self:Render(); self:RestoreScroll(state)
end
function U:Toggle() if self.window:IsHidden() then self:SetVisible(true); self:Render(true) else self:SetVisible(false) end end
function U:Last()
    for i = #B.db.matches, 1, -1 do if B.Storage:Valid(B.db.matches[i]) then self:OpenMatch(B.db.matches[i]); return end end
    self:Open("MATCHES")
end
function U:OpenMatch(m)
    if self.section == "MATCHES" and self.view == "history" then self:SaveState() end
    self.section, self.view, self.match = "MATCHES", "scoreboard", m
    self.expanded, self.compareA, self.compareB, self.search, self.page = nil, nil, nil, "", 1
    self.rosterState, self.selectedPlayer = nil, nil
    self.teamFilter = "All players"; self.abilityCache = {}; self:SetVisible(true); self:Render()
end
function U:Back()
    if self.section == "MATCHES" and self.view ~= "history" then
        if self.view == "dossier" or self.view == "comparison" then self.view, self.expanded = "scoreboard", nil; self:Render(); self:RestoreScroll(self.rosterState)
        else
            self.view, self.expanded = "history", nil
            local state = self.states.MATCHES or {}; self.page, self.search = state.page or 1, state.search or ""
            self:Render(); self:RestoreScroll(state)
        end
    elseif self.section == "PLAYERS" and self.profile then
        self.profile = nil; self:Render(); self:RestoreScroll(self.states.PLAYERS)
    else self:Open("MATCHES") end
end
function U:ClearFilters()
    self.filters = { result = "All results", mode = "All modes", format = "All formats" }
    self.teamFilter, self.search, self.page = "All players", "", 1; self:Render()
end
function U:CycleFilter()
    local choices = { "All players", "My team", "Opposing teams", "Familiar players" }
    for i, value in ipairs(choices) do if value == self.teamFilter then self.teamFilter = choices[i % #choices + 1]; break end end
    self:Render()
end
function U:Toolbar()
    local history = self.section == "MATCHES" and self.view == "history"
    local roster = self.section == "MATCHES" and self.view == "scoreboard"
    local players = self.section == "PLAYERS" and not self.profile
    local searchable = history or roster or players
    self.searchLabel:SetHidden(not searchable); self.searchBox.container:SetHidden(not searchable)
    self.clearButton:SetHidden(not searchable); self.contextLabel:SetHidden(searchable)
    self.bindingSearch = true; self.searchBox:SetText(self.search); self.bindingSearch = false
    for i = 1, 3 do self.dropLabels[i]:SetHidden(true); self.dropdowns[i].control:SetHidden(true) end
    local function dropdown(index, title, options, selected, callback)
        self.dropLabels[index]:SetText(title); self.dropLabels[index]:SetHidden(false); self.dropdowns[index].control:SetHidden(false)
        C:Options(self.dropdowns[index], options, selected, callback)
    end
    if history then
        dropdown(1, "RESULT", { "All results", "Win", "Loss", "Draw", "Unresolved" }, self.filters.result, function(v) self.filters.result = v; self.page = 1; self:Render() end)
        local modes, formats = {}, {}
        for _, m in ipairs(B.db.matches) do if B.Storage:Valid(m) then modes[m.modeName or "Unknown mode"] = true; formats[V.Format(m)] = true end end
        local modeOptions, formatOptions = { "All modes" }, { "All formats", "Competitive", "Big Team Battles" }
        local sorted = {}; for mode in pairs(modes) do sorted[#sorted + 1] = mode end; table.sort(sorted); for _, v in ipairs(sorted) do modeOptions[#modeOptions + 1] = v end
        sorted = {}; for f in pairs(formats) do sorted[#sorted + 1] = f end; table.sort(sorted); for _, v in ipairs(sorted) do formatOptions[#formatOptions + 1] = v end
        dropdown(2, "GAME MODE", modeOptions, self.filters.mode, function(v) self.filters.mode = v; self.page = 1; self:Render() end)
        dropdown(3, "FORMAT", formatOptions, self.filters.format, function(v) self.filters.format = v; self.page = 1; self:Render() end)
    elseif roster then
        local options = { "All players", "My team", "Opposing teams", "Familiar players" }
        local ids = {}; for id in pairs(self.match.teams) do ids[#ids + 1] = id end; table.sort(ids)
        for _, id in ipairs(ids) do options[#options + 1] = { value = "team:" .. id, label = self.match.teams[id].name } end
        dropdown(2, "TEAM / RECOGNITION", options, self.teamFilter, function(v) self.teamFilter = v; self:Render() end)
    elseif players then
        self.contextLabel:SetHidden(false); self.contextLabel:SetText("Search known accounts and character aliases. Select a row to open its dossier.")
        C:Place(self.contextLabel, self.toolbar, 330, 19, 640, 40)
    else
        C:Place(self.contextLabel, self.toolbar, 12, 16, 1095, 40)
        self.contextLabel:SetText(self.section == "MATCHES" and self.view == "comparison" and "Compare recorded match totals. Differences are A minus B; no overall player rating is assigned."
            or self.section == "SETTINGS" and "Settings apply immediately. Your saved match records and observations remain compatible."
            or self.section == "STATISTICS" and "Lifetime records and trends from retained matches. Missing values remain unavailable."
            or "Player dossier • Observations describe activity visible to your client, not a confirmed equipped build.")
    end
end
function U:Render(preserveScroll)
    if not self.canvas then return end
    self:Preferences()
    ClearTooltip(InformationTooltip); self.canvas:Begin(); self:Toolbar()
    for _, section in ipairs(sections) do C:ButtonStyle(self.tabs[section], section == self.section) end
    self.sectionLabel:SetText(self.section .. "  /  " .. (self.section == "MATCHES" and string.upper(self.view) or self.section == "PLAYERS" and self.profile and "PLAYER DOSSIER" or "OVERVIEW"))
    self.backButton:SetHidden(not (self.section == "MATCHES" and self.view ~= "history" or self.section == "PLAYERS" and self.profile))
    self.resetTables = not preserveScroll
    if self.section == "MATCHES" then
        if self.view == "comparison" and self.match then self:Comparison(self.match)
        elseif (self.view == "dossier" or self.expanded) and self.match and self.expanded then self:Dossier(self.match, self.expanded)
        elseif self.view == "scoreboard" and self.match then self:Scoreboard(self.match)
        else self:History() end
    elseif self.section == "PLAYERS" then self:Players()
    elseif self.section == "STATISTICS" then self:Statistics()
    else self:Settings() end
    self.body:SetHeight(math.max(510, self.canvas.y + 12))
    if not preserveScroll then self.scroll:GetNamedChild("Scroll"):SetVerticalScroll(0) end
    self.seenMatches, self.seenProfiles, self.seenLast, self.seenTotal = B.db.matches, B.db.profiles, B.db.matches[#B.db.matches], B.db.stats.total
    self.seenSettings = self:SettingsStamp()
end
function U:Pager(rows, size)
    size = size or 40; local pages = math.max(1, math.ceil(#rows / size)); self.page = math.max(1, math.min(self.page, pages))
    local c = self.canvas
    c:Button("‹ Previous", 12, c.y, 125, function() self.page = math.max(1, self.page - 1); self:Render() end)
    c:Button("Next ›", 147, c.y, 125, function() self.page = math.min(pages, self.page + 1); self:Render() end)
    c:Label("Page " .. self.page .. " / " .. pages .. "    •    " .. #rows .. " records", 290, c.y, 700, 34, "ZoFontGame", T.muted); c.y = c.y + 44
    local slice = {}; for i = (self.page - 1) * size + 1, math.min(#rows, self.page * size) do slice[#slice + 1] = rows[i] end
    return slice
end
function U:TeamColor(m, p)
    if B.TeamRelation(m, p) == "unknown" then return C.theme.muted end
    local color = B.API:Call("GetBattlegroundTeamColor", p.team)
    if color and color.UnpackRGB then local r, g, b = color:UnpackRGB(); return { r * 0.75, g * 0.75, b * 0.75, 1 } end
    return p.team == m.localTeam and T.ally or T.enemy
end
function U:ClassIcon(p)
    if not p.classId then return nil end
    if self.classIcons[p.classId] == nil then
        local index = B.API:Call("GetClassIndexById", p.classId)
        local texture
        if index and type(GetClassInfo) == "function" then
            local ok, id, _, normal, _, _, _, ingame = pcall(GetClassInfo, index)
            if ok and id == p.classId then texture = ingame or normal end
        end
        self.classIcons[p.classId] = type(texture) == "string" and texture ~= "" and texture or false
    end
    return self.classIcons[p.classId] or nil
end
function U:AbilityIcon(id)
    if not B.db.settings.presentation.abilityIcons then return nil end
    if self.iconCache[id] == nil then
        local texture = type(id) == "number" and B.API:Call("GetAbilityIcon", id)
        -- No speculative replacement icon. The row retains consistent padding with a neutral swatch.
        if B.Count(self.iconCache) > 512 then self.iconCache = {} end
        self.iconCache[id] = type(texture) == "string" and texture ~= "" and texture or false
    end
    return self.iconCache[id] or nil
end
