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
local view = vec(800, 600)
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
    if key == "AbsolutePosition" then
        if self.ClassName == "ScreenGui" or self.ClassName == "PlayerGui" then return vec() end
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
        AnchorPoint = vec(), Visible = true, ZIndex = 1, Text = "", BackgroundTransparency = 0, Rotation = 0},
        _children = {}, _changes = {}, _events = {}}, mt)
end}
local Geometry = require("Geometry")
local UI = require("UI")
local playerGui = Instance.new("PlayerGui")
local camera = {ViewportSize = view, changed = signal()}
function camera:GetPropertyChangedSignal() return self.changed end
local services = {UserInputService = {TouchEnabled = true}, Workspace = {CurrentCamera = camera},
    GuiService = {GetGuiInset = function() return vec(0, 24), vec() end}}
local target = Instance.new("TextButton")
target.Name = "Jump Mock"; target.Size = UDim2.fromOffset(100, 100); target.Position = UDim2.fromOffset(50, 60); target.Parent = playerGui
local descriptor = {path = {{name = "HUD", class = "ScreenGui"}, {name = "Jump Mock", class = "TextButton"}}, class = "TextButton"}
local record = {key = "a", descriptor = descriptor, object = target, editable = true}
local records = {record}
local app = {version = "3.0.0", selection = {}, preferences = {grid = true, snapping = false, launcherX = .4, launcherY = .3},
    capabilities = {}, groups = {}, logs = {}, dirty = false, statusMessage = "Ready"}
