local B = BattlegroundDossier
B.Controls = { serial = 0 }
local C = B.Controls
C.layout = { padding = 12, gap = 12, buttonHeight = 36, inputHeight = 36, stepWidth = 48,
    numberWidth = 228, settingsRight = 30, headerHeight = 40, rowHeight = 44, scrollGutter = 24 }
C.theme = {
    background = { 0.035, 0.038, 0.041, 0.98 }, panel = { 0.065, 0.068, 0.071, 0.98 },
    row = { 0.075, 0.078, 0.081, 0.96 }, alternate = { 0.09, 0.092, 0.095, 0.96 },
    hover = { 0.17, 0.15, 0.115, 1 }, selected = { 0.21, 0.175, 0.115, 1 },
    border = { 0.25, 0.23, 0.19, 1 }, gold = { 0.79, 0.67, 0.44, 1 },
    text = { 0.9, 0.88, 0.83, 1 }, muted = { 0.64, 0.65, 0.64, 1 },
    ally = { 0.48, 0.67, 0.52, 1 }, enemy = { 0.76, 0.44, 0.41, 1 },
}
function C:New(parent, kind, template)
    self.serial = self.serial + 1
    local name = B.name .. "Control" .. self.serial
    if template then return WINDOW_MANAGER:CreateControlFromVirtual(name, parent, template) end
    return WINDOW_MANAGER:CreateControl(name, parent, kind)
end
function C:Place(c, parent, x, y, width, height)
    c:ClearAnchors(); c:SetAnchor(TOPLEFT, parent, TOPLEFT, x, y); c:SetDimensions(width, height)
end
function C:Backdrop(parent, fill)
    local c = self:New(parent, CT_BACKDROP)
    c:SetAnchorFill(parent); c:SetDrawLayer(DL_BACKGROUND)
    c:SetCenterColor(unpack(fill or self.theme.panel)); c:SetEdgeColor(unpack(self.theme.border))
    c:SetEdgeTexture("", 1, 1, 1, 0)
    return c
end
function C:Label(parent, text, x, y, width, height, font)
    local c = self:New(parent, CT_LABEL)
    self:Place(c, parent, x, y, width, height or 28)
    c:SetFont(font or "ZoFontGame"); c:SetColor(unpack(self.theme.text))
    c:SetVerticalAlignment(TEXT_ALIGN_CENTER); c:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    c:SetMaxLineCount(1); c:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS); c:SetText(text or "")
    return c
end
function C:OneLine(c) c:SetMaxLineCount(1); c:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS) end
function C:ButtonStyle(c, selected)
    c.selected = selected; c.baseColor = selected and self.theme.selected or self.theme.panel
    if c.enabled == false then c.baseColor = self.theme.background end
    c.background:SetCenterColor(unpack(c.baseColor))
    c.background:SetEdgeColor(unpack(selected and self.theme.gold or self.theme.border))
end
function C:SetButtonEnabled(c, enabled)
    c.enabled = enabled; c:SetEnabled(enabled); self:ButtonStyle(c, c.selected)
end
function C:Button(parent, text, x, y, width, callback)
    local c = self:New(parent, CT_BUTTON); self:Place(c, parent, x, y, width, self.layout.buttonHeight)
    c.background = self:Backdrop(c); c:SetFont("ZoFontGameBold")
    c:SetHorizontalAlignment(TEXT_ALIGN_CENTER); c:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    c:SetNormalOffset(0, 0); c:SetPressedOffset(0, 1)
    c:SetNormalFontColor(unpack(self.theme.gold)); c:SetMouseOverFontColor(1, 0.9, 0.69, 1); c:SetPressedFontColor(1, 0.96, 0.85, 1)
    c:SetDisabledFontColor(unpack(self.theme.muted)); self:SetButtonEnabled(c, true)
    self:OneLine(c:GetLabelControl())
    c:SetText(text); c:SetHandler("OnClicked", callback)
    c:SetHandler("OnMouseEnter", function(button)
        if button.enabled ~= false then button.background:SetCenterColor(unpack(self.theme.hover)) end
        local tip = button.tip
        local label = button:GetLabelControl()
        local text = label:GetText()
        if not tip and label:GetStringWidth(text) > button:GetWidth() - 12 then tip = text end
        self:ShowTooltip(button, tip)
    end)
    c:SetHandler("OnMouseExit", function(button)
        button.background:SetCenterColor(unpack(button.baseColor)); ClearTooltip(InformationTooltip)
    end)
    self:ButtonStyle(c, false); return c
