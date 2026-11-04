-- Heavenly Axis V3 controlled Studio fixture. Put this LocalScript in StarterPlayerScripts.
-- These GUI controls are mocks. They do not verify Roblox internal touch regions or movement.
local Players = game:GetService("Players")
local Input = game:GetService("UserInputService")
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local previous = _G.__HEAVENLY_AXIS_TEST_HUD
if previous then previous:Destroy() end

local fixture = {connections = {}, hudConnections = {}, destroyed = false}
local function connect(signal, callback)
    local connection = signal:Connect(callback)
    fixture.connections[#fixture.connections + 1] = connection
    return connection
end
local function make(class, props, parent)
    local object = Instance.new(class)
    for key, value in pairs(props) do object[key] = value end
    object.Parent = parent
    return object
end
local gui = make("ScreenGui", {
    Name = "AxisFixtureHUD", ResetOnSpawn = false, DisplayOrder = 4,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = false,
}, playerGui)
fixture.gui = gui
function fixture:Destroy()
    if self.destroyed then return end
    self.destroyed = true
    for _, connection in ipairs(self.connections) do connection:Disconnect() end
    self.connections = {}
    for _, connection in ipairs(self.hudConnections) do connection:Disconnect() end
    self.hudConnections = {}
    gui:Destroy()
    if _G.__HEAVENLY_AXIS_TEST_HUD == self then _G.__HEAVENLY_AXIS_TEST_HUD = nil end
end
_G.__HEAVENLY_AXIS_TEST_HUD = fixture

local cyan = Color3.fromRGB(62, 218, 240)
local dark = Color3.fromRGB(24, 37, 46)
local white = Color3.fromRGB(234, 243, 247)
local function rounded(object, radius)
    make("UICorner", {CornerRadius = UDim.new(0, radius or 12)}, object)
    return object
end
local function label(parent, name, text, position, size)
    return make("TextLabel", {
        Name = name, Text = text, Position = position, Size = size,
        BackgroundTransparency = 1, TextColor3 = white, Font = Enum.Font.Gotham,
        TextSize = 13, TextWrapped = true,
    }, parent)
end
local hud
local function button(parent, name, text, position, size, callback)
    local object = rounded(make("TextButton", {
        Name = name, Text = text, Position = position, Size = size,
        BackgroundColor3 = dark, TextColor3 = white, Font = Enum.Font.GothamMedium,
        TextSize = 13, AutoButtonColor = true,
    }, parent))
    if callback then
        local connection = object.Activated:Connect(callback)
        local list = hud and object:IsDescendantOf(hud) and fixture.hudConnections or fixture.connections
        list[#list + 1] = connection
    end
    return object
end

local admin = rounded(make("Frame", {
    Name = "FixtureControls", Position = UDim2.fromOffset(12, 12),
    Size = UDim2.new(1, -24, 0, 124), BackgroundColor3 = dark,
}, gui))
label(admin, "Notice", "STUDIO FIXTURE · Mock controls only · No actual jump or movement", UDim2.fromOffset(8, 4), UDim2.new(1, -16, 0, 28))
local status = label(admin, "FixtureStatus", "Gameplay activations: 0", UDim2.fromOffset(8, 88), UDim2.new(1, -16, 0, 28))
local count = 0
local function activate(name)
    count = count + 1
    status.Text = "Gameplay activations: " .. count .. " · " .. name
end
local function makeHud()
    for _, connection in ipairs(fixture.hudConnections) do connection:Disconnect() end
    fixture.hudConnections = {}
    local function connectHud(signal, callback)
        local connection = signal:Connect(callback)
        fixture.hudConnections[#fixture.hudConnections + 1] = connection
        return connection
    end
    if hud then hud:Destroy() end
    hud = make("Frame", {
        Name = "RecreatedHUD", BackgroundTransparency = 1,
        Position = UDim2.fromOffset(0, 144), Size = UDim2.new(1, 0, 1, -144),
    }, gui)
    local jump = button(hud, "JumpStyle", "JUMP\n(mock)", UDim2.new(1, -118, 1, -118), UDim2.fromOffset(96, 96), function() activate("JumpStyle") end)
    jump:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(1, 0)
    jump.BackgroundColor3 = Color3.fromRGB(25, 100, 115)
    jump.AnchorPoint = Vector2.new(0.5, 0.5)
    jump.Position = UDim2.new(0.88, 0, 0.82, 0)

    local classic = rounded(make("Frame", {
        Name = "ClassicJoystickStyle", Position = UDim2.new(0, 30, 1, -174),
        Size = UDim2.fromOffset(132, 132), BackgroundColor3 = dark, Active = true,
    }, hud), 66)
    local classicThumb = rounded(make("Frame", {
        Name = "Thumb", Position = UDim2.new(0.5, -23, 0.5, -23),
        Size = UDim2.fromOffset(46, 46), BackgroundColor3 = cyan,
    }, classic), 23)
    label(classic, "Caption", "CLASSIC\n(mock)", UDim2.new(0, 0, 1, 4), UDim2.new(1, 0, 0, 34))
    local activeClassic
    connectHud(classic.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            activeClassic = input
            activate("Classic mock begin")
        end
    end)
    local function moveThumb(input)
        if not activeClassic then return end
        local touch = activeClassic.UserInputType == Enum.UserInputType.Touch
        if (touch and input ~= activeClassic) or (not touch and input.UserInputType ~= Enum.UserInputType.MouseMovement) then return end
        local delta = Vector2.new(input.Position.X, input.Position.Y) - classic.AbsolutePosition - classic.AbsoluteSize / 2
        local length = math.min(delta.Magnitude, classic.AbsoluteSize.X * 0.3)
        if delta.Magnitude > 0 then delta = delta.Unit * length end
        classicThumb.Position = UDim2.new(0.5, delta.X - 23, 0.5, delta.Y - 23)
    end
    connectHud(Input.InputChanged, moveThumb)
    connectHud(Input.InputEnded, function(input)
        if input == activeClassic or (activeClassic and activeClassic.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1) then
            activeClassic = nil
            if classicThumb.Parent then classicThumb.Position = UDim2.new(0.5, -23, 0.5, -23) end
        end
    end)

    local dynamic = rounded(make("Frame", {
        Name = "DynamicJoystickStyle", Position = UDim2.new(0.25, 0, 1, -130),
        Size = UDim2.fromOffset(170, 88), BackgroundColor3 = dark, Active = true,
    }, hud))
    label(dynamic, "Caption", "DYNAMIC REGION (mock)", UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 30))
    local dot = rounded(make("Frame", {
        Name = "DynamicDot", Position = UDim2.new(0.5, -12, 0.5, 0),
        Size = UDim2.fromOffset(24, 24), BackgroundColor3 = cyan,
    }, dynamic), 12)
    connectHud(dynamic.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dot.Position = UDim2.fromOffset(input.Position.X - dynamic.AbsolutePosition.X - 12, input.Position.Y - dynamic.AbsolutePosition.Y - 12)
            activate("Dynamic mock anchored")
        end
    end)

    local nested = rounded(make("Frame", {
        Name = "NestedParent", Position = UDim2.new(0.15, 0, 0.05, 0),
        Size = UDim2.fromOffset(220, 120), BackgroundColor3 = Color3.fromRGB(53, 47, 75),
    }, hud))
    label(nested, "ParentCaption", "Nested parent (select with child)", UDim2.fromOffset(4, 4), UDim2.new(1, -8, 0, 28))
    button(nested, "NestedChild", "Child", UDim2.new(0.5, -42, 0.5, 0), UDim2.fromOffset(84, 48), function() activate("Nested child") end)
    local scaled = rounded(make("Frame", {
        Name = "ScaledParent", Position = UDim2.new(0.5, 10, 0.05, 0),
        Size = UDim2.fromOffset(160, 100), BackgroundColor3 = Color3.fromRGB(46, 65, 45),
    }, hud))
    make("UIScale", {Scale = 0.85}, scaled)
    button(scaled, "ScaledChild", "UIScale child", UDim2.fromOffset(10, 30), UDim2.fromOffset(138, 54), function() activate("Scaled child") end)

    button(hud, "OverlapBack", "Back", UDim2.new(0.36, 0, 0.37, 0), UDim2.fromOffset(120, 64), function() activate("Overlap back") end).ZIndex = 1
    button(hud, "OverlapFront", "Front", UDim2.new(0.36, 28, 0.37, 24), UDim2.fromOffset(120, 64), function() activate("Overlap front") end).ZIndex = 2
    local layout = rounded(make("Frame", {
        Name = "LayoutManaged", Position = UDim2.new(0.72, 0, 0.05, 0),
        Size = UDim2.fromOffset(136, 160), BackgroundColor3 = dark,
    }, hud))
    make("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, layout)
    for index = 1, 3 do
        button(layout, "Managed" .. index, "Managed " .. index, UDim2.new(), UDim2.fromOffset(120, 44), function() activate("Managed") end)
    end
    local constrained = button(hud, "Constrained", "Aspect constraint", UDim2.new(0.63, 0, 0.57, 0), UDim2.fromOffset(100, 60), function() activate("Constrained") end)
    make("UIAspectRatioConstraint", {AspectRatio = 1.8}, constrained)
    local rotated = button(hud, "Rotated", "Rotated 12°", UDim2.new(0.55, 0, 0.77, 0), UDim2.fromOffset(100, 50), function() activate("Rotated") end)
    rotated.Rotation = 12
    local hidden = button(hud, "HiddenControl", "Hidden", UDim2.fromOffset(0, 0), UDim2.fromOffset(90, 42))
    hidden.Visible = false
    button(hud, "OffscreenControl", "Recover me", UDim2.new(1, 80, 0.4, 0), UDim2.fromOffset(100, 48))
    for index = 1, 3 do
        button(hud, "GroupItem" .. index, "Group " .. index, UDim2.new(0.04, (index - 1) * 110, 0.44, index * 12), UDim2.fromOffset(88 + index * 6, 44 + index * 4), function() activate("Group") end)
    end
end
makeHud()

local menu
button(admin, "Recreate", "Recreate HUD", UDim2.new(0, 8, 0, 38), UDim2.new(0.31, -8, 0, 44), function()
    fixture.rebuildGeneration = (fixture.rebuildGeneration or 0) + 1
    local generation = fixture.rebuildGeneration
    for _, connection in ipairs(fixture.hudConnections) do connection:Disconnect() end
    fixture.hudConnections = {}
    if hud then hud:Destroy(); hud = nil end
    status.Text = "HUD removed; returns after one second. Check delayed restoration."
    task.delay(1, function()
        if fixture.destroyed or generation ~= fixture.rebuildGeneration then return end
        makeHud()
        status.Text = "HUD recreated with identical names/classes. Check saved restoration."
    end)
end)
button(admin, "TemporaryMenu", "Temporary menu", UDim2.new(0.33, 0, 0, 38), UDim2.new(0.34, -8, 0, 44), function()
    if menu and menu.Parent then menu:Destroy(); menu = nil; return end
    menu = rounded(make("Frame", {
        Name = "TemporaryMenu", Position = UDim2.new(0.5, -120, 0.5, -70),
        Size = UDim2.fromOffset(240, 140), BackgroundColor3 = Color3.fromRGB(77, 49, 53),
    }, gui))
    label(menu, "Notice", "Temporary menu\nDestroy and recreate using fixture button", UDim2.fromOffset(12, 12), UDim2.new(1, -24, 1, -24))
end)
button(admin, "ToggleHUD", "Hide / show HUD", UDim2.new(0.68, 0, 0, 38), UDim2.new(0.32, -8, 0, 44), function()
    if hud then hud.Visible = not hud.Visible end
end)
