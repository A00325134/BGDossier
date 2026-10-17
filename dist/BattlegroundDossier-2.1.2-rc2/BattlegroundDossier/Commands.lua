local B = BattlegroundDossier
function B.InitializeCommands()
    SLASH_COMMANDS["/bgd"] = function(text)
        local command = (B.Normalize(text) or "")
        if command == "" then B.UI:Toggle()
        elseif command == "last" then B.UI:Last()
        elseif command == "history" then B.UI:Open("MATCHES")
        elseif command == "players" then B.UI:Open("PLAYERS")
        elseif command == "stats" then B.UI:Open("STATISTICS")
        elseif command == "settings" then B.UI:Open("SETTINGS")
        elseif command == "debug on" or command == "debug off" then
            B.db.settings.debug = command == "debug on"; B.Say("Debug " .. (B.db.settings.debug and "on" or "off"))
        elseif command == "reset" then
            B.resetUntil = GetFrameTimeMilliseconds() + 30000
            B.Say("This deletes all recorded matches, profiles and lifetime totals. Confirm within 30 seconds using /bgd reset confirm.")
        elseif command == "reset confirm" then
            if B.resetUntil and GetFrameTimeMilliseconds() <= B.resetUntil then
                B.resetUntil = nil; B.Storage:Reset(); B.UI.match, B.UI.profile = nil, nil; B.UI:Open("MATCHES")
            else B.Say("No active reset confirmation. Use /bgd reset first.") end
        else B.Say("/bgd — toggle; last; history; players; stats; settings; help; debug on|off; reset (requires confirmation)") end
    end
end
