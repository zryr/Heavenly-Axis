-- Heavenly Axis V3 — Roblox HUD & Interface Editor
-- Original project by Syshi; V2 inspired by Danechka.
local Geometry = require("Geometry")
local UI = {}
UI.__index = UI

local C = {
    surface = Color3.fromRGB(15, 23, 32), raised = Color3.fromRGB(26, 38, 50),
    cyan = Color3.fromRGB(82, 217, 233), text = Color3.fromRGB(233, 242, 247),
    muted = Color3.fromRGB(161, 180, 194), border = Color3.fromRGB(55, 79, 94),
    warning = Color3.fromRGB(255, 195, 108), danger = Color3.fromRGB(211, 105, 111),
}
local function make(class, props, parent)
    local object = Instance.new(class)
    for name, value in pairs(props or {}) do object[name] = value end
    object.Parent = parent
    return object
end
local function corners(object, radius)
    make("UICorner", {CornerRadius = UDim.new(0, radius or 8)}, object)
end
local function outline(object, color, thickness)
    return make("UIStroke", {Color = color or C.border, Thickness = thickness or 1, Transparency = .2}, object)
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
    local p, s = object.AbsolutePosition, object.AbsoluteSize
    return x >= p.X and y >= p.Y and x <= p.X + s.X and y <= p.Y + s.Y
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
    local b = make("TextButton", {Name = text:gsub("[^%w]", ""), Text = text, Size = UDim2.new(width or 1, width and -5 or 0, 0, 42),
        Position = UDim2.new(x or 0, 0, 0, 0), BackgroundColor3 = color or C.raised, BorderSizePixel = 0,
        TextColor3 = C.text, TextSize = 12, Font = Enum.Font.GothamMedium, TextWrapped = true,
        AutoButtonColor = true, ZIndex = parent.ZIndex + 1}, parent)
    corners(b, 7)
    outline(b)
    if callback then self:connect(b.Activated, callback, dynamic) end
    return b
end