end
function C:ShowTooltip(c, text)
    if type(text) == "function" then text = text() end
    if not text or text == "" then return end
    InitializeTooltip(InformationTooltip, c, BOTTOM, 0, -6); SetTooltipText(InformationTooltip, text)
end
function C:Tooltip(c, text)
    c.tip = text; c:SetMouseEnabled(true)
    if c.background then return end
    c:SetHandler("OnMouseEnter", function(control) self:ShowTooltip(control, control.tip) end)
    c:SetHandler("OnMouseExit", function() ClearTooltip(InformationTooltip) end)
end
function C:InputStyle(edit)
    if not edit.inputPanel then return end
    local active = edit:HasFocus()
    edit.inputPanel.background:SetEdgeColor(unpack(active and self.theme.gold or self.theme.border))
    edit.inputPanel.background:SetCenterColor(unpack(active and self.theme.hover or self.theme.background))
end
function C:IsEditing() return self.focusedEdit and self.focusedEdit:HasFocus() or false end
function C:Edit(parent, font, selectAll)
    -- Native template supplies OnMouseDown -> TakeFocus. Mouse-enabled alone
    -- does not focus a bare CT_EDITBOX and cannot deliver editing keystrokes.
    local edit = self:New(parent, nil, "ZO_DefaultEdit")
    edit:SetFont(font or "ZoFontGame"); edit:SetMouseEnabled(true); edit:SetKeyboardEnabled(true)
    edit:SetEditEnabled(true); edit:SetCopyEnabled(true); edit:SetPasteEnabled(true)
    edit:SetMultiLine(false); edit:SetNewLineEnabled(false); edit:SetSelectAllOnFocus(selectAll == true)
    edit:SetSelectionColor(0.48, 0.39, 0.23, 0.8)
    edit:SetHandler("OnFocusGained", function(control) self.focusedEdit = control; self:InputStyle(control) end)
    edit:SetHandler("OnFocusLost", function(control)
        if self.focusedEdit == control then self.focusedEdit = nil end
        self:InputStyle(control)
    end)
    return edit
end
function C:Search(parent, x, y, width, callback)
    local bg = self:New(parent, CT_CONTROL); self:Place(bg, parent, x, y, width, self.layout.inputHeight); bg.background = self:Backdrop(bg)
    local edit = self:Edit(bg); self:Place(edit, bg, 10, 4, width - 20, 28)
    edit.inputPanel = bg; self:InputStyle(edit); edit:SetMaxInputChars(100)
    bg:SetMouseEnabled(true); bg:SetHandler("OnMouseDown", function() edit:TakeFocus() end)
    edit:SetHandler("OnTextChanged", function(c) callback(c:GetText()) end)
    edit:SetHandler("OnEscape", function(c) c:LoseFocus() end); edit:SetHandler("OnEnter", function(c) c:LoseFocus() end)
    edit.container = bg; return edit
end
function C.ValidateNumber(text, low, high, step)
    if type(text) ~= "string" then return nil end
    text = text:match("^%s*(.-)%s*$")
    -- No exponents, signs, suffixes or partial decimals. Commas are display-only.
    if not text:match("^%d+%.?%d*$") or text:sub(-1) == "." then return nil end
    local value = tonumber(text)
    if not value or value ~= value or value < low or value > high then return nil end
    if value ~= low and value ~= high then value = math.floor(value / step + 0.5) * step end
    return math.max(low, math.min(high, math.floor(value * 1000000 + 0.5) / 1000000))
end
function C:FinishNumeric(edit, commit)
    if not edit.editing then return end
    local value = commit and self.ValidateNumber(edit:GetText(), edit.low, edit.high, edit.step) or nil
    edit.editing = false; self.activeNumeric = nil
    edit.value = value or edit.previous
    edit:SetText(tostring(edit.value)); edit:LoseFocus(); self:InputStyle(edit)
    if value ~= nil and value ~= edit.previous then edit.commit(value) end
end
function C:LayoutNumeric(edit)
    if not edit.bounds then return end
    local b = edit.bounds
    -- EditControl has no horizontal-alignment setter in API 101051. Center a
    -- measured native editor, leaving native cursor/selection/scroll intact.
    local width = math.min(b.width - 24, math.max(32, edit.measure:GetStringWidth(edit:GetText()) + 8))
    self:Place(edit, edit.canvasParent, b.x + (b.width - width) / 2, b.y + 4, width, b.height - 8)
