local A = BGSessionTracker
local C = A.Core

function A:Print(message)
    d("|cc7a66aBGSessionTracker|r: " .. message)
end

function A:PrintStats()
    local s = self.session
    local rank = self.rank and ("#" .. self.rank) or "Unranked"
    self:Print(string.format("%d wins / %d losses / %d draws | %d completed | %s win rate | Competitive rank %s | +%s AP (%d exact). Session age: %d minutes.",
        s.wins, s.losses, s.draws, C.Completed(s), C.WinRate(s), rank, C.FormatAP(s.ap), s.ap,
        math.max(0, math.floor((GetTimeStamp() - s.startedAt) / 60))))
end

function A:ResetSession()
    -- Preserve the encounter's deduplication latch even if reset on the results
    -- screen. An ongoing uncompleted match can still count after the reset.
    local match = self.session.match
    local session = C.NewSession(GetTimeStamp())
    session.match = match
    session.lastAP = self:ReadAPBalance()
    self.saved.session = session
    self.session = session
    self.apWarning = false
    self.resetUntil = nil
    self:RefreshUI()
    self:Print("Session statistics reset.")
end

function A:ConfirmReset(argument)
    local now = GetFrameTimeMilliseconds()
    if self.resetUntil and now <= self.resetUntil and (argument == "" or argument == "confirm") then
        self:ResetSession()
    else
        self.resetUntil = now + 15000
        self:Print("Reset all session statistics? Type /bgreset again within 15 seconds to confirm.")
    end
end

function A:RegisterCommands()
    SLASH_COMMANDS["/bgtracker"] = function(argument)
        local command, value = string.match(string.lower(argument or ""), "^%s*(%S*)%s*(.-)%s*$")
        local p = self.preferences
        if command == "" then p.visible = not p.visible
        elseif command == "show" then p.visible = true
        elseif command == "hide" then p.visible = false
        elseif command == "scale" then
            local number = tonumber(value)
            if not C.IsNumber(number) or number < 0.65 or number > 1.75 then
                self:Print("Usage: /bgtracker scale 0.65-1.75") return
            end
            p.scale = number
        elseif command == "opacity" then
            local number = tonumber(value)
            if not C.IsNumber(number) or number < 0 or number > 1 then
                self:Print("Usage: /bgtracker opacity 0-1") return
            end
            p.opacity = number
        elseif command == "header" and (value == "on" or value == "off") then p.header = value == "on"
        elseif command == "position" and value == "reset" then p.x, p.y = nil, nil
        else
            self:Print("/bgtracker [show|hide|scale 0.65-1.75|opacity 0-1|header on/off|position reset] | /bglock | /bgstats | /bgreset")
            return
        end
        self:ApplyPreferences()
    end
    SLASH_COMMANDS["/bgreset"] = function(argument)
        self:ConfirmReset(string.lower(string.match(argument or "", "^%s*(.-)%s*$")))
    end
    SLASH_COMMANDS["/bglock"] = function()
        self.preferences.locked = not self.preferences.locked
        self:ApplyPreferences()
        self:Print(self.preferences.locked and "HUD locked." or "HUD unlocked. Enable cursor mode to drag; mouse interaction is disabled in combat.")
    end
    SLASH_COMMANDS["/bgstats"] = function() self:PrintStats() end
end

function A:Initialize()
    local now = GetTimeStamp()
    self.saved = ZO_SavedVars:NewCharacterIdSettings("BGSessionTrackerSavedVariables", 1, nil, {}, GetWorldName())
    local preferences = self.saved.preferences
    if type(preferences) ~= "table" then preferences = {} end
    preferences.scale = C.Clamp(preferences.scale, 0.65, 1.75, 1)
    preferences.opacity = C.Clamp(preferences.opacity, 0, 1, 0.82)
    preferences.visible = preferences.visible ~= false
    preferences.locked = preferences.locked ~= false
    preferences.header = preferences.header ~= false
    self.preferences = preferences
    self.saved.preferences = preferences
    local restored = C.CanResume(self.saved.session, now)
    if not restored then self.saved.session = C.NewSession(now) end
    self.session = self.saved.session
    self.session.reloadAt = nil -- consume the one-use reload marker
    if type(self.session.match) ~= "table" then self.session.match = nil end
    self.session.lastAP = self:ReadAPBalance() -- never infer earnings across a UI outage
    ZO_PreHook("ReloadUI", function()
        self.session.reloadAt = GetTimeStamp()
        -- Returning nil lets ESO and other addons continue the reload normally.
    end)
    self:CreateUI()
    self:RegisterCommands()
    self:RegisterTracking()
    self:Print(restored and "Session restored after UI reload." or "New session started. /bgtracker help for controls.")
end

EVENT_MANAGER:RegisterForEvent(A.name, EVENT_ADD_ON_LOADED, function(_, addonName)
    if addonName ~= A.name then return end
    EVENT_MANAGER:UnregisterForEvent(A.name, EVENT_ADD_ON_LOADED)
    A:Initialize()
end)
