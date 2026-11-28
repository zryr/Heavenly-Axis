-- Execute the shipped script with public Roblox API mocks. Rendering and native input dispatch require Studio.
local Roblox = require("support/Roblox")
local buildVersion = require("App").VERSION
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local externalRequire, initialGame, initialGetgenv, initialTask, initialWarn = require, game, getgenv, task, warn
local opened, safed = 0, 0
local singleton = { alive = true, version = buildVersion }
function singleton:Open() opened = opened + 1 end
function singleton:SafeMode() safed = safed + 1 end
local env = { __HEAVENLY_AXIS_V3 = singleton }
getgenv = function() return env end
require = function() error("release must not call global require") end
game = setmetatable({}, { __index = function() error("duplicate release must not call Roblox APIs") end })
local release = assert(loadfile("dist/HeavenlyAxis.lua"))
check(release() == singleton and opened == 1, "self-contained release loads private modules and reopens existing singleton")
env.HeavenlyAxisOptions = { LoaderOnly = true }
check(release() == singleton and opened == 1, "self-contained loader run reuses singleton without UI creation")
env.HeavenlyAxisOptions = { SafeMode = true }
check(release() == singleton and safed == 1, "self-contained Safe Mode run delegates to singleton")
local source = assert(loadfile("Source"))
env.HeavenlyAxisOptions = nil
check(source() == singleton and opened == 2, "legacy Source entry is also self-contained and duplicate-safe")
local upgradeNotice
warn = function(message) upgradeNotice = message end
singleton.version = "0.0.0"
check(release() == singleton and opened == 3 and upgradeNotice and upgradeNotice:find(buildVersion, 1, true),
    "upgrading preserves the running session and reports when the shipped version will start")