end
function C:CancelNumeric()
    if self.activeNumeric then self:FinishNumeric(self.activeNumeric, false) end
end
function C:Dropdown(parent, x, y, width)
    local control = self:New(parent, nil, "ZO_ComboBox"); self:Place(control, parent, x, y, width, self.layout.buttonHeight)
    local combo = ZO_ComboBox_ObjectFromContainer(control); combo:SetSortsItems(false); combo:SetFont("ZoFontGame")
    return { control = control, combo = combo }
end
function C:Options(dropdown, options, selected, callback)
    local combo = dropdown.combo; combo:ClearItems()
    for _, option in ipairs(options) do
        local value, label = option, option
        if type(option) == "table" then value, label = option.value, option.label end
        combo:AddItem(combo:CreateItemEntry(label, function() callback(value) end))
    end
    local label = selected
    for _, option in ipairs(options) do if type(option) == "table" and option.value == selected then label = option.label end end
    combo:SetSelectedItem(label)
end

-- Every canvas owns its reusable controls; rebinding clears row-specific handlers and tips.
function C:Canvas(parent, width)
    local canvas = { parent = parent, width = width, pools = {}, used = {}, tables = {}, tableUsed = 0, y = 0 }
    function canvas:Begin()
        C:CancelNumeric()
        for _, pool in pairs(self.pools) do for _, c in ipairs(pool) do c:SetHidden(true); c.tip = nil end end
        for _, t in ipairs(self.tables) do t.control:SetHidden(true) end
        self.used, self.tableUsed, self.y = {}, 0, 0
    end
    function canvas:Get(kind)
        self.used[kind] = (self.used[kind] or 0) + 1; local index = self.used[kind]
        self.pools[kind] = self.pools[kind] or {}; local c = self.pools[kind][index]
        if not c then
            if kind == "label" then c = C:Label(self.parent, "", 0, 0, 1, 1)
            elseif kind == "button" then c = C:Button(self.parent, "", 0, 0, 1, function() end)
            elseif kind == "icon" then c = C:New(self.parent, CT_TEXTURE)
            elseif kind == "number" then
                c = C:Edit(self.parent, "ZoFontGameBold", true); c:SetMaxInputChars(16)
                c:SetColor(unpack(C.theme.gold))
                c.measure = C:Label(c, "", 0, 0, 1, 1, "ZoFontGameBold"); c.measure:SetHidden(true); c.measure:SetMouseEnabled(false)
                c:SetHandler("OnTextChanged", function(edit) C:LayoutNumeric(edit) end)
                c:SetHandler("OnFocusGained", function(edit)
                    if C.activeNumeric and C.activeNumeric ~= edit then C:FinishNumeric(C.activeNumeric, true) end
                    edit.editing, edit.previous, C.activeNumeric = true, edit.value, edit
                    C.focusedEdit = edit; C:InputStyle(edit)
                end)
                c:SetHandler("OnEnter", function(edit) C:FinishNumeric(edit, true) end)
                c:SetHandler("OnEscape", function(edit) C:FinishNumeric(edit, false) end)
                c:SetHandler("OnFocusLost", function(edit)
                    if C.focusedEdit == edit then C.focusedEdit = nil end
                    C:FinishNumeric(edit, true); C:InputStyle(edit)
                end)
            else c = C:New(self.parent, CT_CONTROL); c.background = C:Backdrop(c) end
            self.pools[kind][index] = c
        end
        c:SetHidden(false); c.tip = nil; return c
    end
    function canvas:Label(text, x, y, width, height, font, color, align)
        local c = self:Get("label"); C:Place(c, self.parent, x, y, width, height)
        c:SetFont(font or "ZoFontGame"); c:SetColor(unpack(color or C.theme.text)); c:SetText(text or "")
        c:SetHorizontalAlignment(align or TEXT_ALIGN_LEFT); c:SetVerticalAlignment(TEXT_ALIGN_CENTER); C:OneLine(c)
        c:SetMouseEnabled(false); c:SetHandler("OnMouseEnter", nil); c:SetHandler("OnMouseExit", nil)
        return c
    end
    function canvas:Paragraph(text, color)
        local c = self:Label(text, 12, self.y, self.width - 24, 48, "ZoFontGame", color)
        c:SetMaxLineCount(0); c:SetWrapMode(TEXT_WRAP_MODE_TRUNCATE); c:SetVerticalAlignment(TEXT_ALIGN_TOP)
        local height = math.max(30, c:GetTextHeight() + 12); c:SetHeight(height); self.y = self.y + height
        return c
    end
    function canvas:Button(text, x, y, width, callback, selected)
        local c = self:Get("button"); C:Place(c, self.parent, x, y, width, C.layout.buttonHeight)
        C:SetButtonEnabled(c, true)
        c:SetText(text); c:SetHandler("OnClicked", function(...) if c.enabled ~= false then callback(...) end end); C:ButtonStyle(c, selected); return c
    end
    function canvas:NumberEdit(value, x, y, width, low, high, step, commit)
        local panel = self:Panel(x, y, width, C.layout.inputHeight, C.theme.background)
        local edit = self:Get("number")
        edit.bounds, edit.canvasParent, edit.inputPanel = { x = x, y = y, width = width, height = C.layout.inputHeight }, self.parent, panel
        panel:SetMouseEnabled(true); panel:SetHandler("OnMouseDown", function() edit:TakeFocus() end)
        edit.value, edit.low, edit.high, edit.step, edit.commit = value, low, high, step, commit
        if not edit.editing then edit:SetText(tostring(value)) end
        C:LayoutNumeric(edit); C:InputStyle(edit)
        C:Tooltip(edit, "Click to type. Enter commits; Escape cancels. Focus loss validates.\nRange " .. low .. " to " .. high .. "; rounded to step " .. step .. ". No changes while typing.")
        return edit
    end
    function canvas:Panel(x, y, width, height, fill, border)
        local c = self:Get("panel"); C:Place(c, self.parent, x, y, width, height)
        c:SetMouseEnabled(false); c:SetHandler("OnMouseDown", nil)
        c.background:SetCenterColor(unpack(fill or C.theme.panel)); c.background:SetEdgeColor(unpack(border or C.theme.border)); return c
    end
    function canvas:Icon(texture, x, y, size)
        local c = self:Get("icon"); C:Place(c, self.parent, x, y, size, size); c:SetTexture(texture); c:SetMouseEnabled(false); return c
    end
    function canvas:Heading(text, subtitle)
        self.y = self.y + 16
        local heading = self:Label(text, 12, self.y, self.width - 24, 40, "ZoFontHeader3", C.theme.gold)
        local height = math.max(40, heading:GetFontHeight() + 10); heading:SetHeight(height)
        C:Tooltip(heading, text)
        self.y = self.y + height + 6; if subtitle then self:Paragraph(subtitle, C.theme.muted) end
    end
    function canvas:Cards(cards, columns)
        columns = columns or 4
        local gap, start, padding = 12, self.y, 12
        columns = math.min(columns, math.max(1, math.floor((self.width - 12) / 235)))
        local width = (self.width - 24 - gap * (columns - 1)) / columns
        -- Measure actual font heights so the same layout works for localized fonts.
        local probe = self:Label("", 0, 0, width, 1, "ZoFontGame")
        local labelHeight = math.max(30, probe:GetFontHeight() + 6)
        probe:SetFont("ZoFontHeader3")
        local valueHeight = math.max(38, probe:GetFontHeight() + 8)
        local cardHeight = padding * 2 + labelHeight + 4 + valueHeight
        for i, card in ipairs(cards) do
            local x, y = 12 + (i - 1) % columns * (width + gap), start + math.floor((i - 1) / columns) * (cardHeight + gap)
            self:Panel(x, y, width, cardHeight)
            local caption = self:Label(card.label, x + padding, y + padding, width - padding * 2, labelHeight, "ZoFontGame", C.theme.muted, TEXT_ALIGN_CENTER)
            C:Tooltip(caption, card.tip or card.label)
            local label = self:Label(card.value, x + padding, y + padding + labelHeight + 4, width - padding * 2, valueHeight, card.font or "ZoFontHeader3", card.color or C.theme.text, card.align or TEXT_ALIGN_CENTER)
            if label:GetStringWidth(tostring(card.value or "")) > width - padding * 2 then label:SetFont("ZoFontGameBold") end
            C:Tooltip(label, card.tip or tostring(card.value or "Unavailable"))
        end
        self.y = start + math.ceil(#cards / columns) * (cardHeight + gap)
    end
    function canvas:Empty(title, message)
        self:Panel(100, self.y + 36, self.width - 200, 176)
        self:Label(title, 120, self.y + 62, self.width - 240, 40, "ZoFontHeader2", C.theme.gold, TEXT_ALIGN_CENTER)
        self:Label(message, 120, self.y + 110, self.width - 240, 60, "ZoFontGame", C.theme.muted, TEXT_ALIGN_CENTER):SetMaxLineCount(2)
        self.y = self.y + 240
    end
    function canvas:Table(columns, rows, options)
        self.tableUsed = self.tableUsed + 1; local t = self.tables[self.tableUsed]
        if not t then t = C:Table(self.parent); self.tables[self.tableUsed] = t end
        t.control:SetHidden(false); C:Place(t.control, self.parent, 12, self.y, self.width - 24, options.height or 350)
        t:Bind(columns, rows, options, self.width - 24); self.y = self.y + (options.height or 350) + 12; return t
    end
    return canvas
end

-- Sticky table header; native independently scrollable rows. Large databases are paged.
function C.LayoutColumns(columns, available)
    local result, fixed, flexible, total = {}, 0, 0, 0
    for i, col in ipairs(columns) do
        result[i] = {}; for k, v in pairs(col) do result[i][k] = v end
        total = total + col.width
        if col.flex then flexible = flexible + col.flex else fixed = fixed + col.width end
    end
    if flexible > 0 and fixed < available then
        for _, col in ipairs(result) do if col.flex then col.width = (available - fixed) * col.flex / flexible end end
    elseif total > available then
        for _, col in ipairs(result) do col.width = col.width * available / total end
    elseif result[1] then result[1].width = result[1].width + available - total end
    return result
end
local compactColumns = { kills = true, deaths = true, assists = true, team = true, kda = true,
    record = true, encounters = true, allies = true, opponents = true, placement = true, count = true, total = true }
function C.ColumnAlignment(col)
    if col.align then return col.align end
    if compactColumns[col.key] or col.numeric and col.width < 80 then return TEXT_ALIGN_CENTER end
    return col.numeric and TEXT_ALIGN_RIGHT or TEXT_ALIGN_LEFT
end
function C:Table(parent)
    local t = { control = self:New(parent, CT_CONTROL), rowControls = {}, headers = {} }
    self:Backdrop(t.control); t.scroll = self:New(t.control, nil, "ZO_ScrollContainer")
    t.scroll:SetAnchor(TOPLEFT, t.control, TOPLEFT, 0, self.layout.headerHeight + 2); t.scroll:SetAnchor(BOTTOMRIGHT, t.control, BOTTOMRIGHT, -2, -4)
    t.body = t.scroll:GetNamedChild("ScrollChild"); t.body:SetResizeToFitDescendents(false)
    function t:Bind(columns, rows, options, width)
        local rowHeight, innerWidth = options.rowHeight or C.layout.rowHeight, width - C.layout.scrollGutter
        columns = C.LayoutColumns(columns, innerWidth - 12)
        self.rows, self.columns, self.options = rows, columns, options
        local x = 6
        for i, col in ipairs(columns) do
            local header = self.headers[i]
            if not header then
                header = C:Button(self.control, "", 0, 0, 1, function() end)
                header.caption = C:Label(header, "", 0, 0, 1, 1, "ZoFontGameBold"); C:OneLine(header.caption)
                header.caption:SetMouseEnabled(false); self.headers[i] = header
            end
            local padding = col.padding or (col.width < 65 and 4 or 10)
            local align = C.ColumnAlignment(col)
            header:SetHidden(false); C:Place(header, self.control, x, 2, col.width, C.layout.buttonHeight)
            C:Place(header.caption, header, padding, 2, col.width - padding * 2, C.layout.buttonHeight - 4)
            header.caption:SetText(col.title .. (options.sort == col.key and (options.descending and " ↓" or " ↑") or ""))
            header.caption:SetHorizontalAlignment(align); header.caption:SetColor(unpack(C.theme.gold))
            C:ButtonStyle(header, options.sort == col.key)
            header:SetHandler("OnClicked", function() if options.onSort then options.onSort(col.key) end end)
            C:Tooltip(header, col.tip or (options.onSort and "Sort by " .. col.title .. ". Missing values sort last." or col.title)); x = x + col.width
        end
        for i = #columns + 1, #self.headers do self.headers[i]:SetHidden(true) end
        self.contentWidth = x + 6
        for i, row in ipairs(rows) do
            local r = self.rowControls[i]
            if not r then
                r = { control = C:New(self.body, CT_BUTTON), labels = {} }; r.background = C:Backdrop(r.control)
                r.stripe = C:Backdrop(r.control); r.stripe:ClearAnchors(); r.stripe:SetAnchor(TOPLEFT, r.control, TOPLEFT, 0, 1); r.stripe:SetDimensions(3, rowHeight - 2)
                r.placeholder = C:Backdrop(r.control); r.placeholder:ClearAnchors()
                r.placeholder:SetCenterColor(0.17, 0.16, 0.14, 1)
                r.icon = C:New(r.control, CT_TEXTURE); r.icon:SetMouseEnabled(false)
                r.control:SetHandler("OnMouseEnter", function() r.background:SetCenterColor(unpack(C.theme.hover)); C:ShowTooltip(r.control, r.control.tip) end)
                r.control:SetHandler("OnMouseExit", function() r.background:SetCenterColor(unpack(r.base)); ClearTooltip(InformationTooltip) end)
                self.rowControls[i] = r
            end
            r.control:SetHidden(false); C:Place(r.control, self.body, 0, (i - 1) * rowHeight, innerWidth, rowHeight); r.stripe:SetHeight(rowHeight - 2)
            r.base = options.selected == row and C.theme.selected or i % 2 == 0 and C.theme.alternate or C.theme.row
            if options.rowColor then r.base = options.rowColor(row, i) or r.base end
            r.background:SetCenterColor(unpack(r.base)); r.background:SetEdgeColor(0, 0, 0, 0)
            r.stripe:SetCenterColor(unpack(options.stripe and options.stripe(row) or C.theme.border)); r.stripe:SetEdgeColor(0, 0, 0, 0)
            r.control.tip = options.tooltip and options.tooltip(row) or nil
            if not r.control.tip then
                local lines = {}
                for _, col in ipairs(columns) do
                    local raw = row[col.key]
                    lines[#lines + 1] = col.title .. ": " .. (raw ~= nil and tostring(raw) or col.text and col.text(row) or "Unavailable")
                end
                r.control.tip = table.concat(lines, "\n")
            end
            r.control:SetHandler("OnClicked", function() if options.onClick then options.onClick(row) end end)
            local texture = options.icon and options.icon(row); r.icon:SetHidden(not texture)
            r.placeholder:SetHidden(not options.icon or texture ~= nil)
            if options.icon and not texture then C:Place(r.placeholder, r.control, 10, (rowHeight - 26) / 2, 26, 26) end
            if texture then C:Place(r.icon, r.control, 10, (rowHeight - 26) / 2, 26, 26); r.icon:SetTexture(texture) end
            x = 6
            local truncated = {}
            for j, col in ipairs(columns) do
                local label = r.labels[j]
                if not label then label = C:Label(r.control, "", 0, 0, 1, 1); C:OneLine(label); r.labels[j] = label end
                local inset = col.padding or (col.width < 65 and 4 or 10)
                local padding = j == 1 and options.icon and 40 or inset
                label:SetHidden(false); C:Place(label, r.control, x + padding, 2, math.max(1, col.width - padding - inset), rowHeight - 4)
                label:SetMouseEnabled(false); label:SetText(col.text and col.text(row) or tostring(row[col.key] or "—"))
                label:SetFont(col.font or "ZoFontGame"); label:SetColor(unpack(col.color and col.color(row) or C.theme.text))
                local text = label:GetText()
                if label:GetStringWidth(text) > col.width - padding - inset and not r.control.tip:find(text, 1, true) then
                    truncated[#truncated + 1] = col.title .. ": " .. text
                end
                label:SetHorizontalAlignment(C.ColumnAlignment(col)); x = x + col.width
            end
            if #truncated > 0 then r.control.tip = r.control.tip .. "\n" .. table.concat(truncated, "\n") end
            for j = #columns + 1, #r.labels do r.labels[j]:SetHidden(true) end
        end
        for i = #rows + 1, #self.rowControls do self.rowControls[i].control:SetHidden(true); self.rowControls[i].control.tip = nil end
        self.body:SetDimensions(innerWidth, math.max(1, #rows * rowHeight))
        if options.resetScroll then self.scroll:GetNamedChild("Scroll"):SetVerticalScroll(0) end
    end
    return t
end
