local B = BattlegroundDossier
B.Controls = { serial = 0 }
local C = B.Controls
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
    c:SetVerticalAlignment(TEXT_ALIGN_CENTER); c:SetText(text or "")
    return c
end
function C:OneLine(c) c:SetMaxLineCount(1); c:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS) end
function C:ButtonStyle(c, selected)
    c.selected = selected; c.baseColor = selected and self.theme.selected or self.theme.panel
    c.background:SetCenterColor(unpack(c.baseColor))
    c.background:SetEdgeColor(unpack(selected and self.theme.gold or self.theme.border))
end
function C:Button(parent, text, x, y, width, callback)
    local c = self:New(parent, CT_BUTTON); self:Place(c, parent, x, y, width, 34)
    c.background = self:Backdrop(c); c:SetFont("ZoFontGameBold")
    c:SetNormalFontColor(unpack(self.theme.gold)); c:SetMouseOverFontColor(1, 0.9, 0.69, 1); c:SetPressedFontColor(1, 0.96, 0.85, 1)
    c:SetText(text); c:SetHandler("OnClicked", callback)
    c:SetHandler("OnMouseEnter", function(button)
        button.background:SetCenterColor(unpack(self.theme.hover)); self:ShowTooltip(button, button.tip)
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
function C:Search(parent, x, y, width, callback)
    local bg = self:New(parent, CT_CONTROL); self:Place(bg, parent, x, y, width, 34); self:Backdrop(bg)
    local edit = self:New(bg, CT_EDITBOX); self:Place(edit, bg, 10, 4, width - 20, 26)
    edit:SetFont("ZoFontGame"); edit:SetMaxInputChars(100)
    edit:SetHandler("OnTextChanged", function(c) callback(c:GetText()) end)
    edit:SetHandler("OnEscape", function(c) c:LoseFocus() end); edit:SetHandler("OnEnter", function(c) c:LoseFocus() end)
    edit.container = bg; return edit
end
function C:Dropdown(parent, x, y, width)
    local control = self:New(parent, nil, "ZO_ComboBox"); self:Place(control, parent, x, y, width, 34)
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
        local c = self:Get("button"); C:Place(c, self.parent, x, y, width, 34)
        c:SetText(text); c:SetHandler("OnClicked", callback); C:ButtonStyle(c, selected); return c
    end
    function canvas:Panel(x, y, width, height, fill, border)
        local c = self:Get("panel"); C:Place(c, self.parent, x, y, width, height)
        c.background:SetCenterColor(unpack(fill or C.theme.panel)); c.background:SetEdgeColor(unpack(border or C.theme.border)); return c
    end
    function canvas:Icon(texture, x, y, size)
        local c = self:Get("icon"); C:Place(c, self.parent, x, y, size, size); c:SetTexture(texture); c:SetMouseEnabled(false); return c
    end
    function canvas:Heading(text, subtitle)
        self.y = self.y + 12; self:Label(text, 12, self.y, self.width - 24, 34, "ZoFontHeader3", C.theme.gold)
        self.y = self.y + 38; if subtitle then self:Paragraph(subtitle, C.theme.muted) end
    end
    function canvas:Cards(cards, columns)
        columns = columns or 4
        local gap, start = 10, self.y; local width = (self.width - 24 - gap * (columns - 1)) / columns
        for i, card in ipairs(cards) do
            local x, y = 12 + (i - 1) % columns * (width + gap), start + math.floor((i - 1) / columns) * 86
            self:Panel(x, y, width, 76); self:Label(card.label, x + 12, y + 5, width - 24, 25, "ZoFontGame", C.theme.muted)
            local label = self:Label(card.value, x + 12, y + 29, width - 24, 36, "ZoFontHeader3", card.color or C.theme.text)
            if card.tip then C:Tooltip(label, card.tip) end
        end
        self.y = start + math.ceil(#cards / columns) * 86
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
function C:Table(parent)
    local t = { control = self:New(parent, CT_CONTROL), rowControls = {}, headers = {} }
    self:Backdrop(t.control); t.scroll = self:New(t.control, nil, "ZO_ScrollContainer")
    t.scroll:SetAnchor(TOPLEFT, t.control, TOPLEFT, 0, 38); t.scroll:SetAnchor(BOTTOMRIGHT, t.control, BOTTOMRIGHT, -2, -4)
    t.body = t.scroll:GetNamedChild("ScrollChild"); t.body:SetResizeToFitDescendents(false)
    function t:Bind(columns, rows, options, width)
        local rowHeight, innerWidth = options.rowHeight or 38, width - 24
        self.rows, self.columns, self.options = rows, columns, options
        local x = 6
        for i, col in ipairs(columns) do
            local header = self.headers[i]
            if not header then header = C:Button(self.control, "", 0, 0, 1, function() end); self.headers[i] = header end
            header:SetHidden(false); C:Place(header, self.control, x, 2, col.width, 34)
            header:SetText(col.title .. (options.sort == col.key and (options.descending and " ↓" or " ↑") or "")); C:ButtonStyle(header, options.sort == col.key)
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
            r.control:SetHandler("OnClicked", function() if options.onClick then options.onClick(row) end end)
            local texture = options.icon and options.icon(row); r.icon:SetHidden(not texture)
            r.placeholder:SetHidden(not options.icon or texture ~= nil)
            if options.icon and not texture then C:Place(r.placeholder, r.control, 10, (rowHeight - 26) / 2, 26, 26) end
            if texture then C:Place(r.icon, r.control, 10, (rowHeight - 26) / 2, 26, 26); r.icon:SetTexture(texture) end
            x = 6
            for j, col in ipairs(columns) do
                local label = r.labels[j]
                if not label then label = C:Label(r.control, "", 0, 0, 1, 1); C:OneLine(label); r.labels[j] = label end
                local padding = j == 1 and options.icon and 36 or 4
                label:SetHidden(false); C:Place(label, r.control, x + padding, 2, col.width - padding - 8, rowHeight - 4)
                label:SetMouseEnabled(false); label:SetText(col.text and col.text(row) or tostring(row[col.key] or "—"))
                label:SetFont(col.font or "ZoFontGame"); label:SetColor(unpack(col.color and col.color(row) or C.theme.text))
                label:SetHorizontalAlignment(col.numeric and TEXT_ALIGN_RIGHT or TEXT_ALIGN_LEFT); x = x + col.width
            end
            for j = #columns + 1, #r.labels do r.labels[j]:SetHidden(true) end
        end
        for i = #rows + 1, #self.rowControls do self.rowControls[i].control:SetHidden(true); self.rowControls[i].control.tip = nil end
        self.body:SetDimensions(innerWidth, math.max(1, #rows * rowHeight))
        if options.resetScroll then self.scroll:GetNamedChild("Scroll"):SetVerticalScroll(0) end
    end
    return t
end
