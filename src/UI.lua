-- Heavenly Axis V3 — Roblox HUD & Interface Editor
-- Original project by Syshi; V2 inspired by Danechka.
local Geometry = require("Geometry")
local Coordinates = require("Coordinates")
local Layout = require("UILayout")
local Notifications = require("Notifications")
local Onboarding = require("Onboarding")
local ActionReference = require("ActionReference")
local Design = require("Design")
local UI = {}
UI.__index = UI

local C = Design.colors
local Fonts, Text, Space, Radius, Touch = Design.font, Design.text, Design.space, Design.radius, Design.touch
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
    return Design.round(object, radius or Radius.control)
end
local function outline(object, color, thickness)
    return Design.stroke(object, color or C.border, thickness or 1, .48)
end
local function label(parent, text, height, size)
    return make("TextLabel", {Name = "Label", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, height or 30),
        Text = text, Font = Fonts.body, TextSize = size or Text.body, TextColor3 = C.text,
        TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 24}, parent)
end
local function frame(parent, height)
    return make("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, height or Touch.minimum), ZIndex = 23}, parent)
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
    local b = make("TextButton", {Name = text:gsub("[^%w]", ""), Text = text, Size = UDim2.new(width or 1, width and -Space.tight or 0, 0, Touch.minimum),
        Position = UDim2.new(x or 0, 0, 0, 0), BackgroundColor3 = color or C.raised, BorderSizePixel = 0,
        TextColor3 = C.text, TextSize = Text.control, Font = Fonts.medium, TextWrapped = true,
        AutoButtonColor = true, ZIndex = parent.ZIndex + 1}, parent)
    corners(b, Radius.control)
    if callback then
        self:connect(b.Activated, function(...)
            local input = self.app.input
            if self.onboardingOpen or (input and input.isBusy and input:isBusy()) then return end
            if self.helpMode and not self.modalOpen and b ~= self.helpExit then
                self:showActionReference(self.helpActions[b] or "compatibility")
                return
            end
            if self.disabled[b] then return end
            callback(...)
        end, dynamic)
    end
    return b
end

function UI:enable(button, enabled)
    self.disabled[button] = not enabled or nil
    button.AutoButtonColor = enabled
    pcall(function() button.Interactable = enabled or self.helpMode == true end)
    button.TextColor3 = enabled and C.text or C.quiet
end

function UI:textbox(parent, placeholder, initial, callback, width, x, dynamic)
    local b = make("TextBox", {Name = placeholder:gsub("[^%w]", ""), Text = initial or "", PlaceholderText = placeholder,
        PlaceholderColor3 = C.muted, ClearTextOnFocus = false, Size = UDim2.new(width or 1, width and -Space.tight or 0, 0, Touch.minimum),
        Position = UDim2.new(x or 0, 0, 0, 0), BackgroundColor3 = C.field, BorderSizePixel = 0,
        TextColor3 = C.text, TextSize = Text.body, Font = Fonts.body, ZIndex = parent.ZIndex + 1}, parent)
    corners(b, Radius.field)
    local stroke = outline(b)
    self:connect(b.Focused, function()
        local input = self.app.input
        if self.onboardingOpen or self.helpMode or (input and input.isBusy and input:isBusy()) then b:ReleaseFocus(); return end
        stroke.Color, stroke.Transparency = C.cyan, .05
    end, dynamic)
    self:connect(b.FocusLost, function() stroke.Color, stroke.Transparency = C.border, .35 end, dynamic)
    if callback then
        self.presentedText[b] = b.Text
        self:connect(b.FocusLost, function(enter)
            local input = self.app.input
            if not self.onboardingOpen and not self.helpMode and b.TextEditable ~= false and b.Text ~= self.presentedText[b]
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
    local t = label(parent, title, 28, Text.section)
    t.TextColor3, t.Font = C.text, Fonts.strong
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

function UI:labeledField(parent, title, placeholder, initial, callback)
    local row = frame(parent, Touch.minimum)
    local caption = label(row, title, Touch.minimum, Text.control)
    caption.Size = UDim2.new(1, -88, 1, 0)
    caption.TextColor3 = C.muted
    truncate(caption)
    local field = self:textbox(row, placeholder, initial, callback)
    field.Position = UDim2.new(1, -78, 0, 0)
    field.Size = UDim2.fromOffset(78, Touch.minimum)
    return field, row
end

local function preferenceValue(app, key, default, smart)
    local prefs = smart and (app.smartPreferences or {}) or app.preferences
    local value = prefs[key]
    if value == nil then value = default end
    return value == true
end

function UI:toggle(parent, title, key, default, style)
    local smart = style == "smart"
    local button = self:button(parent, "", function()
        local value = not preferenceValue(self.app, key, default, smart)
        if smart then
            if self.app.setSmartPreference then self.app:setSmartPreference(key, value) end
        else self.app:setPreference(key, value) end
    end)
    button.Name = title:gsub("[^%w]", "")
    local entry = {button = button, title = title, key = key, default = default, smart = smart}
    if style ~= "compact" then
        local caption = label(button, title, 44, 13)
        caption.Position, caption.Size = UDim2.fromOffset(11, 0), UDim2.new(1, -65, 0, 44)
        truncate(caption)
        local track = make("Frame", {Name = "Switch", AnchorPoint = Vector2.new(1, .5), BorderSizePixel = 0,
            Position = UDim2.new(1, -11, .5, 0), Size = UDim2.fromOffset(34, 19)}, button)
        corners(track, 10)
        local thumb = make("Frame", {Name = "Thumb", BorderSizePixel = 0, Size = UDim2.fromOffset(13, 13)}, track)
        corners(thumb, 7)
        entry.caption, entry.track, entry.thumb = caption, track, thumb
    end
    table.insert(self.toggles, entry)
    return button
end

function UI:refreshToggles()
    for _, entry in ipairs(self.toggles) do
        local on = preferenceValue(self.app, entry.key, entry.default, entry.smart)
        local disabled = self.disabled[entry.button]
        if entry.track then
            entry.track.BackgroundColor3 = on and C.cyan or C.border
            entry.thumb.BackgroundColor3 = on and C.ink or C.text
            entry.thumb.Position = UDim2.fromOffset(on and 18 or 3, 3)
            entry.caption.TextColor3 = disabled and C.quiet or C.text
        else
            entry.button.Text = entry.title .. (on and " on" or " off")
            entry.button.TextColor3 = disabled and C.quiet or (on and C.cyan or C.muted)
        end
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
    local shield = make("TextButton", {Name = "DialogShield", Text = "", AutoButtonColor = false, BackgroundColor3 = C.scrim,
        BackgroundTransparency = .32, Size = UDim2.fromScale(1, 1), ZIndex = 70}, self.root)
    local card = make("Frame", {Name = "Dialog", BackgroundColor3 = C.surface, BorderSizePixel = 0, ZIndex = 71}, shield)
    corners(card, Radius.dialog)
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
    desc.TextColor3, desc.Visible = C.muted, message ~= ""
    local box
    if text ~= nil then
        box = make("TextBox", {Text = text, ClearTextOnFocus = false, MultiLine = true, TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Font = Enum.Font.Code,
            TextColor3 = C.text, TextSize = Text.body, BackgroundColor3 = C.field, BorderSizePixel = 0,
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
                desc.Text, desc.TextColor3, desc.Visible = tostring(result), C.warning, true
                self.app:status(result)
            end
        end, 1 / #actions, (i - 1) / #actions, entry.primary and C.cyan or nil, self.modalConnections)
        if i == #actions then b.Size = UDim2.new(1 / #actions, 0, 0, 44) end
        if entry.primary then b.TextColor3 = C.ink end
    end
    self:layoutDialog()
    return box, body
end

function UI:layoutDialog()
    if not self.dialogCard or not self.layoutPlan then return end
    local area = self.layoutPlan.area
    local w, h = math.min(area.w, 490), math.min(area.h, self.dialogMaxHeight or (self.dialogHasText and 364 or 172))
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
    self.modalConnections, self.modalOpen, self.pickerRows = {}, false, nil
    if self.modalGui then self.modalGui:Destroy(); self.modalGui = nil end
    self.dialogCard, self.dialogHeading, self.dialogScroller, self.dialogMaxHeight = nil, nil, nil, nil
end

function UI:chooseElement(key)
    self.app:select(key, self.app.preferences.multiSelect)
    if not self.app.preferences.multiSelect then self:setWorkspace(false) end
end

local layerFilters = {"Visible", "All accessible", "Editable", "Selected", "Ignored", "Locked"}

local function displayName(record)
    return record.displayName or record.object.Name
end

local function elementPath(record)
    local path = {}
    for _, segment in ipairs(record.descriptor.path or {}) do path[#path + 1] = segment.name end
    return table.concat(path, " / ")
end

local function hasOperation(record, operation)
    local info = record.capabilities and record.capabilities[operation]
    if info ~= nil then return info.supported == true end
    return record.editable == true
end

function UI:layerState(record)
    if self.app.layerState then return self.app:layerState(record.key) end
    return {ignored = record.ignored == true, locked = record.locked == true}
end

function UI:contextMenu(title, description, entries)
    local _, body = self:dialog(title, description or "", nil, {{label = "Close"}})
    self.dialogMaxHeight = math.min(330, 130 + #entries * 50)
    for _, entry in ipairs(entries) do
        self:button(body, entry[1], function()
            self:closeModal()
            entry[2]()
        end, nil, nil, nil, self.modalConnections)
    end
    self:layoutDialog()
end

function UI:setLayerFilter(filter)
    self.layerFilter = filter
    self.elementPage, self.elementSignature = 1, nil
    self.childParent = nil
    self:setTab("Elements")
end

function UI:chooseLayerFilter()
    local entries = {}
    for _, filter in ipairs(layerFilters) do
        local value = filter
        entries[#entries + 1] = {(self.layerFilter == value and "Current: " or "") .. value,
            function() self:setLayerFilter(value) end}
    end
    self:contextMenu("Show layers", "Filter the browser. Canvas selection stays as configured.", entries)
end

function UI:armSelectThrough()
    self:setWorkspace(false)
    if self.app.armSelectThrough then
        self.app:armSelectThrough()
    elseif self.overlapKeys and #self.overlapKeys > 0 then
        self:openSelectThrough()
    else
        self.app:status("Long-press a control to see the layers under it.")
    end
end

function UI:makeElements()
    local body = self.pageBodies.Elements
    self.search = self:textbox(body, "Search layers", "")
    self.search.TextXAlignment = Enum.TextXAlignment.Left
    make("UIPadding", {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 10)}, self.search)
    self:connect(self.search:GetPropertyChangedSignal("Text"), function()
        self.elementPage, self.elementSignature = 1, nil
        self:refreshElements()
    end)
    local selectionTools = frame(body, 44)
    self.compatibleFilter = self:button(selectionTools, "Show: Visible", function() self:chooseLayerFilter() end, .5, 0)
    local through = self:button(selectionTools, "Select through", function() self:armSelectThrough() end, .5, .5, C.selected)
    self.selectThroughButton = through
    through.Size = UDim2.new(.5, 0, 0, 44)
    local builtins = frame(body, 44)
    self.builtinButtons = {}
    for i, entry in ipairs({{"JumpButton", "Jump"}, {"ThumbstickFrame", "Classic joystick"}, {"DynamicThumbstickFrame", "Dynamic joystick"}}) do
        local kind = entry[1]
        local button = self:button(builtins, entry[2], function()
            if self.builtinKeys[kind] then self:chooseElement(self.builtinKeys[kind]) end
        end, 1 / 3, (i - 1) / 3)
        if i == 3 then button.Size = UDim2.new(1 / 3, 0, 0, 44) end
        self.builtinButtons[kind] = button
    end
    self.builtinRow = builtins
    self.elementPath = label(body, "", 24, 12)
    self.elementPath.TextColor3 = C.muted
    truncate(self.elementPath)
    self.layerActions = self:button(body, "Layer actions", function() self:openLayerActions() end)
    self.layerActions.Visible = false
    self.overlapList = self:button(body, "Inspect layers under last tap", function() self:openSelectThrough() end)
    self.overlapList.Visible = false
    self.elementSummary = self:section(body, "Layers")
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
    self.remapLabel = label(body, "Choose a missing saved layer and its replacement, then remap.", 44, 12)
    self.remapLabel.TextColor3 = C.muted
    self.missingList = make("Frame", {Name = "MissingElements", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 23}, body)
    flow(self.missingList, 5)
    self.remapButton = self:button(body, "Remap to selection", function()
        if self.remapKey and #self.app.selection == 1 then
            self:confirm("Remap saved layer", "Use the selected layer in place of the missing layer?", function()
                self.app:remap(self.remapKey, self.app.selection[1])
                self.remapKey = nil
                self:refreshElements()
            end)
        else self.app:status("Choose a missing layer and one replacement.") end
    end)
end

function UI:showLayerDetails(record)
    record = record or self.app.discovery:get(self.app.selection[1])
    if not record then return end
    local state = self:layerState(record)
    local lines = {
        "Instance: " .. record.object.Name,
        "Type: " .. record.object.ClassName,
        "Hierarchy: " .. elementPath(record),
        "Presentation: " .. (record.visibility or "visible"),
        "Selection: " .. (state.ignored and "ignored" or "included") .. ", " .. (state.locked and "locked" or "unlocked"),
    }
    if record.layoutController then lines[#lines + 1] = "Layout: " .. record.layoutController.ClassName end
    for _, operation in ipairs({{"move", "Move"}, {"resize", "Resize"}, {"visual", "Visual edits"},
        {"groupMove", "Move in a group"}, {"groupResize", "Resize in a group"}}) do
        local info = record.capabilities and record.capabilities[operation[1]]
        local support = hasOperation(record, operation[1]) and "Available" or "Unavailable"
        lines[#lines + 1] = operation[2] .. ": " .. support .. (info and info.reason and (" — " .. info.reason) or "")
    end
    local parent = record.parentKey and self.app.discovery:get(record.parentKey)
    if parent then lines[#lines + 1] = "Container: " .. displayName(parent) end
    local groups = self.app.groupMembers and self.app:groupMembers(record.key) or {}
    if #groups > 0 then lines[#lines + 1] = "Groups: " .. table.concat(groups, ", ") end
    local rect = Coordinates.rect(record.object)
    if rect then
        lines[#lines + 1] = "Geometry: " .. numberText(rect.w) .. " × " .. numberText(rect.h) ..
            " px at " .. numberText(rect.x) .. ", " .. numberText(rect.y)
    end
    if record.reason then lines[#lines + 1] = record.reason end
    local failure = self.app.transform and self.app.transform.failureFor and self.app.transform:failureFor(record.key)
    if failure then lines[#lines + 1] = "Last adjustment: " .. tostring(failure) end
    local text = self.app.layerDetails and self.app:layerDetails(record.key) or table.concat(lines, "\n")
    self:modal(displayName(record), "Layer details", text, "Copy", function(value)
        if self.app.storage then return self.app.storage:copy(value) end
        return false, "Copy this report from the text field."
    end)
end

function UI:changeLayerState(field)
    local record = self.app.discovery:get(self.app.selection[1])
    if not record or #self.app.selection ~= 1 or not self.app.setLayerState then return end
    local state = self:layerState(record)
    self.app:setLayerState(record.key, field, not state[field])
end

function UI:openLayerActions()
    local record = self.app.discovery:get(self.app.selection[1])
    local count = #self.app.selection
    if count > 1 then
        local entries = {{"Clear selection", function() self.app:clearSelection() end}}
        if self.app.quickGroup and not self.app.groupFocus then
            table.insert(entries, 1, {"Quick group", function() self.app:quickGroup() end})
        else table.insert(entries, 1, {"Group tools", function() self:setTab("Groups") end}) end
        return self:contextMenu(tostring(count) .. " controls selected", "", entries)
    end
    if not record then return end
    local state = self:layerState(record)
    local entries = {
        {state.ignored and "Unignore" or "Ignore in editor", function() self:changeLayerState("ignored") end},
        {state.locked and "Unlock editing" or "Lock editing", function() self:changeLayerState("locked") end},
        {"Details", function() self:showLayerDetails(record) end},
    }
    if record.parentKey then
        entries[#entries + 1] = {"Select parent", function() self:selectParent(); self:showSelectionInLayers() end}
        if self.app.siblingKeys then entries[#entries + 1] = {"Select siblings", function() self:selectSiblings() end} end
    end
    if #(record.childKeys or {}) > 0 then
        entries[#entries + 1] = {self.childParent and "Show all layers" or "Choose children",
            function() self:setTab("Elements"); self:showChildren() end}
    end
    entries[#entries + 1] = {"Clear selection", function() self.childParent = nil; self.app:clearSelection() end}
    self:contextMenu(displayName(record), "Ignore skips canvas selection. Lock protects editing.", entries)
end

function UI:showSelectionInLayers()
    if self.workspaceOpen and self.tab == "Elements" then self:refreshElements() end
end

function UI:selectContainer()
    local caps = self.selectionCapabilities or {}
    if not caps.parentKey then return self:selectParent() end
    self.app:selectMany({caps.parentKey})
    self:setWorkspace(false)
end

function UI:selectSiblings()
    local keys = self.app.siblingKeys and self.app:siblingKeys(self.app.selection[1]) or {}
    if not keys or #keys == 0 then return self.app:status("No related layers were found.") end
    local names = {}
    for i, key in ipairs(keys) do
        if i > 8 then names[#names + 1] = "and " .. (#keys - 8) .. " more"; break end
        local record = self.app.discovery:get(key)
        if record then names[#names + 1] = displayName(record) end
    end
    self:confirm("Select related layers?", table.concat(names, ", "), function()
        self.app:selectMany(keys)
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
    local context = frame(body, 44)
    self.selectionContainer = self:button(context, "Select container", function() self:selectContainer() end, .55, 0, C.selected)
    self.selectionActions = self:button(context, "Layer actions", function() self:openLayerActions() end, .45, .55)
    self.selectionActions.Size = UDim2.new(.45, 0, 0, 44)
    self.selectionTools = context
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
            local bounds = self.app:currentBounds(true, (name == "X" or name == "Y") and "move" or "resize")
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
    self.positionActions = self:row(body, {{"Left", function() self.app:move(-(self.app.preferences.step or 1), 0) end},
        {"Up", function() self.app:move(0, -(self.app.preferences.step or 1)) end},
        {"Down", function() self.app:move(0, self.app.preferences.step or 1) end},
        {"Right", function() self.app:move(self.app.preferences.step or 1, 0) end}})
    local recoveryRow = frame(body, 44)
    self.resetAdvanced = self:button(recoveryRow, "Reset selection", function() self.app:reset() end, .5, 0)
    self.recoverAdvanced = self:button(recoveryRow, "Bring into view", function() self.app:recover() end, .5, .5)
    self.recoverAdvanced.Size = UDim2.new(.5, 0, 0, 44)
    self:section(body, "Visual properties")
    self.visualHint = label(body, "Select one editable element.", 34, 12)
    self.visualHint.TextColor3 = C.muted
    self.rotation, self.rotationRow = self:labeledField(body, "Angle (degrees)", "Degrees", "", function(v)
        local n = validNumber(v)
        if n then self.app:geometry("rotation", n) else self.app:status("Enter rotation in degrees.") end
    end)
    self.transparency, self.transparencyRow = self:labeledField(body, "Background transparency", "0–1", "", function(v)
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
    local candidate = record.parentKey and self.app.discovery:get(record.parentKey)
        or self.app.discovery.byObject and self.app.discovery.byObject[parent]
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

function UI:summaryCard(parent, titleText, detailText)
    local card = frame(parent, 62)
    card.BackgroundTransparency, card.BackgroundColor3 = 0, C.field
    corners(card, Radius.surface)
    local title = label(card, titleText, 25, Text.section)
    title.Position, title.Size, title.Font = UDim2.fromOffset(12, 6), UDim2.new(1, -24, 0, 25), Fonts.strong
    truncate(title)
    local detail = label(card, detailText, 22, Text.control)
    detail.Position, detail.Size, detail.TextColor3 = UDim2.fromOffset(12, 33), UDim2.new(1, -24, 0, 22), C.muted
    truncate(detail)
    return title, detail
end

function UI:listItem(parent, primary, secondary, activate, connections, active)
    local button = self:button(parent, "", activate, nil, nil, active and C.selected or C.raised, connections)
    button.Name = "ListItem"
    button.Size = UDim2.new(1, 0, 0, 52)
    button.BackgroundTransparency = active and 0 or .42
    local title = label(button, primary, 22, Text.body)
    title.Position, title.Size, title.Font = UDim2.fromOffset(12, 4), UDim2.new(1, -53, 0, 22), Fonts.medium
    truncate(title)
    local caption = label(button, secondary, 17, Text.caption)
    caption.Position, caption.Size, caption.TextColor3 = UDim2.fromOffset(12, 27), UDim2.new(1, -53, 0, 17), C.muted
    truncate(caption)
    local menu = label(button, "...", 44, Text.section)
    menu.Position, menu.Size, menu.TextColor3 = UDim2.new(1, -40, 0, 2), UDim2.fromOffset(34, 44), C.quiet
    menu.TextXAlignment = Enum.TextXAlignment.Center
    return button
end

function UI:promptName(title, copy, initial, action, commit)
    local input
    local _, body = self:dialog(title, copy, nil, {{label = "Cancel"},
        {label = action, primary = true, action = function()
            local value = input.Text:match("^%s*(.-)%s*$")
            if value == "" then return false, "Enter a name to continue." end
            return commit(value)
        end}})
    input = self:textbox(body, "Name", initial, nil, nil, nil, self.modalConnections)
    input.TextXAlignment = Enum.TextXAlignment.Left
    make("UIPadding", {PaddingLeft = UDim.new(0, Space.medium), PaddingRight = UDim.new(0, Space.medium)}, input)
    self.dialogMaxHeight = 220
    self:layoutDialog()
end

function UI:openSavedGroup(name)
    local actions = {
        {"Select group", function() self.app:group("select", name); self:setWorkspace(false) end},
        {"Rename group", function()
            self:promptName("Rename group", "", name, "Rename", function(value) return self.app:group("rename", name, value) end)
        end},
        {"Add selection", function() self.app:group("add", name) end},
        {"Remove selection", function() self.app:group("remove", name) end},
        {"Reset members", function()
            self:confirm("Reset group members?", "This restores the original supported properties of this group's controls.", function()
                self.app:group("select", name)
                self.app:reset()
            end)
        end},
        {"Delete group", function()
            self:confirm("Delete group?", "The controls keep their current properties.", function() self.app:group("delete", name) end)
        end},
    }
    self:contextMenu(name, "", actions)
end

function UI:makeGroups()
    local body = self.pageBodies.Groups
    self.groupTitle, self.groupSummary = self:summaryCard(body, "Current selection", "")
    local groupActions = frame(body, 44)
    self.groupActions = groupActions
    self.temporaryGroup = self:button(groupActions, "Quick group", function()
        if self.app.quickGroup then self.app:quickGroup() end
    end, .5, 0, C.selected)
    self.leaveGroup = self:button(groupActions, "Ungroup", function()
        local focus = self.app.groupFocus
        if not focus or not self.app.ungroup then return end
        if focus.member and self.app.returnToGroup then return self.app:returnToGroup() end
        if focus.name then
            self:confirm("Remove this saved group?", "The controls will keep their current positions and sizes.",
                function() self.app:ungroup(true) end)
        else self.app:ungroup() end
    end, .5, .5)
    self.leaveGroup.Size = UDim2.new(.5, 0, 0, 44)
    self.groupMemberList = make("Frame", {Name = "GroupMembers", BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false}, body)
    flow(self.groupMemberList, 5)
    self:section(body, "Saved groups")
    self.groupList = make("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 23}, body)
    flow(self.groupList, 5)
    self.nameGroupButton = self:button(body, "Name this group", function()
        self:promptName("Name this group", "Keep these controls together for future edits.", "", "Create group",
            function(value) return self.app:group("create", value) end)
    end, nil, nil, C.selected)
    self:section(body, "Group transforms")
    self:toggle(body, "Adjust each member's size", "equalSize", false)
    label(body, "Member resizing keeps controls in place. Proportional group scaling changes their spacing.", 40, 12).TextColor3 = C.muted
    self:section(body, "Alignment and spacing")
    self:row(body, {{"Left", function() self.app:align("left") end}, {"Center X", function() self.app:align("centerX") end}, {"Right", function() self.app:align("right") end}})
    self:row(body, {{"Top", function() self.app:align("top") end}, {"Center Y", function() self.app:align("centerY") end}, {"Bottom", function() self.app:align("bottom") end}})
    self:row(body, {{"Distribute X", function() self.app:distribute("x") end}, {"Distribute Y", function() self.app:distribute("y") end}})
end

local profileScopes = {
    {"place", "This place"}, {"experience", "This experience"}, {"device", "This device type"},
    {"orientation", "This orientation"}, {"global", "Built-in controls in all games"},
}

local function profileScopeLabel(scope)
    for _, option in ipairs(profileScopes) do if option[1] == scope then return option[2] end end
    return scope or "Saved profile"
end

function UI:newProfile()
    local scopes = {}
    for _, option in ipairs(profileScopes) do
        scopes[#scopes + 1] = {option[2], function()
            self:promptName("New profile", option[2], "", "Create profile",
                function(value) return self.app:profile("create", value, option[1]) end)
        end}
    end
    self:contextMenu("Where should this profile apply?", "More specific profiles take priority when their settings overlap.", scopes)
end

function UI:openProfileActions(profile)
    self:contextMenu(profile.name, profileScopeLabel(profile.scope), {
        {"Preview profile", function() self.app:profile("preview", profile.id) end},
        {"Rename", function()
            self:promptName("Rename profile", "", profile.name, "Rename",
                function(value) return self.app:profile("rename", profile.id, value) end)
        end},
        {"Duplicate", function()
            self:promptName("Duplicate profile", "", profile.name .. " copy", "Duplicate",
                function(value) return self.app:profile("duplicate", profile.id, value) end)
        end},
        {"Delete profile", function()
            self:confirm("Delete this profile?", "This removes the saved configuration for this profile.",
                function() self.app:profile("delete", profile.id, true) end)
        end},
    })
end

function UI:makeProfiles()
    local body = self.pageBodies.Profiles
    self.activeProfile, self.profileSummary = self:summaryCard(body, "Current layout", "")
    self.previewActions = self:row(body, {{"Cancel preview", function() self.app:profile("cancel") end},
        {"Apply preview", function() self.app:profile("apply") end, C.selected}})
    self.previewActions.Visible = false
    self:section(body, "Saved profiles")
    self.profileList = make("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 23}, body)
    flow(self.profileList, 5)
    self.newProfileButton = self:button(body, "New profile", function() self:newProfile() end, nil, nil, C.selected)
    self:section(body, "Import and export")
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
    self:section(body, "Recovery")
    self.profileSuspend = self:button(body, "Pause saved layout", function()
        if self.app.profiles.suspended then self.app:profile("suspend", false) else self.app:profile("restore") end
    end)
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
    self:section(body, "Editing")
    self:toggle(body, "Snap to grid and guides", "snapping", false)
    self:toggle(body, "Keep width and height in proportion", "aspectLock", true)
    self:toggle(body, "Resize from center", "centerScale", false)
    self:toggle(body, "Box selection", "boxSelect", false)
    self.preferenceFields = {}
    self.preferenceFields.step = self:labeledField(body, "Movement step (px)", "1–64", tostring(self.app.preferences.step or 1), function(v)
        local n = tonumber(v); if n and n >= 1 and n <= 64 then self.app:setPreference("step", n) else self.app:status("Choose a step from 1 to 64 px.") end
    end)
    self:section(body, "Smart Layers")
    self:toggle(body, "Prioritize meaningful controls", "smartSelection", true, "smart")
    self:toggle(body, "Skip transparent overlays on tap", "skipTransparent", true, "smart")
    self:row(body, {{"Review ignored", function() self:setLayerFilter("Ignored") end},
        {"Review locked", function() self:setLayerFilter("Locked") end}})
    self:row(body, {{"Clear ignores", function() self:confirm("Clear ignored layers?", "Layers can be selected on the canvas again. This applies to this place.",
        function() if self.app.clearLayerStates then self.app:clearLayerStates("ignored") end end) end},
        {"Clear locks", function() self:confirm("Clear layer locks?", "Locked editing protections for this place will be removed.",
        function() if self.app.clearLayerStates then self.app:clearLayerStates("locked") end end) end}})
    self:section(body, "Appearance")
    self:toggle(body, "Canvas grid", "grid", true)
    self.preferenceFields.gridSize = self:labeledField(body, "Grid spacing (px)", "4–128", tostring(self.app.preferences.gridSize or 24), function(v)
        local n = tonumber(v); if n and n >= 4 and n <= 128 then self.app:setPreference("gridSize", n) else self.app:status("Grid spacing must be 4–128 pixels.") end
    end)
    self.preferenceFields.snapThreshold = self:labeledField(body, "Guide threshold (px)", "1–32", tostring(self.app.preferences.snapThreshold or 6), function(v)
        local n = tonumber(v); if n and n >= 1 and n <= 32 then self.app:setPreference("snapThreshold", n) else self.app:status("Guide threshold must be 1–32 pixels.") end
    end)
    self:section(body, "Editor panels")
    self:toggle(body, "Dock panels near screen edges", "panelDocking", false, "smart")
    self.resetEditorButton = self:button(body, "Reset Editor Layout", function()
        if self.app.resetEditorLayout then self.app:resetEditorLayout() end
    end)
    self:section(body, "Behavior")
    self.preferenceFields.shortcut = self:labeledField(body, "Reopen shortcut", "F8", self.app.preferences.shortcut or "F8", function(v)
        local ok, key = pcall(function() return Enum.KeyCode[v] end)
        if ok and key and key ~= Enum.KeyCode.Unknown then self.app:setPreference("shortcut", v) else self.app:status("Enter a valid Roblox KeyCode name.") end
    end)
    self:row(body, {{"Hide launcher", function() self.app:setPreference("launcherHidden", true) end}, {"Recover launcher", function()
        self.app:setPreference("launcherHidden", false)
        if self.app.setEditorPlacement then self.app:setEditorPlacement("launcher", {x = 0, y = .35})
        else self.app:setPreference("launcherX", .02); self.app:setPreference("launcherY", .35) end
        self:layout()
    end}})
    label(body, "Reopen with the keyboard shortcut or rerun the release on a phone. The Heavenly Axis API also supports Open and SafeMode.", 54, 12)
    self:section(body, "Help and recovery")
    self:button(body, "Open Help", function() self:setTab("Help") end)
    self:button(body, "Replay Quick Start", function() self:startTutorial("quick") end)
    self.resetAllButton = self:button(body, "Reset All Changes", function() self:confirmResetAll() end)
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
    self:section(body, "Version and diagnostics")
    label(body, "Heavenly Axis " .. tostring(self.app.version or "3.0.0")
        .. "\nRoblox HUD & Interface Editor\nOriginal by Syshi. V2 inspired by Danechka.", 60, 12)
    self:button(body, "Check project releases (optional)", function() self.app:checkUpdates() end)
    self:button(body, "Runtime capabilities", function()
        self:modal("Runtime capabilities", "See which optional features are available in this session.", self.capabilityText or "")
    end)
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

function UI:showActionReference(id)
    local entry = ActionReference.get(id)
    if not entry then return end
    local detail = entry.how .. "\n\n" .. entry.effect
    if entry.note then detail = detail .. "\n\n" .. entry.note end
    self:dialog(entry.label, detail, nil, {{label = "Close"}})
    self.dialogMaxHeight = 245
    self:layoutDialog()
end

function UI:setHelpMode(active)
    if self.app.input then self.app.input:cancel() end
    self.helpMode = active == true
    if self.helpMode then self:setWorkspace(false) end
    self.helpExit.Visible = self.visible and self.helpMode
    self:showSurfaces()
    self:updateSelection()
    self:refreshToolbar()
    self:layoutNotifications()
end

function UI:refreshReference()
    local query = self.referenceSearch.Text
    if self.referenceQuery == query then return end
    self.referenceQuery = query
    self:clearDynamic(self.referenceList, self.referenceConnections)
    self.referenceConnections = {}
    local sections = ActionReference.search(query)
    for _, section in ipairs(sections) do
        local matches = section.items
        self:button(self.referenceList, section.title .. "  /  " .. tostring(#matches), function()
            local actions = {}
            for _, item in ipairs(matches) do
                actions[#actions + 1] = {item.label, function() self:showActionReference(item.id) end}
            end
            self:contextMenu(section.title, "Choose a control to see what it does.", actions)
        end, nil, nil, nil, self.referenceConnections)
    end
    if #sections == 0 then label(self.referenceList, "No matching actions.", 40, 12).TextColor3 = C.muted end
end

function UI:makeHelp()
    local body = self.pageBodies.Help
    self:section(body, "Learn by doing")
    self:row(body, {{"Quick Start", function() self:startTutorial("quick") end, C.selected},
        {"Guided Tour", function() self:startTutorial("tour") end}})
    self.resumeTutorialButton = self:button(body, "Resume Guided Tour", function() self:startTutorial("tour", true) end)
    self.resumeTutorialButton.Visible = false
    self:section(body, "Explain controls")
    self:button(body, "Tap controls for help", function() self:setHelpMode(true) end)
    self:section(body, "Button reference")
    self.referenceSearch = self:textbox(body, "Search actions, tools or gestures", "")
    self:connect(self.referenceSearch:GetPropertyChangedSignal("Text"), function() self:refreshReference() end)
    self.referenceList = make("Frame", {Name = "ReferenceCategories", BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y}, body)
    flow(self.referenceList, 5)
    self:refreshReference()
end

function UI:startTutorial(mode, resume)
    if not self.visible or not self.onboarding then return end
    self:closeModal()
    if self.helpMode then self:setHelpMode(false) end
    if self.app.input then self.app.input:cancel() end
    self:setWorkspace(false)
    self.onboarding:layout(self.layoutPlan.area)
    return self.onboarding:start(mode or "quick", resume)
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

local function gripDots(parent, x, y)
    for row = 0, 2 do
        for column = 0, 1 do
            local dot = make("Frame", {BackgroundColor3 = C.quiet, BorderSizePixel = 0,
                Position = UDim2.new(x, (x == 1 and -14 or 4) + column * 5, 0, y + row * 5), Size = UDim2.fromOffset(3, 3)}, parent)
            corners(dot, 2)
        end
    end
end

function UI:confirmResetAll()
    if not self.app.resetAll then return end
    local summary = self.app.resetAllSummary and self.app:resetAllSummary() or {}
    local context = summary.profile and ("Profile: " .. summary.profile) or "This device and orientation"
    if summary.context then context = context .. " (" .. summary.context .. ")" end
    local state = context .. "\nRestore the original properties of supported controls in this context. " ..
        "An override keeps inherited edits from returning here. Saved profiles and locked controls are kept. " ..
        "You can Undo the reset or Save it as a checkpoint."
    if summary.count then
        state = state .. "\n" .. tostring(summary.count) .. " to restore. " ..
            tostring(summary.protected or 0) .. " protected. " .. tostring(summary.missing or 0) .. " currently unavailable."
    end
    self:dialog("Reset All Changes", state, nil, {{label = "Keep editing"},
        {label = "Reset all", action = function() self.app:resetAll() end, primary = true, closeFirst = true}})
    self.dialogMaxHeight = 245
    self:layoutDialog()
end

function UI:openToolsMenu()
    if self.workspaceOpen then return self:setWorkspace(false) end
    self:setTab(self.lastToolsTab or "Advanced")
end

function UI:openWorkspaceActions()
    local actions = {}
    if not self.saveButton.Visible then actions[#actions + 1] = {"Save layout", function() self.app:save() end} end
    actions[#actions + 1] = {"Reset All Changes", function() self:confirmResetAll() end}
    self:contextMenu("Layout actions", "", actions)
end

function UI:openHistory()
    local actions = {}
    if not self.disabled[self.undoButton] then actions[#actions + 1] = {"Undo last change", function() self.app:undo() end} end
    if not self.disabled[self.redoButton] then actions[#actions + 1] = {"Redo last change", function() self.app:redo() end} end
    self:contextMenu("History", #actions == 0 and "Undo and redo will appear after an edit." or "", actions)
end

function UI:makeToolbar()
    local toolbar = make("Frame", {Name = "Toolbar", BackgroundColor3 = C.surface, BackgroundTransparency = .035,
        BorderSizePixel = 0, ZIndex = 34, Visible = false, Active = true}, self.root)
    self.toolbar = toolbar
    corners(toolbar, Radius.surface); outline(toolbar)
    self.toolbarGrip = self:button(toolbar, "", nil, nil, nil, C.field)
    self.toolbarGrip.Name = "MoveToolbar"
    self.toolbarGrip.Position, self.toolbarGrip.Size = UDim2.fromOffset(2, 2), UDim2.fromOffset(Touch.minimum, Touch.minimum)
    self.toolbarGrip.AutoButtonColor = false
    gripDots(self.toolbarGrip, 0, 14)
    self.toolbarBrand = brand(self.toolbarGrip, 36)
    self.toolbarBrand.Position = UDim2.fromOffset(15, 11)
    local actions = {
        {"Elements", function()
            if self.workspaceOpen and self.tab == "Elements" then self:setWorkspace(false)
            else self:setTab("Elements") end
        end, 54},
        {"Multi", function() self.app:setPreference("multiSelect", not self.app.preferences.multiSelect) end, 45},
        {"Undo", function() self.app:undo() end, 44},
        {"Redo", function() self.app:redo() end, 44},
        {"History", function() self:openHistory() end, 52},
        {"Tools", function() self:openToolsMenu() end, 45},
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
    self.toolbarDividers = {}
    for _, boundary in ipairs({"Undo", "Tools"}) do
        self.toolbarDividers[boundary] = make("Frame", {Name = boundary .. "Divider", BackgroundColor3 = C.border,
            BackgroundTransparency = .35, BorderSizePixel = 0, Size = UDim2.fromOffset(1, 19), ZIndex = 35}, toolbar)
    end
    self.editButton = self:button(self.root, "Show Quick Edit", function() self:setCollapsed(false) end, nil, nil, C.surface)
    self.editButton.Visible, self.editButton.ZIndex = false, 34
    outline(self.editButton)
    self.doneButton.Font, self.saveButton.Font = Fonts.strong, Fonts.strong
    self.toolsSaveIndicator = make("Frame", {Name = "Unsaved", BackgroundColor3 = C.cyan, BorderSizePixel = 0,
        Position = UDim2.new(1, -9, 0, 8), Size = UDim2.fromOffset(4, 4), ZIndex = 36, Visible = false}, self.toolsButton)
    corners(self.toolsSaveIndicator, 2)

    self.canvasHint = make("Frame", {Name = "SelectionHint", Active = false, BackgroundColor3 = C.surface,
        BackgroundTransparency = .1, BorderSizePixel = 0, ZIndex = 20, Visible = false}, self.root)
    corners(self.canvasHint, Radius.control)
    outline(self.canvasHint)
    local text = label(self.canvasHint, "Tap a control to edit", 30, 12)
    self.canvasHintText = text
    text.Position, text.Size, text.TextColor3 = UDim2.fromOffset(11, 0), UDim2.new(1, -22, 1, 0), C.muted
    truncate(text)
    self.helpExit = self:button(self.root, "Exit Help", function() self:setHelpMode(false) end, nil, nil, C.cyan)
    self.helpExit.TextColor3, self.helpExit.ZIndex, self.helpExit.Visible = C.ink, 36, false
end

local transformTools = {{"move", "Move"}, {"size", "Size"}, {"rotate", "Rotate"}, {"opacity", "Opacity"}}

function UI:getTransformTool()
    return self.transformTool
end

function UI:setTransformTool(tool)
    if not self.toolPanels[tool] or self.transformTool == tool then return end
    if self.app.input then self.app.input:cancel() end
    self.transformTool, self.quickMode = tool, nil
    self.quickBody.CanvasPosition = Vector2.new(0, 0)
    self:updateSelection()
    self:layoutNotifications()
end

function UI:makeVisualSlider(parent, kind, title)
    local button = self:button(parent, "", nil, nil, nil, C.field)
    button.Name = kind == "rotation" and "RotationSlider" or "OpacitySlider"
    button.AutoButtonColor = false
    local caption = label(button, title, 19, 12)
    caption.Position, caption.Size = UDim2.fromOffset(10, 1), UDim2.new(.7, -10, 0, 19)
    caption.Font = Enum.Font.GothamMedium
    truncate(caption)
    local value = label(button, "", 19, 12)
    value.Position, value.Size = UDim2.new(.7, 0, 0, 1), UDim2.new(.3, -10, 0, 19)
    value.TextColor3, value.TextXAlignment = C.muted, Enum.TextXAlignment.Right
    local track = make("Frame", {Name = "Track", BackgroundColor3 = C.border, BorderSizePixel = 0,
        Position = UDim2.fromOffset(15, 27), Size = UDim2.new(1, -30, 0, 4)}, button)
    corners(track, 2)
    local fill = make("Frame", {Name = "Amount", BackgroundColor3 = C.cyan, BorderSizePixel = 0,
        Size = UDim2.fromScale(0, 1)}, track)
    corners(fill, 2)
    local thumb = make("Frame", {Name = "Thumb", BackgroundColor3 = C.cyan, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(0, .5), Size = UDim2.fromOffset(14, 14)}, track)
    corners(thumb, 7)
    self.visualSliders[kind] = button
    self.visualControls[kind] = {button = button, caption = caption, value = value, track = track, fill = fill, thumb = thumb}
end

function UI:makeTransformTools(body, sizePanel)
    self.toolPanels = {size = sizePanel, move = frame(body, 44), rotate = frame(body, 92), opacity = frame(body, 92)}
    self.visualSliders, self.visualControls, self.visualEnabled = {}, {}, {}
    local moves = {{"Left", -1, 0}, {"Up", 0, -1}, {"Down", 0, 1}, {"Right", 1, 0}}
    local moveButtons = {}
    for _, move in ipairs(moves) do
        moveButtons[#moveButtons + 1] = {move[1], function()
            local step = self.app.preferences.step or 1
            self.app:move(move[2] * step, move[3] * step)
        end}
    end
    self.moveNudges = self:row(self.toolPanels.move, moveButtons)

    self:makeVisualSlider(self.toolPanels.rotate, "rotation", "Angle")
    self.rotateNudges = self:row(self.toolPanels.rotate, {{"-90°", function()
        if self.app.stepRotation then self.app:stepRotation(-90) end
    end}, {"-1°", function()
        if self.app.stepRotation then self.app:stepRotation(-1) end
    end}, {"+1°", function()
        if self.app.stepRotation then self.app:stepRotation(1) end
    end}, {"+90°", function()
        if self.app.stepRotation then self.app:stepRotation(90) end
    end}})
    self.rotateNudges.Position = UDim2.fromOffset(0, 48)
    self:makeVisualSlider(self.toolPanels.opacity, "opacity", "Relative opacity")
    local scopes = frame(self.toolPanels.opacity, 44)
    scopes.Position = UDim2.fromOffset(0, 48)
    self.opacityScopes = {}
    for i, entry in ipairs({{"element", "Element only"}, {"contents", "Include contents"}}) do
        local scope = entry[1]
        local button = self:button(scopes, entry[2], function()
            if self.app.input then self.app.input:cancel() end
            self.opacityScope = scope
            self:updateSelection()
        end, .5, (i - 1) / 2)
        if i == 2 then button.Size = UDim2.new(.5, 0, 0, 44) end
        self.opacityScopes[scope] = button
    end
end

function UI:makeQuickEdit()
    local panel = make("Frame", {Name = "QuickEdit", BackgroundColor3 = C.surface, BackgroundTransparency = .04,
        BorderSizePixel = 0, ZIndex = 24, Visible = false, Active = true, ClipsDescendants = true}, self.root)
    self.panel = panel
    corners(panel, 13)
    outline(panel)
    self.inspectorGrip = self:button(panel, "", nil)
    self.inspectorGrip.Name = "MoveInspector"
    self.inspectorGrip.Position, self.inspectorGrip.Size = UDim2.fromOffset(7, 4), UDim2.new(1, -64, 0, 44)
    self.inspectorGrip.BackgroundTransparency = 1
    self.inspectorGrip.AutoButtonColor = false
    self.quickName = label(self.inspectorGrip, "Selection", 21, 16)
    self.quickName.Font = Enum.Font.GothamBold
    self.quickName.ZIndex = 26
    self.quickName.Position, self.quickName.Size = UDim2.fromOffset(10, 2), UDim2.new(1, -23, 0, 21)
    truncate(self.quickName)
    self.quickHint = label(self.inspectorGrip, "Drag element to move", 18, 11)
    self.quickHint.ZIndex, self.quickHint.TextColor3 = 26, C.muted
    self.quickHint.Position, self.quickHint.Size = UDim2.fromOffset(10, 24), UDim2.new(1, -21, 0, 16)
    truncate(self.quickHint)
    self.selectionAccent = make("Frame", {Name = "SelectionState", BackgroundColor3 = C.cyan, BorderSizePixel = 0,
        Position = UDim2.fromOffset(2, 9), Size = UDim2.fromOffset(2, 26), ZIndex = 26}, self.inspectorGrip)
    corners(self.selectionAccent, 1)
    for y = 15, 25, 5 do
        for x = -10, -5, 5 do
            local dot = make("Frame", {BackgroundColor3 = C.quiet, BorderSizePixel = 0,
                Position = UDim2.new(1, x, 0, y), Size = UDim2.fromOffset(3, 3), ZIndex = 26}, self.inspectorGrip)
            corners(dot, 2)
        end
    end
    local hide = self:button(panel, "Hide", function() self:setCollapsed(true) end)
    hide.Position, hide.Size = UDim2.new(1, -52, 0, 4), UDim2.fromOffset(44, 44)
    hide.BackgroundTransparency, hide.TextColor3 = 1, C.muted
    self.quickHide = hide
    local tabs = make("Frame", {Name = "TransformTools", BackgroundColor3 = C.field, BorderSizePixel = 0,
        Position = UDim2.fromOffset(8, 47), Size = UDim2.new(1, -16, 0, 44), ZIndex = 25}, panel)
    corners(tabs, 10)
    self.quickTabs, self.transformButtons = tabs, {}
    for i, item in ipairs(transformTools) do
        local tool = item[1]
        local button = self:button(tabs, item[2], function() self:setTransformTool(tool) end, .25, (i - 1) / 4)
        button.Size = UDim2.new(.25, i == #transformTools and 0 or -2, 0, 44)
        self.transformButtons[tool] = button
    end
    local body = make("ScrollingFrame", {Name = "QuickControls", BackgroundTransparency = 1, BorderSizePixel = 0,
        Position = UDim2.fromOffset(8, 96), Size = UDim2.new(1, -16, 1, -102),
        CanvasSize = UDim2.fromOffset(0, 142), ScrollBarThickness = 2, ScrollingDirection = Enum.ScrollingDirection.Y,
        Active = true, ScrollingEnabled = true, ClipsDescendants = true,
        ScrollBarImageColor3 = C.cyan, ZIndex = 25}, panel)
    self.quickBody = body
    local sizePanel = frame(body, 92)
    self.slider = self:button(sizePanel, "", nil)
    self.slider.Name = "SizeSlider"
    self.slider.BackgroundColor3 = C.field
    self.slider.AutoButtonColor = false
    self.sliderTitle = label(self.slider, "Size", 18, 11)
    self.sliderTitle.Position, self.sliderTitle.ZIndex = UDim2.fromOffset(10, 1), 28
    self.sliderTitle.Size, self.sliderTitle.TextColor3 = UDim2.new(.5, -10, 0, 19), C.text
    self.sliderTitle.Font = Enum.Font.GothamMedium
    truncate(self.sliderTitle)
    self.sliderReference = label(self.slider, "", 18, 11)
    self.sliderReference.Position, self.sliderReference.Size = UDim2.new(.5, 0, 0, 1), UDim2.new(.5, -10, 0, 19)
    self.sliderReference.ZIndex, self.sliderReference.TextColor3 = 28, C.muted
    self.sliderReference.TextXAlignment = Enum.TextXAlignment.Right
    truncate(self.sliderReference)
    self.sliderTrack = make("Frame", {Name = "Track", BackgroundColor3 = C.border, BorderSizePixel = 0,
        Position = UDim2.fromOffset(15, 26), Size = UDim2.new(1, -30, 0, 3), ZIndex = 28}, self.slider)
    corners(self.sliderTrack, 2)
    self.sliderFill = make("Frame", {Name = "Amount", BackgroundColor3 = C.cyan, BorderSizePixel = 0,
        Size = UDim2.fromScale(0, 1), ZIndex = 29}, self.sliderTrack)
    corners(self.sliderFill, 2)
    self.sliderThumb = make("Frame", {Name = "Thumb", BackgroundColor3 = C.cyan, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(0, .5), Size = UDim2.fromOffset(14, 14), ZIndex = 30}, self.sliderTrack)
    corners(self.sliderThumb, 7)
    local values = frame(sizePanel, 44)
    values.Position, values.ZIndex = UDim2.fromOffset(0, 48), 26
    local stepper = make("Frame", {Name = "SizeStepper", BackgroundColor3 = C.raised, BorderSizePixel = 0,
        Size = UDim2.fromOffset(155, 44), ZIndex = 27}, values)
    corners(stepper, 9)
    outline(stepper)
    local minus = self:button(stepper, "−", function()
        if self.app.stepSize then self.app:stepSize(-1) else self.app:scale(.99) end
    end)
    minus.Name = "DecreaseSize"
    minus.Size = UDim2.fromOffset(44, 44)
    minus.BackgroundTransparency, minus.TextSize = 1, 19
    self.percent = self:textbox(stepper, "Size %", "", function(value)
        local n = validNumber((value:gsub("%%", "")))
        if n and self.app.setSizePercent then self.app:setSizePercent(n)
        elseif not n then self.app:status("Enter a valid size percentage.") end
        self:updateSelection()
    end)
    self.percent.Position, self.percent.Size = UDim2.fromOffset(44, 0), UDim2.fromOffset(67, 44)
    self.percent.Font = Enum.Font.GothamMedium
    local plus = self:button(stepper, "+", function()
        if self.app.stepSize then self.app:stepSize(1) else self.app:scale(1.01) end
    end)
    plus.Name = "IncreaseSize"
    plus.Position, plus.Size = UDim2.fromOffset(111, 0), UDim2.fromOffset(44, 44)
    plus.BackgroundTransparency, plus.TextSize = 1, 19
    self.quickSize = label(values, "", 44, 13)
    self.quickSize.Position, self.quickSize.Size = UDim2.fromOffset(160, 0), UDim2.new(1, -160, 0, 44)
    self.quickSize.TextXAlignment, self.quickSize.TextColor3, self.quickSize.ZIndex = Enum.TextXAlignment.Center, C.muted, 28
    truncate(self.quickSize)
    self:makeTransformTools(body, sizePanel)
    local actions = frame(body, 44)
    actions.Position, actions.ZIndex = UDim2.fromOffset(0, 96), 26
    self.quickLock = self:toggle(actions, "Aspect", "aspectLock", true, "compact")
    self.quickLock.Size = UDim2.new(.34, -4, 0, 44)
    self.quickReset = self:button(actions, "Reset", function() self.app:reset() end, .30, .34)
    self.toolReset = self:button(actions, "Reset angle", function()
        if self.transformTool == "rotate" and self.app.resetRotation then self.app:resetRotation()
        elseif self.transformTool == "opacity" and self.app.resetOpacity then self.app:resetOpacity(self.opacityScope) end
    end, .34, 0)
    self.quickMore = self:button(actions, "Edit tools", function() self:openQuickAction() end, .36, .64, C.selected)
    self.quickMore.Size = UDim2.new(.36, 0, 0, 44)
    self.quickMore.TextColor3 = C.cyan
    self.quickEdits = {minus, plus, self.quickLock}
    self.quickValues, self.quickActions = values, actions
    self.sliderEnabled = false
end

function UI:openQuickAction()
    local caps, focus = self.selectionCapabilities or {}, self.app.groupFocus
    if self.selectionLayerState and self.selectionLayerState.locked then return self:changeLayerState("locked") end
    if caps.parentKey and not caps.move then return self:selectContainer() end
    if focus and focus.member and self.app.returnToGroup then return self.app:returnToGroup() end
    if #self.app.selection > 1 and self.app.quickGroup then
        if not focus then self.app:quickGroup()
        else self:setTab("Groups") end
        return
    end
    local entries = {{"Precision and appearance", function() self:setTab("Advanced") end}}
    if #self.app.selection == 1 then entries[#entries + 1] = {"Layer actions", function() self:openLayerActions() end} end
    if self.app.armSelectThrough then entries[#entries + 1] = {"Select through", function() self:armSelectThrough() end} end
    self:contextMenu("Selection tools", "", entries)
end

local destinations = {{"Elements", "Layers", 61}, {"Advanced", "Edit tools", 70}, {"Groups", "Groups", 61},
    {"Profiles", "Profiles", 63}, {"Settings", "Settings", 66}, {"Help", "Help", 48}}

function UI:makeWorkspace()
    self.workspace = make("Frame", {Name = "Workspace", BackgroundColor3 = C.surface, BorderSizePixel = 0,
        ZIndex = 40, Visible = false, Active = true, ClipsDescendants = true}, self.root)
    corners(self.workspace, Radius.surface); outline(self.workspace)
    local header = frame(self.workspace, 44)
    header.Position, header.Size, header.ZIndex = UDim2.fromOffset(8, 4), UDim2.new(1, -16, 0, 44), 41
    local back = self:button(header, "Canvas", function() self:setWorkspace(false) end)
    back.Size = UDim2.fromOffset(68, 44)
    back.BackgroundTransparency, back.TextColor3 = 1, C.cyan
    self.workspaceHeading = label(header, "Layers", 44, Text.title)
    self.workspaceHeading.Position, self.workspaceHeading.Size = UDim2.fromOffset(75, 0), UDim2.new(1, -195, 0, 44)
    self.workspaceHeading.Font = Fonts.strong
    truncate(self.workspaceHeading)
    self.workspaceActions = self:button(header, "Actions", function() self:openWorkspaceActions() end, nil, nil, C.field)
    self.workspaceActions.Position, self.workspaceActions.Size = UDim2.new(1, -110, 0, 0), UDim2.fromOffset(57, 44)
    self.workspaceMenu = self:button(header, "Choose section", function()
        local entries = {}
        for _, destination in ipairs(destinations) do
            entries[#entries + 1] = {destination[2], function() self:setTab(destination[1]) end}
        end
        self:contextMenu("Editor sections", "", entries)
    end)
    self.workspaceMenu.Position, self.workspaceMenu.Size = UDim2.fromOffset(75, 0), UDim2.new(1, -195, 0, 44)
    self.workspaceGrip = self:button(header, "Drag", nil, nil, nil, C.field)
    self.workspaceGrip.Name, self.workspaceGrip.AutoButtonColor = "MoveTools", false
    self.workspaceGrip.Position, self.workspaceGrip.Size = UDim2.new(1, -48, 0, 0), UDim2.fromOffset(48, 44)
    self.workspaceGrip.TextSize = 10
    gripDots(self.workspaceGrip, 1, 14)
    self.workspaceGrip.TextXAlignment = Enum.TextXAlignment.Left
    make("UIPadding", {PaddingLeft = UDim.new(0, 5)}, self.workspaceGrip)
    self.workspaceMenu.Visible = false
    self.tabs = make("ScrollingFrame", {Name = "ToolsNavigation", BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 2, ScrollBarImageColor3 = C.cyan, ScrollingDirection = Enum.ScrollingDirection.X,
        Active = true, ClipsDescendants = true,
        Position = UDim2.fromOffset(8, 50), Size = UDim2.new(1, -16, 0, 47),
        CanvasSize = UDim2.fromOffset(330, 0), ZIndex = 41}, self.workspace)
    self.tabButtons, self.tabMarks, self.pages, self.pageBodies = {}, {}, {}, {}
    local navX = 0
    self.tabPositions = {}
    for _, destination in ipairs(destinations) do
        local name, caption, width = destination[1], destination[2], destination[3]
        local button = self:button(self.tabs, caption, function() self:setTab(name) end)
        self.tabPositions[name] = navX
        button.Position, button.Size = UDim2.fromOffset(navX, 0), UDim2.fromOffset(width, 44)
        button.BackgroundTransparency = 1
        local mark = make("Frame", {Name = "ActiveSection", BackgroundColor3 = C.cyan, BorderSizePixel = 0,
            AnchorPoint = Vector2.new(.5, 1), Position = UDim2.new(.5, 0, 1, -2), Size = UDim2.new(1, -16, 0, 2),
            Visible = name == "Elements"}, button)
        corners(mark, 1)
        self.tabButtons[name], self.tabMarks[name] = button, mark
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
    self:makeElements(); self:makeAdvanced(); self:makeGroups(); self:makeProfiles(); self:makeSettings(); self:makeHelp()
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
    self.handleBounds = make("Frame", {Name = "ResizeBounds", BackgroundTransparency = 1, BorderSizePixel = 0,
        ZIndex = 7, Visible = false}, self.overlay)
    self.handleStroke = outline(self.handleBounds, C.cyan)
    self.handleStroke.Enabled = false
    self.touchHandleLink = make("Frame", {Name = "TouchHandleLink", BackgroundColor3 = C.cyan, BackgroundTransparency = .25,
        AnchorPoint = Vector2.new(.5, .5), BorderSizePixel = 0, Visible = false, ZIndex = 9}, self.handleBounds)
    self.rotationLink = make("Frame", {Name = "RotationLink", BackgroundColor3 = C.cyan, BackgroundTransparency = .22,
        AnchorPoint = Vector2.new(.5, .5), BorderSizePixel = 0, Visible = false, ZIndex = 9}, self.overlay)
    local rotation = make("TextButton", {Name = "RotationHandle", Text = "", BackgroundTransparency = 1,
        AutoButtonColor = false, ZIndex = 11, Visible = false}, self.overlay)
    local marker = make("Frame", {Name = "RotateMarker", BackgroundColor3 = C.surface, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.fromOffset(24, 24)}, rotation)
    corners(marker, 12)
    outline(marker, C.cyan, 2)
    for i, line in ipairs({{12, 5, 25}, {15, 8, -65}}) do
        local arrow = make("Frame", {Name = "TurnArrow" .. i, BackgroundColor3 = C.cyan, BorderSizePixel = 0,
            Position = UDim2.fromOffset(line[1], line[2]), Size = UDim2.fromOffset(7, 2), Rotation = line[3]}, marker)
        corners(arrow, 1)
    end
    self.rotationHandle = {gui = rotation, marker = marker, handle = "rotation"}
    self.individual = {}
    self.box = make("Frame", {Name = "BoxSelection", BackgroundColor3 = C.cyan, BackgroundTransparency = .9,
        BorderSizePixel = 0, ZIndex = 6, Visible = false}, self.overlay)
    outline(self.box, C.cyan)
    for _, handle in ipairs({"nw", "n", "ne", "e", "se", "s", "sw", "w"}) do
        local b = make("TextButton", {Name = "Resize_" .. handle, Text = "", BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(.5, .5), AutoButtonColor = false, ZIndex = 10, Visible = false}, self.handleBounds)
        local marker = make("Frame", {BackgroundColor3 = C.cyan, BorderSizePixel = 0, AnchorPoint = Vector2.new(.5, .5),
            Position = UDim2.fromScale(.5, .5), Size = UDim2.fromOffset(14, 14), ZIndex = 11}, b)
        corners(marker, 5); outline(marker, C.ink)
        local entry = {gui = b, marker = marker, handle = handle, anchor = anchors[handle]}
        self.handles[#self.handles + 1] = entry
        if handle == "se" then self.touchHandle = entry end
    end
end

function UI.new(app, playerGui, services)
    local self = setmetatable({app = app, services = services, connections = {}, elementConnections = {}, groupConnections = {},
        profileConnections = {}, missingConnections = {}, selectionConnections = {}, groupMemberConnections = {}, toggles = {},
        handles = {}, guideObjects = {}, gridObjects = {}, disabled = setmetatable({}, {__mode = "k"}),
        presentedText = setmetatable({}, {__mode = "k"}), helpActions = setmetatable({}, {__mode = "k"}), referenceConnections = {},
        visible = false, tab = "Elements", collapsed = false, elementPage = 1, builtinKeys = {},
        layerFilter = "Visible", collapsedLayers = {}, transformTool = "size", opacityScope = "element", surfaceRects = {}}, UI)
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

        self.notifications = Notifications.new(self.root, self.services)
        self.onboarding = Onboarding.new(self.root, self.services, {
            finished = function(outcome, mode)
                if (mode == "quick" or mode == nil) and (outcome == "skipped" or outcome == "completed")
                    and self.app.markTutorialSeen then self.app:markTutorialSeen() end
            end,
            readProgress = function(mode) if self.app.tutorialProgress then return self.app:tutorialProgress(mode) end end,
            saveProgress = function(mode, step) if self.app.setTutorialProgress then self.app:setTutorialProgress(mode, step) end end,
            highlight = function(id) return self:referenceTarget(id) end,
            changed = function()
                if self.dead then return end
                self.onboardingOpen = self.onboarding and self.onboarding:isActive() or false
                self:layoutNotifications()
            end,
        })

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
        self:bindHelpTargets()
        self:layout()
        self:refresh()
        return self
    end)
    if not ok then self:destroy(); error(result, 0) end
    return result
end

function UI:referenceTarget(id)
    local target = self.helpTargets and self.helpTargets[id]
    if target and target.Visible then
        local node = target.Parent
        while node and node ~= self.root do
            if node:IsA("GuiObject") and not node.Visible then return nil end
            node = node.Parent
        end
        return target
    end
end

function UI:bindHelpTargets()
    self.helpTargets = {
        launcher = self.launcher, toolbar = self.toolbarGrip, dragPanel = self.inspectorGrip,
        quickEdit = self.editButton, tools = self.toolsButton, layers = self.elementsButton,
        groups = self.tabButtons.Groups, profiles = self.tabButtons.Profiles, settings = self.tabButtons.Settings,
        help = self.tabButtons.Help, collapse = self.quickHide, done = self.doneButton, save = self.saveButton,
        move = self.transformButtons.move, size = self.transformButtons.size, rotate = self.transformButtons.rotate,
        opacity = self.transformButtons.opacity, selectThrough = self.selectThroughButton, undo = self.undoButton,
        redo = self.redoButton, multi = self.multiButton, resetElement = self.quickReset,
        opacityElement = self.opacityScopes.element, opacityContents = self.opacityScopes.contents,
        resetRotation = self.toolReset, resetAll = self.resetAllButton, resetEditor = self.resetEditorButton,
        aspect = self.quickLock, lock = self.layerActions,
    }
    for id, object in pairs(self.helpTargets) do self.helpActions[object] = id end
end

function UI:setCollapsed(collapsed)
    if self.collapsed == collapsed then return end
    if self.app.input then self.app.input:cancel() end
    self.collapsed = collapsed
    self:showSurfaces()
    self:updateSelection()
    self:layoutNotifications()
    self:refreshToolbar()
end

function UI:setWorkspace(open)
    if self.workspaceOpen ~= open then
        if self.app.input then self.app.input:cancel() end
        self.workspaceOpen = open
        if open and self.tab == "Elements" then self.elementRevision = nil end
        self:showSurfaces()
        self:updateSelection()
        self:layoutNotifications()
    end
    self:refreshToolbar()
    if open then self:refreshPage() end
end

function UI:setTab(name)
    if not self.pages[name] then return end
    if self.tab ~= name and self.app.input then self.app.input:cancel() end
    if self.tab ~= name and name == "Elements" then self.elementRevision = nil end
    self.tab = name
    if name ~= "Elements" then self.lastToolsTab = name end
    self.workspaceHeading.Text = self.tabButtons[name].Text
    self.workspaceMenu.Text = self.tabButtons[name].Text
    local tabPosition = self.tabs.CanvasPosition
    local tabX, tabW, viewW = self.tabPositions[name], self.tabButtons[name].AbsoluteSize.X, self.tabs.AbsoluteSize.X
    local offset = tabPosition and tabPosition.X or 0
    if tabX < offset or tabX + tabW > offset + viewW then
        self.tabs.CanvasPosition = Vector2.new(math.max(0, tabX + tabW - viewW), 0)
    end
    for key, page in pairs(self.pages) do page.Visible = key == name end
    for key, button in pairs(self.tabButtons) do
        button.TextColor3 = key == name and C.text or C.muted
        self.tabMarks[key].Visible = key == name
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
    self.panel.Visible = self.visible and not self.workspaceOpen and not self.collapsed and not self.selectThroughArmed
        and #self.app.selection > 0
    self.helpExit.Visible = self.toolbar.Visible and self.helpMode == true
    self.canvasHint.Visible = self.toolbar.Visible and not self.workspaceOpen and not self.helpMode
        and (#self.app.selection == 0 or self.selectThroughArmed == true)
    self.editButton.Visible = self.toolbar.Visible and not self.workspaceOpen and self.collapsed and #self.app.selection > 0
        and not self.selectThroughArmed and not self.helpMode
    self.launcher.Visible = not self.visible and self.app.preferences.launcherHidden ~= true
end

function UI:setSelectThroughArmed(armed)
    self.selectThroughArmed = armed == true
    self.canvasHintText.Text = self.selectThroughArmed and "Tap a spot to inspect its layers" or "Tap a control to edit"
    self:placeCanvasHint()
    self:showSurfaces()
    self:layoutNotifications()
end

function UI:placeCanvasHint()
    local plan = self.layoutPlan
    if not plan then return end
    local width = self.selectThroughArmed and 220 or 184
    local toolbar = self.surfaceRects.toolbar or plan.toolbar
    local y = toolbar.y + toolbar.h + 8
    if y + 30 > plan.area.y + plan.area.h then y = toolbar.y - 38 end
    self.hintRect = Layout.place({w = math.min(width, plan.area.w), h = math.min(30, plan.content.h)}, plan.area, toolbar.x, y)
    localRect(self.canvasHint, self.hintRect)
    localRect(self.editButton, Layout.place({w = 126, h = 44}, plan.area, toolbar.x, self.hintRect.y))
    local hintY = self.hintRect.y
    localRect(self.helpExit, Layout.place({w = 92, h = 44}, plan.area, toolbar.x + toolbar.w + 7, hintY))
end

function UI:layoutToolbar(plan)
    local compact = plan.toolbar.w < 379
    local x, gutter = 46, not compact and 5 or 0
    local available = plan.toolbar.w - x - 4 - gutter * 2
    local showSave = available >= (compact and 6 or 7) * Touch.minimum
    self.toolbarBrand.Visible = plan.toolbar.w >= 287
    local function shown(name)
        if name == "History" then return compact end
        if name == "Undo" or name == "Redo" then return not compact end
        return name ~= "Save" or showSave
    end
    local count, preferred = 0, 0
    for _, entry in ipairs(self.toolbarButtons) do
        if shown(entry.name) then count, preferred = count + 1, preferred + entry.width end
    end
    local minimum = math.min(Touch.minimum, math.max(1, math.floor(available / count)))
    local extra = math.max(0, available - minimum * count)
    local requested = preferred - Touch.minimum * count
    local factor = math.min(1, extra / math.max(1, requested))
    local shared = math.floor(math.max(0, extra - requested) / count)
    for _, entry in ipairs(self.toolbarButtons) do
        local button = entry.button
        button.Visible = shown(entry.name)
        local edge = self.toolbarDividers[entry.name]
        if edge then
            edge.Visible = gutter > 0
            edge.Position = UDim2.fromOffset(x + 1, 14)
            x = x + gutter
        end
        if button.Visible then
            local width = minimum + math.floor((entry.width - Touch.minimum) * factor) + shared
            button.Position = UDim2.fromOffset(x, 2)
            button.Size = UDim2.fromOffset(width, math.max(1, math.min(Touch.minimum, plan.toolbar.h - 2)))
            x = x + width
        end
    end
end

local surfaceNames = {inspector = "panel", toolbar = "toolbar", workspace = "workspace", launcher = "launcher"}

function UI:surfaceArea(kind)
    return kind == "launcher" and self:launcherArea() or self.layoutPlan.area
end

function UI:placeSurface(kind, rect)
    local area = self:surfaceArea(kind)
    local drag = self.draggedSurface
    if drag and drag.kind == kind then
        rect = Layout.place(rect, area, drag.rect.x, drag.rect.y)
    else
        local placement = self.app.getEditorPlacement and self.app:getEditorPlacement(kind)
            or self.localPlacements and self.localPlacements[kind]
        rect = Layout.fromPlacement(rect, area, placement)
    end
    if (kind == "inspector" or kind == "workspace") and self.layoutPlan.toolbarVisible
        and (not drag or drag.kind ~= kind) then
        rect = Layout.avoid(rect, area, self.surfaceRects.toolbar)
    end
    self.surfaceRects[kind] = rect
    localRect(self[surfaceNames[kind]], rect)
    return rect
end

function UI:placeInspector()
    local plan = self.layoutPlan
    local panel = Layout.panelForSelection(plan, self.selectionDockBounds)
    local maxHeight = ({actions = 106, inspect = 56, move = 196})[self.quickMode] or 244
    if panel.h > maxHeight then
        local y = plan.portrait and panel.y + panel.h - maxHeight or panel.y
        panel = Layout.place({w = panel.w, h = maxHeight}, plan.content, panel.x, y)
    end
    self.panelRect = self:placeSurface("inspector", panel)
end

function UI:layoutNotifications()
    if not self.notifications or not self.layoutPlan then return end
    local avoid = {}
    if self.toolbar.Visible then avoid[#avoid + 1] = self.surfaceRects.toolbar end
    if self.canvasHint.Visible then avoid[#avoid + 1] = self.hintRect end
    if self.editButton.Visible then avoid[#avoid + 1] = Coordinates.rect(self.editButton) end
    if self.helpExit.Visible then avoid[#avoid + 1] = Coordinates.rect(self.helpExit) end
    if self.panel.Visible then avoid[#avoid + 1] = self.panelRect end
    if self.workspace.Visible then avoid[#avoid + 1] = self.surfaceRects.workspace end
    if self.visible and self.selectionBounds.Visible then
        avoid[#avoid + 1] = self.selectionOverlayRect
        if self.rotationHandle.gui.Visible then avoid[#avoid + 1] = Coordinates.rect(self.rotationHandle.gui) end
        for _, handle in ipairs(self.handles) do
            if handle.gui.Visible then avoid[#avoid + 1] = Coordinates.rect(handle.gui) end
        end
    end
    if self.onboarding and self.onboardingOpen then
        for _, rect in ipairs(self.onboarding:protectedRects()) do avoid[#avoid + 1] = rect end
    end
    if self.launcher.Visible then avoid[#avoid + 1] = Coordinates.rect(self.launcher) end
    self.notifications:layout(self.layoutPlan.area, avoid)
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
    local area = self.safeArea
    local signature = table.concat({area.x, area.y, area.w, area.h, keyboardHeight or 0}, ":")
    if self.safeGeometry and self.safeGeometry ~= signature and self.visible and self.app.input
        and self.app.input.isBusy and self.app.input:isBusy() then
        self.safeGeometry = signature
        self.app.input:cancel()
    else self.safeGeometry = signature end
    self.mobile = (preferred ~= nil and preferred == touchPreference) or (preferred == nil and uis.TouchEnabled == true)
    local plan = Layout.plan(self.safeArea, self.mobile, keyboardHeight)
    self.layoutPlan = plan
    self:placeSurface("toolbar", plan.toolbar)
    self:layoutToolbar(plan)
    self:placeCanvasHint()
    self:placeInspector()
    self:placeSurface("workspace", plan.workspace)
    self.tabs.Visible = plan.workspace.h >= 132
    self.workspaceHeading.Visible, self.workspaceMenu.Visible = self.tabs.Visible, not self.tabs.Visible
    local bodyTop = self.tabs.Visible and 100 or 49
    for _, page in pairs(self.pages) do
        page.Position, page.Size = UDim2.fromOffset(10, bodyTop), UDim2.new(1, -20, 0, math.max(1, plan.workspace.h - bodyTop - 8))
    end
    self:positionLauncher()
    self:showSurfaces()
    self:layoutDialog()
    self:drawGrid()
    self:updateSelection()
    self:layoutKeyboard((keyboardHeight or 0) > 0)
    if self.onboarding then self.onboarding:layout(plan.area) end
    self:layoutNotifications()
end

function UI:viewportChanged()
    self.elementRevision = nil
    self:layout()
    self:refresh()
end

function UI:positionQuickControls()
    local hasTools = self.quickMode == "full" or self.quickMode == "move"
    self.quickTabs.Visible = hasTools and not self.quickKeyboard
    local top = self.quickKeyboard and 6 or (hasTools and 96 or 52)
    self.quickBody.Position, self.quickBody.Size = UDim2.fromOffset(8, top), UDim2.new(1, -16, 1, -top - 6)
end

function UI:layoutKeyboard(keyboard)
    local quickFocused = keyboard and self.percent:IsFocused()
    self.inspectorGrip.Visible, self.quickHide.Visible = not quickFocused, not quickFocused
    local wasKeyboard = self.quickKeyboard
    self.quickKeyboard = quickFocused
    self:positionQuickControls()
    if quickFocused then
        self.quickBody.CanvasPosition = Vector2.new(0, 48)
    elseif wasKeyboard then
        self.quickBody.CanvasPosition = Vector2.new(0, 0)
    end
    if not keyboard or not self.workspace.Visible then return end
    local page, focused = self.pages[self.tab], self.services.UserInputService:GetFocusedTextBox()
    if not focused and self.tab == "Advanced" then
        for _, box in pairs(self.fields) do if box:IsFocused() then focused = box; break end end
        if not focused then
            if self.rotation:IsFocused() then focused = self.rotation
            elseif self.transparency:IsFocused() then focused = self.transparency end
        end
    elseif not focused and self.tab == "Settings" then
        for _, box in pairs(self.preferenceFields) do if box:IsFocused() then focused = box; break end end
    end
    if not focused then return end
    local parent = focused.Parent
    while parent and parent ~= page do parent = parent.Parent end
    if not parent then return end
    local pageRect, fieldRect = Coordinates.rect(page), Coordinates.rect(focused)
    if pageRect and fieldRect then
        local scroll = page.CanvasPosition
        page.CanvasPosition = Vector2.new(0, math.max(0, (scroll and scroll.Y or 0) + fieldRect.y - pageRect.y - 4))
    end
end

function UI:surfacePosition(kind)
    local rect = self.surfaceRects[kind]
    return rect and rect.x, rect and rect.y
end

function UI:moveSurface(kind, x, y)
    local rect = self.surfaceRects[kind]
    local object = self[surfaceNames[kind]]
    if not rect or not object or not object.Visible then return end
    local target = Layout.place(rect, self:surfaceArea(kind), x, y)
    self.draggedSurface = {kind = kind, rect = target}
    self.surfaceRects[kind] = target
    localRect(object, target)
    if kind == "inspector" then self.panelRect = target end
    if kind == "toolbar" then self:placeCanvasHint() end
end

function UI:finishSurfaceMove(kind, cancelled)
    local drag = self.draggedSurface
    if not drag or drag.kind ~= kind then return end
    self.draggedSurface = nil
    if not cancelled then
        local prefs = self.app.editorPreferences and self.app.editorPreferences.data
        local docking = prefs and prefs.panelDocking == true
        local area = self:surfaceArea(kind)
        local target = drag.rect
        if kind == "inspector" or kind == "workspace" then
            target = Layout.avoid(target, area, self.layoutPlan.toolbarVisible and self.surfaceRects.toolbar)
        end
        local placement = Layout.toPlacement(target, area, docking)
        if self.app.setEditorPlacement then self.app:setEditorPlacement(kind, placement)
        elseif kind == "launcher" then
            local x = placement.x < .5 and 0 or 1
            if self.app.setLauncherPosition then self.app:setLauncherPosition(x, placement.y)
            else
                self.app:setPreference("launcherX", x)
                self.app:setPreference("launcherY", placement.y)
            end
        else
            self.localPlacements = self.localPlacements or {}
            self.localPlacements[kind] = placement
        end
    end
    self:layout()
end

function UI:resetPlacements()
    self.draggedSurface, self.localPlacements = nil, nil
    if not self.dead then self:layout() end
end

-- Compatibility for older Input adapters.
function UI:inspectorPosition()
    return self:surfacePosition("inspector")
end

function UI:moveInspector(x, y)
    self:moveSurface("inspector", x, y)
end

function UI:finishInspectorMove(cancelled)
    self:finishSurfaceMove("inspector", cancelled)
end

function UI:launcherArea()
    local safe = self.safeArea
    return {x = safe.x + 8, y = safe.y + 8, w = math.max(1, safe.w - 16), h = math.max(1, safe.h - 16)}
end

function UI:positionLauncher()
    if not self.safeArea then return end
    local area = self:launcherArea()
    local shape = {w = 48, h = 48}
    local prefs = self.app.preferences
    local x = (prefs.launcherX or .02) <= .5 and area.x or area.x + area.w - shape.w
    local y = area.y + (prefs.launcherY or .35) * math.max(0, area.h - shape.h)
    self:placeSurface("launcher", Layout.place(shape, area, x, y))
end

function UI:moveLauncher(x, y)
    self:moveSurface("launcher", x, y)
end

function UI:finishLauncherMove(cancelled)
    self:finishSurfaceMove("launcher", cancelled)
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
            object = make("Frame", {BackgroundColor3 = C.cyan, BackgroundTransparency = .952, BorderSizePixel = 0, ZIndex = 3}, self.gridLayer)
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
    return self.onboardingOpen or self.modalOpen or self.helpMode or inside(self.editButton, x, y) or inside(self.toolbar, x, y) or inside(self.panel, x, y)
        or inside(self.workspace, x, y) or inside(self.launcher, x, y)
end

function UI:sliderTrackRect()
    return self.sliderEnabled and self.panel.Visible and Coordinates.rect(self.sliderTrack) or nil
end

function UI:visualSliderTrackRect(kind)
    local controls = self.visualControls and self.visualControls[kind]
    return controls and self.visualEnabled[kind] and self.panel.Visible and Coordinates.rect(controls.track) or nil
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
    local cornerX, cornerY = bounds.w * corner.anchor[1], bounds.h * corner.anchor[2]
    local markX, markY = x - bounds.x + markerX, y - bounds.y + markerY
    local dx, dy = markX - cornerX, markY - cornerY
    local link = self.touchHandleLink
    link.Position = UDim2.fromOffset((cornerX + markX) / 2, (cornerY + markY) / 2)
    link.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), 1)
    link.Rotation = math.deg((math.atan2 or math.atan)(dy, dx))
    link.Visible = true
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

local function visualAngle(record)
    if not record then return 0 end
    local ok, value = pcall(function() return record.object.AbsoluteRotation or record.object.Rotation or 0 end)
    return ok and value or 0
end

function UI:placeRotationHandle(bounds, info, angle)
    local size = self.mobile and 44 or 26
    local half = size / 2
    local center = info.pivot or {x = bounds.x + bounds.w / 2, y = bounds.y + bounds.h / 2}
    local toolbar = self.toolbar.Visible and self.surfaceRects.toolbar
    local panel = self.panel.Visible and self.panelRect
    local workspace = self.workspace.Visible and self.surfaceRects.workspace
    local sides = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}}
    local radians = math.rad(angle)
    local cos, sin = math.cos(radians), math.sin(radians)
    for _, side in ipairs(sides) do
        local edgeX, edgeY = side[1] * bounds.w / 2, side[2] * bounds.h / 2
        local dx, dy = side[1] * (half + 10), side[2] * (half + 10)
        local startX, startY = center.x + edgeX * cos - edgeY * sin, center.y + edgeX * sin + edgeY * cos
        local x, y = startX + dx * cos - dy * sin, startY + dx * sin + dy * cos
        local hit = {x = x - half, y = y - half, w = size, h = size}
        if usableHandle(hit, self.safeArea, panel, toolbar, workspace) then
            localRect(self.rotationHandle.gui, hit)
            self.rotationHandle.gui.Visible = true
            local line = self.rotationLink
            local lx, ly = Coordinates.screenToLocal((startX + x) / 2, (startY + y) / 2, line.Parent)
            line.Position, line.Size = UDim2.fromOffset(lx, ly), UDim2.fromOffset(half + 10, 1)
            line.Rotation, line.Visible = math.deg((math.atan2 or math.atan)(y - startY, x - startX)), true
            return
        end
    end
end

function UI:paintVisualSlider(kind, info, enabled)
    local control = self.visualControls[kind]
    local rotation = kind == "rotation"
    local value = info and (rotation and info.angle or info.percent or info.value)
    local minimum = (info and (info.min or info.minimum)) or (rotation and -180 or 0)
    local maximum = (info and (info.max or info.maximum)) or (rotation and 180 or 100)
    if self.app.input and self.app.input.sliderRange then
        local activeMinimum, activeMaximum = self.app.input:sliderRange(kind)
        if activeMinimum then minimum, maximum = activeMinimum, activeMaximum end
    end
    self.visualEnabled[kind] = enabled and value ~= nil
    control.value.Text = info and info.mixed and "Mixed" or (value and (numberText(value) .. (rotation and "°" or "%")) or "")
    control.caption.Text = rotation and (info and info.group and "Group angle" or "Angle")
        or (value ~= nil and "Relative opacity" or "No own appearance")
    local fraction = value and math.max(0, math.min(1, (value - minimum) / math.max(.01, maximum - minimum))) or 0
    control.fill.Size = UDim2.fromScale(fraction, 1)
    control.thumb.Position = UDim2.fromScale(fraction, .5)
    control.thumb.Visible = value ~= nil
    local accent = self.visualEnabled[kind] and C.cyan or C.quiet
    control.fill.BackgroundColor3, control.thumb.BackgroundColor3 = accent, accent
end

function UI:updateSelection()
    if self.dead or not self.visible then return end
    local caps = self.selectionCapabilities or {}
    local rects, historyKeys = self.app:getRects()
    local displayedBounds = Geometry.bounds(rects or {})
    local tool = self.transformTool
    local sizeActive = tool == "size"
    local resizeRects, resizeKeys = {}, {}
    if caps.resize and (sizeActive or self.workspaceOpen) then resizeRects, resizeKeys = self.app:getRects(true, "resize") end
    local resizeBounds = Geometry.bounds(resizeRects or {})
    local record = #self.app.selection == 1 and self.app.discovery:get(self.app.selection[1]) or nil
    if not displayedBounds and record then displayedBounds = Coordinates.rect(record.object) end
    local suspended = self.app.profiles and self.app.profiles.suspended
    local checking = self.app.finishingGesture or self.app.saving
    local writable = not self.app.previewState and not checking and not suspended
    local resizeReady = resizeBounds ~= nil and writable and sizeActive
    local info = resizeBounds and self.app.sizeInfo and self.app:sizeInfo(resizeBounds, resizeRects, resizeKeys) or nil
    local rotationInfo = tool == "rotate" and caps.rotate and self.app.rotationInfo and self.app:rotationInfo() or nil
    local scopeAvailable = self.opacityScope == "element" and caps.opacity or self.opacityScope == "contents" and caps.opacityContents
    local opacityInfo = tool == "opacity" and scopeAvailable and self.app.opacityInfo and self.app:opacityInfo(self.opacityScope) or nil
    local opacityAvailable = caps.opacity == true or caps.opacityContents == true
    local enabled = {move = caps.move == true, size = caps.resize == true, rotate = caps.rotate == true, opacity = opacityAvailable}
    local focus = self.app.groupFocus
    local group = #self.app.selection > 1
    local directLock = self.selectionLayerState and self.selectionLayerState.locked
    local hint = group and "Drag the group to move" or "Drag on the canvas to move"
    if self.app.previewState then hint = "Profile preview"
    elseif suspended then hint = "Profiles suspended"
    elseif checking then hint = "Checking layout"
    elseif directLock then hint = "Locked in the editor"
    elseif caps.locked and group then hint = "Some group members are locked"
    elseif caps.locked then hint = "Contains a locked layer"
    elseif caps.parentKey and not caps.move then hint = caps.layout and "Layout sets the position" or "Try its container"
    elseif tool == "rotate" and enabled.rotate then hint = "Drag handle to rotate"
    elseif tool == "size" and enabled.size then hint = self.mobile and "Pinch in or out to resize" or "Drag a handle to resize"
    elseif tool == "opacity" and enabled.opacity then
        if opacityInfo and (opacityInfo.percent or opacityInfo.value) == 0 then hint = "Still tappable at 0%"
        elseif not opacityInfo then hint = "Try Include contents"
        elseif self.opacityScope == "contents" then hint = "Fades the layer and contents"
        else hint = "100% is original" end
    elseif not caps.move and caps.resize then hint = "Size can be edited"
    elseif not caps.move then hint = "View details in Tools"
    elseif not caps.resize then hint = "Drag to move. Size is fixed." end
    if self.quickHint.Text ~= hint then self.quickHint.Text = hint end

    local hasTool = enabled.move or enabled.size or enabled.rotate or enabled.opacity
    local mode = hasTool and (tool == "move" and "move" or "full")
        or ((caps.parentKey or caps.locked or focus) and "actions" or "inspect")
    if self.dockSelection or self.quickMode ~= mode then
        if self.dockSelection then self.selectionDockBounds = displayedBounds end
        self.dockSelection, self.quickMode = false, mode
        self:placeInspector()
    end
    self.inspectorUnavailable = not (caps.move or caps.resize)
    self.selectionBounds.Visible = displayedBounds ~= nil
    self.selectionOverlayRect = displayedBounds
    if displayedBounds then localRect(self.selectionBounds, displayedBounds) end
    local rotation = visualAngle(record)
    self.selectionBounds.Rotation = rotation
    self.selectionStroke.Color = hasTool and C.cyan or C.warning
    self.selectionStroke.Transparency = group and .34 or .22
    self.selectionAccent.BackgroundColor3 = writable and hasTool and C.cyan or C.quiet
    self.touchHandleLink.Visible = false
    self.rotationHandle.gui.Visible, self.rotationLink.Visible = false, false
    if rotationInfo and writable and displayedBounds then self:placeRotationHandle(displayedBounds, rotationInfo, rotation) end
    self.handleBounds.Visible = resizeReady
    if resizeBounds then
        localRect(self.handleBounds, resizeBounds)
        local full = displayedBounds
        self.handleStroke.Enabled = full ~= nil and (full.x ~= resizeBounds.x or full.y ~= resizeBounds.y
            or full.w ~= resizeBounds.w or full.h ~= resizeBounds.h)
    end
    for _, entry in ipairs(self.handles) do
        local handle = entry.gui
        handle.Visible = resizeReady and not self.mobile
        if handle.Visible then
            handle.Position = UDim2.fromScale(entry.anchor[1], entry.anchor[2])
            handle.Size = UDim2.fromOffset(16, 16)
            entry.marker.Position = UDim2.fromScale(.5, .5)
        end
    end
    self.touchHandle.handle = "se"
    if self.mobile and resizeReady then self:placeTouchHandle(resizeBounds) end
    for i, rect in ipairs(rects or {}) do
        local object = self.individual[i]
        if not object and #rects > 1 then
            object = make("Frame", {Name = "ElementBoundary", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5}, self.overlay)
            Design.stroke(object, C.cyan, 1, .68)
            self.individual[i] = object
        end
        if object then
            object.Visible = #rects > 1
            if object.Visible then
                localRect(object, rect)
                object.Rotation = visualAngle(historyKeys and self.app.discovery:get(historyKeys[i]))
            end
        end
    end
    for i = #(rects or {}) + 1, #self.individual do self.individual[i].Visible = false end

    self.sliderEnabled = sizeActive and info ~= nil and writable
    self:positionQuickControls()
    self.quickBody.Visible = mode ~= "inspect"
    for key, panel in pairs(self.toolPanels) do panel.Visible = tool == key and enabled[key] end
    for key, button in pairs(self.transformButtons) do
        self:enable(button, enabled[key])
        button.BackgroundTransparency = key == tool and 0 or 1
        button.BackgroundColor3 = C.selected
        if key == tool and enabled[key] then button.TextColor3 = C.cyan end
    end
    local visualOffset = mode == "move" and 48 or (mode == "full" and 96 or 0)
    self.quickActions.Position = UDim2.fromOffset(0, visualOffset)
    self.quickBody.CanvasSize = UDim2.fromOffset(0, visualOffset + 46)
    self.quickLock.Visible = sizeActive and info ~= nil
    self.toolReset.Visible = tool == "rotate" and rotationInfo ~= nil or tool == "opacity" and opacityInfo ~= nil
    self.toolReset.Text = tool == "rotate" and "Reset angle" or "Reset opacity"
    self:enable(self.toolReset, writable and self.toolReset.Visible)
    local canReset = writable and caps.reset == true
    local aspectShown, toolResetShown = self.quickLock.Visible, self.toolReset.Visible
    self.quickReset.Visible = canReset and not toolResetShown
    self.quickReset.Position = UDim2.new(aspectShown and .34 or 0, 0, 0, 0)
    self.quickReset.Size = UDim2.new(aspectShown and .30 or .46, -4, 0, 44)
    self.toolReset.Size = UDim2.new(.46, -4, 0, 44)
    local edge = toolResetShown and .46 or (canReset and (aspectShown and .64 or .46) or (aspectShown and .34 or 0))
    self.quickMore.Position = UDim2.new(edge, 0, 0, 0)
    self.quickMore.Size = UDim2.new(1 - edge, 0, 0, 44)
    if tool == "rotate" then self:paintVisualSlider("rotation", rotationInfo, writable)
    else self.visualEnabled.rotation = false end
    if tool == "opacity" then self:paintVisualSlider("opacity", opacityInfo, writable)
    else self.visualEnabled.opacity = false end
    if tool == "opacity" then
        for scope, button in pairs(self.opacityScopes) do
            local available = scope == "element" and caps.opacity == true or scope == "contents" and caps.opacityContents == true
            self:enable(button, available)
            button.BackgroundColor3 = self.opacityScope == scope and C.selected or C.raised
            if self.opacityScope == scope and available then button.TextColor3 = C.cyan end
        end
    end
    local more = "More"
    if directLock then more = "Unlock"
    elseif caps.parentKey and not caps.move then more = "Select container"
    elseif focus and focus.member then more = "Back to group"
    elseif group and self.app.quickGroup then more = focus and "Group tools" or "Quick group" end
    self.quickMore.Text = more
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
        self.sliderTitle.Text = group and self.app.preferences.equalSize and "Member size" or (group and "Group size" or "Size")
        self.sliderReference.Text = info.original and "100% original" or "100% starting size"
        self:syncTextBox(self.percent, numberText(info.scale) .. "%")
        self.quickSize.Text = numberText(resizeBounds.w) .. " × " .. numberText(resizeBounds.h)
    else self:syncTextBox(self.percent, "") end
    if self.workspaceOpen and self.tab == "Advanced" then
        local position = caps.move and self.app:currentBounds(true, "move") or displayedBounds
        local size = info and info.size or displayedBounds
        local map = displayedBounds and {X = position.x, Y = position.y, W = size.w, H = size.h}
        self.precisionHeading.Text = group and self.app.preferences.equalSize
            and "Group position / largest member size (px)" or "Position and size (px)"
        for name, box in pairs(self.fields) do
            local positionAxis = name == "X" or name == "Y"
            self:syncTextBox(box, map and numberText(map[name]) or "")
            box.TextEditable = writable and ((positionAxis and caps.move) or (not positionAxis and caps.resize)) == true
        end
        self.positionActions.Visible = caps.move == true
        self:enable(self.resetAdvanced, canReset)
        self:enable(self.recoverAdvanced, writable and caps.move == true)
    end
end

function UI:describeSelection()
    local selectedCount = #self.app.selection
    local record = selectedCount == 1 and self.app.discovery:get(self.app.selection[1]) or nil
    local caps
    if self.app.capabilitiesForSelection then caps = self.app:capabilitiesForSelection()
    else
        local editable = #self.app:getRects(true) > 0
        caps = {move = editable, resize = editable, reset = editable, visual = record and record.editable == true}
    end
    self.selectionCapabilities = caps
    local available = {move = caps.move, size = caps.resize, rotate = caps.rotate, opacity = caps.opacity or caps.opacityContents}
    if not available[self.transformTool] then
        for _, name in ipairs({"size", "move", "rotate", "opacity"}) do
            if available[name] then self.transformTool = name; break end
        end
    end
    self.selectionLayerState = record and self:layerState(record) or nil
    local focus = self.app.groupFocus
    self.selectionTools.Visible = selectedCount == 1 or caps.parentKey ~= nil
    self.selectionContainer.Visible = caps.parentKey ~= nil
    self.selectionActions.Visible = selectedCount == 1
    self.selectionActions.Position = UDim2.new(caps.parentKey and .55 or 0, 0, 0, 0)
    self.selectionActions.Size = UDim2.new(caps.parentKey and .45 or 1, 0, 0, 44)
    if record then
        self.selectionName.Text, self.quickName.Text = displayName(record), displayName(record)
        local description
        if self.selectionLayerState.locked then description = "Unlock this layer to change it."
        elseif caps.locked then description = "A locked layer depends on this one. Unlock it before changing the arrangement."
        elseif caps.parentKey and not caps.move then description = caps.layout
            and "The layout sets this control's position. Select its container to move the arrangement."
            or "This layer has limited editing. Its container may support movement."
        elseif caps.move and caps.resize then description = "Move and resize are available."
        elseif caps.resize then description = "Resize is available. The current position is fixed."
        elseif caps.move then description = "Move is available. The current size is fixed."
        elseif caps.visual then description = "Appearance can be edited in Visual properties."
        else description = "This layer is available for inspection." end
        self.selectionDetail.Text = description
        self:syncTextBox(self.rotation, numberText(record.object.Rotation))
        self:syncTextBox(self.transparency, numberText(record.object.BackgroundTransparency))
    elseif selectedCount > 1 then
        self.selectionName.Text = focus and focus.name or (tostring(selectedCount) .. (focus and " in group" or " selected"))
        self.quickName.Text = self.selectionName.Text
        self.selectionDetail.Text = caps.reason or (caps.move and "Drag the selection to move the group." or "This arrangement is controlled by its layout.")
    else
        self.selectionName.Text = "Select a control"
        self.quickName.Text = self.selectionName.Text
        self.selectionDetail.Text = "Tap a control on the canvas or choose one in Layers."
    end
    self.selectionDetail.TextColor3 = selectedCount > 0 and not (caps.move or caps.resize) and C.warning or C.muted
    local visual = record ~= nil and caps.visual == true
    local rotate = visual and (caps.rotation == nil or caps.rotation)
    local transparent = visual and (caps.transparency == nil or caps.transparency)
    local writable = not (self.app.previewState or self.app.finishingGesture or self.app.saving
        or self.app.profiles and self.app.profiles.suspended)
    self.rotation.Visible, self.transparency.Visible = rotate, transparent
    self.rotationRow.Visible, self.transparencyRow.Visible = rotate, transparent
    self.rotation.TextEditable, self.transparency.TextEditable = rotate and writable, transparent and writable
    self.visualHint.Text = transparent and "Background transparency uses 0 for solid and 1 for clear."
        or "Choose one layer with editable appearance."
    self.visualHint.Visible = transparent or not rotate
    local experimental = record and record.experimental == true
        and (not record.capabilities or (record.capabilities.move and record.capabilities.move.experimental)
            or (record.capabilities.resize and record.capabilities.resize.experimental))
    self.experimental.Visible = experimental and not record.experimentalApproved or false
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
    if changed then self:layoutNotifications() end
    if self.workspaceOpen and self.tab == "Elements" then
        if self.layerFilter == "Selected" then self:refreshElements()
        else self:updateElementSelection() end
    end
end

function UI:clearSelectionFeedback()
    self:setOverlaps()
    self:setBox()
    self:setGuides()
    self.selectionDockBounds = nil
    self.dockSelection = true
    self:selectionChanged()
end

function UI:clearDynamic(container, connections)
    for _, connection in ipairs(connections) do connection:Disconnect() end
    for _, child in ipairs(container:GetChildren()) do
        if not child:IsA("UIListLayout") then child:Destroy() end
    end
    orders[container] = 0
end

local displayStates = {hidden = "Hidden", clipped = "Clipped", transparent = "Transparent", container = "Container"}

function UI:layerMeta(record)
    local state = self:layerState(record)
    local move, resize = hasOperation(record, "move"), hasOperation(record, "resize")
    local mode = move and (resize and "Move and resize" or "Move only") or (resize and "Resize only" or "Inspect")
    local tags = {}
    if state.ignored then tags[#tags + 1] = "Ignored" end
    if state.locked then tags[#tags + 1] = "Locked" end
    if displayStates[record.visibility] then tags[#tags + 1] = displayStates[record.visibility] end
    if self.app.groupMembers then
        local groups = self.app:groupMembers(record.key)
        if groups and groups[1] then tags[#tags + 1] = groups[1] end
    end
    tags[#tags + 1] = mode
    return table.concat(tags, "  /  "), state.locked or state.ignored
end

local function layerGlyph(parent, class, x)
    local tile = make("Frame", {Name = "LayerType", BackgroundColor3 = C.field, BorderSizePixel = 0,
        Position = UDim2.fromOffset(x, 12), Size = UDim2.fromOffset(28, 28)}, parent)
    corners(tile, 8)
    local glyph = make("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(7, 7), Size = UDim2.fromOffset(14, 14)}, tile)
    if class:find("Text") and not class:find("Button") then
        for y = 2, 12, 5 do
            make("Frame", {BackgroundColor3 = C.cyan, BorderSizePixel = 0, Position = UDim2.fromOffset(0, y),
                Size = UDim2.fromOffset(y == 12 and 8 or 14, 1)}, glyph)
        end
    else
        corners(glyph, class:find("Button") and 4 or 2)
        outline(glyph, C.cyan)
        if class:find("Image") then
            local dot = make("Frame", {BackgroundColor3 = C.cyan, BorderSizePixel = 0, Position = UDim2.fromOffset(3, 3),
                Size = UDim2.fromOffset(4, 4)}, glyph)
            corners(dot, 2)
        end
    end
end

function UI:configureLayerRow(row, record)
    local active = selected(self.app.selection, record.key)
    row.button.BackgroundColor3 = active and C.selected or C.raised
    row.button.BackgroundTransparency = active and 0 or .45
    row.title.TextColor3 = active and C.cyan or C.text
    row.marker.Visible = active
end

function UI:elementRow(parent, record, connections, picker)
    local key = record.key
    local depth = picker and 0 or math.max(0, math.min(3, (record.depth or 0) - 1))
    local hasChildren = record.childKeys and #record.childKeys > 0
    local right = picker and 57 or (hasChildren and 44 or 0)
    local row = frame(parent, 52)
    row.Name = "LayerRow"
    local button = self:button(row, "", function()
        if self.app.preferences.multiSelect then
            self.app:select(key, true)
            if picker then self:refreshPickerHighlights() end
        elseif picker then self:closeModal(); self:chooseElement(key)
        else self:chooseElement(key) end
    end, nil, nil, nil, connections)
    button.Name, button.Size = "SelectLayer", UDim2.new(1, -right, 1, 0)
    local marker = make("Frame", {Name = "SelectedLayer", BackgroundColor3 = C.cyan, BorderSizePixel = 0,
        Position = UDim2.fromOffset(2, 13), Size = UDim2.fromOffset(2, 26), Visible = false}, button)
    corners(marker, 1)
    local iconX = 8 + 10 * depth
    layerGlyph(button, record.object.ClassName, iconX)
    local x = iconX + 36
    local title = label(button, displayName(record), 20, 13)
    title.Position, title.Size, title.Font = UDim2.fromOffset(x, 6), UDim2.new(1, -x - 8, 0, 20), Enum.Font.GothamBold
    truncate(title)
    local summary, marked = self:layerMeta(record)
    local subtitle = label(button, summary, 16, 11)
    subtitle.Position, subtitle.Size, subtitle.TextColor3 = UDim2.fromOffset(x, 27), UDim2.new(1, -x - 8, 0, 16), marked and C.warning or C.muted
    truncate(subtitle)
    if picker or hasChildren then
        local action = self:button(row, picker and "Details" or (self.collapsedLayers[key] and "Show" or "Hide"), function()
            if picker then self:showLayerDetails(record)
            else
                self.collapsedLayers[key] = not self.collapsedLayers[key] or nil
                self.elementSignature, self.elementFilter = nil, nil
                self:refreshElements()
            end
        end, nil, nil, nil, connections)
        action.Position, action.Size = UDim2.new(1, -right + 4, 0, 4), UDim2.fromOffset(right - 4, 44)
    end
    local result = {root = row, button = button, title = title, record = record, marker = marker}
    self:configureLayerRow(result, record)
    return result
end

function UI:updateElementSelection()
    local record = self.app.discovery:get(self.app.selection[1])
    self.elementPath.Text = self.childParent and ("Children of " .. self.childParent.Name)
        or (record and elementPath(record) or "Tap a layer below to edit it.")
    self.layerActions.Visible = #self.app.selection > 0 or self.childParent ~= nil
    self.layerActions.Text = self.childParent and "Layer actions and hierarchy" or "Layer actions"
    for _, row in pairs(self.elementRows) do self:configureLayerRow(row, row.record) end
end

function UI:setOverlaps(records)
    local keys = {}
    for i, record in ipairs(records or {}) do
        if i > 24 then break end
        keys[#keys + 1] = record.key
    end
    self.overlapKeys = keys
    if self.workspaceOpen and self.tab == "Elements" then self:refreshOverlaps() end
end

function UI:refreshOverlaps()
    local count = 0
    for _, key in ipairs(self.overlapKeys or {}) do
        if self.app.discovery:get(key) then count = count + 1 end
    end
    self.overlapList.Visible = count > 1
end

function UI:refreshPickerHighlights()
    for _, row in ipairs(self.pickerRows or {}) do self:configureLayerRow(row, row.record) end
end

function UI:openSelectThrough(records)
    if not records then
        records = {}
        for _, key in ipairs(self.overlapKeys or {}) do
            local record = self.app.discovery:get(key)
            if record then records[#records + 1] = record end
        end
    end
    if #records == 0 then
        self.app:status("There are no accessible layers at this point.")
        return false
    end
    self:setOverlaps(records)
    local _, body = self:dialog("Select through", "Pick a layer at this point. Other layers stay where they are.", nil, {{label = "Close"}})
    self.dialogMaxHeight = math.min(382, 130 + #records * 56)
    self.pickerRows = {}
    for i, record in ipairs(records) do
        if i > 24 then break end
        self.pickerRows[#self.pickerRows + 1] = self:elementRow(body, record, self.modalConnections, true)
    end
    if #records > 24 then
        label(body, "More nearby layers are available in the Layers browser.", 34, 12).TextColor3 = C.muted
    end
    self:layoutDialog()
    return true
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

local function passesFilter(ui, record)
    local filter = ui.layerFilter
    if filter == "All accessible" then return true end
    if filter == "Selected" then return selected(ui.app.selection, record.key) end
    local state = ui:layerState(record)
    if filter == "Ignored" then return state.ignored end
    if filter == "Locked" then return state.locked end
    if filter == "Editable" then
        return not state.locked and (hasOperation(record, "move") or hasOperation(record, "resize") or hasOperation(record, "visual"))
    end
    return record.visibility ~= "hidden" and record.visibility ~= "clipped"
end

function UI:refreshElements()
    local discovery = self.app.discovery
    if self.childParent and not self.childParent.Parent then self.childParent = nil end
    local fallback = discovery.revision == nil and discovery:list("all")
    local search = self.search.Text:lower():match("^%s*(.-)%s*$")
    local selection = self.layerFilter == "Selected" and table.concat(self.app.selection, "\n") or ""
    local filter = table.concat({search, self.layerFilter, tostring(self.childParent), selection}, "\n")
    local revision, policy = discovery.revision or fallback, self.app.layerRevision or 0
    if revision ~= self.elementRevision or self.elementPolicy ~= policy then
        self.elementRevision, self.elementPolicy = revision, policy
        self.layerRecords = fallback or discovery:list("all")
        self.layerIndex, self.builtinKeys = {}, {}
        for _, record in ipairs(self.layerRecords) do
            self.layerIndex[record.key] = record
            local kind = record.builtin
            if kind and not self.builtinKeys[kind] and record.visibility ~= "hidden" then self.builtinKeys[kind] = record.key end
        end
        self.builtinRow.Visible = next(self.builtinKeys) ~= nil
        for kind, button in pairs(self.builtinButtons) do self:enable(button, self.builtinKeys[kind] ~= nil) end
        self.elementFilter = nil
    end
    if filter ~= self.elementFilter then
        self.elementFilter, self.elementMatches = filter, {}
        for _, record in ipairs(self.layerRecords or {}) do
            local matches = search == "" or (displayName(record) .. " " .. elementPath(record) .. " " .. record.object.ClassName):lower():find(search, 1, true)
            local ancestor, expanded = record.parentKey, true
            if search == "" and not self.childParent and self.layerFilter == "Visible" then
                while ancestor do
                    if self.collapsedLayers[ancestor] then expanded = false; break end
                    local parent = self.layerIndex[ancestor]
                    ancestor = parent and parent.parentKey
                end
            end
            if matches and expanded and passesFilter(self, record)
                and (not self.childParent or record.object.Parent == self.childParent) then
                self.elementMatches[#self.elementMatches + 1] = record
            end
        end
        self.elementSignature = nil
    end
    local limit = 22
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
        if #self.elementMatches == 0 then
            label(self.elementList, "No layers match this view. Try a different filter or search.", 44, 12).TextColor3 = C.muted
        end
    end
    self.elementSummary.Text = tostring(#self.elementMatches) .. (#self.elementMatches == 1 and " layer" or " layers")
    self.compatibleFilter.Text = "Show: " .. self.layerFilter
    self.pager.Visible = pages > 1
    self.pagerCaption.Text = tostring(self.elementPage) .. " / " .. tostring(pages)
    self:enable(self.pagerBack, self.elementPage > 1)
    self:enable(self.pagerNext, self.elementPage < pages)
    self:updateElementSelection()
    self:refreshOverlaps()
    self:refreshMissing()
end

function UI:refreshGroups()
    local focus = self.app.groupFocus
    local members = focus and focus.keys or {}
    local count = #self.app.selection
    self.groupTitle.Text = focus and (focus.name or "Quick group") or "Current selection"
    self.groupSummary.Text = focus and (#members .. (focus.member and " members / Editing one" or " members"))
        or (count > 1 and (count .. " controls selected") or "Select at least two controls to group them.")
    local canGroup = count > 1 and focus == nil and self.app.quickGroup ~= nil
    local canLeave = focus ~= nil and self.app.ungroup ~= nil
    self.groupActions.Visible = canGroup or canLeave
    self.temporaryGroup.Visible, self.leaveGroup.Visible = canGroup, canLeave
    self.temporaryGroup.Size = UDim2.new(1, 0, 0, Touch.minimum)
    self.leaveGroup.Position, self.leaveGroup.Size = UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, Touch.minimum)
    self.leaveGroup.Text = focus and focus.member and "Back to group" or "Ungroup"
    self.nameGroupButton.Visible = count > 1 and (not focus or not focus.name)
    self.groupMemberList.Visible = #members > 0
    local memberSignature = table.concat(members, "\n") .. tostring(focus and focus.member)
    if memberSignature ~= self.groupMemberSignature then
        self.groupMemberSignature = memberSignature
        self:clearDynamic(self.groupMemberList, self.groupMemberConnections)
        self.groupMemberConnections = {}
        if #members > 0 then self:section(self.groupMemberList, "Edit one member") end
        for i, key in ipairs(members) do
            if i > 20 then break end
            local record = self.app.discovery:get(key)
            if record then
                self:button(self.groupMemberList, displayName(record), function()
                    if self.app.enterGroupMember then
                        self.app:enterGroupMember(key)
                        self:setWorkspace(false)
                    end
                end, nil, nil, nil, self.groupMemberConnections)
            end
        end
    end
    local names, parts = {}, {}
    for name, members in pairs(self.app.groups or {}) do table.insert(names, name); table.insert(parts, name .. ":" .. tostring(#members)) end
    table.sort(names); table.sort(parts)
    local signature = table.concat(parts, "\n") .. tostring(focus and focus.name)
    if signature == self.groupSignature then return end
    self.groupSignature = signature
    self:clearDynamic(self.groupList, self.groupConnections); self.groupConnections = {}
    for _, name in ipairs(names) do
        self:listItem(self.groupList, name, tostring(#self.app.groups[name]) .. " controls", function()
            self:openSavedGroup(name)
        end, self.groupConnections, focus and focus.name == name)
    end
    if #names == 0 then label(self.groupList, "Named groups appear here.", 34, Text.control).TextColor3 = C.muted end
end

function UI:refreshProfiles()
    local list = self.app.profiles:list()
    local active = self.app.profiles:active()
    local preview = self.app.previewState or self.app.profiles.preview
    self.activeProfile.Text = preview and "Previewing a layout" or (active and active.name or "Current layout")
    self.profileSummary.Text = preview and "Apply to use this layout or cancel to return."
        or (self.app.profiles.suspended and "Saved layout paused" or (active and profileScopeLabel(active.scope) or "No saved profile selected"))
    self.previewActions.Visible = preview ~= nil and preview ~= false
    self.newProfileButton.Visible = not self.previewActions.Visible
    self.profileSuspend.Text = self.app.profiles.suspended and "Resume saved layout" or "Show original layout"
    local parts = {tostring(active and active.id)}
    for _, profile in ipairs(list) do table.insert(parts, profile.id .. ":" .. profile.name .. ":" .. profile.scope) end
    local signature = table.concat(parts, "\n")
    if signature ~= self.profileSignature then
        self.profileSignature = signature
        self:clearDynamic(self.profileList, self.profileConnections); self.profileConnections = {}
        for _, profile in ipairs(list) do
            self:listItem(self.profileList, profile.name, profileScopeLabel(profile.scope), function()
                self:openProfileActions(profile)
            end, self.profileConnections, active and active.id == profile.id)
        end
        if #list == 0 then label(self.profileList, "Saved layouts appear here.", 34, Text.control).TextColor3 = C.muted end
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
    local tabs = {
        {self.elementsButton, self.workspaceOpen and self.tab == "Elements"},
        {self.multiButton, self.app.preferences.multiSelect},
        {self.toolsButton, self.workspaceOpen and self.tab ~= "Elements"},
    }
    for _, tab in ipairs(tabs) do
        local button, active = tab[1], tab[2]
        button.TextColor3 = active and C.cyan or C.text
        button.BackgroundColor3, button.BackgroundTransparency = C.selected, active and 0 or 1
    end
    self.elementsButton.Text = "Layers"
    self.doneButton.BackgroundColor3, self.doneButton.TextColor3 = C.raised, C.text
    local ready = not self.disabled[self.saveButton]
    self.saveButton.BackgroundTransparency = ready and self.app.dirty and 0 or 1
    self.saveButton.BackgroundColor3 = C.cyan
    self.saveButton.TextColor3 = ready and (self.app.dirty and C.ink or C.muted) or C.quiet
    self.toolsSaveIndicator.Visible = self.app.dirty and ready and not self.saveButton.Visible or false
end

function UI:refreshPage()
    if self.tab == "Elements" then self:refreshElements()
    elseif self.tab == "Groups" then self:refreshGroups()
    elseif self.tab == "Profiles" then self:refreshProfiles()
    elseif self.tab == "Advanced" then self:describeSelection(); self:updateSelection()
    elseif self.tab == "Help" then
        self.resumeTutorialButton.Visible = self.onboarding and self.onboarding.hasProgress and self.onboarding:hasProgress("tour") or false
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
        self.capabilityText = table.concat(caps, "\n")
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

function UI:status(message, options)
    if self.dead then return end
    self:refreshToolbar()
    if not self.visible and not (options and options.keepOnClose) then return end
    self:layoutNotifications()
    self.notifications:show(message, options)
end

function UI:setVisible(visible)
    self.visible = visible == true
    self.canvas.Visible, self.overlay.Visible = self.visible, self.visible
    if not self.visible then
        self.workspaceOpen, self.collapsed, self.helpMode = false, false, false
        self.notifications:close()
        if self.onboarding then self.onboarding:close() end
        self:closeModal()
        self:setGuides()
        self:setBox()
    end
    self:layout()
    self:refresh()
    if self.visible and not self.tutorialOffered and self.app.hasSeenTutorial and not self.app:hasSeenTutorial()
        and not (self.app.options and self.app.options.SafeMode) and not (self.app.profiles and self.app.profiles.suspended) then
        self.tutorialOffered = true
        self:startTutorial()
    end
end

function UI:destroy()
    if self.dead then return end
    self.dead = true
    self:closeModal()
    if self.notifications then self.notifications:destroy() end
    if self.onboarding then self.onboarding:destroy() end
    for _, list in ipairs({self.connections, self.elementConnections, self.profileConnections, self.groupConnections,
        self.missingConnections, self.selectionConnections, self.groupMemberConnections, self.referenceConnections}) do
        for _, connection in ipairs(list) do connection:Disconnect() end
    end
    if self.gui then self.gui:Destroy() end
end

return UI
