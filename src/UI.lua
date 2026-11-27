-- Heavenly Axis V3 — Roblox HUD & Interface Editor
-- Original project by Syshi; V2 inspired by Danechka.
local Geometry = require("Geometry")
local Coordinates = require("Coordinates")
local Layout = require("UILayout")
local UI = {}
UI.__index = UI

local C = {
    surface = Color3.fromRGB(14, 23, 32), raised = Color3.fromRGB(27, 40, 52),
    field = Color3.fromRGB(10, 18, 26), selected = Color3.fromRGB(27, 63, 74),
    cyan = Color3.fromRGB(112, 229, 236), ink = Color3.fromRGB(11, 36, 42),
    text = Color3.fromRGB(239, 245, 248), muted = Color3.fromRGB(164, 184, 197),
    border = Color3.fromRGB(57, 79, 96), quiet = Color3.fromRGB(118, 139, 154),
    warning = Color3.fromRGB(255, 193, 106), danger = Color3.fromRGB(227, 130, 131),
}
local orders = setmetatable({}, {__mode = "k"})
local function make(class, props, parent)
    local object = Instance.new(class)
    for name, value in pairs(props or {}) do object[name] = value end
    if parent and object:IsA("GuiObject") then
        if parent:IsA("GuiObject") and object.ZIndex <= parent.ZIndex then object.ZIndex = parent.ZIndex + 1 end
        if orders[parent] and (not props or props.LayoutOrder == nil) then
            orders[parent] = orders[parent] + 1
            object.LayoutOrder = orders[parent]
        end
    end
    object.Parent = parent
    return object
end
local function corners(object, radius)
    make("UICorner", {CornerRadius = UDim.new(0, radius or 8)}, object)
end
local function outline(object, color, thickness)
    return make("UIStroke", {Color = color or C.border, Thickness = thickness or 1, Transparency = .35,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, object)
end
local function label(parent, text, height, size)
    return make("TextLabel", {Name = "Label", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, height or 30),
        Text = text, Font = Enum.Font.Gotham, TextSize = size or 13, TextColor3 = C.text,
        TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 24}, parent)
