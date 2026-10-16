local B = BattlegroundDossier
local function OnLoaded(_, addonName)
    if addonName ~= B.name then return end
    EVENT_MANAGER:UnregisterForEvent(B.name, EVENT_ADD_ON_LOADED)
    local db = ZO_SavedVars:NewAccountWide("BattlegroundDossierSavedVariables", 1, nil, {})
    if not B.Storage:Initialize(db) then return end
    B.UI:Initialize()
    B.InitializeCommands()
    B.Match:Initialize()
    B.Debug("Loaded " .. B.version .. " on API " .. tostring(GetAPIVersion()))
end
EVENT_MANAGER:RegisterForEvent(B.name, EVENT_ADD_ON_LOADED, OnLoaded)
