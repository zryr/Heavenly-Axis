-- Heavenly Axis V3 controlled Studio fixture. Put this LocalScript in StarterPlayerScripts.
-- These GUI controls are mocks. They do not verify Roblox internal touch regions or movement.
local Players = game:GetService("Players")
local Input = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local previous = _G.__HEAVENLY_AXIS_TEST_HUD
if previous then previous:Destroy() end

local fixture = {connections = {}, hudConnections = {}, screens = {}, destroyed = false}
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
local function screen(name, inset, order)
    local gui = make("ScreenGui", {
        Name = name, ResetOnSpawn = false, DisplayOrder = order,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        ScreenInsets = inset, SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,
    }, playerGui)
    fixture.screens[#fixture.screens + 1] = gui
    return gui
end
local gui = screen("AxisFixtureHUD", Enum.ScreenInsets.CoreUISafeInsets, 4)
fixture.gui = gui
function fixture:Destroy()
    if self.destroyed then return end
    self.destroyed = true
    for _, connection in ipairs(self.connections) do connection:Disconnect() end
    self.connections = {}
    for _, connection in ipairs(self.hudConnections) do connection:Disconnect() end
    self.hudConnections = {}
    for _, screenGui in ipairs(self.screens) do screenGui:Destroy() end
    self.screens = {}
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
local function pointer(input)
    return input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1
end
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
    Name = "FixtureControls", Position = UDim2.new(0.5, 0, 0, 4), AnchorPoint = Vector2.new(0.5, 0),
    Size = UDim2.new(1, -16, 0, 88), BackgroundColor3 = dark,
}, gui))
make("UISizeConstraint", {MaxSize = Vector2.new(560, 88)}, admin)
label(admin, "Notice", "STUDIO FIXTURE · Mock HUD controls", UDim2.fromOffset(8, 0), UDim2.new(1, -16, 0, 20))
local status = label(admin, "FixtureStatus", "Gameplay activations: 0", UDim2.fromOffset(8, 66), UDim2.new(1, -16, 0, 20))
local function adminButton(column, name, text, callback)
    return button(admin, name, text, UDim2.new((column - 1) * 0.2, 4, 0, 20), UDim2.new(0.2, -8, 0, 44), callback)