end
local function frame(parent, height)
    return make("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, height or 44), ZIndex = 23}, parent)
end
local function flow(parent, spacing)
    orders[parent] = 0
    return make("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, spacing or 7)}, parent)
end
local function selected(keys, key)
    for _, value in ipairs(keys or {}) do if value == key then return true end end
    return false
end
local function numberText(value)
    return string.format("%.1f", value or 0):gsub("%.0$", "")
end
local function inside(object, x, y)
    if not object or not object.Visible then return false end
    local r = Coordinates.rect(object)
    return r and x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h
end

local function localRect(object, rect)
    local x, y = Coordinates.screenToLocal(rect.x, rect.y, object.Parent)
    object.Position = UDim2.fromOffset(x, y)
    object.Size = UDim2.fromOffset(rect.w, rect.h)
end

local function truncate(object)
    object.TextWrapped = false
    object.TextTruncate = Enum.TextTruncate.AtEnd
end

local function validNumber(value)
    local n = tonumber(value)
    return n and n == n and math.abs(n) <= 100000 and n or nil
end

function UI:connect(signal, fn, dynamic)
    local connection = signal:Connect(function(...)
        if self.dead then return end
        local ok, problem = pcall(fn, ...)
        if not ok then self.app:log("Editor interaction failed: " .. tostring(problem)); self.app:status("That interaction failed; see diagnostics.") end
    end)
    table.insert(dynamic or self.connections, connection)
    return connection
end

function UI:button(parent, text, callback, width, x, color, dynamic)
    local b = make("TextButton", {Name = text:gsub("[^%w]", ""), Text = text, Size = UDim2.new(width or 1, width and -4 or 0, 0, 44),
        Position = UDim2.new(x or 0, 0, 0, 0), BackgroundColor3 = color or C.raised, BorderSizePixel = 0,
        TextColor3 = C.text, TextSize = 12, Font = Enum.Font.GothamMedium, TextWrapped = true,
        AutoButtonColor = true, ZIndex = parent.ZIndex + 1}, parent)
    corners(b, 8)
    if callback then
        self:connect(b.Activated, function(...)
            local input = self.app.input
            if self.disabled[b] or (input and input.isBusy and input:isBusy()) then return end
            callback(...)
        end, dynamic)
    end
    return b
end

function UI:enable(button, enabled)
    self.disabled[button] = not enabled or nil
    button.AutoButtonColor = enabled
    pcall(function() button.Interactable = enabled end)
    button.TextColor3 = enabled and C.text or C.quiet
end

function UI:textbox(parent, placeholder, initial, callback, width, x, dynamic)
    local b = make("TextBox", {Name = placeholder:gsub("[^%w]", ""), Text = initial or "", PlaceholderText = placeholder,
        PlaceholderColor3 = C.muted, ClearTextOnFocus = false, Size = UDim2.new(width or 1, width and -4 or 0, 0, 44),
        Position = UDim2.new(x or 0, 0, 0, 0), BackgroundColor3 = C.field, BorderSizePixel = 0,
        TextColor3 = C.text, TextSize = 13, Font = Enum.Font.Gotham, ZIndex = parent.ZIndex + 1}, parent)
    corners(b, 7); outline(b)
    self:connect(b.Focused, function()
        local input = self.app.input
        if input and input.isBusy and input:isBusy() then b:ReleaseFocus() end
    end, dynamic)
    if callback then
        self.presentedText[b] = b.Text
        self:connect(b.FocusLost, function(enter)
            local input = self.app.input
            if b.TextEditable ~= false and b.Text ~= self.presentedText[b]
                and not (input and input.isBusy and input:isBusy()) then callback(b.Text, enter) end
        end, dynamic)
    end
    return b
end

function UI:syncTextBox(box, text)
    if not box:IsFocused() then
        self.presentedText[box] = text
        if box.Text ~= text then box.Text = text end
    end
end

function UI:section(parent, title)
    local t = label(parent, title, 26, 12)
    t.TextColor3 = C.cyan
    t.Font = Enum.Font.GothamBold
    return t
end

function UI:row(parent, buttons)
    local r = frame(parent, 44)
    for i, entry in ipairs(buttons) do
        local b = self:button(r, entry[1], entry[2], 1 / #buttons, (i - 1) / #buttons, entry[3])
        if i == #buttons then b.Size = UDim2.new(1 / #buttons, 0, 0, 44) end
    end
    return r
end

function UI:toggle(parent, title, key, default)
    local b
    b = self:button(parent, "", function()
        local value = self.app.preferences[key]
        if value == nil then value = default or false end
        self.app:setPreference(key, not value)
    end)
    table.insert(self.toggles, {button = b, title = title, key = key, default = default})
    return b
end

function UI:refreshToggles()
    for _, entry in ipairs(self.toggles) do
        local value = self.app.preferences[entry.key]
        if value == nil then value = entry.default or false end
        entry.button.Text = entry.title .. (value and "  On" or "  Off")
        entry.button.TextColor3 = self.disabled[entry.button] and C.quiet or (value and C.cyan or C.muted)
    end
end

function UI:bindScroll(scroller, body, spacing)
    local flowLayout = flow(body, spacing)
    local function updateCanvas()
        local content = flowLayout.AbsoluteContentSize
        if content then scroller.CanvasSize = UDim2.fromOffset(0, content.Y + 6) end
    end
    self:connect(flowLayout:GetPropertyChangedSignal("AbsoluteContentSize"), updateCanvas,
        self.modalOpen and self.modalConnections or nil)
    updateCanvas()
end

function UI:dialog(title, message, text, actions)
    if self.app.input then self.app.input:cancel() end
    self:closeModal()
    local shield = make("TextButton", {Name = "DialogShield", Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = .32, Size = UDim2.fromScale(1, 1), ZIndex = 70}, self.root)
    local card = make("Frame", {Name = "Dialog", BackgroundColor3 = C.surface, BorderSizePixel = 0, ZIndex = 71}, shield)
    corners(card, 14)
    outline(card)
    self.modalGui, self.modalConnections, self.modalOpen = shield, {}, true
    self.dialogCard, self.dialogHasText = card, text ~= nil
    local heading = label(card, title, 28, 16)
    heading.Position = UDim2.fromOffset(12, 7)
    heading.Size = UDim2.new(1, -24, 0, 28)
    heading.Font, heading.ZIndex = Enum.Font.GothamBold, 72
    truncate(heading)
    local scroller = make("ScrollingFrame", {Name = "DialogContent", BackgroundTransparency = 1, BorderSizePixel = 0,
        Position = UDim2.fromOffset(12, 36), Size = UDim2.new(1, -24, 1, -92), CanvasSize = UDim2.new(),
        Active = true, ClipsDescendants = true,
        ScrollBarThickness = 3, ScrollBarImageColor3 = C.cyan, ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 72}, card)
    self.dialogHeading, self.dialogScroller = heading, scroller
    local body = make("Frame", {Name = "Content", BackgroundTransparency = 1, Size = UDim2.new(1, -6, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 72}, scroller)
    self:bindScroll(scroller, body, 8)
    local desc = label(body, message, 28, 13)
    desc.AutomaticSize, desc.TextYAlignment, desc.ZIndex = Enum.AutomaticSize.Y, Enum.TextYAlignment.Top, 73
    desc.TextColor3 = C.muted
    local box
    if text ~= nil then
        box = make("TextBox", {Text = text, ClearTextOnFocus = false, MultiLine = true, TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Font = Enum.Font.Code,
            TextColor3 = C.text, TextSize = 13, BackgroundColor3 = C.field, BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 102), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 73}, body)
        corners(box, 8)
        make("UIPadding", {PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7),
            PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6)}, box)
    end
    local strip = frame(card, 44)
    strip.Position = UDim2.new(0, 12, 1, -52)
    strip.Size, strip.ZIndex = UDim2.new(1, -24, 0, 44), 73
    for i, entry in ipairs(actions) do
        local b = self:button(strip, entry.label, function()
            if not entry.action then self:closeModal(); return end
            if entry.closeFirst then self:closeModal() end
            local ok, result = entry.action(box and box.Text or "")
            if entry.closeFirst then return end
            if ok ~= false then self:closeModal()
            elseif result then
                desc.Text, desc.TextColor3 = tostring(result), C.warning
                self.app:status(result)
            end
        end, 1 / #actions, (i - 1) / #actions, entry.primary and C.cyan or nil, self.modalConnections)
        if i == #actions then b.Size = UDim2.new(1 / #actions, 0, 0, 44) end
        if entry.primary then b.TextColor3 = C.ink end
    end
    self:layoutDialog()
    return box
end

function UI:layoutDialog()
    if not self.dialogCard or not self.layoutPlan then return end
    local area = self.layoutPlan.area
    local w, h = math.min(area.w, 490), math.min(area.h, self.dialogHasText and 364 or 172)
    local headingVisible = h >= 118
    local bodyTop = headingVisible and 36 or 7
    self.dialogHeading.Visible = headingVisible
    self.dialogScroller.Position = UDim2.fromOffset(12, bodyTop)
    self.dialogScroller.Size = UDim2.new(1, -24, 0, math.max(1, h - bodyTop - 56))
    localRect(self.dialogCard, {x = area.x + (area.w - w) / 2, y = area.y + (area.h - h) / 2, w = w, h = h})
end

function UI:modal(title, message, text, actionText, action)
    local actions = {{label = "Close"}}
    if action then actions[#actions + 1] = {label = actionText or "Continue", action = action, primary = true} end
    return self:dialog(title, message, text, actions)
end

function UI:confirm(title, message, callback)
    return self:dialog(title, message, nil, {{label = "Cancel"},
        {label = "Confirm", action = callback, primary = true, closeFirst = true}})
end

function UI:confirmDone(save, discard)
    return self:dialog("Finish editing?", "Save your changes or return to the last checkpoint before closing the editor.", nil,
        {{label = "Continue editing"}, {label = "Discard", action = discard, closeFirst = true},
        {label = "Save", action = save, primary = true, closeFirst = true}})
end

function UI:closeModal()
    for _, c in ipairs(self.modalConnections or {}) do c:Disconnect() end
    self.modalConnections, self.modalOpen = {}, false
    if self.modalGui then self.modalGui:Destroy(); self.modalGui = nil end
    self.dialogCard, self.dialogHeading, self.dialogScroller = nil, nil, nil
end

function UI:chooseElement(key)
    self.app:select(key, self.app.preferences.multiSelect)
    if not self.app.preferences.multiSelect then self:setWorkspace(false) end
end

function UI:makeElements()
    local body = self.pageBodies.Elements
    self.search = self:textbox(body, "Search elements", "")
    self:connect(self.search:GetPropertyChangedSignal("Text"), function()
        self.elementPage, self.elementSignature = 1, nil
        self:refreshElements()
    end)
    local builtins = frame(body, 44)
    self.builtinButtons = {}
    for i, entry in ipairs({{"JumpButton", "Jump"}, {"ThumbstickFrame", "Classic stick"}, {"DynamicThumbstickFrame", "Dynamic stick"}}) do
        local kind = entry[1]
        local button = self:button(builtins, entry[2], function()
            if self.builtinKeys[kind] then self:chooseElement(self.builtinKeys[kind]) end
        end, 1 / 3, (i - 1) / 3)
        if i == 3 then button.Size = UDim2.new(1 / 3, 0, 0, 44) end
        self.builtinButtons[kind] = button
    end
    self.elementPath = label(body, "", 24, 12)
    self.elementPath.TextColor3 = C.muted
    truncate(self.elementPath)
    self:row(body, {{"Parent", function() self:selectParent() end}, {"Children", function() self:showChildren() end},
        {"Clear", function()
            self.childParent = nil
            self.app:clearSelection()
            self:refreshElements()
        end}})
    self.overlapList = make("Frame", {Name = "OverlapCandidates", BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false, ZIndex = 23}, body)
    flow(self.overlapList, 5)
    self.compatibleFilter = self:button(body, "All visible elements", function()
        self.onlyEditable = not self.onlyEditable
        self.compatibleFilter.Text = self.onlyEditable and "Editable elements only" or "All visible elements"
        self.elementPage, self.elementSignature = 1, nil
        self:refreshElements()
    end)
    self.elementList = make("Frame", {Name = "Matches", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 23}, body)
    flow(self.elementList, 5)
    self.elementRows = {}
    self.pager = frame(body, 44)
    self.pagerBack = self:button(self.pager, "Previous", function()
        self.elementPage = self.elementPage - 1
        self:refreshElements()
    end, .33, 0)
    self.pagerNext = self:button(self.pager, "Next", function()
        self.elementPage = self.elementPage + 1
        self:refreshElements()
    end, .33, .67)
    self.pagerCaption = label(self.pager, "", 44, 12)
    self.pagerCaption.Position, self.pagerCaption.Size = UDim2.new(.33, 0, 0, 0), UDim2.new(.34, 0, 0, 44)
    self.pagerCaption.TextXAlignment = Enum.TextXAlignment.Center
    self.remapLabel = label(body, "Choose a missing saved element, select its replacement, then remap.", 44, 12)
    self.remapLabel.TextColor3 = C.muted
    self.missingList = make("Frame", {Name = "MissingElements", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 23}, body)
    flow(self.missingList, 5)
    self.remapButton = self:button(body, "Remap to selection", function()
        if self.remapKey and #self.app.selection == 1 then
            self:confirm("Remap saved element", "Use the selected element in place of the missing element?", function()
                self.app:remap(self.remapKey, self.app.selection[1])
                self.remapKey = nil
                self:refreshElements()
            end)
        else self.app:status("Choose a missing element and exactly one replacement.") end
    end)
end

function UI:makeAdvanced()
    local body = self.pageBodies.Advanced
    self.selectionName = label(body, "Select an element", 28, 16)
    self.selectionName.Font = Enum.Font.GothamMedium
    truncate(self.selectionName)
    self.selectionDetail = label(body, "", 42, 12)
    self.selectionDetail.TextColor3 = C.muted
    self.selectionDetail.AutomaticSize = Enum.AutomaticSize.Y
    self.precisionHeading = self:section(body, "Position and size (px)")
    local names = {"X", "Y", "W", "H"}
    local fieldRow = frame(body, 66)
    self.fields = {}
    for i, name in ipairs(names) do
        local caption = label(fieldRow, name, 18, 12)
        caption.Position = UDim2.new((i - 1) / 4, 0, 0, 0)
        caption.Size = UDim2.new(.25, -4, 0, 18)
        caption.TextColor3 = C.muted
        local field = self:textbox(fieldRow, name, "", function(value)
            local n = validNumber(value)
            if not n then
                self.app:status("Enter a finite numeric value.")
                self:updateSelection()
                return
            end
            local bounds = self.app:currentBounds(true)
            if not bounds then return end
            if name == "X" or name == "Y" then
                self.app:geometry("position", {x = name == "X" and n or bounds.x, y = name == "Y" and n or bounds.y})
            else
                local info = self.app.sizeInfo and self.app:sizeInfo()
                local size = info and info.size or bounds
                local width, height = name == "W" and n or size.w, name == "H" and n or size.h
                if self.app.preferences.aspectLock ~= false then
                    if name == "W" then height = size.h * n / math.max(1, size.w)
                    else width = size.w * n / math.max(1, size.h) end
                end
                self.app:resize(width, height)
            end
        end, .25, (i - 1) / 4)
        field.Position = UDim2.new((i - 1) / 4, 0, 0, 20)
        self.fields[name] = field
    end
    self:row(body, {{"Left", function() self.app:move(-(self.app.preferences.step or 1), 0) end},
        {"Up", function() self.app:move(0, -(self.app.preferences.step or 1)) end},
        {"Down", function() self.app:move(0, self.app.preferences.step or 1) end},
        {"Right", function() self.app:move(self.app.preferences.step or 1, 0) end}})
    self:row(body, {{"Reset selection", function() self.app:reset() end}, {"Bring into view", function() self.app:recover() end}})
    self:section(body, "Group transformations")
    self:toggle(body, "Scale from center", "centerScale", false)
    self:toggle(body, "Adjust each member's size", "equalSize", false)
    label(body, "Member size changes keep the members in place. Group scaling also changes their spacing.", 42, 12).TextColor3 = C.muted
    self:row(body, {{"Align left", function() self.app:align("left") end}, {"Center X", function() self.app:align("centerX") end},
        {"Align right", function() self.app:align("right") end}})
    self:row(body, {{"Align top", function() self.app:align("top") end}, {"Center Y", function() self.app:align("centerY") end},
        {"Align bottom", function() self.app:align("bottom") end}})
    self:row(body, {{"Distribute X", function() self.app:distribute("x") end}, {"Distribute Y", function() self.app:distribute("y") end}})
    self:section(body, "Visual properties")
    self.visualHint = label(body, "Select one editable element.", 34, 12)
    self.visualHint.TextColor3 = C.muted
    self.rotation = self:textbox(body, "Rotation in degrees", "", function(v)
        local n = validNumber(v)
        if n then self.app:geometry("rotation", n) else self.app:status("Enter rotation in degrees.") end
    end)
    self.transparency = self:textbox(body, "Transparency from 0 to 1", "", function(v)
        local n = validNumber(v)
        if n then self.app:geometry("transparency", n) else self.app:status("Enter transparency from 0 to 1.") end
    end)
    self.experimental = self:button(body, "Approve experimental edits", function()
        local record = self.app.discovery:get(self.app.selection[1])
        if record and record.experimental then
            self:confirm("Experimental element", "A layout can overwrite this element's properties. Approval applies to this element and can be revoked.", function()
                self.app:approve(record.key, true)
            end)
        end
    end)
    self.revoke = self:button(body, "Revoke experimental approval", function()
        if self.app.selection[1] then self.app:approve(self.app.selection[1], false) end
    end)
end

function UI:selectParent()
    local record = self.app.discovery:get(self.app.selection[1])
    if not record then return end
    local parent = record.object.Parent
    local candidate = self.app.discovery.byObject and self.app.discovery.byObject[parent]
    if candidate then
        self.childParent = nil
        if self.app.selectMany then self.app:selectMany({candidate.key}) else self.app:select(candidate.key, false) end
        self:refreshElements()
        return
    end
    self.app:status("No accessible GUI parent is available.")
end

function UI:showChildren()
    if self.childParent then
        self.childParent = nil
    else
        local record = self.app.discovery:get(self.app.selection[1])
        if not record then self.app:status("Select a parent to list its children."); return end
        self.childParent = record.object
    end
    self.elementPage, self.elementSignature = 1, nil
    self:refreshElements()
end

function UI:makeGroups()
    local body = self.pageBodies.Groups
    self:section(body, "REUSABLE NAMED GROUPS")
    label(body, "Groups store element identities. Missing members stay saved; deleting a group leaves its elements intact.", 60, 12)
    self.groupName = self:textbox(body, "Group name", "")
    self:row(body, {{"Create from selection", function() self.app:group("create", self.groupName.Text) end}, {"Rename selected", function()
        self.app:group("rename", self.chosenGroup, self.groupName.Text)
    end}})
    self:row(body, {{"Add selected", function() self.app:group("add", self.chosenGroup) end}, {"Remove selected", function()
        self.app:group("remove", self.chosenGroup)
    end}})
    self:row(body, {{"Select group", function() self.app:group("select", self.chosenGroup) end}, {"Delete group", function()
        if self.chosenGroup then self:confirm("Delete group", "Delete “" .. self.chosenGroup .. "”? GUI elements will remain.", function() self.app:group("delete", self.chosenGroup) end) end
    end}})
    self:row(body, {{"Reset members", function() self.app:group("select", self.chosenGroup); self.app:reset() end}, {"Elements tab", function() self:setTab("Elements") end}})
    self.groupList = make("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 23}, body)
    flow(self.groupList)
    self:toggle(body, "Adjust each member's size", "equalSize", false)
    self:toggle(body, "Scale from center", "centerScale", false)
    self:section(body, "GROUP ALIGNMENT")
    self:row(body, {{"Left", function() self.app:align("left") end}, {"Center X", function() self.app:align("centerX") end}, {"Right", function() self.app:align("right") end}})
    self:row(body, {{"Top", function() self.app:align("top") end}, {"Center Y", function() self.app:align("centerY") end}, {"Bottom", function() self.app:align("bottom") end}})
    self:row(body, {{"Distribute X", function() self.app:distribute("x") end}, {"Distribute Y", function() self.app:distribute("y") end}})
end

function UI:makeProfiles()
    local body = self.pageBodies.Profiles
    self:section(body, "PROFILE SCOPE & PREVIEW")
    self.activeProfile = label(body, "No active profile", 44, 13)
    self:button(body, "Apply preview", function() self.app:profile("apply") end)
    self:button(body, "Cancel preview", function() self.app:profile("cancel") end)
    self.profileName = self:textbox(body, "Profile name", "")
    self.scope = "place"
    self.scopeButton = self:button(body, "Scope: place", function()
        local scopes = {"global", "experience", "place", "device", "orientation"}
        local index = 1
        for i, v in ipairs(scopes) do if v == self.scope then index = i end end
        self.scope = scopes[index % #scopes + 1]; self.scopeButton.Text = "Scope: " .. self.scope
    end)
    label(body, "Priority: global built-ins → experience → place → device → orientation. Create, preview, Apply, then Save.", 60, 11)
    self:row(body, {{"Create", function() self.app:profile("create", self.profileName.Text, self.scope) end},
        {"Rename", function() self.app:profile("rename", self.chosenProfile, self.profileName.Text) end},
        {"Duplicate", function() self.app:profile("duplicate", self.chosenProfile, self.profileName.Text) end}})
    self:row(body, {{"Preview selected", function() self.app:profile("preview", self.chosenProfile) end}, {"Delete selected", function()
        if self.chosenProfile then self:confirm("Delete profile", "Delete the selected saved profile? This is separate from restoring the original layout.", function()
            self.app:profile("delete", self.chosenProfile, true)
        end) end
    end}})
    self.profileList = make("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 23}, body)
    flow(self.profileList)
    self:section(body, "PORTABLE CONFIGURATION")
    self:row(body, {{"Export JSON", function() self:showExport() end}, {"Import JSON", function()
        self:modal("Import configuration", "Paste JSON, then preview. Existing profiles require explicit overwrite approval. Imported text is never executed.", "", "Preview import", function(value)
            local ok, problem = self.app:import(value)
            if ok == false or ok == nil then return false, problem or "Import rejected; see status." end
            return true
        end)
    end}})
    self:button(body, "Import with confirmed overwrite…", function()
        self:modal("Confirm profile overwrite", "This explicitly permits replacing profiles with matching IDs after validation. Settings first appear as a preview; Apply and Save are still required.", "", "Preview overwrite", function(value)
            local ok, problem = self.app:import(value, true)
            if ok == false or ok == nil then return false, problem or "Import rejected; see status." end
            return true
        end)
    end)
    self:row(body, {{"Suspend profile", function() self.app:profile("suspend", true) end}, {"Resume profile", function() self.app:profile("suspend", false) end}})
    self:button(body, "Restore original layout (keep profiles)", function() self.app:profile("restore") end)
    self.draftSection = make("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 23}, body)
    flow(self.draftSection)
    self.draftLabel = label(self.draftSection, "", 48, 12)
    local draftActions = frame(self.draftSection, 44)
    self.previewDraft = self:button(draftActions, "Preview draft", function() self.app:profile("recoverDraft") end, .5, 0)
    self:button(draftActions, "Discard draft", function()
        self:confirm("Discard draft", "Delete the local draft? Your saved profiles will stay available.", function() self.app:profile("discardDraft") end)
    end, .5, .5)
end

function UI:showExport()
    local text, problem = self.app:export()
    if not text then self.app:status(problem or "Export unavailable."); return end
    self:modal("Export configuration", "This JSON contains the latest Save checkpoint. Copy it somewhere you can access later.", text, "Copy", function(value)
        if self.app.storage then
            local ok, message = self.app.storage:copy(value)
            self.app:status(message)
            return ok, message
        end
        return false, "Clipboard unavailable. Select and copy the JSON from the text box."
    end)
end

function UI:makeSettings()
    local body = self.pageBodies.Settings
    self:section(body, "EDITING PREFERENCES")
    self:toggle(body, "Editing grid", "grid", true)
    self:toggle(body, "Snap to grid & guides", "snapping", false)
    self:toggle(body, "Multi-select taps", "multiSelect", false)
    self:toggle(body, "Box selection", "boxSelect", false)
    self.preferenceFields = {}
    self.preferenceFields.gridSize = self:textbox(body, "Grid spacing (4–128 pixels)", tostring(self.app.preferences.gridSize or 24), function(v)
        local n = tonumber(v); if n and n >= 4 and n <= 128 then self.app:setPreference("gridSize", n) else self.app:status("Grid spacing must be 4–128 pixels.") end
    end)
    self.preferenceFields.snapThreshold = self:textbox(body, "Guide threshold (1–32 pixels)", tostring(self.app.preferences.snapThreshold or 6), function(v)
        local n = tonumber(v); if n and n >= 1 and n <= 32 then self.app:setPreference("snapThreshold", n) else self.app:status("Guide threshold must be 1–32 pixels.") end
    end)
    self.preferenceFields.step = self:textbox(body, "Fine adjustment step (1–64)", tostring(self.app.preferences.step or 1), function(v)
        local n = tonumber(v); if n and n >= 1 and n <= 64 then self.app:setPreference("step", n) else self.app:status("Step must be 1–64 pixels.") end
    end)
    self.preferenceFields.shortcut = self:textbox(body, "Reopen key (for example F8)", self.app.preferences.shortcut or "F8", function(v)
        local ok, key = pcall(function() return Enum.KeyCode[v] end)
        if ok and key and key ~= Enum.KeyCode.Unknown then self.app:setPreference("shortcut", v) else self.app:status("Enter a valid Roblox KeyCode name.") end
    end)
    self:row(body, {{"Hide launcher", function() self.app:setPreference("launcherHidden", true) end}, {"Recover launcher", function()
        self.app:setPreference("launcherHidden", false); self.app:setPreference("launcherX", .02); self.app:setPreference("launcherY", .35)
    end}})
    label(body, "Reopen with the keyboard shortcut or rerun the release on a phone. The Heavenly Axis API also supports Open and SafeMode.", 54, 12)
    self:section(body, "RECOVERY & CAPABILITIES")
    self:button(body, "SAFE MODE · originals, profiles preserved", function() self.app:safeMode() end)
    self:button(body, "Verify automatic startup", function()
        if self.app.VerifyStartup then
            local result = self.app:VerifyStartup()
            local lines = {}
            for _, key in ipairs({"version", "startedAt", "alive", "mode", "profile", "storage", "unmatched", "note"}) do
                table.insert(lines, key .. ": " .. tostring(result[key]))
            end
            if result.application then table.insert(lines, "Applied: " .. tostring(result.application.applied or 0) .. "; skipped: " .. tostring(result.application.skipped or 0)) end
            self:modal("Startup session verification", "This reports the current session. Restart / rejoin and verify again to test your documented auto-execution setup.", table.concat(lines, "\n"))
        elseif self.app.verifyStartup then self.app:verifyStartup() else
            self.app:status("Verify by running LoaderOnly at a fresh join, then rerun to open. See startup instructions.")
        end
    end)
    self:button(body, "Automatic startup instructions", function()
        self:modal("Automatic startup", "Saving profiles does not install auto-execution. Only configure an executor you use and trust.",
            "1. Save a profile; confirm the status reports persistent storage.\n2. Put the local bundled release in the environment's documented startup folder.\n3. Before running it, set HeavenlyAxisOptions = {LoaderOnly = true}. Use getgenv().HeavenlyAxisOptions when supported.\n4. Restart/join, then call getgenv().__HEAVENLY_AXIS_V3:Open() to inspect diagnostics. In Studio use _G.__HEAVENLY_AXIS_V3:Open(). Alternatively set HeavenlyAxisOptions = {LoaderOnly = false} before rerunning the release.\n5. If the environment has no startup capability, run the release manually. No automatic installer is used.\n\nRecovery: rerun with HeavenlyAxisOptions = {SafeMode = true}; saved profiles remain intact.")
    end)
    self.capabilityLabel = label(body, "", 168, 11)
    self.capabilityLabel.TextYAlignment = Enum.TextYAlignment.Top
    self:section(body, "VERSION & DIAGNOSTICS")
    label(body, "Heavenly Axis " .. tostring(self.app.version or "3.0.0")
        .. "\nRoblox HUD & Interface Editor\nOriginal by Syshi. V2 inspired by Danechka.", 60, 12)
    self:button(body, "Check project releases (optional)", function() self.app:checkUpdates() end)
    self:button(body, "Expandable diagnostic log", function()
        local lines = {}
        local stats = self.app.discovery.stats
        if stats then
            lines[#lines + 1] = string.format("Discovery: %s scans, %s indexed, %.2f ms last scan", tostring(stats.scans or 0),
                tostring(stats.indexed or 0), stats.lastScanMs or 0)
        end
        for _, entry in ipairs(self.app.logs or self.app.diagnostics or {}) do
            table.insert(lines, type(entry) == "table" and tostring(entry.message or entry.text or "") or tostring(entry))
        end
        self:modal("Diagnostics", "Runtime observations and failures. This log does not establish device or executor compatibility.", table.concat(lines, "\n"))
    end)
    label(body, "Touch-control visuals are editable only when accessible. Functional joystick / jump hit regions and complete gameplay-input isolation remain unverified until tested on your device.", 92, 11).TextColor3 = C.warning
end

local function brand(parent, zIndex)
    local mark = make("Frame", {Name = "AxisMark", BackgroundTransparency = 1, Size = UDim2.fromOffset(24, 24),
        ZIndex = zIndex}, parent)
    local axis = make("Frame", {BackgroundColor3 = C.cyan, BorderSizePixel = 0, Position = UDim2.fromOffset(5, 3),
        Size = UDim2.fromOffset(2, 16), ZIndex = zIndex}, mark)
    corners(axis, 1)
    local base = make("Frame", {BackgroundColor3 = C.cyan, BorderSizePixel = 0, Position = UDim2.fromOffset(5, 17),
        Size = UDim2.fromOffset(14, 2), ZIndex = zIndex}, mark)
    corners(base, 1)
    local point = make("Frame", {BackgroundColor3 = C.cyan, BorderSizePixel = 0, Position = UDim2.fromOffset(12, 4),
        Size = UDim2.fromOffset(8, 8), Rotation = 45, ZIndex = zIndex}, mark)
    corners(point, 2)
    return mark
end

function UI:makeToolbar()
    local toolbar = make("Frame", {Name = "Toolbar", BackgroundColor3 = C.surface, BackgroundTransparency = .035,
        BorderSizePixel = 0, ZIndex = 34, Visible = false, Active = true}, self.root)
    self.toolbar = toolbar
    corners(toolbar, 12); outline(toolbar)
    self.toolbarBrand = brand(toolbar, 35)
    self.toolbarBrand.Position = UDim2.fromOffset(9, 12)
    local actions = {
        {"Edit", function()
            self:setWorkspace(false)
            self:setCollapsed(false)
        end, 45},
        {"Elements", function()
            if self.workspaceOpen and self.tab == "Elements" then self:setWorkspace(false)
            else self:setTab("Elements") end
        end, 58},
        {"Multi", function() self.app:setPreference("multiSelect", not self.app.preferences.multiSelect) end, 45},
        {"Undo", function() self.app:undo() end, 44},
        {"Redo", function() self.app:redo() end, 44},
        {"Tools", function()
            if self.workspaceOpen then self:setWorkspace(false)
            else self:setTab(self.tab == "Elements" and "Settings" or self.tab) end
        end, 45},
        {"Save", function() self.app:save() end, 44},
        {"Done", function()
            if self.app.Done then self.app:Done()
            else self.app:setEditing(false) end
        end, 46},
    }
    self.toolbarButtons = {}
    for _, action in ipairs(actions) do
        local name, callback, width = action[1], action[2], action[3]
        local button = self:button(toolbar, name, callback)
        button.BackgroundTransparency = name == "Done" and 0 or 1
        button.TextSize = 12
        truncate(button)
        self.toolbarButtons[#self.toolbarButtons + 1] = {name = name, button = button, width = width}
        self[name:lower() .. "Button"] = button
    end
end

function UI:makeQuickEdit()
    local panel = make("Frame", {Name = "QuickEdit", BackgroundColor3 = C.surface, BackgroundTransparency = .02,
        BorderSizePixel = 0, ZIndex = 24, Visible = false, Active = true, ClipsDescendants = true}, self.root)
    self.panel = panel
    corners(panel, 13)
    outline(panel)
    self.inspectorGrip = self:button(panel, "", nil)
    self.inspectorGrip.Name = "MoveInspector"
    self.inspectorGrip.Position, self.inspectorGrip.Size = UDim2.fromOffset(7, 4), UDim2.new(1, -64, 0, 44)
    self.inspectorGrip.BackgroundTransparency = 1
    self.inspectorGrip.AutoButtonColor = false
    self.quickName = label(self.inspectorGrip, "Selection", 20, 15)
    self.quickName.Font = Enum.Font.GothamBold
    self.quickName.ZIndex = 26
    self.quickName.Position, self.quickName.Size = UDim2.fromOffset(4, 2), UDim2.new(1, -17, 0, 20)
    truncate(self.quickName)
    self.quickHint = label(self.inspectorGrip, "Drag element to move", 18, 11)
    self.quickHint.ZIndex, self.quickHint.TextColor3 = 26, C.muted
    self.quickHint.Position, self.quickHint.Size = UDim2.fromOffset(4, 22), UDim2.new(1, -10, 0, 18)
    truncate(self.quickHint)
    for y = 18, 24, 6 do
        local gripLine = make("Frame", {BackgroundColor3 = C.quiet, BorderSizePixel = 0,
            Position = UDim2.new(1, -9, 0, y), Size = UDim2.fromOffset(9, 2), ZIndex = 26}, self.inspectorGrip)
        corners(gripLine, 1)
    end
    local hide = self:button(panel, "Hide", function() self:setCollapsed(true) end)
    hide.Position, hide.Size = UDim2.new(1, -52, 0, 4), UDim2.fromOffset(44, 44)
    hide.BackgroundTransparency, hide.TextColor3 = 1, C.muted
    self.quickHide = hide
    local body = make("ScrollingFrame", {Name = "QuickControls", BackgroundTransparency = 1, BorderSizePixel = 0,
        Position = UDim2.fromOffset(8, 52), Size = UDim2.new(1, -16, 1, -58),
        CanvasSize = UDim2.fromOffset(0, 142), ScrollBarThickness = 2, ScrollingDirection = Enum.ScrollingDirection.Y,
        Active = true, ScrollingEnabled = true, ClipsDescendants = true,
        ScrollBarImageColor3 = C.cyan, ZIndex = 25}, panel)
    self.quickBody = body
    self.slider = self:button(body, "", nil)
    self.slider.Name = "SizeSlider"
    self.slider.BackgroundColor3 = C.field
    self.slider.AutoButtonColor = false
    self.sliderTitle = label(self.slider, "Size", 18, 11)
    self.sliderTitle.Position, self.sliderTitle.ZIndex = UDim2.fromOffset(10, 1), 28
    self.sliderTitle.Size, self.sliderTitle.TextColor3 = UDim2.new(1, -20, 0, 19), C.muted
    self.sliderTrack = make("Frame", {Name = "Track", BackgroundColor3 = C.border, BorderSizePixel = 0,
        Position = UDim2.fromOffset(15, 26), Size = UDim2.new(1, -30, 0, 3), ZIndex = 28}, self.slider)
    corners(self.sliderTrack, 2)
    self.sliderFill = make("Frame", {Name = "Amount", BackgroundColor3 = C.cyan, BorderSizePixel = 0,
        Size = UDim2.fromScale(0, 1), ZIndex = 29}, self.sliderTrack)
    corners(self.sliderFill, 2)
    self.sliderThumb = make("Frame", {Name = "Thumb", BackgroundColor3 = C.cyan, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(0, .5), Size = UDim2.fromOffset(14, 14), ZIndex = 30}, self.sliderTrack)
    corners(self.sliderThumb, 7)
    local values = frame(body, 44)
    values.Position, values.ZIndex = UDim2.fromOffset(0, 48), 26
    local minus = self:button(values, "-", function()
        if self.app.stepSize then self.app:stepSize(-1) else self.app:scale(.99) end
    end)
    minus.Size = UDim2.fromOffset(44, 44)
    self.percent = self:textbox(values, "Size %", "", function(value)
        local n = validNumber((value:gsub("%%", "")))
        if n and self.app.setSizePercent then self.app:setSizePercent(n)
        elseif not n then self.app:status("Enter a valid size percentage.") end
        self:updateSelection()
    end)
    self.percent.Position, self.percent.Size = UDim2.fromOffset(48, 0), UDim2.fromOffset(59, 44)
    self.percent.Font = Enum.Font.GothamMedium
    local plus = self:button(values, "+", function()
        if self.app.stepSize then self.app:stepSize(1) else self.app:scale(1.01) end
    end)
    plus.Position, plus.Size = UDim2.fromOffset(111, 0), UDim2.fromOffset(44, 44)
    self.quickSize = label(values, "", 44, 12)
    self.quickSize.Position, self.quickSize.Size = UDim2.fromOffset(160, 0), UDim2.new(1, -160, 0, 44)
    self.quickSize.TextXAlignment, self.quickSize.TextColor3, self.quickSize.ZIndex = Enum.TextXAlignment.Center, C.muted, 28
    truncate(self.quickSize)
    local actions = frame(body, 44)
    actions.Position, actions.ZIndex = UDim2.fromOffset(0, 96), 26
    self.quickLock = self:toggle(actions, "Aspect", "aspectLock", true)
    self.quickLock.Size = UDim2.new(.34, -4, 0, 44)
    self.quickReset = self:button(actions, "Reset", function() self.app:reset() end, .30, .34)
    local advanced = self:button(actions, "Advanced", function() self:setTab("Advanced") end, .36, .64)
    advanced.Size = UDim2.new(.36, 0, 0, 44)
    self.quickEdits = {minus, plus, self.quickLock, self.quickReset}
    self.sliderEnabled = false
end

function UI:makeWorkspace()
    self.workspace = make("Frame", {Name = "Workspace", BackgroundColor3 = C.surface, BorderSizePixel = 0,
        ZIndex = 40, Visible = false, Active = true, ClipsDescendants = true}, self.root)
    corners(self.workspace, 13); outline(self.workspace)
    local header = frame(self.workspace, 44)
    header.Position, header.Size, header.ZIndex = UDim2.fromOffset(8, 4), UDim2.new(1, -16, 0, 44), 41
    local back = self:button(header, "Canvas", function() self:setWorkspace(false) end)
    back.Size = UDim2.fromOffset(68, 44)
    back.BackgroundTransparency, back.TextColor3 = 1, C.cyan
    local title = label(header, "Editor tools", 44, 16)
    title.Position, title.Size, title.ZIndex = UDim2.fromOffset(75, 0), UDim2.new(1, -75, 0, 44), 42
    title.Font = Enum.Font.GothamBold
    self.tabs = make("ScrollingFrame", {Name = "ToolsNavigation", BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 2, ScrollBarImageColor3 = C.cyan, ScrollingDirection = Enum.ScrollingDirection.X,
        Active = true, ClipsDescendants = true,
        Position = UDim2.fromOffset(8, 50), Size = UDim2.new(1, -16, 0, 47),
        CanvasSize = UDim2.fromOffset(330, 0), ZIndex = 41}, self.workspace)
    self.tabButtons, self.pages, self.pageBodies = {}, {}, {}
    local navX = 0
    for _, name in ipairs({"Elements", "Advanced", "Groups", "Profiles", "Settings"}) do
        local width = name == "Advanced" and 68 or 62
        local button = self:button(self.tabs, name, function() self:setTab(name) end)
        button.Position, button.Size = UDim2.fromOffset(navX, 0), UDim2.fromOffset(width, 44)
        self.tabButtons[name] = button
        navX = navX + width + 3
        local page = make("ScrollingFrame", {Name = name, BackgroundTransparency = 1, BorderSizePixel = 0,
            ScrollBarThickness = 3, ScrollBarImageColor3 = C.cyan, CanvasSize = UDim2.new(),
            Active = true, ClipsDescendants = true,
            AutomaticCanvasSize = Enum.AutomaticSize.None, Position = UDim2.fromOffset(10, 102),
            Size = UDim2.new(1, -20, 1, -110), Visible = name == "Elements", ZIndex = 41,
            ScrollingDirection = Enum.ScrollingDirection.Y}, self.workspace)
        local body = make("Frame", {Name = "Content", BackgroundTransparency = 1, Size = UDim2.new(1, -6, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 42}, page)
        self:bindScroll(page, body, 6)
        self.pages[name], self.pageBodies[name] = page, body
    end
    self.tabs.CanvasSize = UDim2.fromOffset(navX - 3, 0)
    self:makeElements(); self:makeAdvanced(); self:makeGroups(); self:makeProfiles(); self:makeSettings()
end

local anchors = {
    nw = {0, 0}, n = {.5, 0}, ne = {1, 0}, e = {1, .5}, se = {1, 1}, s = {.5, 1}, sw = {0, 1}, w = {0, .5},
}

function UI:makeCanvas()
    self.canvas = make("TextButton", {Name = "EditSurface", Text = "", BackgroundTransparency = 1, AutoButtonColor = false,
        Active = true, Size = UDim2.fromScale(1, 1), ZIndex = 2, Visible = false}, self.root)
    self.gridLayer = make("Frame", {Name = "Grid", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3, Visible = false}, self.root)
    self.overlay = make("Frame", {Name = "SelectionOverlay", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5, Visible = false}, self.root)
    self.selectionBounds = make("Frame", {Name = "SelectionBounds", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 6, Visible = false}, self.overlay)
    self.selectionStroke = outline(self.selectionBounds, C.cyan, 2)
    self.individual = {}
    self.box = make("Frame", {Name = "BoxSelection", BackgroundColor3 = C.cyan, BackgroundTransparency = .9,
        BorderSizePixel = 0, ZIndex = 6, Visible = false}, self.overlay)
    outline(self.box, C.cyan)
    for _, handle in ipairs({"nw", "n", "ne", "e", "se", "s", "sw", "w"}) do
        local b = make("TextButton", {Name = "Resize_" .. handle, Text = "", BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(.5, .5), AutoButtonColor = false, ZIndex = 10, Visible = false}, self.selectionBounds)
        local marker = make("Frame", {BackgroundColor3 = C.cyan, BorderSizePixel = 0, AnchorPoint = Vector2.new(.5, .5),
            Position = UDim2.fromScale(.5, .5), Size = UDim2.fromOffset(12, 12), ZIndex = 11}, b)
        corners(marker, 4); outline(marker, C.ink)
        local entry = {gui = b, marker = marker, handle = handle, anchor = anchors[handle]}
        self.handles[#self.handles + 1] = entry
        if handle == "se" then self.touchHandle = entry end
    end
end

function UI.new(app, playerGui, services)
    local self = setmetatable({app = app, services = services, connections = {}, elementConnections = {}, groupConnections = {},
        profileConnections = {}, missingConnections = {}, selectionConnections = {}, overlapConnections = {}, toggles = {},
        handles = {}, guideObjects = {}, gridObjects = {}, disabled = setmetatable({}, {__mode = "k"}),
        presentedText = setmetatable({}, {__mode = "k"}),
        visible = false, tab = "Elements", collapsed = false, elementPage = 1, builtinKeys = {}}, UI)
    local ok, result = pcall(function()
        self.gui = make("ScreenGui", {Name = "HeavenlyAxis", ResetOnSpawn = false, IgnoreGuiInset = true,
            DisplayOrder = 10000, ZIndexBehavior = Enum.ZIndexBehavior.Global}, playerGui)
        pcall(function()
            self.gui.ScreenInsets = Enum.ScreenInsets.None
            self.gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
            self.gui.ClipToDeviceSafeArea = false
        end)
        self.root = make("Frame", {Name = "EditorRoot", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1}, self.gui)
        self:makeCanvas()
        self:makeToolbar()
        self:makeQuickEdit()
        self:makeWorkspace()

        self.toast = make("Frame", {Name = "Toast", BackgroundColor3 = C.surface, BackgroundTransparency = .04,
            BorderSizePixel = 0, Visible = false, ZIndex = 55}, self.root)
        corners(self.toast, 10); outline(self.toast)
        self.statusLabel = label(self.toast, "", 34, 12)
        self.statusLabel.Position, self.statusLabel.Size = UDim2.fromOffset(9, 4), UDim2.new(1, -18, 1, -8)
        self.statusLabel.TextXAlignment, self.statusLabel.ZIndex = Enum.TextXAlignment.Center, 56

        self.launcher = make("TextButton", {Name = "HeavenlyAxisLauncher", Text = "", BackgroundColor3 = C.surface,
            BorderSizePixel = 0, Size = UDim2.fromOffset(48, 48), ZIndex = 50, AutoButtonColor = true}, self.root)
        corners(self.launcher, 15); outline(self.launcher)
        local mark = brand(self.launcher, 51)
        mark.Position = UDim2.fromOffset(13, 6)
        local launcherName = label(self.launcher, "AXIS", 13, 10)
        launcherName.Position, launcherName.Size = UDim2.fromOffset(0, 28), UDim2.new(1, 0, 0, 13)
        launcherName.TextXAlignment = Enum.TextXAlignment.Center
        launcherName.TextColor3, launcherName.ZIndex, launcherName.Font = C.cyan, 51, Enum.Font.GothamBold

        self:connect(self.root:GetPropertyChangedSignal("AbsoluteSize"), function() self:layout() end)
        self:connect(self.root:GetPropertyChangedSignal("AbsolutePosition"), function() self:layout() end)
        local uis = self.services.UserInputService
        if uis.GetPropertyChangedSignal then
            for _, property in ipairs({"PreferredInput", "OnScreenKeyboardVisible", "OnScreenKeyboardSize"}) do
                local exists, signal = pcall(function() return uis:GetPropertyChangedSignal(property) end)
                if exists and signal then self:connect(signal, function() self:layout() end) end
            end
        end
        self:layout()
        self:refresh()
        return self
    end)
    if not ok then self:destroy(); error(result, 0) end
    return result
end

function UI:setCollapsed(collapsed)
    if self.collapsed == collapsed then return end
    if self.app.input then self.app.input:cancel() end
    self.collapsed = collapsed
    self:showSurfaces()
    self:updateSelection()
    self:refreshToolbar()
end

function UI:setWorkspace(open)
    if self.workspaceOpen ~= open then
        if self.app.input then self.app.input:cancel() end
        self.workspaceOpen = open
        if open and self.tab == "Elements" then self.elementRevision = nil end
        self:showSurfaces()
        self:updateSelection()
    end
    self:refreshToolbar()
    if open then self:refreshPage() end
end

function UI:setTab(name)
    if not self.pages[name] then return end
    if self.tab ~= name and self.app.input then self.app.input:cancel() end
    if self.tab ~= name and name == "Elements" then self.elementRevision = nil end
    self.tab = name
    for key, page in pairs(self.pages) do page.Visible = key == name end
    for key, button in pairs(self.tabButtons) do
        button.TextColor3 = key == name and C.cyan or C.muted
        button.BackgroundColor3 = key == name and C.selected or C.raised
    end
    self:setWorkspace(true)
end

function UI:viewport()
    local camera = self.services.Workspace.CurrentCamera
    if camera then return camera.ViewportSize.X, camera.ViewportSize.Y end
    local rect = Coordinates.rect(self.root)
    return math.max(1, rect and rect.w or 320), math.max(1, rect and rect.h or 240)
end

function UI:showSurfaces()
    self.toolbar.Visible = self.visible and self.layoutPlan and self.layoutPlan.toolbarVisible or false
    self.workspace.Visible = self.visible and self.workspaceOpen == true
    self.panel.Visible = self.visible and not self.workspaceOpen and not self.collapsed and #self.app.selection > 0
    self.launcher.Visible = not self.visible and self.app.preferences.launcherHidden ~= true
end

function UI:layoutToolbar(plan)
    local showSave = plan.toolbar.w >= 425
    self.toolbarBrand.Visible = plan.brandVisible
    local x = plan.brandVisible and 38 or 4
    local total = 0
    for _, entry in ipairs(self.toolbarButtons) do
        if showSave or entry.name ~= "Save" then total = total + entry.width end
    end
    local factor = (plan.toolbar.w - x - 4) / total
    for _, entry in ipairs(self.toolbarButtons) do
        local button = entry.button
        button.Visible = showSave or entry.name ~= "Save"
        if button.Visible then
            local width = math.floor(entry.width * factor)
            button.Position, button.Size = UDim2.fromOffset(x, 2), UDim2.fromOffset(width, math.max(1, math.min(44, plan.toolbar.h - 2)))
            x = x + width
        end
    end
end

function UI:placeInspector()
    local plan = self.layoutPlan
    local panel = Layout.panelForSelection(plan, self.selectionDockBounds, self.manualPanel)
    if self.inspectorUnavailable then
        local height = math.min(56, panel.h)
        local y = plan.portrait and not self.manualPanel and panel.y + panel.h - height or panel.y
        panel = Layout.place({w = panel.w, h = height}, plan.content, panel.x, y)
    end
    localRect(self.panel, panel)
end

function UI:layout()
    if self.dead then return end
    local w, h = self:viewport()
    local guiService = self.services.GuiService
    local device = Coordinates.safeRect(guiService, w, h)
    local core = Coordinates.coreRect(guiService, w, h)
    self.safeArea = Coordinates.intersection(device, core) or device
    local uis = self.services.UserInputService
    local preferred, touchPreference, keyboardHeight
    pcall(function() preferred, touchPreference = uis.PreferredInput, Enum.PreferredInput.Touch end)
    pcall(function() if uis.OnScreenKeyboardVisible then keyboardHeight = uis.OnScreenKeyboardSize.Y end end)
    self.mobile = (preferred ~= nil and preferred == touchPreference) or (preferred == nil and uis.TouchEnabled == true)
    local plan = Layout.plan(self.safeArea, self.mobile, keyboardHeight)
    self.layoutPlan = plan
    localRect(self.toolbar, plan.toolbar)
    self:layoutToolbar(plan)
    self:placeInspector()
    localRect(self.workspace, plan.workspace)
    self.tabs.Visible = plan.workspace.h >= 142
    local bodyTop = self.tabs.Visible and 100 or 49
    for _, page in pairs(self.pages) do
        page.Position, page.Size = UDim2.fromOffset(10, bodyTop), UDim2.new(1, -20, 0, math.max(1, plan.workspace.h - bodyTop - 8))
    end
    local area = plan.area
    local toastW = math.min(395, area.w)
    localRect(self.toast, {x = area.x + (area.w - toastW) / 2, y = area.y + math.max(0, area.h - 44), w = toastW, h = 44})
    self:positionLauncher()
    self:showSurfaces()
    self:layoutDialog()
    self:drawGrid()
    self:updateSelection()
    self:layoutKeyboard((keyboardHeight or 0) > 0)
end

function UI:viewportChanged()
    self.elementRevision = nil
    self:layout()
    self:refresh()
end

function UI:layoutKeyboard(keyboard)
    local quickFocused = keyboard and self.percent:IsFocused()
    self.inspectorGrip.Visible, self.quickHide.Visible = not quickFocused, not quickFocused
    self.quickBody.Position = UDim2.fromOffset(8, quickFocused and 6 or 52)
    self.quickBody.Size = UDim2.new(1, -16, 1, quickFocused and -12 or -58)
    if quickFocused then
        self.quickBody.CanvasPosition = Vector2.new(0, 48)
    elseif self.quickKeyboard then
        self.quickBody.CanvasPosition = Vector2.new(0, 0)
    end
    self.quickKeyboard = quickFocused
    if not keyboard or not self.workspace.Visible or self.tab ~= "Advanced" then return end
    local page = self.pages.Advanced
    local focused
    for _, box in pairs(self.fields) do if box:IsFocused() then focused = box; break end end
    if not focused then
        if self.rotation:IsFocused() then focused = self.rotation
        elseif self.transparency:IsFocused() then focused = self.transparency end
    end
    if not focused then return end
    local pageRect, fieldRect = Coordinates.rect(page), Coordinates.rect(focused)
    if pageRect and fieldRect then
        local scroll = page.CanvasPosition
        page.CanvasPosition = Vector2.new(0, math.max(0, (scroll and scroll.Y or 0) + fieldRect.y - pageRect.y - 4))
    end
end

function UI:inspectorPosition()
    local rect = Coordinates.rect(self.panel)
    return rect and rect.x or 0, rect and rect.y or 0
end

function UI:moveInspector(x, y)
    if not self.layoutPlan or not self.panel.Visible then return end
    if not self.movingPanel then
        self.movingPanel, self.priorManualPanel = true, self.manualPanel
    end
    self.manualPanel = {x = x, y = y}
    self:placeInspector()
end

function UI:finishInspectorMove(cancelled)
    if not self.movingPanel then return end
    if cancelled then self.manualPanel = self.priorManualPanel end
    self.movingPanel, self.priorManualPanel = false, nil
    self:placeInspector()
    self:updateSelection()
end

function UI:launcherArea()
    local safe = self.safeArea
    return {x = safe.x + 8, y = safe.y + 8, w = math.max(1, safe.w - 16), h = math.max(1, safe.h - 16)}
end

function UI:positionLauncher()
    if self.launcherDragging or not self.safeArea then return end
    local area = self:launcherArea()
    local shape = {w = 48, h = 48}
    local prefs = self.app.preferences
    local x = (prefs.launcherX or .02) <= .5 and area.x or area.x + area.w - shape.w
    local y = area.y + (prefs.launcherY or .35) * math.max(0, area.h - shape.h)
    localRect(self.launcher, Layout.place(shape, area, x, y))
end

function UI:moveLauncher(x, y)
    if not self.safeArea then return end
    self.launcherDragging = true
    self.launcherDragRect = Layout.place({w = 48, h = 48}, self:launcherArea(), x, y)
    localRect(self.launcher, self.launcherDragRect)
end

function UI:finishLauncherMove(cancelled)
    self.launcherDragging = false
    local rect = self.launcherDragRect
    self.launcherDragRect = nil
    if not cancelled and self.safeArea and rect then
        local area = self:launcherArea()
        local x = rect.x + rect.w / 2 <= area.x + area.w / 2 and 0 or 1
        local y = math.max(0, math.min(1, (rect.y - area.y) / math.max(1, area.h - rect.h)))
        if self.app.setLauncherPosition then self.app:setLauncherPosition(x, y)
        else
            self.app:setPreference("launcherX", x)
            self.app:setPreference("launcherY", y)
        end
    end
    self:positionLauncher()
end

function UI:gridSpacing()
    local w, h = self:viewport()
    local base = math.max(4, math.min(128, self.app.preferences.gridSize or 24))
    return base * math.max(1, math.ceil(math.max(w, h) / (80 * base)))
end

function UI:drawGrid()
    self.gridLayer.Visible = self.visible and self.app.preferences.grid ~= false
    if not self.gridLayer.Visible then return end
    local display = Coordinates.rect(self.root)
    if not display or display.w <= 0 or display.h <= 0 then return end
    local spacing = self:gridSpacing()
    local signature = table.concat({display.x, display.y, display.w, display.h, spacing}, ":")
    if signature == self.gridSignature then return end
    self.gridSignature = signature
    local count = 0
    local function line(x, y, w, h)
        count = count + 1
        local object = self.gridObjects[count]
        if not object then
            object = make("Frame", {BackgroundColor3 = C.cyan, BackgroundTransparency = .93, BorderSizePixel = 0, ZIndex = 3}, self.gridLayer)
            self.gridObjects[count] = object
        end
        object.Position, object.Size, object.Visible = UDim2.fromOffset(x, y), UDim2.fromOffset(w, h), true
    end
    for x = math.ceil(display.x / spacing) * spacing, display.x + display.w - 1, spacing do
        line(x - display.x, 0, 1, display.h)
    end
    for y = math.ceil(display.y / spacing) * spacing, display.y + display.h - 1, spacing do
        line(0, y - display.y, display.w, 1)
    end
    for i = count + 1, #self.gridObjects do self.gridObjects[i].Visible = false end
end

function UI:pointInPanel(x, y)
    return self.modalOpen or inside(self.toolbar, x, y) or inside(self.panel, x, y)
        or inside(self.workspace, x, y) or inside(self.launcher, x, y)
end

function UI:sliderTrackRect()
    return self.sliderEnabled and self.panel.Visible and Coordinates.rect(self.sliderTrack) or nil
end

function UI:setSliderDragging(dragging)
    self.quickBody.ScrollingEnabled = not dragging
end

function UI:setBox(rect)
    self.box.Visible = rect ~= nil and self.visible
    if rect then localRect(self.box, rect) end
end

function UI:setGuides(guides)
    local display = Coordinates.rect(self.root)
    if not display then return end
    for i = 1, 6 do
        local guide, object = guides and guides[i], self.guideObjects[i]
        local coordinate = guide and (guide.value or guide.position)
        if coordinate and self.visible then
            if not object then
                object = make("Frame", {BackgroundColor3 = C.cyan, BackgroundTransparency = .2, BorderSizePixel = 0,
                    ZIndex = 7}, self.overlay)
                self.guideObjects[i] = object
            end
            local axis = guide.axis
            localRect(object, {x = axis == "x" and coordinate or display.x, y = axis == "y" and coordinate or display.y,
                w = axis == "x" and 1 or display.w, h = axis == "y" and 1 or display.h})
            object.Visible = true
        elseif object then object.Visible = false end
    end
end

local touchCorners = {
    {name = "se", anchor = anchors.se, sx = 1, sy = 1}, {name = "sw", anchor = anchors.sw, sx = -1, sy = 1},
    {name = "ne", anchor = anchors.ne, sx = 1, sy = -1}, {name = "nw", anchor = anchors.nw, sx = -1, sy = -1},
}
local touchOffsets = {{0, 1}, {1, 0}, {1, 1}}

local function usableHandle(hit, safe, panel, toolbar, workspace)
    return hit.x >= safe.x and hit.y >= safe.y and hit.x + hit.w <= safe.x + safe.w
        and hit.y + hit.h <= safe.y + safe.h and not Layout.intersects(hit, panel)
        and not Layout.intersects(hit, toolbar) and not Layout.intersects(hit, workspace)
end

function UI:showTouchHandle(bounds, corner, x, y, size, markerX, markerY)
    local handle = self.touchHandle
    handle.handle = corner.name
    handle.gui.Position = UDim2.fromOffset(x - bounds.x, y - bounds.y)
    handle.gui.Size = UDim2.fromOffset(size, size)
    handle.marker.Position = UDim2.new(.5, markerX, .5, markerY)
    handle.gui.Visible = true
end

function UI:placeTouchHandle(bounds)
    local safe, panel, toolbar, workspace = self.safeArea, self.panel.Visible and Coordinates.rect(self.panel),
        self.toolbar.Visible and Coordinates.rect(self.toolbar), self.workspace.Visible and Coordinates.rect(self.workspace)
    for _, size in ipairs({44, 34}) do
        local half = size / 2
        for _, offset in ipairs(touchOffsets) do
            for _, corner in ipairs(touchCorners) do
                local dx, dy = offset[1] * corner.sx, offset[2] * corner.sy
                local x = bounds.x + corner.anchor[1] * bounds.w + dx * (half + 2)
                local y = bounds.y + corner.anchor[2] * bounds.h + dy * (half + 2)
                if usableHandle({x = x - half, y = y - half, w = size, h = size}, safe, panel, toolbar, workspace) then
                    self:showTouchHandle(bounds, corner, x, y, size, -dx * 10, -dy * 10)
                    return
                end
            end
        end
    end
    -- A large selection still has room for movement if a corner handle sits just inside it.
    if bounds.w < 88 or bounds.h < 88 then return end
    for _, corner in ipairs(touchCorners) do
        local x = bounds.x + corner.anchor[1] * bounds.w - corner.sx * 24
        local y = bounds.y + corner.anchor[2] * bounds.h - corner.sy * 24
        if usableHandle({x = x - 22, y = y - 22, w = 44, h = 44}, safe, panel, toolbar, workspace) then
            self:showTouchHandle(bounds, corner, x, y, 44, corner.sx * 10, corner.sy * 10)
            return
        end
    end
end

function UI:updateSelection()
    if self.dead or not self.visible then return end
    local rects, keys = self.app:getRects(true)
    local bounds = Geometry.bounds(rects or {})
    local displayedBounds = bounds
    local record = #self.app.selection == 1 and self.app.discovery:get(self.app.selection[1]) or nil
    if not displayedBounds and record then displayedBounds = Coordinates.rect(record.object) end
    local suspended = self.app.profiles and self.app.profiles.suspended
    local checking = self.app.finishingGesture or self.app.saving
    local writable = not self.app.previewState and not checking and not suspended
    local gestureReady = bounds ~= nil and writable
    local hint = "Drag element to move"
    if not bounds then hint = "View details in Tools"
    elseif self.app.previewState then hint = "Profile preview"
    elseif suspended then hint = "Profiles suspended"
    elseif checking then hint = "Checking layout"
    elseif #self.app.selection > 1 then hint = "Drag selection to move" end
    if self.quickHint.Text ~= hint then self.quickHint.Text = hint end
    local unavailable = not bounds and #self.app.selection > 0
    if self.dockSelection or self.inspectorUnavailable ~= unavailable then
        if self.dockSelection then self.selectionDockBounds = displayedBounds end
        self.dockSelection, self.inspectorUnavailable = false, unavailable
        self:placeInspector()
    end
    self.selectionBounds.Visible = displayedBounds ~= nil
    if displayedBounds then localRect(self.selectionBounds, displayedBounds) end
    local rotation = 0
    if not bounds and record then
        pcall(function() rotation = record.object.AbsoluteRotation or record.object.Rotation or 0 end)
    end
    self.selectionBounds.Rotation = rotation
    self.selectionStroke.Color = bounds and C.cyan or C.warning
    for _, entry in ipairs(self.handles) do
        local g = entry.gui
        g.Visible = gestureReady and not self.mobile
        if g.Visible then
            g.Position = UDim2.fromScale(entry.anchor[1], entry.anchor[2])
            g.Size = UDim2.fromOffset(16, 16)
            entry.marker.Position = UDim2.fromScale(.5, .5)
        end
    end
    self.touchHandle.handle = "se"
    if self.mobile and gestureReady then self:placeTouchHandle(bounds) end
    for i, rect in ipairs(rects or {}) do
        local object = self.individual[i]
        if not object and #rects > 1 then
            object = make("Frame", {Name = "ElementBoundary", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5}, self.overlay)
            outline(object, C.cyan)
            self.individual[i] = object
        end
        if object then
            object.Visible = #rects > 1
            if object.Visible then localRect(object, rect) end
        end
    end
    for i = #(rects or {}) + 1, #self.individual do self.individual[i].Visible = false end
    if not self.slider then return end
    local info = bounds and self.app.sizeInfo and self.app:sizeInfo(bounds, rects, keys) or nil
    self.sliderEnabled = info ~= nil and writable
    self.quickBody.Visible = info ~= nil
    if self.quickEditable ~= self.sliderEnabled then
        self.quickEditable = self.sliderEnabled
        self.sliderThumb.BackgroundColor3 = self.sliderEnabled and C.cyan or C.quiet
        self.sliderFill.BackgroundColor3 = self.sliderThumb.BackgroundColor3
        self.percent.TextEditable = self.sliderEnabled
        for _, action in ipairs(self.quickEdits) do self:enable(action, self.sliderEnabled) end
    end
    if info then
        local minimum, maximum = info.minimum, info.maximum
        local input = self.app.input
        if input and input.sliderRange then
            local activeMin, activeMax = input:sliderRange()
            if activeMin then minimum, maximum = activeMin, activeMax end
        end
        local fraction = math.max(0, math.min(1, (info.scale - minimum) / math.max(.001, maximum - minimum)))
        self.sliderFill.Size = UDim2.fromScale(fraction, 1)
        self.sliderThumb.Position = UDim2.fromScale(fraction, .5)
        local group = #rects > 1
        local sizeLabel = group and self.app.preferences.equalSize and "Member size" or (group and "Group size" or "Size")
        self.sliderTitle.Text = sizeLabel .. (info.original and " / 100% original" or " / 100% starting size")
        self:syncTextBox(self.percent, numberText(info.scale) .. "%")
        self.quickSize.Text = numberText(bounds.w) .. " x " .. numberText(bounds.h)
    else self:syncTextBox(self.percent, "") end
    if self.workspaceOpen and self.tab == "Advanced" then
        local size = info and info.size or bounds
        local map = bounds and {X = bounds.x, Y = bounds.y, W = size.w, H = size.h}
        self.precisionHeading.Text = #rects > 1 and self.app.preferences.equalSize
            and "Group position / largest member size (px)" or "Position and size (px)"
        for name, box in pairs(self.fields) do
            self:syncTextBox(box, map and numberText(map[name]) or "")
            box.TextEditable = bounds ~= nil and writable
        end
    end
end

function UI:describeSelection()
    local selectedCount = #self.app.selection
    local record = selectedCount == 1 and self.app.discovery:get(self.app.selection[1]) or nil
    local editable = record and record.editable
    if record then
        local path = {}
        for _, segment in ipairs(record.descriptor.path or {}) do path[#path + 1] = segment.name end
        self.selectionName.Text, self.quickName.Text = record.object.Name, record.object.Name
        self.selectionDetail.Text = table.concat(path, " / ")
        if record.reason then self.selectionDetail.Text = self.selectionDetail.Text .. "\n" .. record.reason end
        self:syncTextBox(self.rotation, numberText(record.object.Rotation))
        self:syncTextBox(self.transparency, numberText(record.object.BackgroundTransparency))
    elseif selectedCount > 1 then
        self.selectionName.Text = tostring(selectedCount) .. " selected"
        self.quickName.Text = self.selectionName.Text
        self.selectionDetail.Text = "Drag the selection to move the group."
    else
        self.selectionName.Text = "Select an element"
        self.quickName.Text = self.selectionName.Text
        self.selectionDetail.Text = ""
    end
    self.selectionDetail.TextColor3 = record and not editable and C.warning or C.muted
    self.rotation.Visible, self.transparency.Visible = editable == true, editable == true
    self.rotation.TextEditable, self.transparency.TextEditable = editable == true, editable == true
    self.visualHint.Text = editable and "Rotation in degrees. Transparency from 0 to 1." or "Select one editable element."
    self.experimental.Visible = record ~= nil and record.experimental == true and not record.experimentalApproved
    self.revoke.Visible = record ~= nil and record.experimentalApproved == true
end

function UI:requestSelectionUpdate()
    if not self.visible or self.dead or self.selectionUpdateQueued then return end
    self.selectionUpdateQueued = true
    local function update()
        self.selectionUpdateQueued = false
        self:updateSelection()
    end
    if task and task.defer then task.defer(update) else update() end
end

function UI:watchSelection()
    local objects = {}
    if self.visible then
        for _, key in ipairs(self.app.selection) do
            local record = self.app.discovery:get(key)
            objects[#objects + 1] = record and record.object or false
        end
    end
    local same = self.watched and #objects == #self.watched
    if same then
        for i, object in ipairs(objects) do if object ~= self.watched[i] then same = false; break end end
    end
    if same then return false end
    self.watched = objects
    for _, connection in ipairs(self.selectionConnections) do connection:Disconnect() end
    self.selectionConnections = {}
    for _, object in ipairs(objects) do
        if object then
            for _, name in ipairs({"AbsolutePosition", "AbsoluteSize", "AbsoluteRotation", "Visible"}) do
                local exists, signal = pcall(function() return object:GetPropertyChangedSignal(name) end)
                if exists and signal then self:connect(signal, function() self:requestSelectionUpdate() end, self.selectionConnections) end
            end
        end
    end
    return true
end

function UI:selectionChanged()
    if self.dead then return end
    local changed = self:watchSelection()
    if not self.visible then return end
    self:describeSelection()
    if changed then self.dockSelection = true end
    self:showSurfaces()
    self:updateSelection()
    self:refreshToolbar()
    if self.workspaceOpen and self.tab == "Elements" then self:updateElementSelection() end
end

function UI:clearDynamic(container, connections)
    for _, connection in ipairs(connections) do connection:Disconnect() end
    for _, child in ipairs(container:GetChildren()) do
        if not child:IsA("UIListLayout") then child:Destroy() end
    end
    orders[container] = 0
end

local function elementPath(record)
    local path = {}
    for _, segment in ipairs(record.descriptor.path or {}) do path[#path + 1] = segment.name end
    return table.concat(path, " / ")
end

function UI:elementRow(parent, record, connections)
    local key = record.key
    local title = record.object.Name .. (record.editable and "" or "  /  Inspect")
    local row = self:button(parent, title, function() self:chooseElement(key) end, nil, nil, nil, connections)
    row.TextXAlignment = Enum.TextXAlignment.Left
    row.TextSize = 13
    truncate(row)
    make("UIPadding", {PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 7)}, row)
    return row
end

function UI:updateElementSelection()
    local record = self.app.discovery:get(self.app.selection[1])
    self.elementPath.Text = self.childParent and ("Children of " .. self.childParent.Name)
        or (record and elementPath(record) or "HUD elements")
    for key, row in pairs(self.elementRows) do
        local active = selected(self.app.selection, key)
        row.TextColor3, row.BackgroundColor3 = active and C.cyan or C.text, active and C.selected or C.raised
    end
end

function UI:setOverlaps(records)
    local keys = {}
    for i, record in ipairs(records or {}) do
        if i > 12 then break end
        keys[#keys + 1] = record.key
    end
    local signature = table.concat(keys, "\n")
    if signature == self.overlapSignature then return end
    self.overlapSignature, self.overlapKeys = signature, keys
    self:refreshToolbar()
    if self.workspaceOpen and self.tab == "Elements" then self:refreshOverlaps() end
end

function UI:refreshOverlaps()
    local revision = self.app.discovery.revision
    if self.shownOverlaps == self.overlapSignature and self.overlapRevision == revision then return end
    self.shownOverlaps, self.overlapRevision = self.overlapSignature, revision
    self:clearDynamic(self.overlapList, self.overlapConnections)
    self.overlapConnections = {}
    local records = {}
    for _, key in ipairs(self.overlapKeys or {}) do
        local record = self.app.discovery:get(key)
        if record then records[#records + 1] = record end
    end
    self.overlapList.Visible = #records > 1
    if not self.overlapList.Visible then return end
    self:section(self.overlapList, "At your last tap")
    for _, record in ipairs(records) do self:elementRow(self.overlapList, record, self.overlapConnections) end
end

function UI:refreshMissing()
    local unresolved = self.app.unmatched or self.app.transform:matches(self.app.layout or {})
    local missingKeys = {}
    for _, missing in ipairs(unresolved or {}) do
        missingKeys[#missingKeys + 1] = type(missing) == "table" and tostring(missing.key or missing.id or "") or tostring(missing)
    end
    local missingSignature = table.concat(missingKeys, "\n") .. tostring(self.remapKey)
    if missingSignature ~= self.missingSignature then
        self.missingSignature = missingSignature
        self:clearDynamic(self.missingList, self.missingConnections)
        self.missingConnections = {}
        for i, key in ipairs(missingKeys) do
            if i > 100 then break end
            local chosenKey = key
            local b = self:button(self.missingList, "Missing: " .. key:sub(-70), function()
                self.remapKey = chosenKey
                self:refreshMissing()
            end, nil, nil, nil, self.missingConnections)
            if self.remapKey == key then b.BackgroundColor3, b.TextColor3 = C.selected, C.cyan end
        end
    end
    self.remapLabel.Visible = #missingKeys > 0
    self.missingList.Visible = self.remapLabel.Visible
    self.remapButton.Visible = self.remapLabel.Visible
    self:enable(self.remapButton, self.remapKey ~= nil and #self.app.selection == 1)
end

function UI:refreshElements()
    local discovery = self.app.discovery
    if self.childParent and not self.childParent.Parent then self.childParent = nil end
    local fallback = discovery.revision == nil and discovery:list()
    local search = self.search.Text:lower():match("^%s*(.-)%s*$")
    local filter = table.concat({search, tostring(self.onlyEditable), tostring(self.childParent)}, "\n")
    local revision = discovery.revision or fallback
    if revision ~= self.elementRevision or filter ~= self.elementFilter then
        self.elementRevision, self.elementFilter = revision, filter
        self.builtinKeys, self.elementMatches = {}, {}
        for _, record in ipairs(fallback or discovery:list()) do
            local kind = record.builtin
            if kind and not self.builtinKeys[kind] then self.builtinKeys[kind] = record.key end
            if (not self.onlyEditable or record.editable) and (not self.childParent or record.object.Parent == self.childParent) then
                local matches = search == "" or (elementPath(record) .. " " .. record.object.ClassName):lower():find(search, 1, true)
                if matches then self.elementMatches[#self.elementMatches + 1] = record end
            end
        end
        for kind, button in pairs(self.builtinButtons) do self:enable(button, self.builtinKeys[kind] ~= nil) end
        self.elementSignature = nil
    end
    local limit = 28
    local pages = math.max(1, math.ceil(#self.elementMatches / limit))
    self.elementPage = math.max(1, math.min(pages, self.elementPage))
    if self.elementSignature ~= self.elementPage then
        self.elementSignature = self.elementPage
        self:clearDynamic(self.elementList, self.elementConnections)
        self.elementConnections, self.elementRows = {}, {}
        for i = 1 + (self.elementPage - 1) * limit, math.min(#self.elementMatches, self.elementPage * limit) do
            local record = self.elementMatches[i]
            self.elementRows[record.key] = self:elementRow(self.elementList, record, self.elementConnections)
        end
        if #self.elementMatches == 0 then label(self.elementList, "No matching elements", 35, 12).TextColor3 = C.muted end
    end
    self.pager.Visible = pages > 1
    self.pagerCaption.Text = tostring(self.elementPage) .. " / " .. tostring(pages)
    self:enable(self.pagerBack, self.elementPage > 1)
    self:enable(self.pagerNext, self.elementPage < pages)
    self:updateElementSelection()
    self:refreshOverlaps()
    self:refreshMissing()
end

function UI:refreshGroups()
    local names, parts = {}, {}
    for name, members in pairs(self.app.groups or {}) do table.insert(names, name); table.insert(parts, name .. ":" .. tostring(#members)) end
    table.sort(names); table.sort(parts)
    local signature = table.concat(parts, "\n") .. tostring(self.chosenGroup)
    if signature == self.groupSignature then return end
    self.groupSignature = signature
    self:clearDynamic(self.groupList, self.groupConnections); self.groupConnections = {}
    for _, name in ipairs(names) do
        local chosen = name
        self:button(self.groupList, (name == self.chosenGroup and "✓ " or "") .. name .. " · " .. tostring(#self.app.groups[name]) .. " saved members", function()
            self.chosenGroup = chosen; self.groupName.Text = chosen; self:refreshGroups()
        end, nil, nil, nil, self.groupConnections)
    end
    if #names == 0 then label(self.groupList, "Select elements, enter a name, then create a group.", 44, 12) end
end

function UI:refreshProfiles()
    local list = self.app.profiles:list()
    local active = self.app.profiles:active()
    local preview = self.app.previewState or self.app.profiles.preview
    self.activeProfile.Text = (preview and "PREVIEW · Apply or Cancel\n" or "") .. (active and "Active: " .. active.name .. " · " .. active.scope or "No active profile") .. (self.app.profiles.suspended and " · suspended" or "")
    local parts = {tostring(self.chosenProfile)}
    for _, profile in ipairs(list) do table.insert(parts, profile.id .. ":" .. profile.name .. ":" .. profile.scope) end
    local signature = table.concat(parts, "\n")
    if signature ~= self.profileSignature then
        self.profileSignature = signature
        self:clearDynamic(self.profileList, self.profileConnections); self.profileConnections = {}
        for _, profile in ipairs(list) do
            local id = profile.id
            self:button(self.profileList, (profile.id == self.chosenProfile and "✓ " or "") .. profile.name .. " · " .. profile.scope, function()
                self.chosenProfile = id; self.profileName.Text = profile.name; self:refreshProfiles()
            end, nil, nil, nil, self.profileConnections)
        end
        if #list == 0 then label(self.profileList, "No profiles yet. Create one to save this layout.", 44, 12) end
    end
    local blocked = self.app.draftBlocked ~= nil and self.app.draftBlocked ~= false
    self.draftSection.Visible = blocked or (self.app.draft ~= nil and self.app.draft ~= false)
    self.draftLabel.Text = blocked and "This draft could not be opened. You can discard it."
        or "An unsaved draft is available to preview."
    self:enable(self.previewDraft, not blocked)
end

function UI:refreshToolbar()
    local history = self.app.history
    self:enable(self.undoButton, not history or #(history.past or {}) > 0)
    self:enable(self.redoButton, not history or #(history.future or {}) > 0)
    self:enable(self.saveButton, not self.app.previewState and not (self.app.profiles and self.app.profiles.suspended))
    self.editButton.TextColor3 = not self.workspaceOpen and not self.collapsed and C.cyan or C.text
    self.elementsButton.TextColor3 = self.workspaceOpen and self.tab == "Elements" and C.cyan or C.text
    self.elementsButton.Text = #(self.overlapKeys or {}) > 1 and "Elements+" or "Elements"
    self.elementsButton.TextSize = #(self.overlapKeys or {}) > 1 and 11 or 12
    self.multiButton.TextColor3 = self.app.preferences.multiSelect and C.cyan or C.text
    self.multiButton.BackgroundTransparency = self.app.preferences.multiSelect and 0 or 1
    self.multiButton.BackgroundColor3 = self.app.preferences.multiSelect and C.selected or C.surface
    self.toolsButton.TextColor3 = self.workspaceOpen and self.tab ~= "Elements" and C.cyan or C.text
    self.doneButton.BackgroundColor3, self.doneButton.TextColor3 = C.cyan, C.ink
    self.saveButton.Text = self.app.dirty and "Save*" or "Save"
    if self.app.dirty and not self.disabled[self.saveButton] then self.saveButton.TextColor3 = C.cyan end
end

function UI:refreshPage()
    if self.tab == "Elements" then self:refreshElements()
    elseif self.tab == "Groups" then self:refreshGroups()
    elseif self.tab == "Profiles" then self:refreshProfiles()
    elseif self.tab == "Advanced" then self:describeSelection(); self:updateSelection()
    elseif self.tab == "Settings" then
        for key, box in pairs(self.preferenceFields) do
            local value = self.app.preferences[key]
            if value ~= nil then self:syncTextBox(box, tostring(value)) end
        end
        local caps = {}
        for _, name in ipairs({"storage", "clipboard", "network", "input"}) do
            local value = self.app.capabilities[name] or {}
            caps[#caps + 1] = name .. ": " .. tostring(value.status or "Unsupported") .. "\n" .. tostring(value.detail or "")
        end
        self.capabilityLabel.Text = table.concat(caps, "\n")
    end
end

function UI:refresh()
    if self.dead then return end
    self:refreshToggles()
    if self.boxButton then self.boxButton.TextColor3 = self.app.preferences.boxSelect and C.cyan or C.muted end
    self:showSurfaces()
    self:positionLauncher()
    self:drawGrid()
    self:selectionChanged()
    self:refreshToolbar()
    if self.visible and self.workspaceOpen then self:refreshPage() end
end

function UI:status(message)
    if self.dead then return end
    self:refreshToolbar()
    if not self.visible then return end
    local text = tostring(message or "")
    self.statusLabel.Text = text
    local lower = text:lower()
    local caution = lower:find("fail", 1, true) or lower:find("unsupported", 1, true)
        or lower:find("unavailable", 1, true) or lower:find("draft", 1, true)
    self.statusLabel.TextColor3 = caution and C.warning or C.text
    self.toast.Visible = text ~= ""
    self.toastId = (self.toastId or 0) + 1
    local id = self.toastId
    if task and task.delay then
        task.delay(caution and 6 or 3, function()
            if not self.dead and id == self.toastId then self.toast.Visible = false end
        end)
    end
end

function UI:setVisible(visible)
    self.visible = visible == true
    self.canvas.Visible, self.overlay.Visible = self.visible, self.visible
    if not self.visible then
        self.workspaceOpen, self.collapsed = false, false
        self.toast.Visible = false
        self:closeModal()
        self:setGuides()
        self:setBox()
    end
    self:layout()
    self:refresh()
end

function UI:destroy()
    if self.dead then return end
    self.dead = true
    self:closeModal()
    for _, list in ipairs({self.connections, self.elementConnections, self.profileConnections, self.groupConnections,
        self.missingConnections, self.selectionConnections, self.overlapConnections}) do
        for _, connection in ipairs(list) do connection:Disconnect() end
    end
    if self.gui then self.gui:Destroy() end
end

return UI
