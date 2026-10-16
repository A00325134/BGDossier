local B, C, V = BattlegroundDossier, BattlegroundDossier.Controls, BattlegroundDossier.ViewData
local U, T = B.UI, C.theme
local resultColors = { Win = T.ally, Loss = T.enemy, Draw = T.gold }
local resultLabels = { Win = "Victory", Loss = "Defeat", Draw = "Draw", Unresolved = "Unresolved" }
function U:History()
    local c = self.canvas
    c:Heading("MATCH HISTORY", "Select a match to inspect its saved scoreboard and player dossiers.")
    local rows = V.History(self.filters, self.search)
    if #rows == 0 then
        c:Empty(#B.db.matches == 0 and "Your dossier starts here" or "No matching matches",
            #B.db.matches == 0 and "Complete a Battleground to record its scoreboard, players and observed combat activity." or "Try another search or clear the active filters.")
        return
    end
    local columns = {
        { title = "BATTLEGROUND", key = "map", width = 260, text = V.MapName },
        { title = "MODE", key = "modeName", width = 150 },
        { title = "DATE / TIME", key = "finishedAt", width = 190, text = function(m) return B.DateTime(m.finishedAt) end },
        { title = "RESULT", key = "outcome", width = 100, text = function(m) return resultLabels[m.outcome] or "Unresolved" end, color = function(m) return resultColors[m.outcome] or T.muted end },
        { title = "FORMAT", key = "format", width = 90, text = V.Format },
        { title = "K / D / A", key = "kda", width = 105, text = function(m) local p = V.LocalPlayer(m) or {}; return B.Value(p.kills) .. "/" .. B.Value(p.deaths) .. "/" .. B.Value(p.assists) end },
        { title = "DAMAGE", key = "damage", width = 100, numeric = true, text = function(m) local p = V.LocalPlayer(m) or {}; return self:Number(p.damage) end },
        { title = "PLACE", key = "placement", width = 55, numeric = true, text = function(m) return B.Value(m.placement) end },
    }
    c:Table(columns, self:Pager(rows), { height = 365, rowHeight = 54, resetScroll = self.resetTables,
        stripe = function(m) return resultColors[m.outcome] or T.border end,
        onClick = function(m) self:OpenMatch(m) end,
        tooltip = function(m)
            local p = V.LocalPlayer(m) or {}
            return V.MapName(m) .. "\nOriginal Battleground name: " .. (m.map or "Unavailable") .. "\n" .. (m.modeName or "Unknown mode") .. " • " .. B.DateTime(m.finishedAt)
                .. "\n" .. V.FormatDescription(m) .. " • " .. tostring(m.participantCount or #m.players) .. " participants • Placement by score " .. B.Value(m.placement)
                .. "\nPersonal damage: " .. V.Precise(p.damage) .. "\nClick to open match"
        end })
end
function U:Scoreboard(m)
    local c = self.canvas
    c:Heading(V.MapName(m))
    local y = c.y
    c:Label((m.modeName or "Unknown mode") .. "  •  " .. B.DateTime(m.finishedAt), 12, y, 830, 30, "ZoFontGame", T.muted)
    c:Label(resultLabels[m.outcome] or "Unresolved", 860, y, 230, 30, "ZoFontHeader3", resultColors[m.outcome] or T.muted, TEXT_ALIGN_RIGHT)
    c.y = c.y + 38
    local cards, teams = {}, {}; for id in pairs(m.teams) do teams[#teams + 1] = id end; table.sort(teams)
    for _, id in ipairs(teams) do
        local team = m.teams[id]
        cards[#cards + 1] = { label = team.name .. (id == m.localTeam and " • Your team" or ""),
            value = self:Number(team.score) .. "  •  " .. (resultLabels[team.result] or "Unresolved"), color = self:TeamColor(m, { team = id }),
            tip = (m.scoreLabel or "Team score") .. ": " .. V.Precise(team.score) .. "\n" .. (team.result or "Unresolved") }
    end
    c:Cards(cards, math.max(2, #cards))
    c:Paragraph(V.FormatDescription(m) .. " • " .. tostring(m.participantCount or #m.players) .. " recorded participants • Placement by score " .. B.Value(m.placement)
        .. (m.hasRounds and " • Cumulative totals / objective aggregate unavailable across mixed round modes" or ""), T.muted)
    if m.snapshotIncomplete or m.rosterMayBeIncomplete then c:Paragraph("Partial snapshot: some identity, team, result or statistics information was unavailable, or verification ended early. Known participants are retained.", T.gold) end
    if B.db.settings.debug and type(m.diagnostics) == "table" then
        local d = m.diagnostics
        c:Paragraph("Capture diagnostics • Exposed " .. B.Value(d.scoreboardEntries) .. " • Saved " .. #m.players .. " • Accounts " .. B.Value(d.accountIdentities) .. " • Character-only " .. B.Value(d.characterIdentities) .. " • Unresolved " .. B.Value(d.unresolvedIdentities), T.muted)
    end
    if m.profileLimitReached then c:Paragraph("Profile limit reached: new lifetime profiles were skipped. Match details are retained.", T.gold) end
    if self.compareA or self.compareB then
        c:Button("A: " .. (self.compareA and V.Name(self.compareA) or "Select player"), 12, c.y, 350, function() end, self.compareA ~= nil)
        c:Button("B: " .. (self.compareB and V.Name(self.compareB) or "Select player"), 374, c.y, 350, function() end, self.compareB ~= nil)
        c:Button("Compare selected", 736, c.y, 230, function() if self.compareA and self.compareB then self.view, self.expanded = "comparison", nil; self:Render() end end)
        c.y = c.y + 44
    end
    local columns = {
        { title = "PLAYER", key = "character", width = 240, text = function(p) return (p.isLocal and "★ " or (p.previousEncounters or 0) > 0 and "◆ " or "") .. V.Name(p) end,
            color = function(p) return p.isLocal and T.gold or T.text end },
        { title = "CLASS", key = "classId", width = 110, text = V.Class },
        { title = "TEAM", key = "team", width = 70, text = function(p) local relation = B.TeamRelation(m, p); return relation == "unknown" and "—" or tostring(p.team) .. (relation == "ally" and " Ally" or " Opp") end },
    }
    for _, item in ipairs({ { "K", "kills", 40 }, { "D", "deaths", 40 }, { "A", "assists", 40 }, { "DAMAGE", "damage", 110 },
        { "HEALING", "healing", 110 }, { "SCORE", "score", 90 }, { "OBJ.", "objective", 100 } }) do
        local key = item[2]
        columns[#columns + 1] = { title = item[1], key = key, width = item[3], numeric = true,
            text = function(p) return self:Number(p[key]) end,
            tip = key == "objective" and ((m.objectiveLabel or "Unavailable for mixed round modes") .. " • Click to sort") or nil }
    end
    local rows = {}
    for _, p in ipairs(m.players) do
        local relation, filter = B.TeamRelation(m, p), self.teamFilter
        local accepted = filter == "All players" or filter == "My team" and relation == "ally" or filter == "Opposing teams" and relation == "opponent"
            or filter == "Familiar players" and (p.previousEncounters or 0) > 0 or filter == "team:" .. tostring(p.team)
        if accepted and V.Search(p, self.search) then rows[#rows + 1] = p end
    end
    V.Sort(rows, self.sort, self.descending)
    self.scoreboardRows = rows
    c:Table(columns, rows, { height = 350, selected = self.selectedPlayer, sort = self.sort, descending = self.descending,
        resetScroll = self.resetTables, stripe = function(p) return self:TeamColor(m, p) end, icon = function(p) return self:ClassIcon(p) end,
        onSort = function(key) if self.sort == key then self.descending = not self.descending else self.sort, self.descending = key, true end; self:Render(true) end,
        onClick = function(p) self:OpenDossier(m, p) end,
        tooltip = function(p)
            local details = { V.Name(p), V.Account(p), V.Class(p), m.teams[p.team] and m.teams[p.team].name or "Unresolved team" }
            for _, key in ipairs(B.metrics) do details[#details + 1] = key .. ": " .. V.Precise(p[key]) end
            details[#details + 1] = "Encounters before this match: " .. B.Value(p.previousEncounters)
            details[#details + 1] = "Click anywhere on this row to inspect player"
            return table.concat(details, "\n")
        end })
    if #rows == 0 then c:Paragraph("No participants match these filters. Clear filters to view the full roster.", T.muted) end
    if #(m.rounds or {}) > 1 then
        c:Heading("ROUND SCORES")
        for r, round in ipairs(m.rounds) do
            local scores = {}; for _, id in ipairs(teams) do scores[#scores + 1] = m.teams[id].name .. " " .. B.Value(round.scores[id]) end
            c:Paragraph("Round " .. r .. " • " .. B.API:ModeName(round.mode) .. " • " .. table.concat(scores, "  /  "))
        end
    end
end
function U:Players()
    if self.profile then self:PlayerProfile(self.profile); return end
    local c, rows = self.canvas, {}
    c:Heading("PLAYER INTELLIGENCE", "Encounter frequency describes familiarity. Team records never describe personal duels.")
    for _, profile in pairs(B.db.profiles) do if type(profile) == "table" and V.Search(profile, self.search) then rows[#rows + 1] = profile end end
    V.Sort(rows, "encounters", true)
    if #rows == 0 then
        c:Empty("No matching player dossiers", "Known players appear after completed Battlegrounds. Search by account or character name."); return
    end
    local columns = {
        { title = "PLAYER", key = "account", width = 280, text = V.ProfileName },
        { title = "CLASSES SEEN", key = "classes", width = 180, text = function(p)
            local names = {}; for id in pairs(p.classes or {}) do names[#names + 1] = V.Class({ classId = id }) end; table.sort(names); return table.concat(names, ", ")
        end },
        { title = "SEEN", key = "encounters", width = 95, numeric = true, text = function(p) return self:Number(p.encounters) end },
        { title = "ALLY", key = "allies", width = 75, numeric = true, text = function(p) return self:Number(p.allies) end },
        { title = "OPPONENT", key = "opponents", width = 95, numeric = true, text = function(p) return self:Number(p.opponents) end },
        { title = "TEAM W / L / D", key = "record", width = 155, text = function(p) return B.Value(p.wins) .. "/" .. B.Value(p.losses) .. "/" .. B.Value(p.draws) end },
        { title = "FAMILIARITY", key = "familiar", width = 170, text = function(p) return B.Players:Classification(p):gsub(" Player", "") end },
    }
    c:Table(columns, self:Pager(rows), { height = 365, rowHeight = 44, resetScroll = self.resetTables,
        onClick = function(p) self:SaveState(); self.profile, self.dossierTab, self.profileAbilityScope = p, "Overview", "Lifetime"; self:Render() end,
        stripe = function(p) return (p.opponents or 0) >= (p.allies or 0) and T.enemy or T.ally end,
        tooltip = function(p) return V.ProfileName(p) .. "\n" .. B.Players:Classification(p)
            .. "\nFirst seen " .. B.Date(p.firstSeen) .. " • Last seen " .. B.Date(p.lastSeen)
            .. "\nUnresolved team results: " .. B.Value(p.unresolved) .. "\nClick to open dossier" end })
end
