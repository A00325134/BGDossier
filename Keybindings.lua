local B = BattlegroundDossier
ZO_CreateStringId("SI_BINDING_NAME_BGD_TOGGLE", "Toggle Battleground Dossier")
ZO_CreateStringId("SI_BINDING_NAME_BGD_TOGGLE_HUD", "Toggle Live Session HUD")
ZO_CreateStringId("SI_BGD_KEYBINDINGS_CATEGORY", "Battleground Dossier")
B.Keybindings = {}
function B.Keybindings:Toggle()
    if B.Controls:IsEditing() then return end
    if B.UI and B.UI.window then B.UI:Toggle() end
end
function B.Keybindings:ToggleHUD()
    if B.Controls:IsEditing() then return end
    if B.LiveSession then B.LiveSession:Toggle() end
end
function B.Keybindings:Assigned(actionName)
    if not GetActionIndicesFromName or not GetActionBindingInfo or not GetMaxBindingsPerAction or not GetKeyName then return nil end
    local ok, layer, category, action = pcall(GetActionIndicesFromName, actionName or "BGD_TOGGLE")
    if not ok or not layer or not category or not action then return nil end
    local countOk, count = pcall(GetMaxBindingsPerAction)
    if not countOk or type(count) ~= "number" or count < 1 or count > 32 then return nil end
    local bindings = {}
    for slot = 1, count do
        local read, key, m1, m2, m3, m4 = pcall(GetActionBindingInfo, layer, category, action, slot)
        if not read or key == nil then return nil end
        if key and key ~= 0 and key ~= KEY_INVALID then
            local parts = {}
            for _, code in ipairs({ m1 or 0, m2 or 0, m3 or 0, m4 or 0, key }) do
                if code ~= 0 and code ~= KEY_INVALID then
                    local named, label = pcall(GetKeyName, code)
                    if not named or type(label) ~= "string" or label == "" then return nil end
                    parts[#parts + 1] = label
                end
            end
            bindings[#bindings + 1] = table.concat(parts, " + ")
        end
    end
    return #bindings > 0 and table.concat(bindings, " / ") or "Unassigned"
end