end
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
        Position = UDim2.fromOffset(0, 96), Size = UDim2.new(1, 0, 1, -96),
    }, gui)
    local controls = make("Frame", {
        Name = "TouchControlFrameMock", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
    }, hud)
    local jump = button(controls, "JumpStyle", "JUMP\n(mock)", UDim2.fromScale(0.88, 0.82), UDim2.fromOffset(96, 96), function() activate("JumpStyle") end)
    jump:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(1, 0)
    jump.BackgroundColor3 = Color3.fromRGB(25, 100, 115)
    jump.AnchorPoint = Vector2.new(0.5, 0.5)

    local classic = rounded(make("Frame", {
        Name = "ClassicJoystickStyle", Position = UDim2.new(0, 18, 1, -28), AnchorPoint = Vector2.new(0, 1),
        Size = UDim2.fromOffset(108, 108), BackgroundColor3 = dark, Active = true,
    }, controls), 54)
    local classicThumb = rounded(make("Frame", {
        Name = "Thumb", Position = UDim2.new(0.5, -23, 0.5, -23),
        Size = UDim2.fromOffset(46, 46), BackgroundColor3 = cyan,
    }, classic), 23)
    label(classic, "Caption", "CLASSIC\n(mock)", UDim2.new(0, 0, 1, 4), UDim2.new(1, 0, 0, 34))
    local activeClassic, classicStart
    connectHud(classic.InputBegan, function(input)
        if pointer(input) and not activeClassic then
            activeClassic = input
            classicStart = Vector2.new(input.Position.X, input.Position.Y)
            activate("Classic mock begin")
        end
    end)
    local function moveThumb(input)
        if not activeClassic then return end
        local touch = activeClassic.UserInputType == Enum.UserInputType.Touch
        if (touch and input ~= activeClassic) or (not touch and input.UserInputType ~= Enum.UserInputType.MouseMovement) then return end
        local delta = Vector2.new(input.Position.X, input.Position.Y) - classicStart
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
        Name = "DynamicJoystickStyle", Position = UDim2.new(0.36, 0, 1, -88),
        Size = UDim2.fromOffset(142, 74), BackgroundColor3 = dark, Active = true,
    }, controls))
    label(dynamic, "Caption", "DYNAMIC REGION (mock)", UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 30))
    local dot = rounded(make("Frame", {
        Name = "DynamicDot", Position = UDim2.new(0.5, -12, 0.5, 0),
        Size = UDim2.fromOffset(24, 24), BackgroundColor3 = cyan,
    }, dynamic), 12)
    connectHud(dynamic.InputBegan, function(input)
        if pointer(input) then
            dot.BackgroundColor3 = dot.BackgroundColor3 == cyan and white or cyan
            activate("Dynamic mock activated")
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
    local scaledChild = button(scaled, "ScaledChild", "Nested UIScale", UDim2.new(1, -10, 1, -12), UDim2.fromOffset(138, 54), function() activate("Scaled child") end)
    scaledChild.AnchorPoint = Vector2.new(1, 1)
    make("UIScale", {Scale = 1.2}, scaledChild)

    button(hud, "OverlapBack", "Back", UDim2.new(0.36, 0, 0.37, 0), UDim2.fromOffset(120, 64), function() activate("Overlap back") end).ZIndex = 1
    button(hud, "OverlapFront", "Front", UDim2.new(0.36, 28, 0.37, 24), UDim2.fromOffset(120, 64), function() activate("Overlap front") end).ZIndex = 2
    local layout = rounded(make("Frame", {
        Name = "LayoutManaged", Position = UDim2.new(0.72, 0, 0.05, 0),
        Size = UDim2.fromOffset(136, 160), BackgroundColor3 = dark,
    }, hud))
    make("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, layout)
    for index = 1, 3 do
        local managed = button(layout, "Managed" .. index, "Managed " .. index, UDim2.new(), UDim2.fromOffset(120, 44), function() activate("Managed") end)
        managed.LayoutOrder = index
    end
    local clip = rounded(make("Frame", {
        Name = "ClippingParent", Position = UDim2.new(0.02, 0, 0.2, 0),
        Size = UDim2.fromOffset(104, 48), BackgroundColor3 = Color3.fromRGB(70, 43, 58),
        ClipsDescendants = true,
    }, hud))
    local clipped = button(clip, "PartlyClippedChild", "Clipped", UDim2.fromOffset(28, 12), UDim2.fromOffset(110, 56), function() activate("Clipped") end)
    clipped.ZIndex = 2
    local tiny = button(hud, "TinyControl", "", UDim2.new(0.65, 0, 0.43, 0), UDim2.fromOffset(22, 22), function() activate("Tiny control") end)
    tiny.BackgroundColor3 = cyan
    local relative = button(hud, "RelativeXXControl", "RelativeXX", UDim2.new(0.61, 0, 0.28, 0), UDim2.new(0.05, 32, 0.03, 24), function() activate("RelativeXX") end)
    relative.SizeConstraint = Enum.SizeConstraint.RelativeXX
    local relativeYY = button(hud, "RelativeYYControl", "RelativeYY", UDim2.new(0.04, 0, 0.32, 0), UDim2.new(0.04, 38, 0.025, 26), function() activate("RelativeYY") end)
    relativeYY.SizeConstraint = Enum.SizeConstraint.RelativeYY
    label(hud, "LongElementName_For_Search_And_Hierarchy_With_A_Label_That_Must_Truncate_Cleanly",
        "Long name and decorative label", UDim2.new(0.35, 0, 0.68, 0), UDim2.fromOffset(160, 28))
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
adminButton(1, "Recreate", "Recreate", function()
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
adminButton(2, "TemporaryMenu", "Menu", function()
    if menu and menu.Parent then menu:Destroy(); menu = nil; return end
    menu = rounded(make("Frame", {
        Name = "TemporaryMenu", Position = UDim2.new(0.5, -120, 0.5, -70),
        Size = UDim2.fromOffset(240, 140), BackgroundColor3 = Color3.fromRGB(77, 49, 53),
    }, gui))
    label(menu, "Notice", "Temporary menu\nDestroy and recreate using fixture button", UDim2.fromOffset(12, 12), UDim2.new(1, -24, 1, -24))
end)
adminButton(3, "ToggleHUD", "Show / hide", function()
    if hud then hud.Visible = not hud.Visible end
end)

local probes = {}
local probeSettings = {
    {inset = Enum.ScreenInsets.CoreUISafeInsets, label = "Core UI", x = 0.16, y = 0.32, height = 44, clipped = true},
    {inset = Enum.ScreenInsets.DeviceSafeInsets, label = "Device", x = 0.42, y = 0.32, height = 44, clipped = true},
    {inset = Enum.ScreenInsets.None, label = "None", x = 0.70, y = 0.32, height = 44, clipped = false},
    {inset = Enum.ScreenInsets.TopbarSafeInsets, label = "Top bar", x = 0.50, y = 0.50, height = 30, clipped = true},
}
for index, settings in ipairs(probeSettings) do
    local probeGui = screen("AxisFixtureInset_" .. settings.inset.Name, settings.inset, 8 + index)
    probeGui.ClipToDeviceSafeArea = settings.clipped
    probeGui.Enabled = false
    local probe = button(probeGui, "Probe_" .. settings.inset.Name, settings.label,
        UDim2.fromScale(settings.x, settings.y), UDim2.fromOffset(72, settings.height))
    probe.AnchorPoint = Vector2.new(0.5, 0.5)
    probe.BackgroundColor3 = Color3.fromRGB(91, 48, 104)
    probes[index] = probe
end

local probeEnabled = false
adminButton(4, "InsetProbes", "Insets", function()
    probeEnabled = not probeEnabled
    for _, probe in ipairs(probes) do probe.Parent.Enabled = probeEnabled end
    status.Text = probeEnabled and "Tap the purple probes and compare Studio Output." or "Inset probes hidden."
end)

local function xy(value)
    return string.format("(%.1f, %.1f)", value.X, value.Y)
end
local function describeHits(x, y)
    local hits, found = playerGui:GetGuiObjectsAtPosition(math.floor(x), math.floor(y)), {}
    for rank, object in ipairs(hits) do
        if rank <= 3 or table.find(probes, object) then found[#found + 1] = rank .. ":" .. object.Name end
    end
    return #hits .. " [" .. table.concat(found, ", ") .. "]"
end
connect(Input.InputBegan, function(input)
    if not probeEnabled or not pointer(input) then return end
    local camera = Workspace.CurrentCamera
    local insetTop, insetBottom = GuiService:GetGuiInset()
    local x, y = input.Position.X, input.Position.Y
    print(string.format("[Axis fixture] %s at %s, camera viewport %s, inset %s / %s", input.UserInputType.Name,
        xy(input.Position), camera and xy(camera.ViewportSize) or "unavailable", xy(insetTop), xy(insetBottom)))
    print("[Axis fixture] hit(raw)=" .. describeHits(x, y) .. " hit(raw − inset)=" .. describeHits(x - insetTop.X, y - insetTop.Y))
    for _, probe in ipairs(probes) do
        local inset = probe.Parent.ScreenInsets
        local area = GuiService:GetInsetArea(inset)
        print(string.format("[Axis fixture] %s position %s, size %s; inset area %s to %s", inset.Name,
            xy(probe.AbsolutePosition), xy(probe.AbsoluteSize), xy(area.Min), xy(area.Max)))
    end
end)

local stressGui = screen("AxisFixtureStress", Enum.ScreenInsets.CoreUISafeInsets, 5)
local stress
adminButton(5, "ToggleCollection", "240 items", function()
    if stress then
        stress:Destroy()
        stress = nil
        status.Text = "Removed 240 fixture elements."
        return
    end
    stress = make("Frame", {
        Name = "StressCollection", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.54),
        Size = UDim2.fromOffset(240, 120), BackgroundColor3 = dark,
    }, stressGui)
    for index = 1, 240 do
        local column, row = (index - 1) % 20, math.floor((index - 1) / 20)
        make("Frame", {
            Name = string.format("StressTile%03d", index),
            Position = UDim2.fromOffset(column * 12 + 1, row * 10 + 1), Size = UDim2.fromOffset(10, 8),
            BackgroundColor3 = index % 3 == 0 and cyan or white, BackgroundTransparency = 0.25,
            BorderSizePixel = 0,
        }, stress)
    end
    status.Text = "Added 240 fixture elements. Search StressTile197."
end)
