local B, C, V = BattlegroundDossier, BattlegroundDossier.Controls, BattlegroundDossier.ViewData
local U, P, T = B.UI, B.Personal, C.theme
local colors = { Win = T.ally, Loss = T.enemy, Draw = T.gold }
local metricLabels = { healing = "Healing", damage = "Damage", kills = "Kills", deaths = "Deaths", assists = "Assists",
    score = "Personal score", damageTaken = "Damage taken", shieldsGranted = "Shields granted" }
function U:OpenPersonalMatch(m)
    self.personalReturn = { scroll = self.scroll:GetNamedChild("Scroll"):GetVerticalScroll(),
        personalScroll = self.personalTable and self.personalTable.scroll:GetNamedChild("Scroll"):GetVerticalScroll() or 0 }
    self:OpenMatch(m)
end
function U:PersonalRoleAssignment(m)
    if not P.Player(m) then return end
    local c = self.canvas
    c:Heading("PERSONAL MATCH ROLE", "Optional manual annotation. Unclassified matches stay unclassified; this does not change the Statistics display role.")
    for i, role in ipairs({ "Unclassified", "HEALER", "TANK", "DPS" }) do
        c:Button(role, 12 + (i - 1) * 210, c.y, 198, function()
            m.personalRole = role ~= "Unclassified" and role or nil; self:Render(true)
        end, (m.personalRole or "Unclassified") == role)
    end
    c.y = c.y + 46
