-- Render a pinned subset of Lucide with native GuiObjects, without runtime assets.
local glyphs = require("LucideGlyphs")

local Lucide = {}
Lucide.version = "0.511.0"
Lucide.revision = "ba77aa6a76152a93c0388910427c7ece3f75dd61"
local supportsInteractable, supportsCenteredStroke

local aliases = {
    ["alert-circle"] = "circle-alert", ["alert-triangle"] = "triangle-alert",
    ["check-circle"] = "circle-check-big", ["check-circle-2"] = "circle-check",
    ["help-circle"] = "circle-help", ["x-circle"] = "circle-x",
    ["layout-grid"] = "grid-2x2", ["menu-horizontal"] = "ellipsis",
    ["rotate-left"] = "rotate-ccw", ["rotate-right"] = "rotate-cw",
}

local function glyph(name)
    if type(name) ~= "string" then return nil end
    return glyphs[aliases[name] or name]
end

function Lucide.has(name)
    return glyph(name) ~= nil
end

local function frame(name, color, zIndex)
    local part = Instance.new("Frame")
    part.Name = name
    part.BorderSizePixel = 0
    part.Active = false
    part.Selectable = false
    if supportsInteractable == nil then
        supportsInteractable = pcall(function() part.Interactable = false end)
    elseif supportsInteractable then part.Interactable = false end
    part.BackgroundColor3 = color
    part.ZIndex = zIndex
    return part
end

local function round(object, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = radius
    corner.Parent = object
end

local function line(parent, color, proportion, x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local length = math.sqrt(dx * dx + dy * dy)
    local part = frame("Stroke", color, parent.ZIndex)
    part.AnchorPoint = Vector2.new(.5, .5)
    part.Position = UDim2.fromScale((x1 + x2) / 48, (y1 + y2) / 48)
    part.Size = UDim2.fromScale(length / 24 + proportion, proportion)
    if length > .001 then part.Rotation = math.deg((math.atan2 or math.atan)(dy, dx)) end
    round(part, UDim.new(.5, 0))
    part.Parent = parent
end

local function roundedShape(parent, color, size, thickness, shape)
    local _, x, y, width, height, radius = table.unpack(shape)
    local proportion = thickness / size
    width, height, radius = width / 24, height / 24, radius / 24
    local part = frame("Outline", color, parent.ZIndex)
    part.AnchorPoint = Vector2.new(.5, .5)
    part.Position = UDim2.fromScale(x / 24, y / 24)
    if math.min(width, height) <= proportion then
        part.Size = UDim2.fromScale(width + proportion, height + proportion)
        round(part, UDim.new(.5, 0))
    else
        local stroke = Instance.new("UIStroke")
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Color = color
        stroke.Thickness = thickness
        if supportsCenteredStroke == nil then
            supportsCenteredStroke = pcall(function() stroke.BorderStrokePosition = Enum.BorderStrokePosition.Center end)
        elseif supportsCenteredStroke then stroke.BorderStrokePosition = Enum.BorderStrokePosition.Center end
        local adjustment = supportsCenteredStroke and 0 or proportion
        width, height = width - adjustment, height - adjustment
        part.BackgroundTransparency = 1
        part.Size = UDim2.fromScale(width, height)
        if radius > 0 then round(part, UDim.new(math.max(0, radius - adjustment / 2) / math.min(width, height), 0)) end
        stroke.Parent = part
    end
    part.Parent = parent
end

function Lucide.mount(parent, name, options)
    local shape = glyph(name)
    if not parent or not shape then return nil end
    options = options or {}
    local size = math.max(10, options.size or 18)
    local scale = size / 24
    local color = options.color or Color3.fromRGB(255, 255, 255)
    local thickness = math.max(1, (options.strokeWidth or 2) * scale)
    local zIndex = options.zIndex or (parent:IsA("GuiObject") and parent.ZIndex) or 1
    local icon = frame(options.name or "Lucide_" .. name, color, zIndex)
    icon.BackgroundTransparency = 1
    icon.AnchorPoint = options.anchor or Vector2.new(.5, .5)
    icon.Position = options.position or UDim2.fromScale(.5, .5)
    icon.Size = UDim2.fromOffset(size, size)
    for _, primitive in ipairs(shape) do
        if primitive[1] == "rounded" then roundedShape(icon, color, size, thickness, primitive)
        else
            for index = 1, #primitive - 2, 2 do
                line(icon, color, thickness / size, primitive[index], primitive[index + 1], primitive[index + 2], primitive[index + 3])
            end
        end
    end
    icon.Parent = parent
    return icon
end

function Lucide.setColor(icon, color)
    if not icon or not color or icon.BackgroundColor3 == color then return end
    icon.BackgroundColor3 = color
    for _, part in ipairs(icon:GetChildren()) do
        local stroke = part:FindFirstChildOfClass("UIStroke")
        if stroke then stroke.Color = color else part.BackgroundColor3 = color end
    end
end

return Lucide
