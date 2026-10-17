local B, C, V = BattlegroundDossier, BattlegroundDossier.Controls, BattlegroundDossier.ViewData
local U, T = B.UI, C.theme
function U:Statistics()
    local c, prefs = self.canvas, B.db.settings.presentation
    for i, view in ipairs({ "Lifetime overview", "BG History" }) do
        c:Button(view, 12 + (i - 1) * 275, c.y, 263, function() prefs.statisticsView = view; self:Render() end,
            (prefs.statisticsView or "Lifetime overview") == view)
    end
    c.y = c.y + 48
    if prefs.statisticsView == "BG History" then self:PersonalHistory(); return end
    local c, s = self.canvas, B.db.stats
    c:Heading("BATTLEGROUND OVERVIEW", "Lifetime totals survive match pruning. Record totals are descriptive, not skill ratings.")
    local resolved = (s.Win or 0) + (s.Loss or 0) + (s.Draw or 0)
    local unique, familiar = 0, 0
    for _, p in pairs(B.db.profiles) do
        if type(p) == "table" then unique = unique + 1; if (p.opponents or 0) >= 2 then familiar = familiar + 1 end end
    end
    c:Cards({ { label = "Recorded matches", value = self:Number(s.total or 0) }, { label = "Victories", value = self:Number(s.Win or 0), color = T.ally },
        { label = "Defeats", value = self:Number(s.Loss or 0), color = T.enemy }, { label = "Draws", value = self:Number(s.Draw or 0), color = T.gold },
        { label = "Win percentage", value = resolved > 0 and string.format("%.1f%%", (s.Win or 0) / resolved * 100) or "—", tip = "Wins / resolved matches (draws included). Unresolved results excluded." },
        { label = "Known player identities", value = self:Number(unique), tip = "Stored account or character identities. Character-only records may represent the same account; no speculative merges." },
        { label = "Familiar opponents", value = self:Number(familiar), tip = "Profiles encountered as opponents at least twice." },
        { label = "Unresolved results", value = self:Number(s.Unresolved or 0) } }, 4)
    c:Heading("PERSONAL RECORDS — HIGHEST MATCH TOTALS")
    local cards = {}
    for _, key in ipairs(B.metrics) do
        local best = (s.bests or {})[key]
        cards[#cards + 1] = { label = key:gsub("^%l", string.upper), value = self:Number(best and best.value),
            tip = best and V.Precise(best.value) .. "\nRecorded " .. B.Date(best.timestamp) .. "\nMatch details may have been pruned." or "No recorded value" }
    end
    c:Cards(cards, 4)
    for _, field in ipairs({ "opponents", "allies" }) do
        c:Heading(field == "opponents" and "FREQUENT OPPONENTS" or "FREQUENT TEAMMATES")
        local rows = {}
        for _, p in pairs(B.db.profiles) do if type(p) == "table" and (p[field] or 0) > 0 then rows[#rows + 1] = p end end
        V.Sort(rows, field, true)
        while #rows > 10 do table.remove(rows) end
        c:Table({ { title = "PLAYER", key = "account", width = 550, text = V.ProfileName },
            { title = "ENCOUNTERS", key = field, width = 200, numeric = true, text = function(p) return self:Number(p[field]) end },
            { title = "FAMILIARITY", key = "familiar", width = 300, text = function(p) return B.Players:Classification(p) end } }, rows,
            { height = 260, resetScroll = self.resetTables, onClick = function(p) self.section, self.profile, self.dossierTab = "PLAYERS", p, "Overview"; self:Render() end,
                tooltip = function(p) return V.ProfileName(p) .. "\nClick to inspect lifetime dossier" end })
    end
    c:Heading("RECENT PERFORMANCE", "Latest ten retained matches versus the preceding ten. Different formats and modes affect these averages.")
    local groups = V.Trends()
    if groups[2].count == 0 then c:Paragraph("More match history is needed for a two-period trend. Available averages are shown without an invented comparison.", T.muted) end
    local rows = {}
    for _, key in ipairs({ "kills", "deaths", "damage", "healing", "score" }) do
        local a = (groups[1].counts[key] or 0) > 0 and groups[1].sums[key] / groups[1].counts[key] or nil
        local b = (groups[2].counts[key] or 0) > 0 and groups[2].sums[key] / groups[2].counts[key] or nil
        rows[#rows + 1] = { key = key, a = a, b = b, countA = groups[1].counts[key] or 0, countB = groups[2].counts[key] or 0,
            difference = a and b and a - b }
    end
    c:Table({ { title = "STATISTIC", key = "key", width = 300 }, { title = "LATEST AVERAGE", key = "a", width = 250, numeric = true, text = function(r) return self:Number(r.a) end },
        { title = "PREVIOUS AVERAGE", key = "b", width = 250, numeric = true, text = function(r) return self:Number(r.b) end },
        { title = "CHANGE", key = "difference", width = 250, numeric = true, text = function(r) return self:Number(r.difference) end } }, rows,
        { height = 248, resetScroll = self.resetTables, tooltip = function(r) return "Available samples: " .. r.countA .. " latest / " .. r.countB .. " previous\nExact averages: " .. V.Precise(r.a) .. " / " .. V.Precise(r.b) end })
end
function U:SettingRow(label, detail, value, onClick)
    local c, y = self.canvas, self.canvas.y
    c:Panel(12, y, c.width - 24, 84)
    c:Label(label, 26, y + 12, 775, 28, "ZoFontGameBold")
    local hint = c:Label(detail, 26, y + 44, 775, 28, "ZoFontGame", T.muted); C:Tooltip(hint, detail)
    c:Button(value, 840, y + 25, 240, onClick)
    c.y = y + 96
end
function U:Settings()
    local c, settings = self.canvas, B.db.settings
    local prefs = settings.presentation
    c:Heading("APPEARANCE", "Window position, scale and number presentation are saved account-wide.")
    local function adjustment(key, label, step, low, high, detail, store, onChange)
        local values = store or settings
        local y = c.y
        c:Panel(12, y, c.width - 24, 88); c:Label(label, 26, y + 12, 640, 28, "ZoFontGameBold")
        C:Tooltip(c:Label(detail, 26, y + 46, 640, 28, "ZoFontGame", T.muted), detail)
        local minus, plus
        local function commit(value, fromEdit)
            values[key] = value
            if store then onChange()
            else
                if key == "scale" then self:ApplyScale() end
                if key == "historyLimit" then B.Storage:Prune(); self.abilityCache = {} end
            end
            if minus then C:SetButtonEnabled(minus, value > low); C:SetButtonEnabled(plus, value < high) end
            -- Avoid rebuilding/hiding native editors during focus transfer.
            if not fromEdit then self:Render(true) end
        end
        local function change(delta)
            C:CancelNumeric()
            local value = math.max(low, math.min(high, values[key] + delta))
            commit(math.floor(value * 1000000 + 0.5) / 1000000)
        end
        local stepWidth, gap, fieldWidth = C.layout.stepWidth, C.layout.gap, C.layout.numberWidth
        local left = c.width - C.layout.settingsRight - stepWidth * 2 - gap * 2 - fieldWidth
        minus = c:Button("−", left, y + 26, stepWidth, function() change(-step) end)
        local edit = c:NumberEdit(values[key], left + stepWidth + gap, y + 26, fieldWidth, low, high, step, function(value) commit(value, true) end)
        edit.settingKey, edit.settingStore = key, values
        plus = c:Button("+", left + stepWidth + gap * 2 + fieldWidth, y + 26, stepWidth, function() change(step) end)
        C:SetButtonEnabled(minus, values[key] > low); C:SetButtonEnabled(plus, values[key] < high)
        c.y = y + 100
    end
    local function toggle(key, label, detail, presentation)
        local store = presentation and prefs or settings
        self:SettingRow(label, detail, store[key] and "Enabled" or "Disabled", function()
            store[key] = not store[key]
            if key == "observeCombat" then B.Combat:SetActive(B.API:Call("GetCurrentBattlegroundState") == BATTLEGROUND_STATE_RUNNING) end
            self:Render(true)
        end)
    end
    adjustment("scale", "UI scale", 0.05, 0.6, 1.2, "Requested scale 60–120%; the rendered window automatically fits the screen without changing this preference.")
    self:SettingRow("Window position", "Restore the window to the centre of the screen.", "Centre window", function() settings.position = nil; self:Position() end)
    toggle("compactNumbers", "Compact large numbers", "Use K / M in tables and cards. Tooltips always retain precise values.", true)
    toggle("abilityIcons", "Observed ability icons", "Use the icon returned for the exact ability ID; unknown icons stay neutral.", true)
    c:Heading("KEYBINDINGS")
    c:Paragraph("Assign Toggle Battleground Dossier in ESO's Settings → Controls → Keybindings, under Battleground Dossier. No default key is assigned.")
    c:Paragraph("Current shortcut: " .. (B.Keybindings:Assigned() or "Check ESO's native Controls menu"), T.gold)
    c:Paragraph("ESO manages supported keys, modifiers and conflicts. The shortcut and /bgd both toggle this window.", T.muted)
    c:Paragraph("Toggle Live Session HUD is a separate optional native binding. /bgtracker also toggles the HUD.", T.muted)
    c:Heading("LIVE SESSION HUD", "Independent compact overlay. HUD preferences and sessions are character-specific; match history remains account-wide.")
    local live = B.LiveSession
    if live and live:IsReady() then
        local p = live.preferences
        c:Paragraph("HUD shortcut: " .. (B.Keybindings:Assigned("BGD_TOGGLE_HUD") or "Assign Toggle Live Session HUD in ESO's Controls menu"), T.muted)
        local function hudToggle(key, label, detail)
            self:SettingRow(label, detail, p[key] and "Enabled" or "Disabled", function() p[key] = not p[key]; live:ApplyPreferences(); self:Render(true) end)
        end
        hudToggle("visible", "Show live HUD", "Master switch for the overlay. Manual toggles respect Session Tracker Visibility; tracking continues while hidden.")
        local visibilityY = c.y
        c:Panel(12, visibilityY, c.width - 24, 88)
        c:Label("Session Tracker Visibility", 26, visibilityY + 12, 620, 28, "ZoFontGameBold")
        C:Tooltip(c:Label("Choose where the enabled HUD appears. Session tracking always continues.", 26, visibilityY + 46, 620, 28, "ZoFontGame", T.muted),
            "Always Visible: normal gameplay inside and outside Battlegrounds.\nBattlegrounds Only: the entire BG instance, including pregame and postgame.\nShow live HUD and /bgtracker remain the master visibility switch. This never changes the main Dossier window.")
        for i, option in ipairs({ { value = "always", label = "Always Visible" }, { value = "battlegroundsOnly", label = "Battlegrounds Only" } }) do
            c:Button(option.label, 674 + (i - 1) * 208, visibilityY + 26, 196, function()
                p.visibilityMode = option.value; live:ApplyVisibility(); self:Render(true)
            end, p.visibilityMode == option.value)
        end
        c.y = visibilityY + 100
        hudToggle("locked", "Lock HUD position", "Disable mouse interaction. Unlock and enable ESO cursor mode to drag; combat always disables dragging.")
        adjustment("scale", "HUD scale", 0.05, 0.65, 1.75, "Scale the compact bar independently of the main Dossier window.", p, function() live:ApplyPreferences() end)
        adjustment("opacity", "HUD background opacity", 0.05, 0, 1, "Adjust the original HUD's background transparency from 0 to 1.", p, function() live:ApplyPreferences() end)
        hudToggle("header", "Show HUD header", "Keep or hide the compact BG SESSION title.")
        self:SettingRow("HUD position", "Restore this character's HUD to its original default position.", "Reset HUD position", function() p.x, p.y = nil, nil; live:ApplyPreferences(); self:Render(true) end)
        self:SettingRow("Live session statistics", "Resets live W/L, draws and AP only. Dossier history and player records stay intact.", "Arm session reset", function() live.resetUntil = GetFrameTimeMilliseconds() + 15000; self.liveResetArmed = true; self:Render(true) end)
        if self.liveResetArmed then
            c:Paragraph("Confirm within 15 seconds to reset the current live session. This does not delete recorded matches.", T.gold)
            c:Button("Confirm session reset", 12, c.y, 300, function()
                if live.resetUntil and GetFrameTimeMilliseconds() <= live.resetUntil then live:ResetSession()
                else B.Say("Session reset confirmation expired.") end
                self.liveResetArmed = nil; self:Render(true)
            end)
            c:Button("Cancel session reset", 324, c.y, 250, function() live.resetUntil, self.liveResetArmed = nil, nil; self:Render(true) end)
            c.y = c.y + 46
        end
    else c:Paragraph(live and live.disabledReason or "Live HUD starts when the addon initializes. Existing Dossier history remains available.", T.muted) end
    c:Heading("BEHAVIOUR")
    toggle("autoOpen", "Open completed matches", "Automatically open the saved scoreboard after a match, outside combat.")
    toggle("notifications", "Familiar-player notifications", "Show a subtle match-start recognition message in chat.")
    toggle("observeCombat", "Record observed combat activity", "Preserve attributable client-visible damage and healing observations.")
    self:SettingRow("Default section", "Section shown after logging in or reloading the addon.", prefs.defaultTab, function()
        local choices = { "MATCHES", "PLAYERS", "STATISTICS", "SETTINGS" }
        for i, tab in ipairs(choices) do if tab == prefs.defaultTab then prefs.defaultTab = choices[i % #choices + 1]; break end end
        self:Render(true)
    end)
    adjustment("frequentThreshold", "Frequent-player threshold", 1, 2, 100, "Encounters as an opponent or teammate required for a frequent badge.")
    c:Heading("DATA & RETENTION", "Reducing history retention immediately removes the oldest match details. Lifetime aggregates remain.")
    adjustment("historyLimit", "Detailed match retention", 50, 10, 1000, "Keep 10–1,000 completed match records.")
    adjustment("profileLimit", "Lifetime profile capacity", 1000, 100, 20000, "At capacity, existing profiles update and new identities are skipped.")
    local abilities = 0
    for _, m in ipairs(B.db.matches) do if B.Storage:Valid(m) then for _, p in ipairs(m.players) do abilities = abilities + B.Count(p.abilities) end end end
    c:Cards({ { label = "Retained matches", value = self:Number(#B.db.matches) }, { label = "Stored identities", value = self:Number(B.Count(B.db.profiles)) },
        { label = "Match ability summaries", value = self:Number(abilities) }, { label = "Saved data schema", value = tostring(B.schema) } }, 4)
    self:SettingRow("Delete recorded history", "Deletes matches, profiles and lifetime statistics. Existing settings remain.", "Arm history reset", function()
        B.resetUntil = GetFrameTimeMilliseconds() + 30000; self.resetArmed = true; self:Render(true)
    end)
    if self.resetArmed then
        local remaining = B.resetUntil and B.resetUntil - GetFrameTimeMilliseconds() or 0
        c:Paragraph("Confirm within 30 seconds to delete all recorded history. This cannot be undone in the addon.", T.enemy)
        c:Button(remaining > 0 and "Confirm deletion" or "Confirmation expired", 12, c.y, 300, function()
            if B.resetUntil and GetFrameTimeMilliseconds() <= B.resetUntil then
                B.resetUntil, self.resetArmed = nil, nil; B.Storage:Reset(); self.match, self.profile, self.expanded, self.compareA, self.compareB = nil, nil, nil, nil, nil
                self.abilityCache = {}; self:Render()
            else self.resetArmed = nil; B.Say("Reset confirmation expired. Arm it again to continue."); self:Render(true) end
        end)
        c:Button("Cancel", 324, c.y, 200, function() self.resetArmed, B.resetUntil = nil, nil; self:Render(true) end); c.y = c.y + 46
    end
    c:Heading("DEBUGGING")
    toggle("debug", "Lifecycle debug messages", "Reports match state, final scoreboard retries and API availability in chat.")
    c:Paragraph("Addon " .. B.version .. " • Client API " .. tostring(GetAPIVersion()) .. " • Expected API 101051 • Schema " .. B.schema, T.muted)
    c:Paragraph("SavedVariables are written by ESO on logout or UI reload. No external service or addon library is required.", T.muted)
end
