local Appearance = require("Appearance")
local SmartLayers = require("SmartLayers")
local checks = 0

local function check(value, message)
    checks = checks + 1
    assert(value, message)
end

local function near(actual, expected, message)
    check(math.abs(actual - expected) < 0.00001, message)
end

local screen = {ZIndexBehavior = "Sibling"}
local discovery = {records = {}}
local lookups = 0
function discovery:get(key)
    lookups = lookups + 1
    return self.records[key]
end
function discovery:_metadata(object) return {strokes = object.strokes} end
local appearance = Appearance.new(discovery)

local function record(name, class, fields, parent)
    fields.Name, fields.ClassName, fields.Parent = name, class, parent and parent.object or screen
    local segment = name .. ":" .. class .. ":1"
    local key = parent and parent.key .. "/" .. segment or "HUD:ScreenGui:1/" .. segment
    local item = {object = fields, key = key, screen = screen, descriptor = {}, childKeys = {}, parentKey = parent and parent.key}
    item.baseline = {transparency = fields.BackgroundTransparency}
    if parent then parent.childKeys[#parent.childKeys + 1] = key end
    discovery.records[key] = item
    appearance:remember(item, fields.strokes)
    return item
end

local function target(plan, object, property)
    for _, item in ipairs(plan or {}) do if item.object == object and item.property == property then return item end end
end

local function renderPlan(plan, factor)
    for _, item in ipairs(plan) do item.object[item.property] = Appearance.value(item.original, factor) end
end

local root = record("AbilityBar", "Frame", {BackgroundTransparency = 1})
local image = record("AbilityOne", "ImageButton", {
    BackgroundTransparency = 1, Image = "rbxassetid://12", ImageTransparency = 0.22, Active = true, Interactable = true,
}, root)
local label = record("AbilityLabel", "TextLabel", {
    BackgroundTransparency = 0.35, Text = "Ability", TextTransparency = 0.1, TextStrokeTransparency = 0.7,
}, root)
local stroke = {Name = "Border", ClassName = "UIStroke", Parent = label.object, Thickness = 2,
    Transparency = 0.4, Enabled = true, ApplyStrokeMode = "Border"}
label.object.strokes = {stroke}
appearance:remember(label, label.object.strokes)

local unsupportedOwn = appearance:plan({root.key}, "element")
check(unsupportedOwn == nil, "An originally clear container advertises Include contents rather than no-op opacity")
local imagePlan = appearance:plan({image.key}, "element")
local imageOriginal = image.object.ImageTransparency
renderPlan(imagePlan, 0.5)
near(1 - image.object.ImageTransparency, (1 - imageOriginal) / 2, "Half opacity halves visible image alpha")
check(image.object.BackgroundTransparency == 1, "An originally invisible background stays invisible")
renderPlan(imagePlan, 0.5)
near(image.object.ImageTransparency, 0.61, "Reapplying the same percentage does not compound")
renderPlan(imagePlan, 0)
check(image.object.ImageTransparency == 1 and image.object.Active and image.object.Interactable and image.object.Parent == root.object,
    "A fully faded ability stays interactive, attached, and recoverable")
renderPlan(imagePlan, 1)
check(image.object.ImageTransparency == imageOriginal, "A 100-percent adjustment restores the exact original")
image.object.Image = ""
local clearedAsset = appearance:plan({image.key}, "element")
check(target(clearedAsset, image.object, "ImageTransparency") ~= nil,
    "Clearing a previously displayed texture does not drop its opacity or reset binding")
image.object.Image = "rbxassetid://12"
local late = record("LateImage", "ImageButton", {BackgroundTransparency = 1, Image = "", ImageTransparency = 0.2})
check(appearance:plan({late.key}, "element") == nil, "An unbound empty image does not claim an available visible effect")
check(target(appearance:plan({late.key}, "element", {targets = {late.key}}), late.object, "ImageTransparency") ~= nil,
    "An exact saved opacity can bind a recreated image before the asset is populated")
late.object.Image = "rbxassetid://13"
check(appearance:hasNewContent(late) and appearance:plan({late.key}, "element") ~= nil,
    "A late-loaded image makes its opacity operation available")
local editableImage = record("PaintedAsset", "ImageLabel", {
    BackgroundTransparency = 1, Image = "", ImageContent = {Object = {}}, ImageTransparency = 0.2,
})
check(SmartLayers.painted(editableImage.object) and target(appearance:plan({editableImage.key}, "element"), editableImage.object, "ImageTransparency"),
    "ImageContent-backed artwork participates in selection and opacity even without a legacy Image URI")

local childrenPlan, _, scope = appearance:plan({root.key, image.key}, "contents")
check(scope.layers == 3 and #scope.targets == 2, "Including contents handles selected nesting without duplicate layers")
check(target(childrenPlan, label.object, "TextTransparency") and target(childrenPlan, label.object, "TextStrokeTransparency")
    and target(childrenPlan, stroke, "Transparency"), "The contents scope finds supported text, text outline, and UIStroke components")
renderPlan(childrenPlan, 0.5)
near(1 - label.object.BackgroundTransparency, (1 - 0.35) * 0.5, "Background paint loses the requested fraction of authored alpha")
near(1 - label.object.TextTransparency, (1 - 0.1) * 0.5, "Text paint has its own baseline")
near(1 - label.object.TextStrokeTransparency, (1 - 0.7) * 0.5, "Text outline keeps its original proportion")
near(1 - stroke.Transparency, (1 - 0.4) * 0.5, "Existing UIStroke paint fades independently")
renderPlan(childrenPlan, 1)
check(label.object.TextStrokeTransparency == 0.7 and stroke.Transparency == 0.4, "Reset leaves stroke and text opacity exactly as authored")

local group = record("Blend", "CanvasGroup", {BackgroundTransparency = 1, GroupTransparency = 0.2})
local nestedGroup = record("NestedBlend", "CanvasGroup", {BackgroundTransparency = 1, GroupTransparency = 0.25}, group)
local groupMember = record("Member", "ImageLabel", {BackgroundTransparency = 1, Image = "rbxassetid://16", ImageTransparency = 0.4}, nestedGroup)
local groupPlan = appearance:plan({group.key, nestedGroup.key, groupMember.key}, "contents")
check(#groupPlan == 1 and groupPlan[1].object == group.object and groupPlan[1].contents,
    "A supported CanvasGroup fades the existing composite exactly once")
renderPlan(groupPlan, 0.5)
near((1 - group.object.GroupTransparency) * (1 - nestedGroup.object.GroupTransparency) * (1 - groupMember.object.ImageTransparency),
    (1 - 0.2) * (1 - 0.25) * (1 - 0.4) * 0.5, "Nested group composition does not double-fade visual content")
local lockedPlan = appearance:plan({group.key}, "contents", {canEdit = function(item) return item ~= groupMember end})
check(lockedPlan == nil and groupMember.object.Parent == nestedGroup.object, "A compositor may not fade indirectly locked descendants")
renderPlan(groupPlan, 1)
local flattened = appearance:flattenGroup(group.key)
check(target(flattened, groupMember.object, "ImageTransparency") and not target(flattened, nestedGroup.object, "GroupTransparency")
    and not target(flattened, group.object, "GroupTransparency"), "Flattening an overlapping compositor uses authored descendant components only")
local restrictedFlat = appearance:plan({group.key}, "contents", {targets = {group.key}, flattenGroups = {[group.key] = true}})
check(target(restrictedFlat, groupMember.object, "ImageTransparency") ~= nil,
    "A saved compositor's recorded owner can expand its already-authorized contents when overlap requires direct surfaces")
screen.ZIndexBehavior = "Global"
local individualFallback = appearance:plan({group.key}, "contents")
check(not target(individualFallback, group.object, "GroupTransparency") and target(individualFallback, groupMember.object, "ImageTransparency"),
    "The helper falls back to property-aware contents when the CanvasGroup compositor is unavailable")
screen.ZIndexBehavior = "Sibling"
local priorDirect = appearance:plan({group.key}, "contents", {targets = {group.key, groupMember.key}})
check(target(priorDirect, groupMember.object, "ImageTransparency") and not target(priorDirect, group.object, "GroupTransparency"),
    "Exact direct members do not become a new compositor after a screen layering change")

local future = record("NewPanel", "Frame", {BackgroundTransparency = 0.25}, root)
local exact, _, exactInfo = appearance:plan({root.key}, "contents", {targets = {image.key, root.key .. "/Missing:Frame:1"}})
check(target(exact, image.object, "ImageTransparency") and not target(exact, future.object, "BackgroundTransparency") and exactInfo.missing == 1,
    "Exact replay skips new descendants and reports a missing target while keeping a compatible one")
local vacant, _, vacancy = appearance:plan({root.key}, "contents", {targets = {root.key .. "/Missing:Frame:1"}})
check(#vacant == 0 and vacancy.missing == 1, "A lost saved scope has no writes")
for index = 1, Appearance.MAX_LAYERS do record("Extra" .. index, "Frame", {BackgroundTransparency = 0}, root) end
check(appearance:plan({root.key}, "contents") == nil, "Large live subtrees are refused before any write")
local beforeExact = lookups
check(appearance:plan({root.key}, "contents", {targets = {image.key}}) ~= nil,
    "Previously recorded exact members can replay inside a now-large subtree")
check(lookups - beforeExact == 2, "Exact replay only resolves the root and the authorized child")

local recreated = record("AbilityOne", "ImageButton", {BackgroundTransparency = 1, Image = "rbxassetid://12", ImageTransparency = 0.4}, root)
local replay = appearance:plan({root.key}, "contents", {targets = {image.key}})
renderPlan(replay, 0.5)
check(recreated.key == image.key and target(replay, recreated.object, "ImageTransparency") ~= nil,
    "A recreated exact layer uses its new instance and authored baseline")
near(recreated.object.ImageTransparency, 0.7, "A recreated component uses the saved relative factor and its own original alpha")

if Appearance.value(0.2, 1) ~= 0.2 then error("Exact authored value was lost") end
return checks
