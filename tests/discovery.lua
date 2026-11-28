-- Simulates the documented Roblox coordinate spaces and accessible PlayerGui API.
local Coordinates = require("Coordinates")
local Discovery = require("Discovery")
local checks = 0

local function check(value, message)
    checks = checks + 1
    assert(value, message)
end

local pending = {}
task = {delay = function(_, callback) pending[#pending + 1] = callback end}
local function flush()
    local queue = pending
    pending = {}
    for _, callback in ipairs(queue) do callback() end
end

local function signal()
    local listeners = {}
    return {
        Connect = function(_, callback)
            local subscription = {live = true, Disconnect = function(self) self.live = false end}
            listeners[#listeners + 1] = {callback, subscription}
            return subscription
        end,
        Fire = function(_, value)
            for _, item in ipairs(listeners) do if item[2].live then item[1](value) end end
        end,
    }
end

local enumerations, descendantScans = 0, 0
local classes = {Frame = true, CanvasGroup = true, ImageButton = true, ImageLabel = true, TextButton = true, TextLabel = true, ScrollingFrame = true}
local dim = {X = {Scale = 0, Offset = 0}, Y = {Scale = 0, Offset = 0}}
local function create(class, name, parent, x, y, w, h)
    local object = {
        ClassName = class, Name = name, Parent = parent, Visible = true, Enabled = true, Rotation = 0,
        BackgroundTransparency = 0, AutomaticSize = "None", Position = dim, Size = dim, ZIndex = 1, DisplayOrder = 0,
        ClipsDescendants = false, ClipToDeviceSafeArea = true, DescendantAdded = signal(), DescendantRemoving = signal(),
        AbsolutePosition = {X = x or 0, Y = y or 0}, AbsoluteSize = {X = w or 1000, Y = h or 570}, props = {}, children = {},
    }
    function object:IsA(kind)
        return kind == self.ClassName or kind == "GuiObject" and classes[self.ClassName]
            or kind == "GuiButton" and (self.ClassName == "ImageButton" or self.ClassName == "TextButton")
            or kind == "LayerCollector" and (self.ClassName == "ScreenGui" or self.ClassName == "SurfaceGui")
    end
    function object:GetChildren()
        enumerations = enumerations + 1
        return self.children
    end
    function object:GetDescendants()
        descendantScans = descendantScans + 1
        local result = {}
        local function visit(node)
            for _, child in ipairs(node.children) do
                result[#result + 1] = child
                visit(child)
            end
        end
        visit(self)
        return result
    end
    function object:GetPropertyChangedSignal(property)
        self.props[property] = self.props[property] or signal()
        return self.props[property]
    end
    if parent then parent.children[#parent.children + 1] = object end
    return object
end

Enum = {ScreenInsets = {CoreUISafeInsets = "CoreUISafeInsets", DeviceSafeInsets = "DeviceSafeInsets", None = "None"}}
local area = {
    CoreUISafeInsets = {Min = {X = 0, Y = 0}, Max = {X = 1000, Y = 570}},
    DeviceSafeInsets = {Min = {X = 0, Y = -44}, Max = {X = 1000, Y = 570}},
    None = {Min = {X = -16, Y = -44}, Max = {X = 1016, Y = 570}},
}
local services = {
    GetInsetArea = function(_, inset) return area[inset] end,
    GetGuiInset = function() return {X = 16, Y = 44}, {X = 16, Y = 0} end,
}
local rawPointer = {Position = {X = 24, Y = -10}}
local pointer = Coordinates.point(rawPointer)
check(pointer.x == 24 and pointer.y == -10, "Input positions are already inset-relative, including negative coordinates")
local fullRect = Coordinates.insetRect(services, Enum.ScreenInsets.None)
check(fullRect.x == -16 and fullRect.y == -44 and fullRect.w == 1032, "Full screen origin and width can differ from ViewportSize")
local safe = Coordinates.safeRect(services, 300, 350)
local core = Coordinates.coreRect(services, 300, 350)
check(safe.y == -44 and core.y == 0 and core.h == 570, "Editor safe area and device-safe viewport stay distinct")
local fallback = Coordinates.safeRect({GetGuiInset = services.GetGuiInset}, 1000, 614)
check(fallback.y == -44 and fallback.w == 1000 and fallback.h == 614, "Viewport fallback does not subtract cutouts a second time")

local root = create("PlayerGui", "PlayerGui")
local touch = create("ScreenGui", "TouchGui", root)
local touchFrame = create("Frame", "TouchControlFrame", touch)
touchFrame.BackgroundTransparency = 1
local jump = create("ImageButton", "JumpButton", touchFrame, 875, 450, 82, 82)
local decoration = create("TextLabel", "Decorative overlay", touchFrame, 875, 450, 82, 82)
local classic = create("Frame", "ThumbstickFrame", touchFrame, 79, 434, 100, 100)
local dynamic = create("Frame", "DynamicThumbstickFrame", touchFrame, 0, 330, 400, 220)
dynamic.BackgroundTransparency = 1
create("ImageButton", "Knob", dynamic, 20, 365, 20, 20).Visible = false
local gameGui = create("ScreenGui", "GameHud", root)
local actual = create("ImageButton", "Game button", gameGui, 180, 420, 60, 50)
local ground = create("Frame", "Bottom layer", gameGui, 450, 280, 190, 150)
local front = create("Frame", "Higher sibling layer", gameGui, 450, 280, 190, 150)
front.ZIndex = 2
local bottomButton = create("ImageButton", "Deep high Z", ground, 500, 345, 40, 30)
bottomButton.ZIndex = 100
local topButton = create("ImageButton", "Lower Z in front branch", front, 500, 345, 40, 30)
local rotatedButton = create("ImageButton", "Rotated", gameGui, 500, 245, 100, 20)
rotatedButton.AbsoluteRotation = 90
local hiddenParent = create("Frame", "Hidden", gameGui, 175, 410, 75, 60)
hiddenParent.Visible = false
local hiddenButton = create("ImageButton", "Hidden child", hiddenParent, 180, 420, 60, 50)
local clip = create("ScrollingFrame", "Clip", gameGui, 300, 200, 100, 60)
clip.ClipsDescendants = true
clip.AbsoluteWindowSize = {X = 90, Y = 60}
clip.VerticalScrollBarPosition = "Enum.VerticalScrollBarPosition.Left"
local clippedChild = create("ImageButton", "Partly clipped", clip, 280, 205, 65, 90)
local hud = create("ScreenGui", "DeviceSafeHud", root, 0, -44, 1000, 614)
hud.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
hud.DisplayOrder = 4
local upper = create("TextButton", "Above top bar area", hud, 18, -25, 38, 40)
local full = create("ScreenGui", "FullScreenHud", root, -16, -44, 1032, 614)
full.ScreenInsets = Enum.ScreenInsets.None
local nearCutout = create("TextButton", "Cutout content", full, -14, 280, 10, 10)
local wrongClip = create("TextButton", "Device-clipped", hud, -14, 280, 10, 10)
local editor = create("ScreenGui", "HeavenlyAxis_V3", root)
local own = create("TextButton", "Editor", editor, 875, 450, 82, 82)
local unsupportedWorld = create("SurfaceGui", "World", root)
create("ImageButton", "World button", unsupportedWorld, 875, 450, 82, 82)
local nestedWorld = create("SurfaceGui", "Nested world", gameGui)
local worldButton = create("ImageButton", "3D coordinates", nestedWorld, 875, 450, 82, 82)
local folder = create("Folder", "Nested HUD", root)
local folderGui = create("ScreenGui", "FolderGui", folder)
local folderButton = create("TextButton", "Folder button", folderGui, 600, 440, 48, 48)
local oldOwner = create("Frame", "Old owner", gameGui, 660, 440, 50, 50)
local newOwner = create("Frame", "New owner", gameGui, 720, 440, 50, 50)
local oldMember = create("Frame", "Old member", oldOwner, 665, 445, 35, 35)
local newMember = create("Frame", "New member", newOwner, 725, 445, 35, 35)
local layout = create("UIListLayout", "Move within PlayerGui", oldOwner)
local tableOwner = create("Frame", "Table owner", gameGui, 660, 310, 70, 90)
local tableRow = create("Frame", "Row", tableOwner, 660, 310, 70, 90)
local tableCell = create("TextButton", "Cell", tableRow, 665, 325, 40, 45)
local tableLayout = create("UITableLayout", "Table", tableOwner)
local underSmart = create("TextButton", "BehindSmart", gameGui, 735, 165, 50, 46)
local actionable = create("ImageButton", "AbilityIcon", gameGui, 735, 165, 50, 46)
actionable.BackgroundTransparency = 1
local icon = create("ImageLabel", "Spell_Art", actionable, 735, 165, 50, 46)
icon.BackgroundTransparency, icon.Image, icon.ImageTransparency = 1, "rbxassetid://1", 0
local invisibleText = create("TextLabel", "Invisible Tooltip", gameGui, 735, 165, 50, 46)
invisibleText.BackgroundTransparency, invisibleText.Text, invisibleText.TextTransparency = 1, "Tooltip", 1
invisibleText.TextStrokeTransparency = 1
local hiddenOverlay = create("TextLabel", "Hidden tooltip", gameGui, 735, 165, 50, 46)
hiddenOverlay.Visible = false
local tapZone = create("TextButton", "EmptyAction", gameGui, 790, 165, 45, 45)
tapZone.BackgroundTransparency, tapZone.Active = 1, true
local framed = create("Frame", "Border Only", gameGui, 840, 165, 48, 48)
framed.BackgroundTransparency = 1
local stroke = create("UIStroke", "Outline", framed)
stroke.Thickness, stroke.Transparency, stroke.ApplyStrokeMode, stroke.Enabled = 2, 0.3, "Border", true
local blend = create("CanvasGroup", "Floating blend", gameGui, 40, 120, 46, 46)
blend.GroupTransparency = 0.25
local blendChild = create("ImageLabel", "Blend member", blend, 40, 120, 40, 40)
local controls = create("Frame", "Large collection", gameGui, 300, 0, 450, 200)
for index = 1, 500 do
    create("Frame", "Control " .. index, controls, 400 + index % 220, 10 + index % 100, 1, 1)
end

local discovery = Discovery.new(root, nil, nil, services)
local revisions = {}
discovery:start(function(reason) revisions[#revisions + 1] = reason end)
local function record(object) return discovery.byObject[object] end
local function found(records, object)
    for _, item in ipairs(records) do if item.object == object then return true end end
    return false
end

check(descendantScans == 1 and discovery.stats.indexed >= 500 and enumerations < discovery.stats.indexed + 30,
    "Discovery scans once and enumerates broad siblings once per parent")
check(discovery:match(record(jump).descriptor) == record(jump), "Exact identity matches by key")
check(record(jump).baselineRect.w == 82 and record(hiddenButton).baselineRect == nil, "Baseline records initial usable geometry")
check(record(own) == nil, "Editor ScreenGui and its descendants stay outside discovery")
check(record(worldButton) == nil, "World-space layers within a ScreenGui still use a different coordinate space")
local x, y = Coordinates.screenToLocal(pointer.x, pointer.y, hud)
check(x == 24 and y == 34, "Canonical coordinates map to the destination ScreenGui origin")
check(Coordinates.rect(upper).y == -25 and discovery:hit(pointer.x, pointer.y)[1] == record(upper), "Fallback finds a device-inset button in negative canonical Y")
local hits = discovery:hit(-10, 285)
check(hits[1] == record(nearCutout) and not found(hits, wrongClip), "Explicit None ignores device clipping while device-safe content respects it")
hits = discovery:hit(900, 470)
check(hits[1] == record(jump) and found(hits, decoration) and found(hits, touchFrame), "Fallback prioritizes Jump while retaining explicit overlaps")
local emptyHits, primary = discovery:hit(850, 260)
check(primary == false and found(emptyHits, touchFrame), "Blank-canvas taps can clear selection while retaining explicit parent matches")
local _, topControl = discovery:hit(900, 470)
check(topControl == record(jump), "A populated tap recommends Jump")
hits = discovery:hit(205, 450)
check(hits[1] == record(actual) and found(hits, dynamic) and not found(hits, hiddenButton), "Interactive leaf beats broad dynamic zone and hidden descendants stay excluded")
dynamic.BackgroundTransparency = 0.4
check(discovery:hit(205, 450)[1] == record(actual), "Styling the dynamic-stick input zone does not make it swallow overlapping buttons")
dynamic.BackgroundTransparency = 1
check(discovery:hit(100, 470)[1] == record(classic), "Classic joystick wins against the surrounding dynamic zone")
check(discovery:hit(515, 355)[1] == record(topButton), "Fallback sibling mode respects the top-level branch before child ZIndex")
gameGui.ZIndexBehavior = "Global"
check(discovery:hit(515, 355)[1] == record(bottomButton), "Fallback global mode respects the individual object's ZIndex")
check(found(discovery:hit(550, 223), rotatedButton) and not found(discovery:hit(518, 253), rotatedButton), "Fallback respects a rotated object's screen footprint")
rotatedButton.Rotation = 90
local rotatedCaps = discovery:get(record(rotatedButton).key).capabilities
check(rotatedCaps.move.supported and rotatedCaps.rotationHandle.supported and rotatedCaps.groupRotate.supported
    and not rotatedCaps.resize.supported, "A locally rotated layer keeps independent movement and direct rotation")
check(found(discovery:hit(315, 225), clippedChild), "Fallback finds a partially visible scroll child")
check(not found(discovery:hit(304, 225), clippedChild) and not found(discovery:hit(315, 270), clippedChild), "Scroll gutter and clipped portion are excluded")
local visible = discovery:visibleRect(record(clippedChild))
check(visible.x == 310 and visible.w == 35 and visible.h == 55, "Visible bounds crop at scroll content rather than raw geometry")

local nativeX, nativeY
function root:GetGuiObjectsAtPosition(queryX, queryY)
    nativeX, nativeY = queryX, queryY
    if queryY < 0 then return {upper} end
    if queryX < 400 then return {clippedChild, clip} end
    return {own, touchFrame, decoration, jump, jump}
end
hits = discovery:hit(900.2, 470.8)
check(nativeX == 900 and nativeY == 470 and #hits == 3 and hits[1] == record(jump), "Native query keeps canonical position and resolves duplicates and layers")
check(discovery:hit(pointer.x, pointer.y)[1] == record(upper) and nativeY == -10, "Native query uses the same negative canonical Y without a second inset")
check(found(discovery:hit(315, 225), clippedChild) and not found(discovery:hit(304, 225), clippedChild),
    "Native candidates still honor the visible scrolling region")
check(#discovery:alignmentRects({record(touchFrame).key}, Coordinates.rect(jump), 8) == 8, "Gesture guides use bounded nearby candidates")
local nearby = discovery:alignmentRects({}, Coordinates.rect(upper), 1)
check(#nearby == 1 and nearby[1].x == upper.AbsolutePosition.X and nearby[1].y == upper.AbsolutePosition.Y, "Guides prefer nearby targets")
local afterRefresh = enumerations
for _ = 1, 120 do discovery:_classify(record(jump)) end
check(enumerations == afterRefresh and descendantScans == 1, "Repeated target classification uses cached topology without traversals")

hud.Enabled = false
hud.props.Enabled:Fire()
hud.props.Enabled:Fire()
flush()
check(#revisions == 2 and revisions[2] == "presentation" and descendantScans == 1, "Visibility notifications coalesce without a structural scan")
check(#discovery:hit(pointer.x, pointer.y) == 0 and not found(discovery:list(), upper), "Disabled ScreenGui hides native hits and element list entries")
touchFrame.Rotation = 12
touchFrame.props.Rotation:Fire()
flush()
local rotationCaps = discovery:get(record(jump).key).capabilities
check(not rotationCaps.move.supported and not rotationCaps.resize.supported and not rotationCaps.rotationHandle.supported
    and rotationCaps.rotation.supported and rotationCaps.visual.supported,
    "Ancestor rotation blocks screen geometry while compatible visual editing remains available")
touchFrame.Rotation = 0
touchFrame.props.Rotation:Fire()
flush()
check(discovery:get(record(jump).key).editable, "Clearing ancestor rotation restores compatibility")
local revisionsBefore = #revisions
local style = create("UICorner", "Style only", folderButton)
root.DescendantAdded:Fire(style)
flush()
check(descendantScans == 1 and #revisions == revisionsBefore, "A visual-only descendant does not rescan the HUD")
local listCaps = discovery:get(record(oldMember).key).capabilities
check(not listCaps.move.supported and listCaps.resize.supported and listCaps.transparency.supported
    and not listCaps.rotation.supported and not listCaps.groupResize.supported and not record(oldMember).experimental,
    "A plain list owns child position and rotation while keeping independent size and transparency")
local cellCaps = discovery:get(record(tableCell).key).capabilities
check(record(tableCell).layoutController == tableLayout and not cellCaps.move.supported and not cellCaps.resize.supported
    and cellCaps.visual.supported, "UITableLayout also owns its grandchildren's table cells")
table.remove(oldOwner.children, 2)
newOwner.children[#newOwner.children + 1] = layout
layout.Parent = newOwner
layout.props.Parent:Fire()
flush()
check(discovery:get(record(oldMember).key).capabilities.move.supported and not discovery:get(record(newMember).key).capabilities.move.supported
    and descendantScans == 1, "A layout moved within PlayerGui updates both owners without a tree scan")
layout.HorizontalFlex = "Fill"
layout.props.HorizontalFlex:Fire()
flush()
check(not discovery:get(record(newMember).key).capabilities.resize.supported and descendantScans == 1,
    "Changing flex mode updates independent resize compatibility without a tree scan")
table.remove(newOwner.children, 2)
layout.Parent = nil
root.DescendantRemoving:Fire(layout)
flush()
check(discovery:get(record(newMember).key).capabilities.move.supported and descendantScans == 1,
    "Deferred removal invalidates layout metadata even after Parent was cleared")
local duplicateFolder = create("Folder", folder.Name, root)
root.DescendantAdded:Fire(duplicateFolder)
flush()
check(record(folderButton).descriptor.ambiguous, "An empty same-name folder still invalidates an indexed hierarchy")
table.remove(root.children)
duplicateFolder.Parent = nil
root.DescendantRemoving:Fire(duplicateFolder)
flush()
check(not record(folderButton).descriptor.ambiguous, "Removing the duplicate folder restores the indexed hierarchy")
local oldKey = record(actual).key
for index, child in ipairs(gameGui.children) do
    if child == actual then table.remove(gameGui.children, index); break end
end
front.children[#front.children + 1] = actual
actual.Parent = front
check(discovery:get(oldKey) == nil, "Reparenting inside PlayerGui cannot resolve the stale saved hierarchy")
flush()
check(record(actual).key ~= oldKey and discovery:match(record(actual).descriptor) == record(actual), "Reparented objects acquire their new exact identity")
root.GetGuiObjectsAtPosition = nil
local smartHits, ordinary = discovery:hit(752, 180)
check(ordinary == record(actionable) and found(smartHits, icon) and found(smartHits, invisibleText),
    "Smart Selection promotes an actionable control over its icon and skips invisible decoration")
check(record(actionable).displayName == "Ability Icon" and record(actionable).typeIcon == "BTN"
    and record(icon).parentKey == record(actionable).key and record(actionable).childKeys[1] == record(icon).key,
    "Layers expose friendly names, type icons, and navigable parent-child relationships")
local _, compactPick = discovery:hit(805, 185)
local _, strokePick = discovery:hit(841, 167)
check(compactPick == record(tapZone) and strokePick == record(framed),
    "A compact transparent action and a border painted by UIStroke remain selectable")
hud.Enabled = true
local all = discovery:list("all")
check(found(all, hiddenOverlay) and record(hiddenOverlay).visibility == "hidden"
    and record(invisibleText).visibility == "transparent" and record(actionable).visibility == "container"
    and record(wrongClip).visibility == "clipped", "Layers distinguish hidden, transparent, clipped, and painted-child containers")
function root:GetGuiObjectsAtPosition()
    return {icon, actionable, invisibleText, underSmart}
end
check(found(discovery:hitThrough(752, 180), hiddenOverlay), "Explicit inspection adds hidden candidates omitted by native hit testing")
local ignoredKey, lockedKey = record(actionable).key, record(underSmart).key
discovery:setSelectionPolicy({ignored = {[ignoredKey] = true}, locked = {[lockedKey] = true}})
local _, beneath = discovery:hit(752, 180)
check(beneath == record(underSmart) and record(actionable).ignored and record(underSmart).locked,
    "Ignore skips an actionable subtree's tap decoration while Lock leaves the underneath layer inspectable")
check(found(discovery:list("ignored"), actionable) and found(discovery:list("locked"), underSmart)
    and not found(discovery:list("editable"), underSmart) and actionable.Visible and icon.ImageTransparency == 0,
    "Rules remain explicit and do not modify Roblox presentation")
discovery:setSelectionPolicy({smartSelection = false})
local _, nativeFront = discovery:hit(752, 180)
check(nativeFront == record(icon), "Disabling Smart Selection restores native layer ordering")
root.GetGuiObjectsAtPosition = nil
discovery:setSelectionPolicy({skipTransparent = false})
local _, unfiltered = discovery:hit(850, 260)
check(unfiltered == record(touchFrame), "Disabling transparent filtering makes a transparent structural layer directly selectable")
local noticeCount = #revisions
for _, alpha in ipairs({0.3, 0.6, 0.9}) do
    blend.GroupTransparency = alpha
    blend.props.GroupTransparency:Fire()
end
flush()
check(#revisions == noticeCount, "CanvasGroup opacity drag updates do not refresh Layers while visibility stays the same")
blend.GroupTransparency = 1
blend.props.GroupTransparency:Fire()
flush()
check(#revisions == noticeCount + 1 and found(discovery:list("all"), blendChild) and record(blendChild).visibility == "hidden",
    "Crossing fully faded refreshes layer visibility but keeps descendants available for recovery")
local firstSubscription = discovery.objectConnections[upper][1]
discovery:destroy()
check(not firstSubscription.live, "Discovery destroy disconnects retained GUI subscriptions")
return checks