function UI:textbox(parent, placeholder, initial, callback, width, x, dynamic)
    local b = make("TextBox", {Name = placeholder:gsub("[^%w]", ""), Text = initial or "", PlaceholderText = placeholder,
        PlaceholderColor3 = C.muted, ClearTextOnFocus = false, Size = UDim2.new(width or 1, width and -5 or 0, 0, 42),
        Position = UDim2.new(x or 0, 0, 0, 0), BackgroundColor3 = C.raised, BorderSizePixel = 0,
        TextColor3 = C.text, TextSize = 13, Font = Enum.Font.Gotham, ZIndex = parent.ZIndex + 1}, parent)
    corners(b, 7); outline(b)
    if callback then self:connect(b.FocusLost, function(enter) callback(b.Text, enter) end, dynamic) end
    return b
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
        self:button(r, entry[1], entry[2], 1 / #buttons, (i - 1) / #buttons, entry[3])
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
        entry.button.Text = (value and "✓  " or "○  ") .. entry.title
        entry.button.TextColor3 = value and C.cyan or C.muted
    end
end

function UI:modal(title, message, text, actionText, action)
    if self.app.input then self.app.input:cancel() end
    self:closeModal()
    local viewW, viewH = self:viewport()
    local inset = self.launcherInset or {top = 8, bottom = 8}
    local compact = viewH < 420
    local dialogW = math.max(160, math.min(600, viewW - 24))
    local dialogH = math.max(160, math.min(600, viewH - inset.top - inset.bottom - 16))
    local shield = make("TextButton", {Name = "DialogShield", Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = .25, Size = UDim2.fromScale(1, 1), ZIndex = 70}, self.gui)
    local card = make("Frame", {Name = "Dialog", BackgroundColor3 = C.surface, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromOffset(viewW / 2, inset.top + (viewH - inset.top - inset.bottom) / 2), Size = UDim2.fromOffset(dialogW, dialogH), ZIndex = 71}, shield)
    make("UISizeConstraint", {MaxSize = Vector2.new(600, 600), MinSize = Vector2.new(160, 160)}, card)
    corners(card, 12); outline(card, C.cyan)
    local heading = label(card, title, 32, 17)
    heading.Position = UDim2.new(0, 14, 0, compact and 6 or 10); heading.Size = UDim2.new(1, -28, 0, compact and 28 or 32); heading.ZIndex = 72
    local desc = label(card, message, 68, 12)
    desc.Position = UDim2.new(0, 14, 0, compact and 36 or 48); desc.Size = UDim2.new(1, -28, 0, compact and 40 or 68); desc.ZIndex = 72
    if compact then desc.TextSize = 10 end
    local content = make("ScrollingFrame", {BackgroundColor3 = C.raised, BorderSizePixel = 0, ScrollBarThickness = 5,
        Position = UDim2.new(0, 14, 0, compact and 80 or 120), Size = UDim2.new(1, -28, 1, compact and -144 or -188), CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 72}, card)
    local box = make("TextBox", {Text = text or "", ClearTextOnFocus = false, MultiLine = true, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Font = Enum.Font.Code,
        TextColor3 = C.text, TextSize = 13, BackgroundTransparency = 1, Size = UDim2.new(1, -10, 0, 100),
        AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 73}, content)
    local actions = frame(card, 44)
    actions.Position = UDim2.new(0, 14, 1, -56); actions.Size = UDim2.new(1, -28, 0, 44); actions.ZIndex = 73
    self.modalGui, self.modalConnections, self.modalOpen = shield, {}, true
    self:button(actions, "Close", function() self:closeModal() end, .45, 0, nil, self.modalConnections)
    if action then
        self:button(actions, actionText or "Continue", function()
            local ok, result = action(box.Text)
            if ok ~= false then self:closeModal()
            elseif result then
                desc.Text, desc.TextColor3 = tostring(result), C.warning
                self.app:status(result)
            end
        end, .55, .45, C.raised, self.modalConnections)
    end
    return box
end

function UI:confirm(title, message, callback)
    return self:modal(title, message .. "\nThis action requires confirmation.", "", "Confirm", function() callback(); return true end)
end

function UI:closeModal()
    for _, c in ipairs(self.modalConnections or {}) do c:Disconnect() end
    self.modalConnections, self.modalOpen = {}, false
    if self.modalGui then self.modalGui:Destroy(); self.modalGui = nil end
end

function UI:makeElements()
    local body = self.pages.Elements
    self.selectionName = label(body, "Select an element in the game or the list below.", 48, 14)
    self.selectionName.Font = Enum.Font.GothamMedium
    self.selectionDetail = label(body, "Editing gestures may not isolate every game input.", 48, 11)
    self.selectionDetail.TextColor3 = C.warning
    label(body, "Input isolation is incomplete: game scripts may still observe gestures. Close the editor before testing gameplay.", 48, 11).TextColor3 = C.warning
    self:row(body, {{"Parent", function() self:selectParent() end}, {"Clear", function() self.app:clearSelection() end},
        {"Recover", function() self.app:recover() end}})
    local r = frame(body, 44)
    self.multiButton = self:button(r, "Multi-select", function() self.app:setPreference("multiSelect", not self.app.preferences.multiSelect) end, .5, 0)
    self.boxButton = self:button(r, "Box-select", function() self.app:setPreference("boxSelect", not self.app.preferences.boxSelect) end, .5, .5)
    self:section(body, "POSITION & SIZE · screen pixels")
    local names = {"X", "Y", "W", "H"}
    local fieldRow = frame(body, 64)
    self.fields = {}
    for i, name in ipairs(names) do
        local caption = label(fieldRow, name, 17, 11)
        caption.Position = UDim2.new((i - 1) / 4, 0, 0, 0); caption.Size = UDim2.new(.25, -5, 0, 17)
        local field = self:textbox(fieldRow, name, "", function(value)
            local n = tonumber(value)
            if not n or n ~= n or math.abs(n) > 100000 then self.app:status("Enter a finite numeric value."); self:refresh(); return end
            local bounds = self.app:currentBounds()
            if not bounds then return end
            if name == "X" or name == "Y" then
                self.app:geometry("position", {x = name == "X" and n or bounds.x, y = name == "Y" and n or bounds.y})
            else
                local width, height = name == "W" and n or bounds.w, name == "H" and n or bounds.h
                if self.app.preferences.aspectLock ~= false then
                    if name == "W" then height = bounds.h * n / math.max(16, bounds.w)
                    else width = bounds.w * n / math.max(16, bounds.h) end
                end
                self.app:resize(width, height)
            end
        end, .25, (i - 1) / 4)
        field.Position = UDim2.new((i - 1) / 4, 0, 0, 19)
        self.fields[name] = field
    end
    self:row(body, {{"←", function() self.app:move(-(self.app.preferences.step or 1), 0) end},
        {"↑", function() self.app:move(0, -(self.app.preferences.step or 1)) end},
        {"↓", function() self.app:move(0, self.app.preferences.step or 1) end},
        {"→", function() self.app:move(self.app.preferences.step or 1, 0) end}})
    local sizeRow = frame(body, 44)
    self:button(sizeRow, "−", function() self.app:scale(.95) end, .17, 0)
    self.slider = self:button(sizeRow, "Size · drag", nil, .66, .17)
    self.slider.Name = "SizeSlider"
    self.sliderFill = make("Frame", {Name = "Amount", BackgroundColor3 = C.cyan, BorderSizePixel = 0,
        Position = UDim2.new(0, 8, 1, -6), Size = UDim2.new(.2, 0, 0, 2), ZIndex = self.slider.ZIndex + 1}, self.slider)
    self:button(sizeRow, "+", function() self.app:scale(1.05) end, .17, .83)
    self:toggle(body, "Lock aspect ratio", "aspectLock", true)
    self:row(body, {{"Reset selection", function() self.app:reset() end}, {"Advanced ▾", function()
        self.advanced.Visible = not self.advanced.Visible
    end}})
    self.advanced = make("Frame", {Name = "Advanced", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, Visible = false, ZIndex = 23}, body)
    flow(self.advanced)
    self:toggle(self.advanced, "Scale group from center", "centerScale", false)
    self:toggle(self.advanced, "Equal sizes (instead of group scaling)", "equalSize", false)
    self:section(self.advanced, "ALIGN SELECTED ELEMENTS")
    self:row(self.advanced, {{"Left", function() self.app:align("left") end}, {"Center X", function() self.app:align("centerX") end}, {"Right", function() self.app:align("right") end}})
    self:row(self.advanced, {{"Top", function() self.app:align("top") end}, {"Center Y", function() self.app:align("centerY") end}, {"Bottom", function() self.app:align("bottom") end}})
    self:row(self.advanced, {{"Distribute X", function() self.app:distribute("x") end}, {"Distribute Y", function() self.app:distribute("y") end}})
    self:section(self.advanced, "OPTIONAL VISUAL PROPERTIES")
    self.visualHint = label(self.advanced, "Select one compatible element to edit visual properties.", 40, 11)
    self.rotation = self:textbox(self.advanced, "Rotation degrees", "", function(v)
        local n = tonumber(v); if n then self.app:geometry("rotation", n) else self.app:status("Enter rotation in degrees.") end
    end)
    self.transparency = self:textbox(self.advanced, "Background transparency 0–1", "", function(v)
        local n = tonumber(v); if n then self.app:geometry("transparency", n) else self.app:status("Enter transparency from 0 to 1.") end
    end)
    self.experimental = self:button(self.advanced, "Approve experimental adjustment", function()
        local record = self.app.discovery:get(self.app.selection[1])
        if not record then return end
        if record.experimental then
            self:confirm("Experimental element", "Layout management can overwrite edits. Approval is per element and reversible; repeated failures suspend application.", function() self.app:approve(record.key, true) end)
        else self.app:status("Selected element does not require an experimental override.") end
    end)
    self:button(self.advanced, "Revoke experimental approval", function()
        if self.app.selection[1] then self.app:approve(self.app.selection[1], false) end
    end)
    self:section(body, "ELEMENTS · parent / child hierarchy")
    self.compatibleFilter = self:button(body, "Filter: all visible elements", function()
        self.onlyEditable = not self.onlyEditable
        self.compatibleFilter.Text = self.onlyEditable and "Filter: editable elements only" or "Filter: all visible elements"
        self.elementSignature = nil; self:refreshElements()
    end)
    self.search = self:textbox(body, "Search name, type or hierarchy", "")
    self:connect(self.search:GetPropertyChangedSignal("Text"), function() self.elementSignature = nil; self:refreshElements() end)
    self.elementList = make("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 23}, body)
    flow(self.elementList, 5)
    self.elementRows = {}
    self.remapLabel = label(body, "Missing saved elements remain stored. Choose one, then select its replacement and remap.", 48, 11)
    self.missingList = make("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 23}, body)
    flow(self.missingList, 5)
    self:button(body, "Remap chosen missing element → selection", function()
        if self.remapKey and #self.app.selection == 1 then
            self:confirm("Remap saved element", "Replace the chosen saved identity with the selected compatible element?", function()
                self.app:remap(self.remapKey, self.app.selection[1]); self.remapKey = nil
            end)
        else self.app:status("Choose a missing element and exactly one replacement first.") end
    end)
end

function UI:selectParent()
    local record = self.app.discovery:get(self.app.selection[1])
    if not record then return end
    local parent = record.object.Parent
    for _, candidate in ipairs(self.app.discovery:list()) do
        if candidate.object == parent then self.app:select(candidate.key, false); return end
    end
    self.app:status("No accessible GUI parent is available.")
end

function UI:makeGroups()
    local body = self.pages.Groups
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
    self:toggle(body, "Equal sizes (instead of group scaling)", "equalSize", false)
    self:toggle(body, "Scale from center", "centerScale", false)
    self:section(body, "GROUP ALIGNMENT")
    self:row(body, {{"Left", function() self.app:align("left") end}, {"Center X", function() self.app:align("centerX") end}, {"Right", function() self.app:align("right") end}})
    self:row(body, {{"Top", function() self.app:align("top") end}, {"Center Y", function() self.app:align("centerY") end}, {"Bottom", function() self.app:align("bottom") end}})
    self:row(body, {{"Distribute X", function() self.app:distribute("x") end}, {"Distribute Y", function() self.app:distribute("y") end}})
end

function UI:makeProfiles()
    local body = self.pages.Profiles
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
    self:row(body, {{"Export JSON", function()
        local text, problem = self.app:export()
        if not text then self.app:status(problem or "Export unavailable."); return end
        self:modal("Export configuration", "Copy this JSON manually if clipboard access is unavailable. It contains saved profile data; unsaved edits require Save first.", text, "Copy", function(value)
            if self.app.storage then local ok, message = self.app.storage:copy(value); self.app:status(message); return ok end
            return false, "Clipboard unavailable; select and copy the JSON manually."
        end)
    end}, {"Import JSON", function()
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
    label(self.draftSection, "A recoverable unsaved draft is available. It has not been applied.", 48, 12)
    self:row(self.draftSection, {{"Preview draft", function() self.app:profile("recoverDraft") end}, {"Discard draft…", function()
        self:confirm("Discard draft", "Delete only the recoverable unsaved draft? Saved profiles stay intact.", function() self.app:profile("discardDraft") end)
    end}})
end

function UI:makeSettings()
    local body = self.pages.Settings
    self:section(body, "EDITING PREFERENCES")
    self:toggle(body, "Editing grid", "grid", true)
    self:toggle(body, "Snap to grid & guides", "snapping", false)
    self:toggle(body, "Multi-select taps", "multiSelect", false)
    self:toggle(body, "Box selection", "boxSelect", false)
    self:textbox(body, "Grid spacing (4–128 pixels)", tostring(self.app.preferences.gridSize or 24), function(v)
        local n = tonumber(v); if n and n >= 4 and n <= 128 then self.app:setPreference("gridSize", n) else self.app:status("Grid spacing must be 4–128 pixels.") end
    end)
    self:textbox(body, "Guide threshold (1–32 pixels)", tostring(self.app.preferences.snapThreshold or 6), function(v)
        local n = tonumber(v); if n and n >= 1 and n <= 32 then self.app:setPreference("snapThreshold", n) else self.app:status("Guide threshold must be 1–32 pixels.") end
    end)
    self:textbox(body, "Fine adjustment step (1–64)", tostring(self.app.preferences.step or 1), function(v)
        local n = tonumber(v); if n and n >= 1 and n <= 64 then self.app:setPreference("step", n) else self.app:status("Step must be 1–64 pixels.") end
    end)
    self:textbox(body, "Reopen key (for example F8)", self.app.preferences.shortcut or "F8", function(v)
        local ok, key = pcall(function() return Enum.KeyCode[v] end)
        if ok and key and key ~= Enum.KeyCode.Unknown then self.app:setPreference("shortcut", v) else self.app:status("Enter a valid Roblox KeyCode name.") end
    end)
    self:row(body, {{"Hide launcher", function() self.app:setPreference("launcherHidden", true) end}, {"Recover launcher", function()
        self.app:setPreference("launcherHidden", false); self.app:setPreference("launcherX", .02); self.app:setPreference("launcherY", .35)
    end}})
    label(body, "Reopen with the configured key or rerun the release. The public HeavenlyAxis API also supports Open and SafeMode.", 60, 11)
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
    label(body, "Heavenly Axis " .. tostring(self.app.version or "3.0.0") .. "\nOriginal by Syshi · V2 inspired by Danechka", 44, 12)
    self:button(body, "Check project releases (optional)", function() self.app:checkUpdates() end)
    self:button(body, "Expandable diagnostic log", function()
        local lines = {}
        for _, entry in ipairs(self.app.logs or self.app.diagnostics or {}) do
            table.insert(lines, type(entry) == "table" and tostring(entry.message or entry.text or "") or tostring(entry))
        end
        self:modal("Diagnostics", "Runtime observations and failures. This log does not establish device or executor compatibility.", table.concat(lines, "\n"))
    end)
    label(body, "Touch-control visuals are editable only when accessible. Functional joystick / jump hit regions and complete gameplay-input isolation remain unverified until tested on your device.", 92, 11).TextColor3 = C.warning
end

function UI.new(app, playerGui, services)
    local self = setmetatable({app = app, services = services, connections = {}, elementConnections = {}, groupConnections = {},
        profileConnections = {}, missingConnections = {}, toggles = {}, handles = {}, guideObjects = {}, gridObjects = {},
        visible = false, tab = "Elements", mobile = services.UserInputService.TouchEnabled, collapsed = false}, UI)
    local ok, result = pcall(function()
    self.gui = make("ScreenGui", {Name = "HeavenlyAxis", ResetOnSpawn = false, IgnoreGuiInset = true,
        DisplayOrder = 10000, ZIndexBehavior = Enum.ZIndexBehavior.Global}, playerGui)
    self.canvas = make("TextButton", {Name = "EditSurface", Text = "", BackgroundTransparency = 1, AutoButtonColor = false,
        Active = true, Size = UDim2.fromScale(1, 1), ZIndex = 2, Visible = false}, self.gui)
    self.gridLayer = make("Frame", {Name = "Grid", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3, Visible = false}, self.gui)
    self.overlay = make("Frame", {Name = "SelectionOverlay", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5, Visible = false}, self.gui)
    self.selectionBounds = make("Frame", {Name = "SelectionBounds", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 6, Visible = false}, self.overlay)
    self.selectionStroke = outline(self.selectionBounds, C.cyan, 2)
    self.individual = {}
    self.box = make("Frame", {Name = "BoxSelection", BackgroundColor3 = C.cyan, BackgroundTransparency = .9, BorderSizePixel = 0, ZIndex = 6, Visible = false}, self.overlay)
    outline(self.box, C.cyan)
    local anchors = {nw = {0,0}, n = {.5,0}, ne = {1,0}, e = {1,.5}, se = {1,1}, s = {.5,1}, sw = {0,1}, w = {0,.5}}
    for _, handle in ipairs({"nw", "n", "ne", "e", "se", "s", "sw", "w"}) do
        local anchor = anchors[handle]
        local b = make("TextButton", {Name = "Resize_" .. handle, Text = "", BackgroundColor3 = C.cyan,
            BackgroundTransparency = .1, BorderSizePixel = 0, AnchorPoint = Vector2.new(.5, .5),
            Size = UDim2.fromOffset(self.mobile and 44 or 16, self.mobile and 44 or 16),
            Position = UDim2.fromScale(anchor[1], anchor[2]), ZIndex = 9, AutoButtonColor = false}, self.selectionBounds)
        if self.mobile then
            b.BackgroundTransparency = 1
            local marker = make("Frame", {BackgroundColor3 = C.cyan, BackgroundTransparency = .05, BorderSizePixel = 0,
                AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.fromOffset(16, 16), ZIndex = 10}, b)
            corners(marker, 5); outline(marker, C.surface)
        else corners(b, 5); outline(b, C.surface) end
        table.insert(self.handles, {gui = b, handle = handle})
    end
    self.panel = make("Frame", {Name = "Inspector", BackgroundColor3 = C.surface, BackgroundTransparency = .04,
        BorderSizePixel = 0, ZIndex = 20, Visible = false}, self.gui)
    corners(self.panel, 12); outline(self.panel)
    local header = frame(self.panel, 48)
    self.header = header
    header.Position = UDim2.fromOffset(12, 5); header.Size = UDim2.new(1, -24, 0, 48); header.ZIndex = 21
    self.title = label(header, "HEAVENLY AXIS", 26, 16)
    self.title.TextColor3 = C.cyan; self.title.Font = Enum.Font.GothamBold; self.title.Size = UDim2.new(1, -95, 0, 26)
    self.subtitle = label(header, "Roblox HUD & Interface Editor", 17, 10)
    self.subtitle.Position = UDim2.fromOffset(0, 27)
    self:button(header, "▾", function() self.collapsed = not self.collapsed; self:layout() end, .13, .72)
    self:button(header, "×", function() self.app:setEditing(false) end, .13, .86)
    self.tabs = frame(self.panel, 44)
    self.tabs.Position = UDim2.fromOffset(10, 56); self.tabs.Size = UDim2.new(1, -20, 0, 44); self.tabs.ZIndex = 21
    self.tabButtons, self.pages = {}, {}
    for i, name in ipairs({"Elements", "Groups", "Profiles", "Settings"}) do
        self.tabButtons[name] = self:button(self.tabs, name, function() self:setTab(name) end, .25, (i - 1) * .25)
        local page = make("ScrollingFrame", {Name = name, BackgroundTransparency = 1, BorderSizePixel = 0,
            ScrollBarThickness = 4, ScrollBarImageColor3 = C.cyan, CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y, Position = UDim2.fromOffset(12, 106),
            Size = UDim2.new(1, -24, 1, -232), Visible = name == "Elements", ZIndex = 22,
            ScrollingDirection = Enum.ScrollingDirection.Y}, self.panel)
        make("UIPadding", {PaddingBottom = UDim.new(0, 12), PaddingRight = UDim.new(0, 6)}, page)
        flow(page, 7); self.pages[name] = page
    end
    self.footer = frame(self.panel, 112)
    self.footer.Position = UDim2.new(0, 12, 1, -120); self.footer.Size = UDim2.new(1, -24, 0, 112); self.footer.ZIndex = 23
    local editRow = frame(self.footer, 42)
    self.editRow = editRow
    self:button(editRow, "Undo", function() self.app:undo() end, .25, 0)
    self:button(editRow, "Redo", function() self.app:redo() end, .25, .25)
    self:button(editRow, "Save", function() self.app:save() end, .25, .5, Color3.fromRGB(27, 82, 91))
    self:button(editRow, "Cancel", function() self.app:cancel() end, .25, .75)
    self.statusLabel = label(self.footer, "Ready", 64, 11)
    self.statusLabel.Position = UDim2.fromOffset(0, 46); self.statusLabel.TextYAlignment = Enum.TextYAlignment.Top
    self.launcher = make("TextButton", {Name = "Launcher", Text = "AXIS", BackgroundColor3 = C.surface,
        BorderSizePixel = 0, TextColor3 = C.cyan, TextSize = 12, Font = Enum.Font.GothamBold,
        Size = UDim2.fromOffset(54, 48), Position = UDim2.fromScale(.02, .35), ZIndex = 50, AutoButtonColor = true}, self.gui)
    corners(self.launcher, 12); outline(self.launcher, C.cyan)
    self:makeElements(); self:makeGroups(); self:makeProfiles(); self:makeSettings()
    self:connect(self.gui:GetPropertyChangedSignal("AbsoluteSize"), function() self:layout() end)
    local camera = services.Workspace.CurrentCamera
    if camera then self:connect(camera:GetPropertyChangedSignal("ViewportSize"), function() self:layout() end) end
    self:layout(); self:refresh()
    return self
    end)
    if not ok then self:destroy(); error(result, 0) end
    return result
end

function UI:setTab(name)
    if not self.pages[name] then return end
    self.tab = name
    for key, page in pairs(self.pages) do page.Visible = key == name and not self.collapsed end
    for key, b in pairs(self.tabButtons) do b.TextColor3 = key == name and C.cyan or C.muted end
    self:refresh()
end

function UI:viewport()
    local camera = self.services.Workspace.CurrentCamera
    if camera then return camera.ViewportSize.X, camera.ViewportSize.Y end
    local s = self.gui.AbsoluteSize
    return math.max(320, s.X), math.max(240, s.Y)
end

function UI:layout()
    if self.dead then return end
    local w, h = self:viewport()
    local left, top, right, bottom = 8, 8, 8, 8
    pcall(function()
        local a, b = self.services.GuiService:GetGuiInset()
        left, top, right, bottom = math.max(8, a.X), math.max(8, a.Y), math.max(8, b.X), math.max(8, b.Y)
    end)
    local usableH = math.max(120, h - top - bottom)
    local isBottom = self.mobile or w < 760
    self.compact, self.tiny = h < 420, h < 280
    local bodyTop = self.compact and 80 or 106
    local footerHeight = self.tiny and 44 or (self.compact and 70 or 112)
    local footerReservation = footerHeight + 14
    local minimumExpanded = bodyTop + footerReservation + 70
    local height = self.collapsed and (self.compact and 34 or 56)
        or (isBottom and math.max(minimumExpanded, math.min(500, usableH * .55)) or usableH)
    height = math.min(usableH, height)
    local width = isBottom and math.max(160, w - left - right) or math.min(350, w - left - right)
    self.panel.Size = UDim2.fromOffset(width, height)
    self.panel.Position = UDim2.fromOffset(isBottom and left or w - width - right, h - height - bottom)
    self.header.Position = UDim2.fromOffset(12, self.compact and 2 or 5)
    self.header.Size = UDim2.new(1, -24, 0, self.compact and 30 or 48)
    self.subtitle.Visible = not self.compact
    for _, child in ipairs(self.header:GetChildren()) do
        if child:IsA("TextButton") then child.Size = UDim2.new(child.Size.X.Scale, child.Size.X.Offset, 0, self.compact and 28 or 42) end
    end
    self.tabs.Position = UDim2.fromOffset(10, self.compact and 34 or 56)
    self.tabs.Visible, self.footer.Visible = not self.collapsed, not self.collapsed
    self.footer.Position = UDim2.new(0, 12, 1, -(footerHeight + 8))
    self.footer.Size = UDim2.new(1, -24, 0, footerHeight)
    self.statusLabel.Visible = not self.tiny
    self.statusLabel.Size = UDim2.new(1, 0, 0, self.compact and 24 or 64)
    for name, page in pairs(self.pages) do
        page.Visible = name == self.tab and not self.collapsed
        page.Position = UDim2.fromOffset(12, bodyTop)
        page.Size = UDim2.new(1, -24, 1, -(bodyTop + footerReservation))
    end
    self.launcherInset = {left = left, top = top, right = right, bottom = bottom}
    self:positionLauncher()
    self:drawGrid(w, h)
    self:updateSelection()
end

function UI:positionLauncher()
    if self.launcherDragging then return end
    local w, h = self:viewport()
    local inset = self.launcherInset or {left = 8, top = 8, right = 8, bottom = 8}
    local x = math.max(inset.left, math.min(w - inset.right - 54, (self.app.preferences.launcherX or .02) * (w - 54)))
    local y = math.max(inset.top, math.min(h - inset.bottom - 48, (self.app.preferences.launcherY or .35) * (h - 48)))
    self.launcher.Position = UDim2.fromOffset(x, y)
end

function UI:drawGrid(w, h)
    local spacing = math.max(4, math.min(128, self.app.preferences.gridSize or 24))
    -- At most 160 lines even on very large displays; no frame-time drawing work.
    spacing = math.max(spacing, math.max(w, h) / 80)
    local signature = table.concat({math.floor(w), math.floor(h), spacing}, ":")
    self.gridLayer.Visible = self.visible and self.app.preferences.grid ~= false
    if signature == self.gridSignature then return end
    self.gridSignature = signature
    for _, o in ipairs(self.gridObjects) do o:Destroy() end
    self.gridObjects = {}
    for x = spacing, w, spacing do
        table.insert(self.gridObjects, make("Frame", {BackgroundColor3 = C.cyan, BackgroundTransparency = .93,
            BorderSizePixel = 0, Position = UDim2.fromOffset(x, 0), Size = UDim2.new(0, 1, 1, 0), ZIndex = 3}, self.gridLayer))
    end
    for y = spacing, h, spacing do
        table.insert(self.gridObjects, make("Frame", {BackgroundColor3 = C.cyan, BackgroundTransparency = .93,
            BorderSizePixel = 0, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 1), ZIndex = 3}, self.gridLayer))
    end
end

function UI:pointInPanel(x, y)
    if self.modalGui then return true end
    return (self.visible and inside(self.panel, x, y)) or inside(self.launcher, x, y)
end

function UI:setBox(rect)
    self.box.Visible = rect ~= nil and self.visible
    if rect then
        self.box.Position = UDim2.fromOffset(rect.x, rect.y)
        self.box.Size = UDim2.fromOffset(rect.w, rect.h)
    end
end

function UI:setGuides(guides)
    for _, object in ipairs(self.guideObjects) do object:Destroy() end
    self.guideObjects = {}
    if not self.visible then return end
    local w, h = self:viewport()
    for i, guide in ipairs(guides or {}) do
        if i > 6 then break end
        local axis, coordinate = guide.axis, guide.value or guide.position
        if axis and coordinate then
            table.insert(self.guideObjects, make("Frame", {BackgroundColor3 = C.warning, BackgroundTransparency = .15,
                BorderSizePixel = 0, Position = UDim2.fromOffset(axis == "x" and coordinate or 0, axis == "y" and coordinate or 0),
                Size = UDim2.fromOffset(axis == "x" and 1 or w, axis == "y" and 1 or h), ZIndex = 7}, self.overlay))
        end
    end
end

function UI:updateSelection()
    if self.dead then return end
    local rects = self.app:getRects()
    local bounds = Geometry.bounds(rects or {})
    self.selectionBounds.Visible = self.visible and bounds ~= nil
    for _, handle in ipairs(self.handles) do handle.gui.Visible = self.visible and bounds ~= nil end
    if bounds then
        self.selectionBounds.Position = UDim2.fromOffset(bounds.x, bounds.y)
        self.selectionBounds.Size = UDim2.fromOffset(bounds.w, bounds.h)
    end
    for i, rect in ipairs(rects or {}) do
        local b = self.individual[i]
        if not b then
            b = make("Frame", {Name = "ElementBoundary", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5}, self.overlay)
            outline(b, C.cyan); self.individual[i] = b
        end
        b.Visible = self.visible and #rects > 1
        b.Position, b.Size = UDim2.fromOffset(rect.x, rect.y), UDim2.fromOffset(rect.w, rect.h)
    end
    for i = #(rects or {}) + 1, #self.individual do self.individual[i].Visible = false end
    for name, box in pairs(self.fields or {}) do
        if not box:IsFocused() then
            local map = bounds and {X = bounds.x, Y = bounds.y, W = bounds.w, H = bounds.h}
            box.Text = map and numberText(map[name]) or ""
        end
    end
    if bounds then
        local maxSize = math.max(bounds.w, bounds.h)
        self.slider.Text = "Size " .. numberText(maxSize) .. " px"
        local fraction = math.max(0, math.min(1, (maxSize - 16) / 496))
        self.sliderFill.Size = UDim2.new(fraction, -16 * fraction, 0, 2)
    else self.slider.Text = "Select to resize"; self.sliderFill.Size = UDim2.fromOffset(0, 2) end
    local record = self.app.discovery:get(self.app.selection[1])
    if record and #self.app.selection == 1 then
        local path = {}
        for _, segment in ipairs(record.descriptor.path or {}) do table.insert(path, segment.name) end
        self.selectionName.Text = record.object.Name .. " · " .. record.object.ClassName
        self.selectionDetail.Text = table.concat(path, " / ") .. "\n" .. (record.reason or "Accessible visual properties; functional touch region is unverified.")
        self.selectionDetail.TextColor3 = record.editable and C.muted or C.warning
        if not self.rotation:IsFocused() then self.rotation.Text = numberText(record.object.Rotation) end
        if not self.transparency:IsFocused() then self.transparency.Text = numberText(record.object.BackgroundTransparency) end
    elseif #self.app.selection > 1 then
        self.selectionName.Text = tostring(#self.app.selection) .. " selected · " .. tostring(#(rects or {})) .. " transform roots"
        self.selectionDetail.Text = "Nested descendants are transformed through their selected parent. Pinch or drag handles to resize."
    else
        self.selectionName.Text = "Select an element in the game or the list below."
        self.selectionDetail.Text = "Editing gestures may not isolate every game input. Exit editing to use the HUD."
    end
    local visualEditable = record ~= nil and #self.app.selection == 1 and record.editable
    self.rotation.Visible, self.transparency.Visible = visualEditable, visualEditable
    self.rotation.TextEditable, self.transparency.TextEditable = visualEditable, visualEditable
    self.visualHint.Text = visualEditable and "Rotation (degrees), then background transparency (0–1). Visual properties do not verify hit regions."
        or "Select one compatible element to edit visual properties. Unsupported targets remain unchanged."
    self.experimental.Visible = record ~= nil and record.experimental == true
end

function UI:clearDynamic(container, connections)
    for _, c in ipairs(connections) do c:Disconnect() end
    for _, child in ipairs(container:GetChildren()) do if not child:IsA("UIListLayout") then child:Destroy() end end
end

function UI:refreshElements()
    local records = self.app.discovery:list()
    local search = self.search.Text:lower()
    local pieces = {search, tostring(self.onlyEditable)}
    for _, r in ipairs(records) do table.insert(pieces, r.key .. ":" .. tostring(r.editable) .. ":" .. tostring(r.experimental)) end
    local signature = table.concat(pieces, "\n")
    if signature ~= self.elementSignature then
        self.elementSignature = signature
        self:clearDynamic(self.elementList, self.elementConnections); self.elementConnections = {}; self.elementRows = {}
        local count = 0
        for _, r in ipairs(records) do
            local path = {}
            for _, part in ipairs(r.descriptor.path or {}) do table.insert(path, part.name) end
            local searchText = table.concat(path, "/") .. " " .. r.object.ClassName
            if (not self.onlyEditable or r.editable) and (search == "" or searchText:lower():find(search, 1, true)) then
                count = count + 1
                if count > 200 then break end
                local title = string.rep("  ", math.min(5, math.max(0, #path - 2))) .. r.object.Name .. " · " .. r.object.ClassName
                if not r.editable then title = "⚠ " .. title end
                local key = r.key
                local b = self:button(self.elementList, title, function()
                    self.app:select(key, self.app.preferences.multiSelect)
                end, nil, nil, nil, self.elementConnections)
                b.TextXAlignment = Enum.TextXAlignment.Left
                make("UIPadding", {PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 6)}, b)
                self.elementRows[key] = b
            end
        end
        if count == 0 then label(self.elementList, "No visible accessible matches. Try another search or wait for the game HUD.", 54, 12) end
        if count > 200 then label(self.elementList, "Showing the first 200 matches. Search to narrow the list.", 44, 11) end
    end
    for key, row in pairs(self.elementRows) do
        row.TextColor3 = selected(self.app.selection, key) and C.cyan or C.text
        row.BackgroundColor3 = selected(self.app.selection, key) and Color3.fromRGB(29, 63, 73) or C.raised
    end
    local unresolved = self.app.unmatched or self.app.transform:matches(self.app.layout or {})
    local missingPieces = {}
    for _, missing in ipairs(unresolved or {}) do
        table.insert(missingPieces, type(missing) == "table" and tostring(missing.key or missing.id or "") or tostring(missing))
    end
    local missingSignature = table.concat(missingPieces, "\n") .. tostring(self.remapKey)
    if missingSignature ~= self.missingSignature then
        self.missingSignature = missingSignature
        self:clearDynamic(self.missingList, self.missingConnections); self.missingConnections = {}
        for i, key in ipairs(missingPieces) do
            if i > 100 then break end
            local chosenKey = key
            self:button(self.missingList, (self.remapKey == key and "✓ " or "") .. "Missing: " .. key:sub(-70), function()
                self.remapKey = chosenKey; self.missingSignature = nil; self:refreshElements()
            end, nil, nil, nil, self.missingConnections)
        end
    end
    self.remapLabel.Visible = #missingPieces > 0
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
    self.draftSection.Visible = self.app.draft ~= nil and self.app.draft ~= false
end

function UI:refresh()
    if self.dead then return end
    self:refreshToggles()
    self.multiButton.TextColor3 = self.app.preferences.multiSelect and C.cyan or C.muted
    self.boxButton.TextColor3 = self.app.preferences.boxSelect and C.cyan or C.muted
    self.launcher.Visible = self.app.preferences.launcherHidden ~= true
    self:positionLauncher()
    self:drawGrid(self:viewport())
    self:updateSelection()
    if self.tab == "Elements" then self:refreshElements() end
    if self.tab == "Groups" then self:refreshGroups() end
    if self.tab == "Profiles" then self:refreshProfiles() end
    local caps = {}
    for _, name in ipairs({"storage", "clipboard", "network", "input"}) do
        local value = self.app.capabilities[name] or {}
        table.insert(caps, name .. ": " .. tostring(value.status or "Unsupported") .. "\n" .. tostring(value.detail or ""))
    end
    self.capabilityLabel.Text = table.concat(caps, "\n")
    self:status(self.app.statusMessage or "Ready")
end

function UI:status(message)
    if self.dead then return end
    local text = (self.app.dirty and "● Unsaved  ·  " or "") .. tostring(message)
    self.statusLabel.Text = text
    if self.tiny then self.title.Text = text:sub(1, 110); self.title.TextSize = 10
    else self.title.Text = "HEAVENLY AXIS"; self.title.TextSize = 16 end
end

function UI:setVisible(visible)
    self.visible = visible == true
    self.panel.Visible, self.canvas.Visible, self.overlay.Visible = self.visible, self.visible, self.visible
    self.gridLayer.Visible = self.visible and self.app.preferences.grid ~= false
    if not self.visible then self:closeModal(); self:setGuides(); self:setBox() end
    self:layout(); self:refresh()
end

function UI:destroy()
    if self.dead then return end
    self.dead = true
    self:closeModal()
    for _, list in ipairs({self.connections, self.elementConnections, self.profileConnections, self.groupConnections, self.missingConnections}) do
        for _, c in ipairs(list) do c:Disconnect() end
    end
    if self.gui then self.gui:Destroy() end
end

return UI