function app:log(message) self.logs[#self.logs + 1] = message end
function app:status(message) self.statusMessage = message end
function app:getRects()
    local result = {}
    if self.selection[1] then local p, s = target.AbsolutePosition, target.AbsoluteSize; result[1] = {x = p.X, y = p.Y, w = s.X, h = s.Y} end
    return result, self.selection
end
function app:currentBounds() return Geometry.bounds(self:getRects()) end
function app:getState() return {layout = {}} end
function app:select(key) self.selection = {key} end
function app:selectMany(keys) self.selection = keys end
function app:clearSelection() self.selection = {} end
function app:setPreference(key, value) self.preferences[key] = value end
function app:geometry(mode, value) self.lastGeometry = {mode = mode, value = value} end
function app:resize(w, h) self.lastResize = {w = w, h = h} end
function app:profile(...) self.lastProfile = {...} end
function app:group(...) self.lastGroup = {...} end
app.discovery = {list = function() return records end, get = function(_, key) if key == "a" then return record end end}
app.transform = {matches = function() return {} end}
app.profiles = {list = function() return {} end, active = function() return nil end}
local ui = UI.new(app, playerGui, services)
check(ui.gui.Name == "HeavenlyAxis" and ui.gui.ResetOnSpawn == false and ui.gui.IgnoreGuiInset, "editor creates branded persistent physical-coordinate overlay")
check(#ui.handles == 8, "all corner and edge handles created")
check(not ui.visible and not ui.canvas.Visible, "editor starts hidden until explicitly opened")
ui:setVisible(true)
check(ui.visible and ui.canvas.Visible and ui.panel.Visible, "editing enables shield and panel")
check(ui.gridLayer.Visible, "grid enabled by default")
check(not app.preferences.snapping, "grid does not force snapping")
check(ui.pages.Elements.AbsoluteSize.Y > 0, "mobile scrolling inspector has positive viewport")
check(#ui.gridObjects <= 162, "grid rendering has bounded object count")

for _, dimensions in ipairs({{800, 600}, {360, 800}, {640, 360}, {320, 240}, {240, 320}}) do
    view.X, view.Y = dimensions[1], dimensions[2]
    camera.ViewportSize = view
    ui:layout()
    check(ui.panel.AbsoluteSize.X > 0 and ui.panel.AbsoluteSize.Y > 0, "panel remains usable after viewport change")
    check(ui.pages.Elements.AbsoluteSize.Y >= 24, "scrolling body retains usable viewport on small screens " .. view.X .. "x" .. view.Y .. " body=" .. ui.pages.Elements.AbsoluteSize.Y)
    local pos, size = ui.panel.AbsolutePosition, ui.panel.AbsoluteSize
    check(pos.X >= 0 and pos.Y >= 0 and pos.X + size.X <= view.X and pos.Y + size.Y <= view.Y,
        "panel stays inside display bounds")
end
view.X, view.Y = 800, 600; ui:layout()
app.selection = {"a"}; ui:updateSelection()
check(ui.fields.X.Text == "50" and ui.fields.Y.Text == "60" and ui.fields.W.Text == "100", "numeric inspector syncs current selection")
check(ui.selectionBounds.Visible and ui.selectionBounds.AbsoluteSize.X == 100, "selection boundary follows target geometry")
ui.fields.X.Text = "120"; ui.fields.X.FocusLost:Fire(false)
check(app.lastGeometry and app.lastGeometry.mode == "position" and app.lastGeometry.value.x == 120, "numeric position changes use transactional app API")
ui.fields.W.Text = "125"; ui.fields.W.FocusLost:Fire(false)
check(app.lastResize and app.lastResize.w == 125 and app.lastResize.h == 125, "numeric width preserves aspect ratio by default")
app.preferences.aspectLock = false
ui.fields.W.Text = "130"; ui.fields.W.FocusLost:Fire(false)
check(app.lastResize and app.lastResize.w == 130 and app.lastResize.h == 100, "advanced independent width remains available when aspect lock disabled")
ui.fields.X.Focused = true; ui.fields.X.Text = "1234"; ui:updateSelection()
check(ui.fields.X.Text == "1234", "refresh does not replace a focused numeric draft")
ui.fields.X.Focused = false
ui.fields.X.Text = "nan"; ui.fields.X.FocusLost:Fire(false)
check(app.statusMessage == "Enter a finite numeric value.", "invalid numeric text reports failure")

local count = activeConnections
ui:refreshElements(); ui:refreshElements()
check(activeConnections == count, "unchanged element list does not create additional connections")
records = {}; ui.elementSignature = nil; ui:refreshElements()
check(#ui.elementConnections == 0, "removed list rows release input connections")
records = {record}; ui.elementSignature = nil; ui:refreshElements()
check(#ui.elementConnections == 1, "new visible row receives one input connection")
app.selection = {}; ui:updateSelection()
check(not ui.selectionBounds.Visible, "cleared selection hides bounds")
for _, handle in ipairs(ui.handles) do check(not handle.gui.Visible, "cleared selection hides physical handles") end

local box = ui:modal("Import", "Validate before preview", "{}", "Preview", function(value) return value == "{}" end)
check(ui.modalOpen and ui.modalGui and ui:pointInPanel(0, 0), "modal blocks all canvas interaction")
check(box.Text == "{}", "portable text remains selectable in modal")
local modalConnections = activeConnections
ui:closeModal()
check(not ui.modalOpen and not ui.modalGui and activeConnections < modalConnections, "closing modal destroys its callbacks")
ui:modal("Diagnostics", "Bounded log", "Info")
ui:setVisible(false)
check(not ui.modalOpen and not ui.modalGui and not ui.overlay.Visible, "closing editor also dismisses modal and selection UI")
ui:setVisible(true)
app.preferences.launcherHidden = true; ui:refresh()
check(not ui.launcher.Visible, "launcher can be hidden without destroying editor")
app.preferences.launcherHidden = false; app.preferences.launcherX = .4; app.preferences.launcherY = .3; ui:refresh()
check(math.abs(ui.launcher.AbsolutePosition.X - .4 * (view.X - 54)) < .001, "launcher uses stable normalized available-width placement")
check(math.abs(ui.launcher.AbsolutePosition.Y - .3 * (view.Y - 48)) < .001, "launcher uses stable normalized available-height placement")
check(#app.logs == 0, "all exercised UI callbacks complete without swallowed errors")
local beforeDestroy = destroyed
ui:destroy(); ui:destroy()
check(ui.gui.Destroyed and destroyed > beforeDestroy, "destroy tears down owned GUI once")
check(activeConnections == 0, "destroy releases every UI and service event connection")
target:Destroy()

return checks
