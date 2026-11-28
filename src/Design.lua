-- Native Roblox tokens and shared chrome for editor surfaces.
local Design = {}

Design.colors = {
    surface = Color3.fromRGB(16, 25, 36),
    raised = Color3.fromRGB(29, 43, 57),
    field = Color3.fromRGB(10, 19, 28),
    selected = Color3.fromRGB(28, 58, 69),
    control = Color3.fromRGB(39, 83, 99),
    cyan = Color3.fromRGB(123, 231, 237),
    ink = Color3.fromRGB(13, 37, 43),
    text = Color3.fromRGB(240, 246, 249),
    subtleText = Color3.fromRGB(218, 230, 237),
    muted = Color3.fromRGB(169, 188, 201),
    quiet = Color3.fromRGB(125, 145, 159),
    border = Color3.fromRGB(62, 86, 102),
    scrim = Color3.fromRGB(4, 13, 20),
    success = Color3.fromRGB(138, 233, 197),
    warning = Color3.fromRGB(255, 201, 122),
    danger = Color3.fromRGB(255, 155, 156),
}

Design.font = {body = Enum.Font.Gotham, medium = Enum.Font.GothamMedium, strong = Enum.Font.GothamBold, mono = Enum.Font.Code}
Design.text = {caption = 11, control = 13, body = 14, section = 16, title = 18, hero = 22}
Design.space = {tight = 4, small = 8, medium = 12, large = 16, wide = 24}
Design.radius = {marker = 3, field = 7, control = 9, surface = 13, dialog = 16}
Design.touch = {minimum = 44, comfortable = 48}
Design.motion = {enter = .16, exit = .12}

function Design.round(object, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or Design.radius.control)
    corner.Parent = object
    return corner
end

function Design.stroke(object, color, thickness, transparency)
    local stroke = Instance.new("UIStroke")
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Color = color or Design.colors.border
    stroke.Thickness = thickness or 1
    stroke.Transparency = transparency or .35
    stroke.Parent = object
    return stroke
end

return Design
