-- Exercise the real discovery and transform adapters with the shared Roblox API mock.
local Roblox = require("support/Roblox")
local Coordinates = require("Coordinates")
local Discovery = require("Discovery")
local Geometry = require("Geometry")
local Transform = require("Transform")
local Util = require("Util")

local checks = 0
local function check(condition, message)
    checks = checks + 1
    assert(condition, message)
end
local function close(a, b) return math.abs(a - b) < 1 end
local function transparency(a, b) return math.abs(a - b) < 0.000001 end
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

local function applyFade(keys, scope, factor)
    local snapshot = assert(transform:opacitySnapshot(keys, scope))
    check(transform:beginTransaction() and transform:setOpacity(snapshot, factor), "relative opacity gesture applies")
    commit()
    return snapshot
end

local function replay(before, after)
    local successful, reason
    check(transform:applyHistory(before, after, function(ok, message) successful, reason = ok, message end), "history replay is accepted")
    mock:flush()
    check(successful, reason or "replay verifies the restored state")
end

local legacy = object("ImageButton", "Legacy painted button", screen, 500, 190, 52, 48)
legacy.Image, legacy.BackgroundTransparency, legacy.ImageTransparency = "rbxassetid://1", .215, .25
discovery:refresh()
local legacyKey = key(legacy)
local oldEntry = Discovery.serialize(legacy)
oldEntry.descriptor = Util.copy(discovery:get(legacyKey).descriptor)
oldEntry.transparency = .7
transform:apply({[legacyKey] = oldEntry})
mock:flush()
check(legacy.BackgroundTransparency == .7 and legacy.ImageTransparency == .25, "legacy opacity data changes just its original background property")
applyFade({legacyKey}, "element", .4)
check(transparency(legacy.BackgroundTransparency, .686) and transparency(legacy.ImageTransparency, .7),
    "relative opacity uses authored original values even with a legacy background override")
check(transform:opacityOwnsBackground(legacyKey) and transform:setProperty({legacyKey}, "transparency", .2) == 0,
    "a masked legacy edit does not claim to change the live appearance")
applyFade({legacyKey}, "element", 1)
local relativeLegacy = transform:capture()[legacyKey]
check(legacy.BackgroundTransparency == .215 and legacy.ImageTransparency == .25,
    "one hundred percent restores exact authored component transparency")
replay({[legacyKey] = relativeLegacy}, {[legacyKey] = oldEntry})
check(legacy.BackgroundTransparency == .7 and legacy.ImageTransparency == .25, "releasing the relative claim reveals the saved legacy background")
replay({[legacyKey] = oldEntry}, {[legacyKey] = relativeLegacy})
check(legacy.BackgroundTransparency == .215, "redo restores the authored-relative appearance and keeps legacy data")

screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local canvasGroup = object("CanvasGroup", "Group compositor", screen, 670, 180, 180, 60)
canvasGroup.BackgroundTransparency, canvasGroup.GroupTransparency = 1, .2
local groupImage = object("ImageButton", "Group image", canvasGroup, 10, 5, 40, 48)
groupImage.Image, groupImage.ImageTransparency, groupImage.BackgroundTransparency = "rbxassetid://1", .25, 1
local groupText = object("TextLabel", "Group label", canvasGroup, 60, 5, 56, 48)
groupText.Text, groupText.TextTransparency, groupText.TextStrokeTransparency = "Power", .1, .6
groupText.BackgroundTransparency = 1
local groupStroke = object("UIStroke", "Outline", groupText)
groupStroke.Transparency, groupStroke.Thickness, groupStroke.ApplyStrokeMode = .3, 2, Enum.ApplyStrokeMode.Border
discovery:refresh()
local groupKey, imageKey = key(canvasGroup), key(groupImage)
local composite = applyFade({groupKey, imageKey}, "contents", .5)
check(#composite.groups == 1 and transparency(canvasGroup.GroupTransparency, .6) and groupImage.ImageTransparency == .25,
    "one gesture prunes nested selections and fades an existing CanvasGroup once")
local onlyParent = transform:capture()
applyFade({imageKey}, "element", .25)
local nested = transform:capture()
check(canvasGroup.GroupTransparency == .2 and transparency(groupImage.ImageTransparency, .8125),
    "a specific nested choice replaces its parent factor without multiplying native composites")
check(transparency(groupText.TextTransparency, .55) and transparency(groupText.TextStrokeTransparency, .8)
    and transparency(groupStroke.Transparency, .65), "sibling text, text outline and UIStroke retain the parent fade")
replay(nested, onlyParent)
check(transparency(canvasGroup.GroupTransparency, .6) and groupImage.ImageTransparency == .25
    and groupText.TextTransparency == .1 and groupStroke.Transparency == .3,
    "undo of the nested override recomposes the original CanvasGroup without stale surface edits")
replay(onlyParent, nested)
check(canvasGroup.GroupTransparency == .2 and transparency(groupImage.ImageTransparency, .8125), "redo reproduces the non-composited nested result")
transform:apply({}, {replace = true})
mock:flush()
check(canvasGroup.GroupTransparency == .2 and groupImage.ImageTransparency == .25
    and groupText.TextTransparency == .1 and groupStroke.Transparency == .3,
    "switching away from the profile restores coupled scopes and every authored component")
transform:destroy()
transform = Transform.new(discovery)
transform:apply(nested, {replace = true})
mock:flush()
check(canvasGroup.GroupTransparency == .2 and transparency(groupImage.ImageTransparency, .8125)
    and transparency(groupText.TextTransparency, .55), "cold profile replay computes the same most-specific appearance")
check(transform.pendingStabilization == nil, "cold nested replay has no pending rollback loop")

local missing = object("ImageButton", "Missing owner", screen, 80, 220, 40, 40)
missing.Image, missing.ImageTransparency, missing.BackgroundTransparency = "rbxassetid://1", .18, 1
discovery:refresh()
local missingKey = key(missing)
applyFade({missingKey}, "element", 0)
local beforeRemoval = transform:capture()
local withoutMissing = Util.copy(beforeRemoval)
withoutMissing[missingKey] = nil
missing:Destroy()
discovery:refresh()
replay(beforeRemoval, withoutMissing)
local replacement = object("ImageButton", "Missing owner", screen, 80, 220, 40, 40)
replacement.Image, replacement.ImageTransparency, replacement.BackgroundTransparency = "rbxassetid://1", .18, 1
discovery:refresh()
check(key(replacement) == missingKey and transform:capture()[missingKey] == nil
    and #transform:opacityTargets(missingKey) == 0, "reset of a missing owner forgets its latent portable entry and old receipts")
transform:apply(withoutMissing, {onlyNew = true})
mock:flush()
check(replacement.ImageTransparency == .18, "a recreated owner cannot inherit deliberately removed opacity")

transform:destroy()
check(next(transform.opacity.scopes) == nil and next(transform.opacity.claims) == nil, "destroy releases opacity ownership references")
discovery:destroy()
return checks
