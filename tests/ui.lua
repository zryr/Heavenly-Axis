-- Structural Roblox GUI mocks. These checks exercise UI state and sizing only;
-- they do not establish Roblox rendering, touch interception or device support.
local checks, activeConnections, destroyed = 0, 0, 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local function signal()
    local listeners = {}
    local s = {}
    function s:Connect(callback)
        local entry = {callback = callback, connected = true}
        listeners[#listeners + 1] = entry; activeConnections = activeConnections + 1
        return {Disconnect = function()
            if entry.connected then entry.connected = false; activeConnections = activeConnections - 1 end
        end}
    end
    function s:Fire(...)
        local snapshot = {}; for i, entry in ipairs(listeners) do snapshot[i] = entry end
        for _, entry in ipairs(snapshot) do if entry.connected then entry.callback(...) end end
    end
    function s:Destroy()
        for _, entry in ipairs(listeners) do
            if entry.connected then entry.connected = false; activeConnections = activeConnections - 1 end
        end
    end
    return s
end
local function vec(x, y) return {X = x or 0, Y = y or 0} end
Vector2 = {new = vec}
Color3 = {new = function(r, g, b) return {R = r, G = g, B = b} end,
    fromRGB = function(r, g, b) return {R = r / 255, G = g / 255, B = b / 255} end}
UDim = {new = function(scale, offset) return {Scale = scale or 0, Offset = offset or 0} end}
UDim2 = {new = function(xs, xo, ys, yo) return {X = UDim.new(xs, xo), Y = UDim.new(ys, yo)} end}
UDim2.fromOffset = function(x, y) return UDim2.new(0, x, 0, y) end
UDim2.fromScale = function(x, y) return UDim2.new(x, 0, y, 0) end
Enum = setmetatable({}, {__index = function(t, name)
    local group = setmetatable({}, {__index = function(g, key) rawset(g, key, name .. "." .. key); return rawget(g, key) end})
    rawset(t, name, group); return group
end})
local view, screenOrigin = vec(800, 600), vec(-9, -23)
local methods = {}
local eventNames = {Activated = true, FocusLost = true, InputBegan = true, InputEnded = true}
local guiClasses = {Frame = true, TextButton = true, TextLabel = true, TextBox = true, ScrollingFrame = true, ImageLabel = true}
local function absSize(object)
    if object.ClassName == "ScreenGui" or object.ClassName == "PlayerGui" then return view end
    local parentSize = object.Parent and object.Parent.AbsoluteSize or view
    local size = object.Size
    local result = vec(parentSize.X * size.X.Scale + size.X.Offset, parentSize.Y * size.Y.Scale + size.Y.Offset)
    for _, child in ipairs(object:GetChildren()) do
        if child.ClassName == "UISizeConstraint" then
            if child.MinSize then result.X, result.Y = math.max(result.X, child.MinSize.X), math.max(result.Y, child.MinSize.Y) end
            if child.MaxSize then result.X, result.Y = math.min(result.X, child.MaxSize.X), math.min(result.Y, child.MaxSize.Y) end
        end
    end
    return result
end
local mt = {}
function mt:__index(key)
    if methods[key] then return methods[key] end
    if key == "AbsoluteSize" then return absSize(self) end
    if key == "AbsoluteContentSize" and self.ClassName == "UIListLayout" then
        local width, height, count = 0, 0, 0
        for _, child in ipairs(self.Parent:GetChildren()) do
            if child:IsA("GuiObject") and child.Visible then
                local size = child.AbsoluteSize
                width, height, count = math.max(width, size.X), height + size.Y, count + 1
            end
        end
        return vec(width, height + math.max(0, count - 1) * self.Padding.Offset)
    end
    if key == "AbsolutePosition" then
        if self.ClassName == "ScreenGui" then return screenOrigin end
        if self.ClassName == "PlayerGui" then return vec() end
        local parentSize = self.Parent and self.Parent.AbsoluteSize or view
        local origin = self.Parent and self.Parent.AbsolutePosition or vec()
        local pos, size = self.Position, self.AbsoluteSize
        local anchor = self.AnchorPoint
        return vec(origin.X + parentSize.X * pos.X.Scale + pos.X.Offset - size.X * anchor.X,
            origin.Y + parentSize.Y * pos.Y.Scale + pos.Y.Offset - size.Y * anchor.Y)
    end
    if eventNames[key] then
        local events = rawget(self, "_events")
        events[key] = events[key] or signal(); return events[key]
    end
    return rawget(self, "_props")[key]
end
function mt:__newindex(key, value)
    local props = rawget(self, "_props")
    if key == "Parent" then
        local previous = props.Parent
        if previous then
            local children = rawget(previous, "_children")
            for i, child in ipairs(children) do if child == self then table.remove(children, i); break end end
        end
        props.Parent = value
        if value then table.insert(rawget(value, "_children"), self) end
        return
    end
    if props[key] == value then return end
    props[key] = value
    local changed = rawget(self, "_changes")[key]
    if changed then changed:Fire() end
end
function methods:GetChildren()
    local result = {}; for i, child in ipairs(rawget(self, "_children")) do result[i] = child end
    return result
end
function methods:GetDescendants()
    local result = {}
    local function append(object)
        for _, child in ipairs(object:GetChildren()) do result[#result + 1] = child; append(child) end
    end
    append(self); return result
end
function methods:GetPropertyChangedSignal(key)
    local changes = rawget(self, "_changes")
    changes[key] = changes[key] or signal(); return changes[key]
end
function methods:IsA(class) return class == self.ClassName or class == "GuiObject" and guiClasses[self.ClassName] or class == "Instance" end
function methods:IsFocused() return self.Focused == true end
function methods:CaptureFocus() self.Focused = true end
function methods:ReleaseFocus() self.Focused = false end
function methods:Destroy()
    if self.Destroyed then return end
    self.Destroyed = true; destroyed = destroyed + 1
    for _, child in ipairs(self:GetChildren()) do child:Destroy() end
    for _, collection in ipairs({rawget(self, "_changes"), rawget(self, "_events")}) do
        for _, s in pairs(collection) do s:Destroy() end
    end
    self.Parent = nil
end
Instance = {new = function(class)
    return setmetatable({_props = {ClassName = class, Name = class, Size = UDim2.new(), Position = UDim2.new(),
        AnchorPoint = vec(), CanvasPosition = vec(), Visible = true, ZIndex = 1, Text = "", BackgroundTransparency = 0, Rotation = 0},
        _children = {}, _changes = {}, _events = {}}, mt)
end}
local Geometry = require("Geometry")
local UI = require("UI")
local Coordinates = require("Coordinates")
local Layout = require("UILayout")
local playerGui = Instance.new("PlayerGui")
local camera = {ViewportSize = view, changed = signal()}
function camera:GetPropertyChangedSignal() return self.changed end
local safeLeft, safeRight, safeTop, safeBottom = 12, 16, 23, 10
local function insetArea(_, inset)
    return {Min = vec(safeLeft, inset == Enum.ScreenInsets.DeviceSafeInsets and -safeTop or 0),
        Max = vec(view.X - safeRight, view.Y - safeTop - safeBottom)}
end
local services = {UserInputService = {TouchEnabled = true}, Workspace = {CurrentCamera = camera},
    GuiService = {GetGuiInset = function() return vec(0, safeTop), vec(0, safeBottom) end, GetInsetArea = insetArea}}
local target = Instance.new("TextButton")
target.Name = "Jump Mock"; target.Size = UDim2.fromOffset(100, 100); target.Position = UDim2.fromOffset(50, 162); target.Parent = playerGui
local second = Instance.new("TextButton")
second.Name = "Second"; second.Size = UDim2.fromOffset(30, 40); second.Position = UDim2.fromOffset(320, 154); second.Parent = playerGui
local descriptor = {path = {{name = "HUD", class = "ScreenGui"}, {name = "Jump Mock", class = "TextButton"}}, class = "TextButton"}
local record = {key = "a", descriptor = descriptor, object = target, editable = true, builtin = "JumpButton"}
local record2 = {key = "b", descriptor = {path = {{name = "Second", class = "TextButton"}}}, object = second, editable = true}
local records, listCalls = {record, record2}, 0
local app = {version = "3.1.0", selection = {}, preferences = {grid = true, snapping = false, launcherX = .4, launcherY = .3},
    capabilities = {}, groups = {}, logs = {}, dirty = false, statusMessage = "Ready"}
function app:log(message) self.logs[#self.logs + 1] = message end
function app:status(message) self.statusMessage = message end
function app:getRects(editableOnly)
    local result, keys = {}, {}
    for _, key in ipairs(self.selection) do
        local item = self.discovery:get(key)
        if item and (not editableOnly or item.editable) then
            result[#result + 1] = Coordinates.rect(item.object)
            keys[#keys + 1] = key
        end
    end
    return result, keys
end
function app:currentBounds(editableOnly) return Geometry.bounds(self:getRects(editableOnly)) end
function app:sizeInfo(bounds, rects, keys)
    bounds = bounds or self:currentBounds(true)
    if not bounds then return end
    local size = self.preferences.equalSize and #self.selection > 1 and Coordinates.rect(target) or bounds
    return {scale = size.w, minimum = 16, maximum = 200, original = #self.selection == 1, size = size}
end
function app:getState() return {layout = {}} end
function app:select(key) self.selection = {key}; if self.ui then self.ui:selectionChanged() end end
function app:selectMany(keys) self.selection = keys; if self.ui then self.ui:selectionChanged() end end
function app:clearSelection() self:selectMany({}) end
function app:setPreference(key, value) self.preferences[key] = value end
function app:geometry(mode, value) self.lastGeometry = {mode = mode, value = value} end
function app:resize(w, h) self.lastResize = {w = w, h = h} end
function app:setSizePercent(percent) self.lastPercent = percent end
function app:setLauncherPosition(x, y) self.preferences.launcherX, self.preferences.launcherY = x, y end
function app:profile(...) self.lastProfile = {...} end
function app:group(...) self.lastGroup = {...} end
app.discovery = {revision = 1, list = function() listCalls = listCalls + 1; return records end,
    get = function(_, key) for _, item in ipairs(records) do if item.key == key then return item end end end}
app.transform = {matches = function() return {} end}
app.profiles = {list = function() return {} end, active = function() return nil end}

local function visibleHandles(ui)
    local count = 0
    for _, handle in ipairs(ui.handles) do if handle.gui.Visible then count = count + 1 end end
    return count
end
local function buttonByText(root, text)
    for _, item in ipairs(root:GetDescendants()) do
        if item:IsA("TextButton") and item.Text == text then return item end
    end
end

local ui = UI.new(app, playerGui, services)
app.ui = ui
check(ui.gui.Name == "HeavenlyAxis" and ui.gui.ResetOnSpawn == false and ui.gui.ScreenInsets == Enum.ScreenInsets.None,
    "persistent editor requests a full-coordinate overlay")
check(not ui.visible and not ui.canvas.Visible and ui.launcher.Visible, "editor starts closed with only the launcher")
check(listCalls == 0, "closed editor does not build hidden browsing lists")
ui:setVisible(true)
check(ui.visible and ui.canvas.Visible and ui.toolbar.Visible and not ui.panel.Visible and not ui.workspace.Visible,
    "opening shows the canvas toolbar before a selection")
check(not ui.launcher.Visible, "launcher releases gameplay space while editing")
check(ui.gridLayer.Visible and #ui.gridObjects <= 162, "enabled grid uses bounded line count")
check(not app.preferences.snapping, "grid does not force snapping")

app:select("a")
check(ui.panel.Visible and ui.quickBody.Visible and not ui.workspace.Visible, "compatible selection opens contextual Quick Edit")
check(ui.quickName.Text == "Jump Mock" and ui.percent.Text == "100%", "visual size percentage matches selected element")
check(ui.selectionBounds.AbsolutePosition.X == 50 and ui.selectionBounds.AbsolutePosition.Y == 162,
    "canonical selection placement offsets the full-screen root origin")
check(ui.selectionBounds.Position.X.Offset == 59 and ui.selectionBounds.Position.Y.Offset == 185,
    "canonical-to-local conversion is applied at the overlay boundary")
check(visibleHandles(ui) == 1, "touch layout exposes one resize handle")
local grip = Coordinates.rect(ui.touchHandle.gui)
check(grip.w == 44 and not Layout.intersects(grip, Coordinates.rect(target)), "touch handle has a 44-unit region outside the movement target")
check(ui:pointInPanel(ui.panel.AbsolutePosition.X + 1, ui.panel.AbsolutePosition.Y + 1), "inspector blocks canvas under it")
check(not ui:pointInPanel(760, 490), "canvas outside editor controls remains available")
local oldX, oldY = ui:inspectorPosition()
ui:moveInspector(760, 560)
local movedX, movedY = ui:inspectorPosition()
check(oldX ~= movedX or oldY ~= movedY, "moving the inspector exposes controls behind it")
ui:finishInspectorMove(true)
local restoredX, restoredY = ui:inspectorPosition()
check(restoredX == oldX and restoredY == oldY, "cancelled inspector drag restores its position")
ui:setCollapsed(true)
check(not ui.panel.Visible and ui.selectionBounds.Visible, "hiding Quick Edit leaves selection editing active")
ui.editButton.Activated:Fire()
check(ui.panel.Visible and not ui.workspace.Visible, "Edit restores quick controls after hiding")

for _, dims in ipairs({{1536, 695}, {960, 440}, {640, 360}, {932, 430}, {393, 852}, {360, 640},
    {1024, 768}, {1920, 1080}, {320, 240}, {240, 320}}) do
    view.X, view.Y = dims[1], dims[2]
    ui:layout()
    local panel, toolbar = Coordinates.rect(ui.panel), Coordinates.rect(ui.toolbar)
    local safe = ui.safeArea
    check(panel.x >= safe.x and panel.y >= safe.y and panel.x + panel.w <= safe.x + safe.w
        and panel.y + panel.h <= safe.y + safe.h, "inspector remains inside simulated safe area")
    check(not Layout.intersects(panel, toolbar), "quick editor and toolbar remain distinct")
    if view.X >= 640 and view.X > view.Y then
        check(panel.w <= 262 and panel.h <= 202 and (panel.w * panel.h + toolbar.w * toolbar.h) / (view.X * view.Y) < .35,
            "landscape chrome preserves at least 65 percent of the canvas")
        check(ui.quickBody.AbsoluteSize.Y >= 140, "landscape quick tools fit in initial viewport")
    end
    ui:setTab("Elements")
    check(ui.pages.Elements.AbsoluteSize.Y >= 24 and ui.workspace.Visible, "explicit workspace keeps a usable content viewport")
    ui:setWorkspace(false)
end
view.X, view.Y = 800, 600
ui:layout()
services.UserInputService.PreferredInput = Enum.PreferredInput.KeyboardAndMouse
ui:layout()
check(visibleHandles(ui) == 8 and ui.panel.AbsoluteSize.X <= 286, "hybrid keyboard input uses desktop handles and compact inspector")
services.UserInputService.PreferredInput = Enum.PreferredInput.Touch
ui:layout()
check(visibleHandles(ui) == 1, "hybrid touch input restores exterior handle")

ui.percent.Text = "124%"
ui.percent.FocusLost:Fire(false)
check(app.lastPercent == 124, "quick size commits the numeric percentage")
ui.percent.Focused = true; ui.percent.Text = "12"
services.UserInputService.OnScreenKeyboardVisible, services.UserInputService.OnScreenKeyboardSize = true, vec(640, 440)
ui:layout()
check(not ui.toolbar.Visible and ui.quickBody.CanvasPosition.Y == 48 and ui.percent.Text == "12", "keyboard layout keeps the percentage field and typed draft available")
ui.percent.Focused = false; services.UserInputService.OnScreenKeyboardVisible = false; ui:layout()
check(ui.toolbar.Visible and ui.quickBody.CanvasPosition.Y == 0, "closing the keyboard restores the canvas layout")

ui:setTab("Advanced")
check(ui.fields.X.Text == "50" and ui.fields.Y.Text == "162" and ui.fields.W.Text == "100", "advanced inspector reads canonical selection geometry")
ui.fields.X.Text = "120"; ui.fields.X.FocusLost:Fire(false)
check(app.lastGeometry and app.lastGeometry.mode == "position" and app.lastGeometry.value.x == 120, "numeric position uses the app operation")
ui.fields.W.Text = "125"; ui.fields.W.FocusLost:Fire(false)
check(app.lastResize.w == 125 and app.lastResize.h == 125, "width editing preserves aspect ratio by default")
app.preferences.aspectLock = false
ui.fields.W.Text = "130"; ui.fields.W.FocusLost:Fire(false)
check(app.lastResize.w == 130 and app.lastResize.h == 100, "advanced width can change independently")
ui.fields.X.Focused = true; ui.fields.X.Text = "1234"; ui:updateSelection()
check(ui.fields.X.Text == "1234", "geometry updates preserve a focused draft")
ui.fields.X.Focused = false; ui.fields.X.Text = "nan"; ui.fields.X.FocusLost:Fire(false)
check(app.statusMessage == "Enter a finite numeric value.", "invalid numeric text receives feedback")
app.preferences.equalSize = true
app:selectMany({"a", "b"})
check(ui.fields.W.Text == "100" and ui.precisionHeading.Text:find("largest member"), "group member mode labels and displays the size basis")
ui.fields.H.Text = "120"; ui.fields.H.FocusLost:Fire(false)
check(app.lastResize.w == 100 and app.lastResize.h == 120, "independent member change preserves the other member axis")
app:select("a")

ui:setTab("Elements")
local elementsBody = ui.pageBodies.Elements
local previousOrder = 0
for _, child in ipairs(elementsBody:GetChildren()) do
    if child:IsA("GuiObject") then
        check(child.LayoutOrder > previousOrder and child.ZIndex > ui.workspace.ZIndex, "workspace content has explicit order and renders above its surface")
        previousOrder = child.LayoutOrder
    end
end
local contentLayout
for _, child in ipairs(elementsBody:GetChildren()) do if child:IsA("UIListLayout") then contentLayout = child end end
contentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Fire()
check(ui.pages.Elements.CanvasSize.Y.Offset > 175, "list layout drives the native scrollable viewport")
local rows, connections = listCalls, activeConnections
ui:refreshElements(); ui:refreshElements()
check(listCalls == rows and activeConnections == connections, "unchanged element revision avoids enumeration and callback churn")
ui:setOverlaps({record, record2})
check(ui.overlapList.Visible and #ui.overlapConnections == 2, "touch overlap chooses from explicit candidates")

records = {}; app.discovery.revision = 2; ui:refreshElements()
check(#ui.elementConnections == 0, "removed browser rows disconnect completely")
records = {record, record2}
for i = 1, 70 do
    local copy = {key = tostring(i), descriptor = {path = {{name = "Test " .. i}}}, object = second, editable = true}
    records[#records + 1] = copy
end
app.discovery.revision = 3; ui:refreshElements()
check(#ui.elementConnections == 28 and ui.pager.Visible, "large browser caps active rows through pagination")
ui.search.Text = "Test 70"
check(#ui.elementConnections == 1 and not ui.pager.Visible and ui.elementRows["70"], "search reaches results beyond the first result page")

app:clearSelection()
check(not ui.selectionBounds.Visible and visibleHandles(ui) == 0, "clearing selection removes geometry and active handles")
record.editable = false
ui:setWorkspace(false)
app:select("a")
check(ui.panel.AbsoluteSize.Y <= 56 and not ui.quickBody.Visible and visibleHandles(ui) == 0,
    "unsupported selection remains inspectable without resize affordances")
record.editable = true

local box = ui:modal("Import", "Validate before preview", "{}", "Preview", function(value) return value == "{}" end)
check(ui.modalOpen and ui:pointInPanel(0, 0), "modal blocks all canvas input")
check(box.Text == "{}", "portable text remains available")
ui:closeModal()
local result
ui:confirmDone(function() result = "save" end, function() result = "discard" end)
buttonByText(ui.modalGui, "Continue editing").Activated:Fire()
check(not ui.modalOpen and result == nil, "continuing editing dismisses the prompt without mutating the app")
ui:confirmDone(function() result = "save" end, function() result = "discard" end)
buttonByText(ui.modalGui, "Save").Activated:Fire()
check(not ui.modalOpen and result == "save", "Done offers an explicit checkpoint action")
ui:confirmDone(function() result = "save" end, function() result = "discard" end)
buttonByText(ui.modalGui, "Discard").Activated:Fire()
check(not ui.modalOpen and result == "discard", "discard is explicit")
ui:setTab("Profiles")
app.draftBlocked = true; ui:refreshProfiles()
check(ui.draftSection.Visible and ui.previewDraft.Interactable == false,
    "recovery exposes discard for a stale draft without offering preview")

ui:setVisible(false)
check(not ui.modalOpen and not ui.overlay.Visible and #ui.selectionConnections == 0, "closing releases selection events and editing surfaces")
app.preferences.launcherHidden = true; ui:refresh()
check(not ui.launcher.Visible, "launcher can be hidden without destroying the editor")
app.preferences.launcherHidden = false; ui:refresh()
ui:moveLauncher(700, 345); ui:finishLauncherMove(false)
local launcher = Coordinates.rect(ui.launcher)
check(app.preferences.launcherX == 1 and launcher.x + launcher.w == ui.safeArea.x + ui.safeArea.w - 8, "launcher docks inside the nearest safe edge")
check(#app.logs == 0, "GUI callbacks completed without swallowed errors")
local beforeDestroy = destroyed
ui:destroy(); ui:destroy()
check(ui.gui.Destroyed and destroyed > beforeDestroy, "destroy tears down GUI once")
check(activeConnections == 0, "destroy releases every UI connection")
target:Destroy()
second:Destroy()

return checks
