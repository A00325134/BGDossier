local B, C, V = BattlegroundDossier, BattlegroundDossier.Controls, BattlegroundDossier.ViewData
local U, T = B.UI, C.theme
local labels = { kills = "Kills", deaths = "Deaths", assists = "Assists", damage = "Damage", healing = "Healing", score = "Personal score", objective = "Objective" }
function U:OpenDossier(m, p)
    if self.view == "scoreboard" and self.canvas.tableUsed > 0 then
        self.rosterState = { scroll = self.scroll:GetNamedChild("Scroll"):GetVerticalScroll(),
            tableScroll = self.canvas.tables[1].scroll:GetNamedChild("Scroll"):GetVerticalScroll() }
    end
    self.match, self.expanded, self.selectedPlayer, self.view, self.dossierTab, self.abilityScope = m, p, p, "dossier", "Overview", "This match"
    self:Render()
end
function U:DossierTabs()
    local c = self.canvas
    for i, tab in ipairs({ "Overview", "Observed abilities", "History", "Scoreboard details" }) do
        c:Button(tab, 12 + (i - 1) * 265, c.y, 253, function() self.dossierTab = tab; self:Render() end, self.dossierTab == tab)
    end
    c.y = c.y + 48
end
function U:Dossier(m, p)
    local c, profile = self.canvas, B.Players:Get(p, m.world)
    self.dossierTab = self.dossierTab or "Overview"
    c:Heading(V.Name(p))
    local icon = self:ClassIcon(p); local x = icon and 54 or 12
    if icon then c:Icon(icon, 12, c.y, 30) end
    c:Label(V.Account(p) .. " • " .. V.Class(p) .. " • " .. (m.teams[p.team] and m.teams[p.team].name or "Unresolved team"), x, c.y, 1040 - x, 32)
    c.y = c.y + 36
    c:Paragraph((p.isLocal and "Local player" or (p.previousEncounters or 0) > 0 and "◆ Familiar • " .. p.previousEncounters .. " previous encounters" or p.previousEncounters == 0 and "First Encounter" or "Previous encounter count unavailable")
        .. " • " .. (({ ally = "Allied team", opponent = "Opposing team", unknown = "Unresolved team" })[B.TeamRelation(m, p)]), p.isLocal and T.gold or self:TeamColor(m, p))
    c:Paragraph("Identity: " .. (({ account = "Verified account", character = "Character name only", unresolved = "Unresolved participant" })[p.identityConfidence or select(2, B.Identity(p, m.world))] or "Unresolved participant"), T.muted)
    c:Button("Select as A", 12, c.y, 165, function() self.compareA = p; self:Render(true) end, self.compareA == p)
    c:Button("Select as B", 189, c.y, 165, function() self.compareB = p; self:Render(true) end, self.compareB == p)
    c:Button("Compare with me", 366, c.y, 224, function() self.compareA, self.compareB, self.view, self.expanded = p, V.LocalPlayer(m), "comparison", nil; self:Render() end)
    c:Button("Compare A / B", 602, c.y, 224, function() if self.compareA and self.compareB then self.view, self.expanded = "comparison", nil; self:Render() end end, self.compareA and self.compareB)
    c.y = c.y + 46; self:DossierTabs()
    if self.dossierTab == "Observed abilities" then
        for i, scope in ipairs({ "This match", "Previous matches" }) do
            c:Button(scope, 12 + (i - 1) * 275, c.y, 263, function() self.abilityScope = scope; self:Render() end, (self.abilityScope or "This match") == scope)
        end
        c.y = c.y + 44
        local abilities = p.abilities
        if self.abilityScope == "Previous matches" then
            local cacheKey = m.id .. ":" .. (B.Identity(p, m.world) or "unknown")
            if not self.abilityCache[cacheKey] then self.abilityCache[cacheKey] = V.PreviousAbilities(m, p) end
            abilities = self.abilityCache[cacheKey]
            c:Paragraph("Earlier retained matches only. Previously observed abilities may no longer be equipped.", T.muted)
        end
        self:AbilityList(abilities, "OBSERVED ABILITIES", "dossier:" .. (self.abilityScope or "This match"))
    elseif self.dossierTab == "History" then
        if profile then self:ProfileSummary(profile, m.id)
        else c:Empty(p.isLocal and "Your history is in Statistics" or "First recorded encounter", "No lifetime player profile is available for this participant.") end
    elseif self.dossierTab == "Scoreboard details" then self:ScoreDetails(m, p)
    else
        local cards = {}
        for _, key in ipairs({ "kills", "deaths", "assists", "damage", "healing", "objective" }) do
            cards[#cards + 1] = { label = labels[key], value = self:Number(p[key]), tip = (key == "objective" and (m.objectiveLabel or "Objective unavailable") or labels[key]) .. ": " .. V.Precise(p[key]) }
        end
        c:Cards(cards, 3)
        c:Heading("TEAM CONTEXT", "Averages use available teammates, including this player. Shares and totals are descriptive, not a skill rating.")
        local rows = {}
        for _, key in ipairs(B.metrics) do
            local average, share = V.TeamSummary(m, p, key)
            rows[#rows + 1] = { metric = labels[key], value = p[key], average = average, share = share }
        end
        c:Table({ { title = "STATISTIC", key = "metric", width = 300 },
            { title = "PLAYER", key = "value", width = 250, numeric = true, text = function(r) return self:Number(r.value) end },
            { title = "TEAM AVERAGE", key = "average", width = 250, numeric = true, text = function(r) return self:Number(r.average) end },
            { title = "SHARE OF TEAM", key = "share", width = 250, numeric = true, text = function(r) return r.share and string.format("%.1f%%", r.share) or "—" end } }, rows, { height = 280 })
        c:Paragraph("K/D: " .. V.Number(B.Ratio(p)) .. " • K/D is unavailable with zero deaths or missing values. Personal score: " .. self:Number(p.score), T.muted)
        if profile then self:EncounterCards(profile) end
    end
end
function U:AbilityList(abilities, title, key)
    local c = self.canvas; key = key or title or "abilities"
    local sorting = self.abilitySorts[key]
    if not sorting then
        local damage, healing = false, false
        for _, a in pairs(abilities or {}) do
            if type(a) == "table" then damage = damage or type(a.damage) == "number" and a.damage > 0; healing = healing or type(a.healing) == "number" and a.healing > 0 end
        end
        sorting = { key = damage and "damage" or healing and "healing" or "events", descending = true }; self.abilitySorts[key] = sorting
    end
    c:Heading(title or "OBSERVED ABILITIES", "Client-visible combat events, not casts or confirmed equipped skills. Hover a row for ID, timestamps and exact values.")
    local rows = V.Abilities(abilities, sorting.key, sorting.descending)
    self.abilityRows = rows
    if #rows == 0 then c:Empty("No observed abilities", "No combat activity could be reliably attributed in this scope."); return end
    local visible, pages = rows, math.ceil(#rows / 80)
    if pages > 1 then
        local page = math.max(1, math.min(self.abilityPages[key] or 1, pages)); self.abilityPages[key] = page
        C:SetButtonEnabled(c:Button("‹ Previous abilities", 12, c.y, 230, function() self.abilityPages[key] = math.max(1, page - 1); self:Render() end), page > 1)
        C:SetButtonEnabled(c:Button("Next abilities ›", 254, c.y, 230, function() self.abilityPages[key] = math.min(pages, page + 1); self:Render() end), page < pages)
        c:Label("Page " .. page .. " / " .. pages .. " • All " .. #rows .. " recorded IDs remain accessible", 500, c.y, 580, 34, "ZoFontGame", T.muted)
        c.y = c.y + 44; visible = {}
        for i = (page - 1) * 80 + 1, math.min(page * 80, #rows) do visible[#visible + 1] = rows[i] end
    end
    c:Table({ { title = "ABILITY", key = "name", width = 450 }, { title = "CATEGORY", key = "category", width = 180, color = function(r) return r.category == "Class" and T.gold or T.muted end },
        { title = "EVENTS", key = "events", width = 100, numeric = true, text = function(r) return self:Number(r.events) end },
        { title = "DAMAGE", key = "damage", width = 160, numeric = true, text = function(r) return self:Number(r.damage) end },
        { title = "HEALING", key = "healing", width = 160, numeric = true, text = function(r) return self:Number(r.healing) end } }, visible,
        { height = 350, sort = sorting.key, descending = sorting.descending, resetScroll = self.resetTables,
            icon = function(r) return self:AbilityIcon(r.id) end,
            onSort = function(field) if sorting.key == field then sorting.descending = not sorting.descending else sorting.key, sorting.descending = field, field ~= "name" and field ~= "category" end; self.abilityPages[key] = 1; self:Render(true) end,
            tooltip = function(r) return r.name .. "\nAbility ID: " .. tostring(r.id) .. "\n" .. (r.rawCategory or "Category unavailable")
                .. "\nObserved events: " .. V.Precise(r.events) .. " (not casts)\nObserved damage: " .. V.Precise(r.damage) .. "\nObserved healing: " .. V.Precise(r.healing)
                .. "\nFirst observed: " .. B.DateTime(r.firstSeen) .. "\nLast observed: " .. B.DateTime(r.lastSeen)
                .. "\nOnly activity visible to your client is recorded. Effects do not establish equipment." end })
    c:Paragraph(#rows .. " distinct ability IDs • Identical names remain separate observations • Scroll to view every recorded entry.", T.muted)
end
function U:EncounterCards(p)
    local c = self.canvas
    c:Heading("LIFETIME ENCOUNTERS", "Includes subsequently recorded matches. Results below describe your team against their team.")
    c:Cards({ { label = "Total encounters", value = self:Number(p.encounters) }, { label = "As allies", value = self:Number(p.allies), color = T.ally },
        { label = "As opponents", value = self:Number(p.opponents), color = T.enemy },
        { label = "Team wins / losses", value = B.Value(p.wins) .. " / " .. B.Value(p.losses) } }, 4)
    c:Paragraph("Draws " .. B.Value(p.draws) .. " • Unresolved " .. B.Value(p.unresolved) .. " • First " .. B.Date(p.firstSeen) .. " • Last " .. B.Date(p.lastSeen), T.muted)
end
function U:ProfileSummary(p, excludeId)
    local c = self.canvas
    self:EncounterCards(p)
    c:Heading("KNOWN IDENTITY", "Identity confidence: " .. (p.confidence or "unknown") .. ". Character-only records are not automatically merged into account profiles.")
    local characters = {}; for _, character in pairs(p.characters or {}) do characters[#characters + 1] = B.CharacterName(character) end; table.sort(characters)
    c:Paragraph("Characters: " .. (#characters > 0 and table.concat(characters, ", ") or "Unavailable"))
    local classes = {}; for id in pairs(p.classes or {}) do classes[#classes + 1] = V.Class({ classId = id }) end; table.sort(classes)
    c:Paragraph("Classes observed: " .. (#classes > 0 and table.concat(classes, ", ") or "Unavailable"), T.muted)
    c:Heading("RECORDED MAXIMUM TOTALS", "Records describe the highest observed totals, including deaths; they do not rank player skill.")
    local cards = {}
    for _, key in ipairs(B.metrics) do local best = (p.bests or {})[key]; cards[#cards + 1] = { label = labels[key], value = self:Number(best and best.value), tip = best and B.Date(best.timestamp) or "No recorded value" } end
    c:Cards(cards, 4)
    c:Heading("RETAINED MATCH REFERENCES")
    local refs, rows = {}, {}; for _, id in ipairs(p.matches or {}) do refs[id] = true end
    for i = #B.db.matches, 1, -1 do local m = B.db.matches[i]; if B.Storage:Valid(m) and refs[m.id] and m.id ~= excludeId then rows[#rows + 1] = m end end
    c:Table({ { title = "BATTLEGROUND", key = "map", width = 400, text = V.MapName }, { title = "DATE", key = "finishedAt", width = 280, text = function(m) return B.DateTime(m.finishedAt) end },
        { title = "MODE", key = "modeName", width = 250 }, { title = "RESULT", key = "outcome", width = 120 } }, rows,
        { height = 300, resetScroll = self.resetTables, onClick = function(m) self:OpenMatch(m) end, tooltip = function(m) return V.MapName(m) .. "\nOriginal: " .. (m.map or "Unavailable") .. "\nClick to open saved scoreboard" end })
    if #rows == 0 then c:Paragraph("No other retained match details. Lifetime totals survive pruning.", T.muted) end
end
function U:PlayerProfile(p)
    local c = self.canvas
    c:Heading(V.ProfileName(p), B.Players:Classification(p) .. " • Historical observations may describe old builds.")
    self.dossierTab = self.dossierTab or "Overview"
    for i, tab in ipairs({ "Overview", "Observed abilities" }) do c:Button(tab, 12 + (i - 1) * 275, c.y, 263, function() self.dossierTab = tab; self:Render() end, self.dossierTab == tab) end
    c.y = c.y + 46
    if self.dossierTab == "Observed abilities" then
        local latest, latestPlayer
        for i = #B.db.matches, 1, -1 do
            local m = B.db.matches[i]
            if B.Storage:Valid(m) then for _, peer in ipairs(m.players) do if B.Identity(peer, m.world) == p.id then latest, latestPlayer = m, peer; break end end end
            if latest then break end
        end
        for i, scope in ipairs({ "Lifetime", "Latest match" }) do c:Button(scope, 12 + (i - 1) * 275, c.y, 263, function() self.profileAbilityScope = scope; self:Render() end, (self.profileAbilityScope or "Lifetime") == scope) end
        c.y = c.y + 46
        if self.profileAbilityScope == "Latest match" then
            c:Paragraph(latest and V.MapName(latest) .. " • " .. B.DateTime(latest.finishedAt) or "No retained match for this player.", T.muted)
            self:AbilityList(latestPlayer and latestPlayer.abilities or {}, "OBSERVED ABILITIES — LATEST RETAINED MATCH", "profile-latest")
        else self:AbilityList(p.abilities, "OBSERVED ABILITIES — LIFETIME", "profile-lifetime") end
    else self:ProfileSummary(p) end
end
function U:ScoreDetails(m, p)
    local c, rows = self.canvas, {}
    c:Heading("ADDITIONAL SCOREBOARD STATISTICS", "API-supplied zero is preserved. Missing counters are unavailable; relevance varies by game mode.")
    for key in pairs(B.API.scoreTypes) do rows[#rows + 1] = { name = key:gsub("(%l)(%u)", "%1 %2"), value = p[key] } end
    table.sort(rows, function(a, b) return a.name < b.name end)
    rows[#rows + 1] = { name = "Lives remaining at last recorded round", value = p.livesRemaining }
    c:Table({ { title = "COUNTER", key = "name", width = 800 }, { title = "VALUE", key = "value", width = 250, numeric = true, text = function(r) return V.Precise(r.value) end } }, rows, { height = 350, resetScroll = self.resetTables })
    c:Heading("EARNED MEDALS")
    local medals = {}; for id, medal in pairs(p.medals or {}) do medals[#medals + 1] = { name = medal.name or ("Medal " .. id), count = medal.count } end
    c:Table({ { title = "MEDAL", key = "name", width = 800 }, { title = "EARNED", key = "count", width = 250, numeric = true } }, medals, { height = 220, resetScroll = self.resetTables })
end
function U:Comparison(m)
    local a, b, c = self.compareA, self.compareB, self.canvas
    if not a or not b then c:Empty("Choose two participants", "Select A and B in player dossiers, or use Compare with me."); return end
    c:Heading("PLAYER COMPARISON")
    c:Cards({ { label = "PLAYER A • " .. V.Class(a), value = V.Name(a), tip = V.Name(a) .. "\n" .. (a.account or "Account unavailable") },
        { label = "PLAYER B • " .. V.Class(b), value = V.Name(b), tip = V.Name(b) .. "\n" .. (b.account or "Account unavailable") } }, 2)
    c:Button("Change A", 12, c.y, 240, function() self:OpenDossier(m, a) end)
    c:Button("Change B", 264, c.y, 240, function() self:OpenDossier(m, b) end)
    c:Button("Swap A / B", 516, c.y, 240, function() self.compareA, self.compareB = b, a; self:Render() end)
    c:Button("Clear comparison", 768, c.y, 290, function() self.compareA, self.compareB, self.view = nil, nil, "scoreboard"; self:Render() end); c.y = c.y + 48
    local rows = B.Compare(a, b)
    local pa, pb = B.Players:Get(a, m.world), B.Players:Get(b, m.world)
    rows[#rows + 1] = { key = "Lifetime encounters", a = pa and pa.encounters, b = pb and pb.encounters,
        difference = pa and pb and B.Difference(pa, pb, "encounters") }
    rows[#rows + 1] = { key = "Observed distinct abilities", a = B.Count(a.abilities), b = B.Count(b.abilities), difference = B.Count(a.abilities) - B.Count(b.abilities) }
    c:Table({ { title = "STATISTIC", key = "key", width = 300, text = function(r) return labels[r.key] or r.key end },
        { title = "PLAYER A", key = "a", width = 250, numeric = true, text = function(r) return self:Number(r.a) end },
        { title = "PLAYER B", key = "b", width = 250, numeric = true, text = function(r) return self:Number(r.b) end },
        { title = "A MINUS B", key = "difference", width = 250, numeric = true, text = function(r) return (type(r.difference) == "number" and r.difference > 0 and "+" or "") .. self:Number(r.difference) end } }, rows,
        { height = 370, resetScroll = self.resetTables, tooltip = function(r) return (labels[r.key] or r.key) .. "\nA: " .. V.Precise(r.a) .. "\nB: " .. V.Precise(r.b) .. "\nA minus B: " .. V.Precise(r.difference) end })
    c:Paragraph("Differences have no overall winner. K/D requires deaths above zero. Missing values are not treated as zero.", T.muted)
    c:Button("Observed abilities: A", 12, c.y, 300, function() self.comparisonAbility = "A"; self:Render(true) end, self.comparisonAbility ~= "B")
    c:Button("Observed abilities: B", 324, c.y, 300, function() self.comparisonAbility = "B"; self:Render(true) end, self.comparisonAbility == "B"); c.y = c.y + 44
    self:AbilityList(self.comparisonAbility == "B" and b.abilities or a.abilities, "MATCH OBSERVATIONS • " .. V.Name(self.comparisonAbility == "B" and b or a), "comparison")
end
