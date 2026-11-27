-- Shared structural mocks for Roblox GUI delegates and input signals.
-- Roblox rendering, hit dispatch, focus and scrolling require the real engine.
local Roblox = {}

function Roblox.new(width, height)
    local mock = {activeConnections = 0, destroyed = 0}
    local function signal()
        local listeners = {}
        local s = {}
        function s:Connect(callback)
            local entry = {callback = callback, connected = true}
            listeners[#listeners + 1] = entry; mock.activeConnections = mock.activeConnections + 1
            return {Disconnect = function()
                if entry.connected then entry.connected = false; mock.activeConnections = mock.activeConnections - 1 end
            end}
        end
        function s:Fire(...)
            local snapshot = {}; for i, entry in ipairs(listeners) do snapshot[i] = entry end
            for _, entry in ipairs(snapshot) do if entry.connected then entry.callback(...) end end
        end
        function s:Destroy()
            for _, entry in ipairs(listeners) do
                if entry.connected then entry.connected = false; mock.activeConnections = mock.activeConnections - 1 end
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
    local view, screenOrigin = vec(width or 800, height or 600), vec(-9, -23)
    mock.view, mock.vec, mock.signal = view, vec, signal
    local methods = {}
    local eventNames = {
        Activated = true, Focused = true, FocusLost = true, InputBegan = true, InputEnded = true,
        DescendantAdded = true, DescendantRemoving = true,
    }
    local guiClasses = {Frame = true, TextButton = true, ImageButton = true, TextLabel = true,
        TextBox = true, ScrollingFrame = true, ImageLabel = true}
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
    local function notifyAncestors(parent, event, child)
        while parent do
            local listeners = rawget(parent, "_events")[event]
            if listeners then listeners:Fire(child) end
            parent = parent.Parent
        end
    end
    function mt:__newindex(key, value)
        local props = rawget(self, "_props")
        if key == "Parent" then
            local previous = props.Parent
            if previous then
                notifyAncestors(previous, "DescendantRemoving", self)
                local children = rawget(previous, "_children")
                for i, child in ipairs(children) do if child == self then table.remove(children, i); break end end
            end
            props.Parent = value
            if value then
                table.insert(rawget(value, "_children"), self)
                notifyAncestors(value, "DescendantAdded", self)
            end
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
    function methods:IsA(class)
        return class == self.ClassName or class == "Instance"
            or class == "GuiObject" and guiClasses[self.ClassName]
            or class == "GuiButton" and (self.ClassName == "TextButton" or self.ClassName == "ImageButton")
    end
    function methods:FindFirstChildOfClass(class)
        for _, child in ipairs(self:GetChildren()) do
            if child.ClassName == class then return child end
        end
    end
    function methods:FindFirstChild(name)
        for _, child in ipairs(self:GetChildren()) do
            if child.Name == name then return child end
        end
    end
    methods.WaitForChild = methods.FindFirstChild
    function methods:IsFocused() return rawget(self, "_props").Focused == true end
    function methods:CaptureFocus() rawget(self, "_props").Focused = true end
    function methods:ReleaseFocus() rawget(self, "_props").Focused = false end
    function methods:Destroy()
        if self.Destroyed then return end
        self.Destroyed = true; mock.destroyed = mock.destroyed + 1
        for _, child in ipairs(self:GetChildren()) do child:Destroy() end
        for _, collection in ipairs({rawget(self, "_changes"), rawget(self, "_events")}) do
            for _, s in pairs(collection) do s:Destroy() end
        end
        self.Parent = nil
    end
    Instance = {new = function(class)
        return setmetatable({_props = {ClassName = class, Name = class, Size = UDim2.new(), Position = UDim2.new(),
            AnchorPoint = vec(), CanvasPosition = vec(), Visible = true, Enabled = true, ZIndex = 1, DisplayOrder = 0,
            Text = "", BackgroundTransparency = 0, Rotation = 0, ClipsDescendants = false},
            _children = {}, _changes = {}, _events = {}}, mt)
    end}
    local playerGui = Instance.new("PlayerGui")
    local camera = {ViewportSize = view, changed = signal()}
    function camera:GetPropertyChangedSignal() return self.changed end
    local safeLeft, safeRight, safeTop, safeBottom = 12, 16, 23, 10
    local function insetArea(_, inset)
        return {Min = vec(safeLeft, inset == Enum.ScreenInsets.DeviceSafeInsets and -safeTop or 0),
            Max = vec(view.X - safeRight, view.Y - safeTop - safeBottom)}
    end
    mock.playerGui = playerGui
    local player = Instance.new("Player")
    playerGui.Parent = player
    local input = {TouchEnabled = true, PreferredInput = Enum.PreferredInput.Touch,
        InputBegan = signal(), InputChanged = signal(), InputEnded = signal(), WindowFocusReleased = signal()}
    function input:IsKeyDown() return false end
    function input:GetFocusedTextBox() return self.focused end
    local workspace = {CurrentCamera = camera, changed = signal()}
    function workspace:GetPropertyChangedSignal() return self.changed end
    mock.services = {
        Players = {LocalPlayer = player}, UserInputService = input, Workspace = workspace,
        GuiService = {GetGuiInset = function() return vec(0, safeTop), vec(0, safeBottom) end, GetInsetArea = insetArea},
        RunService = {}, HttpService = {}, TextService = {}, ContextActionService = {},
    }
    mock.game = {GameId = 100, PlaceId = 200, GetService = function(_, name) return assert(mock.services[name], name) end}

    local pending = {}
    mock.task = {
        delay = function(_, callback) pending[#pending + 1] = callback end,
        defer = function(callback) pending[#pending + 1] = callback end,
    }
    function mock:flush()
        -- All scheduled callbacks in an integration action form a short finite queue.
        for _ = 1, 20 do
            if #pending == 0 then return end
            local batch = pending
            pending = {}
            for _, callback in ipairs(batch) do callback() end
        end
        error("Mock Roblox callbacks failed to settle")
    end
    return mock
end

return Roblox