local mock = Roblox.new(960, 440)
local warnings = {}
game, task = mock.game, mock.task
warn = function(message) warnings[#warnings + 1] = tostring(message) end

local function make(class, name, parent)
    local object = Instance.new(class)
    object.Name, object.Parent = name, parent
    return object
end

local hud = make("ScreenGui", "TouchGui", mock.playerGui)
local container = make("Frame", "TouchControlFrame", hud)
container.BackgroundTransparency, container.Size = 1, UDim2.fromScale(1, 1)
local jump = make("ImageButton", "JumpButton", container)
jump.Position, jump.Size = UDim2.fromOffset(762, 274), UDim2.fromOffset(96, 96)
local overlay = make("Frame", "Transparent overlay", container)
overlay.Position, overlay.Size, overlay.BackgroundTransparency, overlay.ZIndex = jump.Position, jump.Size, 1, 31
local auxiliary = make("TextButton", "Interact", container)
auxiliary.Position, auxiliary.Size, auxiliary.Text = UDim2.fromOffset(535, 230), UDim2.fromOffset(75, 54), "Interact"
local origin = jump.AbsolutePosition

-- Opaque tokens stand in for Roblox JSON. Profile validation and storage readback use shipped code.
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local tokens = {}
function mock.services.HttpService:JSONEncode(value)
    tokens[#tokens + 1] = copy(value)
    return string.format('{"stubJSON":%d}', #tokens)
end
function mock.services.HttpService:JSONDecode(text)
    return copy(assert(tokens[tonumber(text:match('^%{"stubJSON":(%d+)%}$'))], "Unknown mock JSON token"))
end

local function skipTutorial(editor)
    local tutorial = editor.ui.onboarding
    check(tutorial and tutorial:isActive(), "fresh editor opens its isolated welcome")
    tutorial.skip.Activated:Fire()
    mock:flush()
    check(editor:hasSeenTutorial() and not tutorial:isActive() and #editor.history.past == 0 and not editor.dirty,
        "Skip records tutorial progress separately from the layout and undo history")
end

-- Standard LocalScripts have the shared _G session and no executor file helpers.
getgenv = nil
local studio = release()
mock:flush()
check(studio and studio == _G.__HEAVENLY_AXIS_V3 and studio.editing and studio.ui.toolbar.Visible,
    "fresh LocalScript path constructs the actual editor: " .. table.concat(warnings, " | "))
skipTutorial(studio)
local durable, _, accepted = studio:save()
check(not durable and accepted and studio:VerifyStartup().storage == "Unsupported" and type(studio:export()) == "string",
    "fresh LocalScript Save reports an in-memory checkpoint with export available")
studio:Destroy()
mock:flush()
check(mock.activeConnections == 0 and _G.__HEAVENLY_AXIS_V3 == nil, "LocalScript teardown clears session and connections")

local files = {}
env = {
    isfile = function(path) return files[path] ~= nil end,
    readfile = function(path) return assert(files[path], path) end,
    writefile = function(path, text) files[path] = text end,
    delfile = function(path) files[path] = nil end,
}
getgenv = function() return env end
local app = release()
mock:flush()
check(app and app == env.__HEAVENLY_AXIS_V3 and app.editing and app.ui.canvas.Visible and not app.ui.panel.Visible,
    "fresh shared-environment bundle starts on a clear mobile editing canvas: " .. table.concat(warnings, " | "))
check(app.version == buildVersion, "shipped and maintained application versions agree")
local ui = app.ui
skipTutorial(app)
local connections = mock.activeConnections
check(release() == app and app.ui == ui and mock.activeConnections == connections,
    "fresh session protects the actual UI from duplicate initialization")

local input = mock.services.UserInputService
local function begin(object, x, y)
    local position, size = object.AbsolutePosition, object.AbsoluteSize
    local pointer = {UserInputType = Enum.UserInputType.Touch,
        Position = mock.vec(x or position.X + size.X / 2, y or position.Y + size.Y / 2)}
    object.InputBegan:Fire(pointer)
    return pointer
end
local function move(pointer, dx, dy)
    pointer.Position = mock.vec(pointer.Position.X + dx, pointer.Position.Y + dy)
    input.InputChanged:Fire(pointer)
end
local function releasePointer(pointer)
    input.InputEnded:Fire(pointer)
    mock:flush()
end
local function jumpPointer()
    local position, size = jump.AbsolutePosition, jump.AbsoluteSize
    return begin(ui.canvas, position.X + size.X / 2, position.Y + size.Y / 2)
end
local function action(name)
    for _, item in ipairs(ui.modalGui:GetDescendants()) do
        if item:IsA("TextButton") and item.Text == name then
            item.Activated:Fire()
            mock:flush()
            return
        end
    end
    error("Dialog action missing: " .. name)
end

releasePointer(jumpPointer())
local key = app.selection[1]
check(key and app.discovery:get(key).object == jump and ui.panel.Visible and #app.history.past == 0,
    "canvas tap chooses JumpButton over its structural parent and opens Quick Edit without history")
check(ui.selectionBounds.AbsolutePosition.X == origin.X and ui.selectionBounds.AbsolutePosition.Y == origin.Y,
    "selection outline and target agree in a mock nonzero overlay origin")

do
    check(app:armSelectThrough(), "the dedicated Select Through action arms one canvas tap")
    releasePointer(jumpPointer())
    check(ui.modalOpen and #ui.pickerRows >= 2 and app.selection[1] == key,
        "Select Through reveals deeper candidates without moving or selecting anything yet")
    local overlayKey
    for _, row in ipairs(ui.pickerRows) do
        if row.record.object == overlay then overlayKey = row.record.key; row.button.Activated:Fire(); break end
    end
    check(overlayKey and app.selection[1] == overlayKey and not ui.modalOpen,
        "explicit picker selects the transparent overlay for inspection")
    check(app:setLayerState(overlayKey, "ignored", true), "an accessible layer can be ignored from editor preferences")
    releasePointer(jumpPointer())
    check(app.selection[1] == key and overlay.BackgroundTransparency == 1 and overlay.Position.X.Offset == 762 and not app.dirty,
        "ignoring the overlay leaves the game object intact and keeps Jump selectable")
    check(files["HeavenlyAxis-v3.editor.json"] and not files["HeavenlyAxis-v3.json"],
        "layer rules and tutorial state are stored separately from HUD layouts")
end

local pointer = jumpPointer()
move(pointer, -36, 14)
releasePointer(pointer)
local editedPosition = jump.AbsolutePosition
check(editedPosition.X == origin.X - 36 and editedPosition.Y == origin.Y + 14 and #app.history.past == 1 and app.dirty,
    "touch drag writes and verifies a single live HUD transformation")
check(ui.selectionBounds.AbsolutePosition.X == editedPosition.X and ui.selectionBounds.AbsolutePosition.Y == editedPosition.Y,
    "selection outline follows verified movement")

local track, info = ui:sliderTrackRect(), app:sizeInfo()
local thumb = (info.scale - info.minimum) / (info.maximum - info.minimum)
pointer = begin(ui.slider, track.x + thumb * track.w, track.y + track.h / 2)
check(jump.AbsoluteSize.X == 96 and #app.history.past == 1, "pressing the relative size thumb is a no-op")
move(pointer, track.w * 0.18, 0)
releasePointer(pointer)
local savedSize = jump.AbsoluteSize.X
check(savedSize > 96 and savedSize == jump.AbsoluteSize.Y and jump.AbsolutePosition.X == editedPosition.X and #app.history.past == 2,
    "relative slider verifies a single anchored, aspect-preserving resize")

ui.saveButton.Activated:Fire()
local toast = ui.notifications
check(toast.frame.Visible and toast.current.kind == "success" and toast.title.Text == "Layout saved",
    "verified toolbar Save shows a short success notification")
ui.doneButton.Activated:Fire()
check(not app.editing and toast.frame.Visible and not toast.frame.Active,
    "Save confirmation remains visible without capturing gameplay after Done")
app:Open()
mock:flush()
check(not toast.frame.Visible, "the Save notification expires after reopening the editor")
local path = "HeavenlyAxis-v3.json"
local checkpoint = files[path]
check(checkpoint and not app.dirty and app:VerifyStartup().storage == "Supported and verified",
    "toolbar Save verifies local file readback and clears dirty state")
ui.undoButton.Activated:Fire()
mock:flush()
check(app.dirty and jump.AbsoluteSize.X == 96 and files[path] == checkpoint,
    "undo after Save verifies previous geometry while retaining the durable checkpoint")
ui.redoButton.Activated:Fire()
mock:flush()
check(not app.dirty and jump.AbsoluteSize.X == savedSize, "redo restores verified checkpoint geometry")

ui.doneButton.Activated:Fire()
check(not app.editing and not ui.canvas.Visible and ui.launcher.Visible, "clean Done returns to gameplay with the reopen launcher")
releasePointer(begin(ui.launcher))
check(app.editing and app.ui == ui and ui.panel.Visible, "launcher reopens the same editor and selection")

local pinchOrigin = jump.AbsolutePosition
pointer = begin(ui.canvas, pinchOrigin.X + savedSize * .25, pinchOrigin.Y + savedSize * .25)
local secondPointer = begin(ui.canvas, pinchOrigin.X + savedSize * .70, pinchOrigin.Y + savedSize * .70)
move(secondPointer, 14, 14)
releasePointer(secondPointer)
releasePointer(pointer)
check(jump.AbsoluteSize.X > savedSize and app.dirty and #app.history.past == 3,
    "two owned touches verify a single pinch resize in the bundled editor")
pinchOrigin = jump.AbsolutePosition
local enlargedWidth = jump.AbsoluteSize.X
pointer = begin(ui.canvas, pinchOrigin.X + enlargedWidth * .27, pinchOrigin.Y + enlargedWidth * .27)
secondPointer = begin(ui.canvas, pinchOrigin.X + enlargedWidth * .71, pinchOrigin.Y + enlargedWidth * .71)
move(secondPointer, -24, -24)
releasePointer(pointer)
releasePointer(secondPointer)
check(jump.AbsoluteSize.X < enlargedWidth and jump.AbsoluteSize.X == jump.AbsoluteSize.Y and #app.history.past == 4,
    "pinching inward contracts the control with aspect lock and either release order commits once")
ui.doneButton.Activated:Fire()
check(app.editing and app.dirty and ui.modalOpen, "dirty Done offers a save/discard dialog before closing")
action("Continue editing")
check(app.editing and app.dirty and not ui.modalOpen, "Continue editing dismisses the dialog and preserves changes")
ui.doneButton.Activated:Fire()
action("Discard")
check(not app.editing and not app.dirty and jump.AbsolutePosition.X == editedPosition.X and jump.AbsoluteSize.X == savedSize
    and files[path] == checkpoint,
    "Discard verifies the last checkpoint before Done closes")

do
    app:Open()
    local secondKey
    for _, record in ipairs(app.discovery:list("all")) do if record.object == auxiliary then secondKey = record.key; break end end
    check(secondKey ~= nil, "the second gameplay control is available to group")
    app:selectMany({key, secondKey})
    check(app:quickGroup() and #app.history.past == 0, "Quick Group establishes a temporary editing selection")
    local before = auxiliary.AbsolutePosition
    app:move(-18, 0)
    mock:flush()
    check(jump.AbsolutePosition.X == editedPosition.X - 18 and auxiliary.AbsolutePosition.X == before.X - 18,
        "temporary grouping transforms both selected controls")
    local function centerX(object) return object.AbsolutePosition.X + object.AbsoluteSize.X / 2 end
    local gap = centerX(jump) - centerX(auxiliary)
    local width, auxiliaryWidth = jump.AbsoluteSize.X, auxiliary.AbsoluteSize.X
    local position = jump.AbsolutePosition
    local first = begin(ui.canvas, position.X + width * .25, position.Y + width * .25)
    local second = begin(ui.canvas, position.X + width * .70, position.Y + width * .70)
    move(second, 14, 14)
    releasePointer(first)
    releasePointer(second)
    local scale = jump.AbsoluteSize.X / width
    check(scale > 1 and math.abs(auxiliary.AbsoluteSize.X / auxiliaryWidth - scale) < .02
        and math.abs((centerX(jump) - centerX(auxiliary)) / gap - scale) < .02 and #app.history.past == 2,
        "one bundled group pinch enlarges both roots and preserves their proportional spacing")
    app:undo()
    mock:flush()
    check(jump.AbsoluteSize.X == width and auxiliary.AbsoluteSize.X == auxiliaryWidth
        and math.abs(centerX(jump) - centerX(auxiliary) - gap) < .01,
        "one undo restores the previous group dimensions and spacing")
    app:group("create", "Gameplay")
    check(#app.groups.Gameplay == 2 and app:enterGroupMember(secondKey) and app:returnToGroup(),
        "a named group can temporarily focus one member and return to both")
    check(app:ungroup(true) and not app.groups.Gameplay and auxiliary.AbsolutePosition.X == before.X - 18,
        "ungrouping removes the group and preserves live geometry")
    app:cancel()
    mock:flush()
    check(not app.dirty and auxiliary.AbsolutePosition.X == before.X and jump.AbsolutePosition.X == editedPosition.X and files[path] == checkpoint,
        "group edits can be discarded back to the original stored checkpoint")
end

do
    local bar = make("Frame", "Practice ability bar", hud)
    bar.Position, bar.Size = UDim2.fromOffset(550, 100), UDim2.fromOffset(240, 50)
    local list = make("UIListLayout", "Row", bar)
    list.Padding = UDim.new(0, 6)
    local ability = make("TextButton", "Ability 1", bar)
    ability.Text, ability.Position, ability.Size = "1", UDim2.fromOffset(0, 0), UDim2.fromOffset(42, 40)
    mock:flush()
    local abilityKey
    for _, record in ipairs(app.discovery:list("all")) do if record.object == ability then abilityKey = record.key; break end end
    check(abilityKey ~= nil, "layout-managed numbered button is available for inspection")
    app:selectMany({abilityKey})
    local operations = app:capabilitiesForSelection()
    check(not operations.move and operations.resize and operations.parentKey and app:layerDetails(abilityKey):find("UIListLayout", 1, true),
        "the selected list member offers resize and a movable parent, and explains position ownership")
    local position = ability.Position
    app:move(15, 0)
    check(ability.Position == position and not app.dirty, "a known managed position is refused before any edit")
    app:resize(63, 60)
    mock:flush()
    check(ability.Position == position and math.abs(ability.AbsoluteSize.X - 63) < 1 and app.dirty,
        "supported list resize writes size without writing position")
    app:selectMany({operations.parentKey})
    app:move(15, 0)
    mock:flush()
    check(bar.Position.X.Offset == 565, "selecting the container moves the representative bar")
    app:cancel()
    mock:flush()
    check(bar.Position.X.Offset == 550 and ability.AbsoluteSize.X == 42 and not app.dirty,
        "discard restores the representative bar and member without changing the saved checkpoint")
end

do
    local grip = ui.toolbarGrip
    local start = ui.toolbar.AbsolutePosition
    local before = #app.history.past
    local finger = begin(grip)
    move(finger, 74, 18)
    releasePointer(finger)
    check(ui.toolbar.AbsolutePosition.X > start.X and app:getEditorPlacement("toolbar") and #app.history.past == before and not app.dirty,
        "moving the toolbar updates its independent placement without changing the HUD")
    check(app:resetEditorLayout() and not app:getEditorPlacement("toolbar"), "Reset Editor Layout restores the default toolbar placement")

    app:selectMany({key})
    ui:setTransformTool("rotate")
    local model = app:appearanceInfo("rotation")
    local handle = ui.rotationHandle.gui
    check(model and handle.Visible and model.pivot, "Rotate presents an exterior handle and the authored center")
    finger = begin(handle)
    local dx, dy = finger.Position.X - model.pivot.x, finger.Position.Y - model.pivot.y
    move(finger, -dy - dx, dx - dy)
    releasePointer(finger)
    check(math.abs(jump.Rotation - 90) < 1 and #app.history.past == before + 1,
        "dragging the rotation handle turns the control and commits a single action")
    local afterTurn = jump.Position.X.Offset
    app:move(-14, 0)
    mock:flush()
    check(jump.Position.X.Offset == afterTurn - 14 and math.abs(jump.Rotation - 90) < 1,
        "a locally rotated control can still move without changing angle")

    local badge = make("ImageButton", "Opacity sample", hud)
    badge.Position, badge.Size = UDim2.fromOffset(515, 160), UDim2.fromOffset(58, 58)
    badge.Image, badge.ImageTransparency, badge.BackgroundTransparency = "rbxassetid://1", .2, 1
    mock:flush()
    local badgeKey
    for _, record in ipairs(app.discovery:list("all")) do if record.object == badge then badgeKey = record.key; break end end
    check(badgeKey ~= nil, "image button is available for property-aware opacity")
    app:selectMany({badgeKey})
    ui:setTransformTool("opacity")
    app:geometry("transparency", .6)
    mock:flush()
    check(badge.BackgroundTransparency == .6, "legacy absolute background editing still applies separately")
    app:setOpacity(25, "element")
    mock:flush()
    check(math.abs(badge.ImageTransparency - .8) < .001 and badge.BackgroundTransparency == 1,
        "quarter opacity fades the visible image relative to its original and leaves the background invisible")
    app:setOpacity(100, "element")
    mock:flush()
    check(badge.ImageTransparency == .2 and badge.BackgroundTransparency == 1,
        "100 percent relative opacity restores authored values even after a legacy background edit")
    app:setOpacity(0, "element")
    mock:flush()
    check(badge.ImageTransparency == 1 and app.discovery:get(badgeKey) ~= nil,
        "a fully faded control remains accessible by its exact layer identity")

    app:setPreference("multiSelect", true)
    app:armSelectThrough()
    ui:setBox({x = 420, y = 60, w = 80, h = 80})
    ui:setGuides({{axis = "x", value = 420}})
    app:resetAll()
    mock:flush()
    check(jump.Rotation == 0 and jump.AbsolutePosition.X == origin.X and jump.AbsoluteSize.X == 96
        and math.abs(badge.ImageTransparency - .2) < .001 and app.resetAllPending,
        "Reset All restores original geometry, rotation, and image opacity together")
    check(#app.selection == 0 and not app.groupFocus and not ui.panel.Visible and not ui.selectionBounds.Visible
        and not ui.handleBounds.Visible and not ui.rotationHandle.gui.Visible and not ui.box.Visible
        and not ui.guideObjects[1].Visible and not app.preferences.multiSelect and not app.input:isSelectThroughArmed(),
        "Reset All leaves a neutral canvas with no selection overlays or pending input mode")
    app:undo()
    mock:flush()
    check(math.abs(jump.Rotation - 90) < 1 and badge.ImageTransparency == 1,
        "one Undo restores both appearance changes and geometry before the reset")
    check(#app.selection == 0 and not ui.selectionBounds.Visible, "undoing Reset All never reselects a HUD control")
    app:cancel()
    mock:flush()
    check(not app.dirty and jump.AbsolutePosition.X == editedPosition.X and jump.AbsoluteSize.X == savedSize
        and math.abs(badge.ImageTransparency - .2) < .001 and files[path] == checkpoint,
        "Discard restores the prior durable checkpoint after direct transformations")
end

local function abilityBar(name, y, managed)
    local bar = make("Frame", name, hud)
    bar.Position, bar.Size = UDim2.fromOffset(570, y), UDim2.fromOffset(320, 62)
    if managed then make("UIListLayout", "Row", bar).Padding = UDim.new(0, 8) end
    local cover = make("Frame", name .. "Cover", hud)
    cover.Position, cover.Size, cover.BackgroundTransparency, cover.ZIndex = bar.Position, bar.Size, 1, 40
    local cards = {}
    for i, title in ipairs({"Leap", "Burst", "Ward", "Dash"}) do
        local control = make(managed and "TextButton" or "Frame", "Ability" .. i, bar)
        control.Position, control.Size = UDim2.fromOffset((i - 1) * 76, 4), UDim2.fromOffset(62, 54)
        if not managed then
            local actionRegion = make("TextButton", "TapRegion", control)
            actionRegion.Size, actionRegion.BackgroundTransparency = UDim2.fromScale(1, 1), 1
        end
        local body = make("Frame", "Visuals", control)
        body.Size, body.BackgroundTransparency = UDim2.fromScale(1, 1), 1
        local overlayParts = make("Frame", "CooldownOverlay", control)
        overlayParts.Size, overlayParts.BackgroundTransparency, overlayParts.ZIndex = UDim2.fromScale(1, 1), 1, 4
        local function text(parent, labelName, value, x, y, width, height)
            local label = make("TextLabel", labelName, parent)
            label.Position, label.Size = UDim2.fromScale(x, y), UDim2.fromScale(width, height)
            label.Text, label.BackgroundTransparency, label.TextTransparency = value, 1, 0
            return label
        end
        local number = text(body, "Number", tostring(i), .04, .04, .22, .24)
        local icon = make("ImageLabel", "Icon", body)
        icon.Position, icon.Size = UDim2.fromScale(.30, .30), UDim2.fromScale(.4, .35)
        icon.Image, icon.BackgroundTransparency, icon.ImageTransparency = "rbxasset://textures/ui/GuiImagePlaceholder.png", 1, .18
        local caption = text(body, "AbilityName", title, .10, .72, .8, .22)
        local cooldown = text(overlayParts, "Cooldown", "2s", .50, .04, .45, .24)
        cards[i] = {root = control, components = {number, icon, caption, cooldown}}
    end
    return {bar = bar, cover = cover, cards = cards}
end

local free = abilityBar("FreeAbilityBar", 111, false)
local managed = abilityBar("ManagedAbilityBar", 185, true)
local function hitRect(object, x, y)
    local p, s = object.AbsolutePosition, object.AbsoluteSize
    return x >= p.X and y >= p.Y and x <= p.X + s.X and y <= p.Y + s.Y
end
function mock.playerGui:GetGuiObjectsAtPosition(x, y)
    for _, row in ipairs({free, managed}) do
        for _, card in ipairs(row.cards) do
            if hitRect(card.root, x, y) then
                -- The native result may only expose a painted component and a
                -- higher transparent sibling, even though the root owns it.
                for _, component in ipairs(card.components) do
                    if hitRect(component, x, y) then return {row.cover, component} end
                end
                return {row.cover, card.root}
            end
        end
    end
    error("Use rectangle-based fallback outside the simulated ability area")
end
mock:flush()
local function abilityPointer(object)
    local position, size = object.AbsolutePosition, object.AbsoluteSize
    return begin(ui.canvas, position.X + size.X / 2, position.Y + size.Y / 2)
end
local function selectedObject()
    local record = app.discovery:get(app.selection[1])
    return record and record.object
end
ui:setTransformTool("size")
app:clearSelection()
local abilityHistory = #app.history.past
for i, card in ipairs(free.cards) do
    local component = card.components[i]
    releasePointer(abilityPointer(component))
    local scopes = app:selectionScopes()
    check(selectedObject() == card.root and scopes and scopes.current == "whole" and scopes.whole.object == card.root
        and scopes.layer.object == component and scopes.container.object == free.bar,
        "number, icon, name and cooldown each identify their whole ability at the actual touched point (" .. i .. ")")
end
check(ui.quickScopeButton.Visible and ui.quickScopeButton.Text == "Whole" and #app.history.past == abilityHistory,
    "whole-control scope is visible in Quick Edit without writing layout changes or history")

local right = free.cards[4]
local cooldown = right.components[4]
local originalDetail = cooldown.Position
check(app:armSelectThrough(), "the composite ability can open Select Through")
releasePointer(abilityPointer(cooldown))
local previewRow
for _, row in ipairs(ui.pickerRows or {}) do
    if row.record.object == cooldown then previewRow = row; break end
end
check(previewRow and previewRow.preview and selectedObject() == right.root, "Select Through shows the actual component beside the whole control")
previewRow.preview.Activated:Fire()
check(ui.pickerPreviewOutline.Visible and selectedObject() == right.root and #app.history.past == abilityHistory,
    "preview highlights an individual component without changing selection or geometry")
action("Close")
check(not ui.modalOpen and not ui.pickerPreviewOutline, "closing Select Through frees its preview overlay")
ui.quickScopeButton.Activated:Fire()
action("Individual layer")
check(selectedObject() == cooldown and ui.quickScopeButton.Text == "Layer", "the scope menu focuses the original touched component")
pointer = abilityPointer(cooldown)
move(pointer, -11, 0)
releasePointer(pointer)
check(cooldown.Position.X.Offset == originalDetail.X.Offset - 11 and right.root.Position.X.Offset == 228,
    "explicit component drag edits the component without moving its ability")
releasePointer(abilityPointer(right.components[2]))
check(selectedObject() == right.root and app:selectionScopes().layer.object == right.components[2],
    "an ordinary tap returns to the whole ability and updates the originating detail")

local leftBefore = free.cards[1].root.AbsolutePosition
local cardBefore, labelBefore = right.root.AbsolutePosition, right.components[3].AbsolutePosition
pointer = abilityPointer(right.components[3])
move(pointer, -12, 9)
releasePointer(pointer)
check(right.root.AbsolutePosition.X == cardBefore.X - 12 and right.components[3].AbsolutePosition.X == labelBefore.X - 12
    and free.cards[1].root.AbsolutePosition.X == leftBefore.X, "an ordinary drag moves the whole composed ability but leaves its peer fixed")
local p, size = right.root.AbsolutePosition, right.root.AbsoluteSize
local first = begin(ui.canvas, p.X + 10, p.Y + 20)
local second = begin(ui.canvas, p.X + 45, p.Y + 20)
move(second, 13, 0)
local expanded = right.root.AbsoluteSize.X
move(second, -21, 0)
releasePointer(first)
releasePointer(second)
check(expanded > size.X and right.root.AbsoluteSize.X < size.X and #app.history.past == abilityHistory + 3,
    "one bundled pinch expands and contracts the composed ability without duplicate history")

app:clearSelection()
local managedCard = managed.cards[2]
local managedPosition = managedCard.root.Position
local barPosition = managed.bar.Position
pointer = abilityPointer(managedCard.components[2])
move(pointer, 12, 0)
releasePointer(pointer)
local managedCaps = app:capabilitiesForSelection()
check(selectedObject() == managedCard.root and not managedCaps.move and managedCaps.resize and managedCaps.parentKey,
    "first drag on a layout-owned ability focuses the whole and shows separate supported operations")
check(managedCard.root.Position == managedPosition and managed.bar.Position == barPosition and #app.history.past == abilityHistory + 3,
    "blocked position editing never substitutes a layer or parent adjustment")
local managedInfo, managedTrack = app:sizeInfo(), ui:sliderTrackRect()
local managedThumb = (managedInfo.scale - managedInfo.minimum) / (managedInfo.maximum - managedInfo.minimum)
pointer = begin(ui.slider, managedTrack.x + managedTrack.w * managedThumb, managedTrack.y + managedTrack.h / 2)
move(pointer, managedTrack.w * .08, 0)
releasePointer(pointer)
check(managedCard.root.Position == managedPosition and managedCard.root.AbsoluteSize.X > 62,
    "supported managed resize changes the whole ability size without writing its Position")
ui.quickScopeButton.Activated:Fire()
action("Entire container")
check(selectedObject() == managed.bar and ui.quickScopeButton.Text == "Container", "scope menu deliberately selects the complete ability bar")
pointer = abilityPointer(managedCard.components[1])
move(pointer, -13, 0)
releasePointer(pointer)
check(managed.bar.Position.X.Offset == barPosition.X.Offset - 13 and managedCard.root.Position == managedPosition,
    "container drag works over a visual child even when its enclosing bar is absent from the native hit list")
releasePointer(abilityPointer(managedCard.components[1]))
check(selectedObject() == managedCard.root and ui.quickScopeButton.Text == "Whole", "ordinary canvas selection returns from container scope to one ability")

local savedAbility = {freeX = right.root.Position.X.Offset, freeW = right.root.AbsoluteSize.X,
    detailX = cooldown.Position.X.Offset, managedW = managedCard.root.AbsoluteSize.X, barX = managed.bar.Position.X.Offset}
ui.saveButton.Activated:Fire()
mock:flush()
check(not app.dirty and files[path] ~= checkpoint, "Save durably checkpoints composed controls, component and container edits")
checkpoint = files[path]
ui.doneButton.Activated:Fire()
releasePointer(begin(ui.launcher))
check(app.editing and right.root.Position.X.Offset == savedAbility.freeX and managed.bar.Position.X.Offset == savedAbility.barX,
    "Done and launcher reopen retain the saved composite layout")

app:Destroy()
mock:flush()
check(env.__HEAVENLY_AXIS_V3 == nil and mock.activeConnections == 0 and jump.AbsolutePosition.X == origin.X and jump.AbsoluteSize.X == 96,
    "destroy releases every runtime connection and restores originals")
for _, row in ipairs({free, managed}) do row.bar:Destroy(); row.cover:Destroy() end
free = abilityBar("FreeAbilityBar", 111, false)
managed = abilityBar("ManagedAbilityBar", 185, true)
env.HeavenlyAxisOptions = {LoaderOnly = true}
local restored = source()
mock:flush()
check(restored and not restored.ui and restored:VerifyStartup().mode == "loader" and jump.AbsolutePosition.X == editedPosition.X
    and jump.AbsoluteSize.X == savedSize, "legacy Source cold loader restores checkpoint without creating UI")
right, managedCard = free.cards[4], managed.cards[2]
check(right.root.Position.X.Offset == savedAbility.freeX and right.root.AbsoluteSize.X == savedAbility.freeW
    and right.components[4].Position.X.Offset == savedAbility.detailX and managedCard.root.AbsoluteSize.X == savedAbility.managedW
    and managed.bar.Position.X.Offset == savedAbility.barX,
    "cold loader restores composite changes onto recreated abilities with matching identities")
check(restored:hasSeenTutorial(), "cold startup remembers completed or skipped onboarding")
check(release() == restored and not restored.ui and jump.AbsoluteSize.X == savedSize,
    "duplicate loader execution does not construct an editor or compound properties")
env.HeavenlyAxisOptions = {SafeMode = true}
check(release() == restored and restored.ui and restored:VerifyStartup().mode == "suspended"
    and jump.AbsolutePosition.X == origin.X and jump.AbsoluteSize.X == 96 and files[path] == checkpoint,
    "Safe Mode opens recovery and restores original visuals while keeping the saved profile")
restored:Destroy()
mock:flush()
check(mock.activeConnections == 0 and #warnings == 0, "the entire bundled workflow completes without leaked callbacks or startup warnings")

require, game, getgenv, task, warn = externalRequire, initialGame, initialGetgenv, initialTask, initialWarn
return checks