end
function U:PersonalHistory()
    local c = self.canvas
    self.personalSummary, self.personalTable, self.personalRows = nil, nil, {}
    c:Heading("PERSONAL BG HISTORY", "Character-specific retained matches. Pruned details are not reconstructed from lifetime totals.")
    local characters, aliases, current = P.Index()
    local exists = false
    for _, option in ipairs(characters) do if option.value == self.personalCharacter then exists = true end end
    if not exists then self.personalCharacter = current end
    local prefs = P.Preferences(self.personalCharacter)
    if not prefs then c:Empty("Personal history preferences preserved", "This version cannot read newer personal history preferences. Existing match history is unchanged."); return end
    -- Reuse one native combo; it is hidden by Render whenever this view is left.
    if not self.personalSelector then self.personalSelector = C:Dropdown(self.body, 0, 0, 1) end
    C:Place(self.personalSelector.control, self.body, 12, c.y, c.width - 24, 34)
    self.personalSelector.control:SetHidden(false)
    C:Options(self.personalSelector, characters, self.personalCharacter, function(value)
        self.personalCharacter, self.personalPage = value, 1; self:Render(true)
    end)
    c.y = c.y + 48
    for i, role in ipairs(P.roles) do
        local button = c:Button(role, 12 + (i - 1) * 210, c.y, 198, function() prefs.role = role; self:Render(true) end, prefs.role == role)
        C:Tooltip(button, "Display role only; no role is inferred from combat statistics.\nIndividual match roles can be assigned in the saved scoreboard.")
    end
    c.y = c.y + 44
    for i, range in ipairs(P.ranges) do
        c:Button(range == 0 and "All retained matches" or "Last " .. range, 12 + (i - 1) * 266, c.y, 254, function()
            prefs.range, self.personalPage = range, 1; self:Render(true)
        end, prefs.range == range)
    end
    c.y = c.y + 46
    local rows = P.Rows(self.personalCharacter, prefs.range, aliases)
    self.personalRows = rows
    if #rows == 0 then
        c:Empty("No retained matches for this character", "Complete a Battleground or select another recorded character. Missing character identities are never guessed."); return
    end
    local s = P.Summary(rows); self.personalSummary = s
    local function metric(key, field) return s.metrics[key] and s.metrics[key][field] end
    local function card(label, key, field)
        local m = s.metrics[key]
        return { label = label, value = self:Number(m and m[field]), tip = (metricLabels[key] or key) .. ": " .. V.Precise(m and m[field]) .. "\nAvailable samples: " .. (m and m.count or 0) .. " / " .. #rows }
    end
    c:Cards({ { label = "Retained BGs in range", value = self:Number(s.total) }, { label = "Wins / losses / draws", value = s.Win .. " / " .. s.Loss .. " / " .. s.Draw },
        { label = "Win percentage", value = s.winRate and string.format("%.1f%%", s.winRate) or "—", tip = "Unresolved outcomes excluded: " .. s.Unresolved },
        { label = "Recorded streak", value = s.streak and s.streak.count .. (s.streak.outcome == "Win" and " wins" or " losses") or "—", tip = "Newest consecutive results in the selected retained range; draws, unresolved outcomes and missing/pruned records limit this claim." } }, 4)
    local averages = c:Paragraph("Average K / D / A: " .. self:Number(metric("kills", "average")) .. " / " .. self:Number(metric("deaths", "average")) .. " / " .. self:Number(metric("assists", "average"))
        .. "     Recent (newest first): " .. table.concat(s.sequence, " "), T.muted)
    C:Tooltip(averages, "Averages use each field's available samples, not zero-filled missing values.\nK / D / A samples: "
        .. (s.metrics.kills and s.metrics.kills.count or 0) .. " / " .. (s.metrics.deaths and s.metrics.deaths.count or 0) .. " / " .. (s.metrics.assists and s.metrics.assists.count or 0)
        .. "\nW = team win; L = team loss; D = draw; ? = unresolved.\nSnapshots without a reliable local character remain in Matches, outside these summaries.")
    local primary = prefs.role == "HEALER" and "healing" or prefs.role == "DPS" and "damage" or "deaths"
    c:Heading(prefs.role .. " PERFORMANCE", prefs.role == "TANK" and "Survival and recorded objectives. No blocked damage or mitigation is inferred. Mode-specific objective units remain separate."
        or "Your own saved scoreboard totals. Team results provide context, not a personal rating.")
    local cards
    if prefs.role == "TANK" then
        cards = { card("Average deaths", "deaths", "average"), card("Average assists", "assists", "average"), card("Average damage", "damage", "average"), card("Average damage taken", "damageTaken", "average") }
    else
        local m = s.metrics[primary]
        cards = { card("Total " .. primary, primary, "total"), card("Average " .. primary .. " / BG", primary, "average"),
            { label = "Highest " .. primary, value = self:Number(m and m.best.value), tip = m and B.DateTime(m.best.row.finishedAt) or "Unavailable" },
            card(prefs.role == "DPS" and "Total kills" or "Average damage", prefs.role == "DPS" and "kills" or "damage", "total") }
        if prefs.role == "HEALER" then cards[4] = card("Average damage", "damage", "average") end
    end
    c:Cards(cards, 4)
    if prefs.role == "HEALER" then
        local a, b = s.outcomes.Win.healing, s.outcomes.Loss.healing
        c:Cards({ { label = "Average healing in wins", value = self:Number(a and a.average), tip = "Available win samples: " .. (a and a.count or 0) },
            { label = "Average healing in losses", value = self:Number(b and b.average), tip = "Available loss samples: " .. (b and b.count or 0) } }, 2)
    elseif prefs.role == "DPS" then
        c:Cards({ { label = "Aggregate K/D", value = self:Number(s.kd), tip = "Total kills / total deaths across " .. s.kdSamples .. " matches with both fields. Unavailable when total deaths is zero." },
            { label = "Highest kills", value = self:Number(s.metrics.kills and s.metrics.kills.best.value) } }, 2)
    else
        local objectives = {}
        for label, m in pairs(s.objectives) do objectives[#objectives + 1] = { label = label, total = m.total, average = m.average, best = m.best.value, count = m.count, row = m.best.row } end
        table.sort(objectives, function(a, b) return a.label < b.label end)
        if #objectives == 0 then c:Paragraph("No recorded objective contributions in this range. Missing values are unavailable, not zero.", T.muted)
        else
            c:Table({ { title = "OBJECTIVE / UNIT", key = "label", width = 420, flex = 1 },
                { title = "TOTAL", key = "total", width = 150, numeric = true, text = function(r) return self:Number(r.total) end },
                { title = "AVERAGE", key = "average", width = 150, numeric = true, text = function(r) return self:Number(r.average) end },
                { title = "BEST", key = "best", width = 150, numeric = true, text = function(r) return self:Number(r.best) end },
                { title = "SAMPLES", key = "count", width = 130, numeric = true } }, objectives, { height = 220,
                    onClick = function(r) self:OpenPersonalMatch(r.row.match) end,
                    tooltip = function(r) return r.label .. "\nTotal " .. V.Precise(r.total) .. "; average " .. V.Precise(r.average) .. "\nClick for highest recorded value's match. Different objective units are never combined." end })
        end
        local defensive = { card("Total damage taken", "damageTaken", "total"), card("Total shields granted", "shieldsGranted", "total") }
        c:Cards(defensive, 2)
    end
    c:Heading("BEST RETAINED PERFORMANCES", "Click a record to open its saved match. Values describe individual metrics, not an overall player ranking.")
    local bestRows = {}
    for _, key in ipairs(prefs.role == "HEALER" and { "healing", "assists" } or prefs.role == "DPS" and { "damage", "kills" } or { "assists", "score" }) do
        local m = s.metrics[key]
        if m then bestRows[#bestRows + 1] = { label = "Highest " .. metricLabels[key]:lower(), value = m.best.value, row = m.best.row } end
    end
    if prefs.role == "TANK" then
        local lowest
        for _, row in ipairs(rows) do if row.deaths ~= nil and (not lowest or row.deaths < lowest.deaths) then lowest = row end end
        if lowest then bestRows[#bestRows + 1] = { label = "Lowest recorded deaths", value = lowest.deaths, row = lowest } end
    end
    c:Table({ { title = "RECORD", key = "label", width = 350, flex = 1 }, { title = "VALUE", key = "value", width = 150, numeric = true, text = function(r) return self:Number(r.value) end },
        { title = "BATTLEGROUND", key = "map", width = 300, text = function(r) return V.MapName(r.row.match) end },
        { title = "DATE", key = "date", width = 240, text = function(r) return B.DateTime(r.row.finishedAt) end } }, bestRows,
        { height = 180, onClick = function(r) self:OpenPersonalMatch(r.row.match) end,
            tooltip = function(r) return r.label .. ": " .. V.Precise(r.value) .. "\nClick to open retained match." end })
    self:PersonalTrends(s, primary)
    self:PersonalMatches(rows, prefs.role)
    c:Heading("MODE / FORMAT BREAKDOWN", "Resolved team outcomes in this character's selected retained range.")
    local modes = {}; for _, mode in pairs(s.modes) do modes[#modes + 1] = mode end
    table.sort(modes, function(a, b) return a.label < b.label end)
    c:Table({ { title = "MODE / FORMAT", key = "label", width = 500, flex = 1 }, { title = "BGS", key = "total", width = 100, numeric = true },
        { title = "W / L / D", key = "result", width = 250, align = TEXT_ALIGN_CENTER, text = function(r) return r.Win .. " / " .. r.Loss .. " / " .. r.Draw end },
        { title = "UNRESOLVED", key = "Unresolved", width = 180, numeric = true } }, modes, { height = 240 })
end
function U:PersonalTrends(s, primary)
    local c, rows = self.canvas, {}
    c:Heading("RECENT PERFORMANCE", "Latest ten versus preceding ten within the selected range. Sample counts exclude missing fields; different modes, durations and team sizes affect totals.")
    for _, key in ipairs({ primary, primary ~= "kills" and "kills" or "damage", "assists" }) do
        local a, b = s.trend.recent[key], s.trend.previous[key]
        rows[#rows + 1] = { label = metricLabels[key], a = a and a.average, b = b and b.average,
            difference = a and b and a.average - b.average, countA = a and a.count or 0, countB = b and b.count or 0 }
    end
    c:Table({ { title = "METRIC", key = "label", width = 350, flex = 1 },
        { title = "LATEST AVG", key = "a", width = 220, numeric = true, text = function(r) return self:Number(r.a) end },
        { title = "PREVIOUS AVG", key = "b", width = 220, numeric = true, text = function(r) return self:Number(r.b) end },
        { title = "CHANGE", key = "difference", width = 220, numeric = true, text = function(r) return self:Number(r.difference) end } }, rows,
        { height = 180, tooltip = function(r) return r.label .. "\nSamples: " .. r.countA .. " latest / " .. r.countB .. " previous\nExact averages: " .. V.Precise(r.a) .. " / " .. V.Precise(r.b) .. "\nAverages are descriptive; no overall better/worse judgement." end })
end
function U:PersonalMatches(rows, role)
    local c = self.canvas
    c:Heading("PERSONAL MATCHES", "Newest first by default. Sort headings or click a row for the full saved scoreboard. Role badges are manual annotations only.")
    local visible = {}; for _, row in ipairs(rows) do visible[#visible + 1] = row end
    local key, descending = self.personalSort or "finishedAt", self.personalDescending ~= false
    V.Sort(visible, key, descending)
    local pages = math.max(1, math.ceil(#visible / 40)); local page = math.max(1, math.min(self.personalPage or 1, pages)); self.personalPage = page
    C:SetButtonEnabled(c:Button("Previous matches", 12, c.y, 180, function() self.personalPage = math.max(1, page - 1); self:Render(true) end), page > 1)
    C:SetButtonEnabled(c:Button("Next matches", 204, c.y, 180, function() self.personalPage = math.min(pages, page + 1); self:Render(true) end), page < pages)
    c:Label("Page " .. page .. " / " .. pages .. " | " .. #visible .. " retained matches", 408, c.y, 650, 34, "ZoFontGame", T.muted); c.y = c.y + 46
    local slice = {}; for i = (page - 1) * 40 + 1, math.min(page * 40, #visible) do slice[#slice + 1] = visible[i] end
    local primary = role == "HEALER" and "healing" or role == "DPS" and "damage" or "objective"
    local columns = {
        { title = "DATE", key = "finishedAt", width = 175, text = function(r) return B.DateTime(r.finishedAt) end },
        { title = "RESULT", key = "outcome", width = 95, align = TEXT_ALIGN_CENTER, color = function(r) return colors[r.outcome] or T.muted end },
        { title = "BG MODE", key = "modeName", width = 150, flex = 1 },
        { title = "ROLE", key = "role", width = 100, align = TEXT_ALIGN_CENTER, text = function(r) return r.role == "Unclassified" and "—" or r.role end },
    }
    for _, item in ipairs({ { "K", "kills", 40 }, { "D", "deaths", 40 }, { "A", "assists", 40 }, { "DAMAGE", "damage", 100 }, { "HEALING", "healing", 100 }, { "SCORE", "score", 90 }, { "OBJ.", "objective", 90 } }) do
        local field = item[2]
        columns[#columns + 1] = { title = item[1], key = field, width = item[3], numeric = true,
            color = function() return field == primary and T.gold or T.text end, text = function(r) return self:Number(r[field]) end,
            tip = field == "objective" and "Objective units vary by mode; hover a row for its label. Sorting these values does not imply equivalent contribution." or nil }
    end
    self.personalTable = c:Table(columns, slice, { height = 360, sort = key, descending = descending, rowHeight = 44, resetScroll = self.resetTables,
        stripe = function(r) return colors[r.outcome] or T.border end,
        onClick = function(r) self:OpenPersonalMatch(r.match) end,
        onSort = function(field)
            if key == field then self.personalSort, self.personalDescending = field, not descending else self.personalSort, self.personalDescending = field, true end
            self.personalPage = 1; self:Render(true)
        end,
        tooltip = function(r)
            local lines = { V.MapName(r.match), r.modeName .. " | " .. V.FormatDescription(r.match), B.DateTime(r.finishedAt), "Assigned role: " .. r.role }
            for _, field in ipairs(B.metrics) do lines[#lines + 1] = field .. ": " .. V.Precise(r[field]) end
            lines[#lines + 1] = r.match.objectiveLabel or "Objective meaning was not captured. No cross-mode total is inferred."
            if not r.player then lines[#lines + 1] = "Local roster entry unavailable or ambiguous; personal fields are unavailable." end
            lines[#lines + 1] = "Click to open the saved scoreboard."
            return table.concat(lines, "\n")
        end })
end
