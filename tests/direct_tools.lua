-- Exercise the real discovery and transform adapters with the shared Roblox API mock.
local Roblox = require("support/Roblox")
local Coordinates = require("Coordinates")
local Discovery = require("Discovery")
local Geometry = require("Geometry")
local Transform = require("Transform")

local checks = 0
local function check(condition, message)
    checks = checks + 1
    assert(condition, message)
end
local function close(a, b) return math.abs(a - b) < 1 end
local function object(class, name, parent, x, y, width, height)
    local instance = Instance.new(class)
    instance.Name, instance.Parent = name, parent
    if x then instance.Position, instance.Size = UDim2.fromOffset(x, y), UDim2.fromOffset(width, height) end
    return instance
end

local mock = Roblox.new(960, 440)
task = mock.task
local screen = object("ScreenGui", "Practice", mock.playerGui)
local left = object("TextButton", "Left", screen, 300, 160, 70, 50)
local right = object("TextButton", "Right", screen, 460, 160, 70, 50)
local panel = object("Frame", "Ability bar", screen, 100, 100, 160, 60)
panel.BackgroundTransparency = 1
local image = object("ImageButton", "First ability", panel, 10, 5, 44, 48)
image.Image, image.ImageTransparency, image.BackgroundTransparency = "rbxassetid://1", .25, 1

local discovery = Discovery.new(mock.playerGui, nil, nil, mock.services.GuiService)
discovery:refresh()
local transform = Transform.new(discovery)
local function key(instance)
    for _, record in ipairs(discovery:list("all")) do
        if record.object == instance then return record.key end
    end
    error("Fixture layer not discovered")
end
local function commit()
    local completed
    transform:endTransaction(function(ok) completed = ok end)
    mock:flush()
    check(completed == true, "transform passed its bounded geometry or property check")
end

local leftStart, rightStart = Geometry.center(Coordinates.rect(left)), Geometry.center(Coordinates.rect(right))
local group = assert(transform:rotationSnapshot({key(left), key(right)}))
check(group.isGroup and close(group.pivot.x, (leftStart.x + rightStart.x) / 2), "group pivot is the arrangement center")
check(transform:beginTransaction() and transform:setRotation(group, 90), "compatible roots rotate as a group")
commit()
local leftEnd, rightEnd = Geometry.center(Coordinates.rect(left)), Geometry.center(Coordinates.rect(right))
check(close(leftEnd.x, group.pivot.x) and close(rightEnd.x, group.pivot.x)
    and close(rightEnd.y - leftEnd.y, rightStart.x - leftStart.x)
    and left.Rotation == 90 and right.Rotation == 90, "group orientation and relative separation match the requested orbit")
local repeated = assert(transform:rotationSnapshot({key(left), key(right)}))
check(transform:beginTransaction() and transform:setRotation(repeated, 40) and transform:cancelTransaction(),
    "interrupting a group rotation cancels the entire live transaction")
check(left.Rotation == 90 and right.Rotation == 90 and close(Geometry.center(Coordinates.rect(left)).y, leftEnd.y),
    "cancellation restores the earlier verified layout")

local panelKey = key(panel)
local fade = assert(transform:opacitySnapshot({panelKey}, "contents"))
check(transform:beginTransaction() and transform:setOpacity(fade, .4), "contents opacity resolves supported visible surfaces")
commit()
local saved = transform:capture()
check(math.abs(image.ImageTransparency - .7) < .001 and panel.BackgroundTransparency == 1
    and saved[panelKey].opacity.factor == .4, "relative opacity is visible through a transparent ancestor and portable")

image:Destroy()
local rebuilt = object("ImageButton", "First ability", panel, 10, 5, 44, 48)
local unrelated = object("ImageButton", "Later ability", panel, 66, 5, 44, 48)
for _, instance in ipairs({rebuilt, unrelated}) do
    instance.Image, instance.ImageTransparency, instance.BackgroundTransparency = "rbxassetid://1", .25, 1
end
discovery:refresh()
transform:apply(saved, {onlyNew = true})
mock:flush()
check(math.abs(rebuilt.ImageTransparency - .7) < .001 and unrelated.ImageTransparency == .25,
    "recreated exact targets inherit the saved fade while new unrelated descendants stay unchanged")

local newFade = assert(transform:opacitySnapshot({panelKey}, "contents"))
check(transform:beginTransaction() and transform:setOpacity(newFade, .2) and transform:setOpacity(newFade, .1),
    "consecutive opacity samples reuse stable originals")
check(transform:cancelTransaction() and math.abs(rebuilt.ImageTransparency - .7) < .001 and unrelated.ImageTransparency == .25,
    "cancel restores prior opacity ownership and all property values")

transform:destroy()
discovery:destroy()
return checks
