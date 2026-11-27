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

app:Destroy()
mock:flush()
check(env.__HEAVENLY_AXIS_V3 == nil and mock.activeConnections == 0 and jump.AbsolutePosition.X == origin.X and jump.AbsoluteSize.X == 96,
    "destroy releases every runtime connection and restores originals")
env.HeavenlyAxisOptions = {LoaderOnly = true}
local restored = source()
mock:flush()
check(restored and not restored.ui and restored:VerifyStartup().mode == "loader" and jump.AbsolutePosition.X == editedPosition.X
    and jump.AbsoluteSize.X == savedSize, "legacy Source cold loader restores checkpoint without creating UI")
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
