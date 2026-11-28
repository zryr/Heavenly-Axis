-- Structural Roblox GUI mocks. These checks exercise UI state and sizing only;
-- they do not establish Roblox rendering, touch interception or device support.
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local mock = require("support/Roblox").new()
local view, vec, signal = mock.view, mock.vec, mock.signal
local playerGui, services = mock.playerGui, mock.services
local Geometry = require("Geometry")
local UI = require("UI")
local Coordinates = require("Coordinates")
local Layout = require("UILayout")
local target = Instance.new("TextButton")
target.Name = "Jump Mock"; target.Size = UDim2.fromOffset(100, 100); target.Position = UDim2.fromOffset(50, 162); target.Parent = playerGui
local second = Instance.new("TextButton")
second.Name = "Second"; second.Size = UDim2.fromOffset(30, 40); second.Position = UDim2.fromOffset(320, 154); second.Parent = playerGui
local descriptor = {path = {{name = "HUD", class = "ScreenGui"}, {name = "Jump Mock", class = "TextButton"}}, class = "TextButton"}
local record = {key = "a", descriptor = descriptor, object = target, editable = true, builtin = "JumpButton"}
local record2 = {key = "b", descriptor = {path = {{name = "Second", class = "TextButton"}}}, object = second, editable = true}
local records, listCalls = {record, record2}, 0
local flags = {}
local app = {version = "3.1.0", selection = {}, preferences = {grid = true, snapping = false, launcherX = .4, launcherY = .3},
    capabilities = {}, groups = {}, logs = {}, dirty = false, statusMessage = "Ready"}
function app:log(message) self.logs[#self.logs + 1] = message end
function app:status(message) self.statusMessage = message end
function app:getRects(editableOnly, operation)
    local result, keys = {}, {}
    for _, key in ipairs(self.selection) do
        local item = self.discovery:get(key)
        local support = item and item.capabilities and item.capabilities[operation]
        if item and (not editableOnly or (item.editable and (not support or support.supported))) and not (editableOnly and flags[key] and flags[key].locked) then
            result[#result + 1] = Coordinates.rect(item.object)
            keys[#keys + 1] = key
        end
    end
    return result, keys
end
function app:currentBounds(editableOnly, operation) return Geometry.bounds(self:getRects(editableOnly, operation)) end
function app:layerState(key) return flags[key] or {} end
function app:setLayerState(key, field, value)
    flags[key] = flags[key] or {}
    flags[key][field] = value
    self.layerRevision = (self.layerRevision or 0) + 1
    self.ui:refresh()
end
function app:sizeInfo(bounds, rects, keys)
    bounds = bounds or self:currentBounds(true)
    if not bounds then return end
    local size = self.preferences.equalSize and #self.selection > 1 and Coordinates.rect(target) or bounds
    return {scale = size.w, minimum = 16, maximum = 200, original = #self.selection == 1, size = size}
end
function app:getState() return {layout = {}} end
function app:select(key) self.selection = {key}; if self.ui then self.ui:selectionChanged() end end
function app:selectMany(keys) self.selection = keys; if self.ui then self.ui:selectionChanged() end end
function app:clearSelection() self:selectMany({}) end
function app:setPreference(key, value) self.preferences[key] = value end
function app:geometry(mode, value) self.lastGeometry = {mode = mode, value = value} end
function app:resize(w, h) self.lastResize = {w = w, h = h} end
function app:setSizePercent(percent) self.lastPercent = percent end
function app:save() self.saved = true end
function app:setLauncherPosition(x, y) self.preferences.launcherX, self.preferences.launcherY = x, y end
function app:profile(...) self.lastProfile = {...} end
function app:group(...) self.lastGroup = {...} end
app.discovery = {revision = 1, list = function() listCalls = listCalls + 1; return records end,
    get = function(_, key) for _, item in ipairs(records) do if item.key == key then return item end end end}
app.transform = {matches = function() return {} end}
app.profiles = {list = function() return {} end, active = function() return nil end}

local function visibleHandles(ui)
    local count = 0
    for _, handle in ipairs(ui.handles) do if handle.gui.Visible then count = count + 1 end end
    return count
end
local function buttonByText(root, text)
    for _, item in ipairs(root:GetDescendants()) do
        if item:IsA("TextButton") and item.Text == text then return item end
    end
end

local ui = UI.new(app, playerGui, services)
app.ui = ui
check(ui.gui.Name == "HeavenlyAxis" and ui.gui.ResetOnSpawn == false and ui.gui.ScreenInsets == Enum.ScreenInsets.None,
    "persistent editor requests a full-coordinate overlay")
check(not ui.visible and not ui.canvas.Visible and ui.launcher.Visible, "editor starts closed with only the launcher")
check(listCalls == 0, "closed editor does not build hidden browsing lists")
ui:setVisible(true)
check(ui.visible and ui.canvas.Visible and ui.toolbar.Visible and not ui.panel.Visible and not ui.workspace.Visible,
    "opening shows the canvas toolbar before a selection")
local hint = Coordinates.rect(ui.canvasHint)
check(ui.canvasHint.Visible and not ui:pointInPanel(hint.x + 3, hint.y + 3), "empty canvas hint leaves the HUD beneath it reachable")
check(not ui.launcher.Visible, "launcher releases gameplay space while editing")
check(ui.gridLayer.Visible and #ui.gridObjects <= 162, "enabled grid uses bounded line count")
check(not app.preferences.snapping, "grid does not force snapping")

app:select("a")
check(ui.panel.Visible and ui.quickBody.Visible and not ui.workspace.Visible, "compatible selection opens contextual Quick Edit")
check(ui.quickName.Text == "Jump Mock" and ui.percent.Text == "100%", "visual size percentage matches selected element")
check(ui.buttonIcons[ui.elementsButton] and ui.elementsButton.Text == "Layers"
    and ui.buttonIcons[ui.transformButtons.size] and ui.transformButtons.size.Text == "Size",
    "Lucide actions retain permanently readable labels")
local lucide = require("Lucide")
local originalTint, tintCalls = lucide.setColor, 0
lucide.setColor = function(...) tintCalls = tintCalls + 1; return originalTint(...) end
ui:updateSelection(); ui:updateSelection()
lucide.setColor = originalTint
check(tintCalls == 0, "stable gesture frames do not rewrite unchanged tool icon tints")
check(not ui.canvasHint.Visible and ui.sliderTitle.Text == "Size" and ui.sliderReference.Text == "100% original"
    and ui.quickSize.Text == "100 × 100", "selection replaces the empty hint with percentage and pixel size context")
check(ui.quickHint.Text == "Pinch in or out to resize", "the active Size tool teaches bidirectional pinch at the point of use")
check(ui.selectionBounds.AbsolutePosition.X == 50 and ui.selectionBounds.AbsolutePosition.Y == 162,
    "canonical selection placement offsets the full-screen root origin")
check(ui.selectionBounds.Position.X.Offset == 59 and ui.selectionBounds.Position.Y.Offset == 185,
    "canonical-to-local conversion is applied at the overlay boundary")
check(visibleHandles(ui) == 1, "touch layout exposes one resize handle")
local grip = Coordinates.rect(ui.touchHandle.gui)
check(grip.w == 44 and not Layout.intersects(grip, Coordinates.rect(target)), "touch handle has a 44-unit region outside the movement target")
check(ui.touchHandleLink.Visible and ui.touchHandleLink.AbsoluteSize.X > 0, "touch handle visibly connects to the resized corner")
local targetSize, targetPosition = target.Size, target.Position
target.Size = UDim2.fromOffset(ui.safeArea.w, ui.safeArea.h)
target.Position = UDim2.fromOffset(ui.safeArea.x, ui.safeArea.y)
ui:updateSelection()
local largeGrip = Coordinates.rect(ui.touchHandle.gui)
check(visibleHandles(ui) == 1 and Layout.intersects(largeGrip, Coordinates.rect(target)) and largeGrip.w == 44,
    "large controls use an interior corner handle when no exterior handle fits")
target.Size, target.Position = targetSize, targetPosition
ui:updateSelection()
local deferred, existingTask = {}, task
task = {defer = function(callback) deferred[#deferred + 1] = callback end}
ui:requestSelectionUpdate()
target:GetPropertyChangedSignal("AbsolutePosition"):Fire()
target:GetPropertyChangedSignal("AbsoluteSize"):Fire()
check(#deferred == 1, "input and selected geometry events share one deferred redraw")
deferred[1]()
task = existingTask
check(ui:pointInPanel(ui.panel.AbsolutePosition.X + 1, ui.panel.AbsolutePosition.Y + 1), "inspector blocks canvas under it")
check(not ui:pointInPanel(760, 490), "canvas outside editor controls remains available")
local oldX, oldY = ui:inspectorPosition()
ui:moveInspector(760, 560)
local movedX, movedY = ui:inspectorPosition()
check(oldX ~= movedX or oldY ~= movedY, "moving the inspector exposes controls behind it")
ui:finishInspectorMove(true)
local restoredX, restoredY = ui:inspectorPosition()
check(restoredX == oldX and restoredY == oldY, "cancelled inspector drag restores its position")
ui:setCollapsed(true)
check(not ui.panel.Visible and ui.selectionBounds.Visible and ui.editButton.Visible, "hiding Quick Edit leaves selection editing active and offers a direct return")
ui.editButton.Activated:Fire()
check(ui.panel.Visible and not ui.workspace.Visible and not ui.editButton.Visible, "Quick Edit restores without a redundant toolbar action")

for _, dims in ipairs({{1536, 695}, {960, 440}, {640, 360}, {932, 430}, {393, 852}, {360, 640},
    {1024, 768}, {1920, 1080}, {320, 240}, {240, 320}}) do
    view.X, view.Y = dims[1], dims[2]
    ui:layout()
    local panel, toolbar = Coordinates.rect(ui.panel), Coordinates.rect(ui.toolbar)
    local safe = ui.safeArea
    check(panel.x >= safe.x and panel.y >= safe.y and panel.x + panel.w <= safe.x + safe.w
        and panel.y + panel.h <= safe.y + safe.h, "inspector remains inside simulated safe area")
    check(not Layout.intersects(panel, toolbar), "quick editor and toolbar remain distinct")
    if view.X >= 640 and view.X > view.Y then
        check(panel.w <= 262 and panel.h <= 244 and (panel.w * panel.h + toolbar.w * toolbar.h) / (view.X * view.Y) < .35,
            "landscape chrome preserves at least 65 percent of the canvas")
        check(ui.quickBody.AbsoluteSize.Y >= 140, "landscape quick tools fit in initial viewport")
    end
    ui:setTab("Elements")
    check(ui.pages.Elements.AbsoluteSize.Y >= 24 and ui.workspace.Visible, "explicit workspace keeps a usable content viewport")
    ui:setWorkspace(false)
end
view.X, view.Y = 800, 600
ui:layout()
services.UserInputService.PreferredInput = Enum.PreferredInput.KeyboardAndMouse
ui:layout()
check(visibleHandles(ui) == 8 and ui.panel.AbsoluteSize.X <= 286, "hybrid keyboard input uses desktop handles and compact inspector")
check(not ui.touchHandleLink.Visible, "desktop markers sit on the outline without an exterior handle link")
services.UserInputService.PreferredInput = Enum.PreferredInput.Touch
ui:layout()
check(visibleHandles(ui) == 1, "hybrid touch input restores exterior handle")
view.X, view.Y = 393, 852
ui:layout()
check(ui.saveButton.Visible and ui.historyButton.Visible and not ui.undoButton.Visible and not ui.redoButton.Visible,
    "portrait keeps Save visible by grouping history tools")
check(ui.saveButton.AbsoluteSize.X >= 44 and ui.doneButton.AbsoluteSize.X >= 44,
    "portrait keeps separate touch-sized checkpoint and exit controls")
ui.saveButton.Activated:Fire()
check(app.saved, "portrait Save directly reaches the App checkpoint action")
ui.historyButton.Activated:Fire()
check(buttonByText(ui.modalGui, "Undo last change") and buttonByText(ui.modalGui, "Redo last change"), "compact history exposes both operations")
ui:closeModal()
view.X, view.Y = 360, 640
ui:layout()
check(ui.saveButton.Visible and ui.saveButton.AbsoluteSize.X >= 44 and ui.doneButton.AbsoluteSize.X >= 44,
    "compact phone portrait keeps Save at one tap with touch-sized buttons")
view.X, view.Y = 320, 640
ui:layout()
app.saved = false
check(not ui.saveButton.Visible, "very narrow portrait preserves full touch targets and moves Save to layout actions")
ui.toolsButton.Activated:Fire()
check(ui.workspace.Visible and not ui.modalOpen, "Tools opens one workspace directly")
ui.workspaceActions.Activated:Fire()
local compactSave = buttonByText(ui.modalGui, "Save layout")
check(compactSave ~= nil, "layout actions exposes Save when the toolbar is too narrow")
compactSave.Activated:Fire()
check(app.saved, "compact Save reaches the App checkpoint action")
ui:setTab("Settings")
local movementField = ui.preferenceFields.step
local labeled = false
for _, object in ipairs(movementField.Parent:GetChildren()) do
    if object:IsA("TextLabel") and object.Text == "Movement step (px)" then labeled = true end
end
check(labeled and movementField.AbsoluteSize.Y == 44, "settings keeps the units beside a populated numeric field")
ui:setWorkspace(false)
ui.toolsButton.Activated:Fire()
check(ui.tab == "Settings" and ui.workspaceHeading.Text == "Settings" and ui.tabMarks.Settings.Visible
    and not ui.tabMarks.Elements.Visible, "Tools restores its last destination and the workspace marks only its current section")
ui:setWorkspace(false)
view.X, view.Y = 800, 600
ui:layout()

local originalSize = target.Size
target.Size = UDim2.fromOffset(100.34, 100)
ui:updateSelection()
ui.percent:CaptureFocus(); ui.percent:ReleaseFocus(); ui.percent.FocusLost:Fire(false)
check(app.lastPercent == nil, "blurring an untouched rounded percentage does not start a resize")
target.Size = originalSize
ui:updateSelection()
ui.percent.Text = "124%"
ui.percent.FocusLost:Fire(false)
check(app.lastPercent == 124, "quick size commits the numeric percentage")
local focusRing = ui.percent:FindFirstChildOfClass("UIStroke")
ui.percent.Focused:Fire()
check(focusRing.Transparency < .2, "numeric field gains a visible focus ring")
ui.percent.FocusLost:Fire(false)
check(focusRing.Transparency >= .2, "numeric focus ring returns to rest when dismissed")
ui.percent.Focused = true; ui.percent.Text = "12"
services.UserInputService.OnScreenKeyboardVisible, services.UserInputService.OnScreenKeyboardSize = true, vec(640, 440)
ui:layout()
check(not ui.toolbar.Visible and ui.quickBody.CanvasPosition.Y == 48 and ui.percent.Text == "12", "keyboard layout keeps the percentage field and typed draft available")
ui.percent.Focused = false; services.UserInputService.OnScreenKeyboardVisible = false; ui:layout()
check(ui.toolbar.Visible and ui.quickBody.CanvasPosition.Y == 0, "closing the keyboard restores the canvas layout")

ui:setTab("Advanced")
check(ui.fields.X.Text == "50" and ui.fields.Y.Text == "162" and ui.fields.W.Text == "100", "advanced inspector reads canonical selection geometry")
ui.fields.W:CaptureFocus(); ui.fields.W:ReleaseFocus(); ui.fields.W.FocusLost:Fire(false)
check(app.lastResize == nil, "blurring the unchanged advanced width does not start a transform")
ui.fields.X.Text = "120"; ui.fields.X.FocusLost:Fire(false)
check(app.lastGeometry and app.lastGeometry.mode == "position" and app.lastGeometry.value.x == 120, "numeric position uses the app operation")
ui.fields.W.Text = "125"; ui.fields.W.FocusLost:Fire(false)
check(app.lastResize.w == 125 and app.lastResize.h == 125, "width editing preserves aspect ratio by default")
app.preferences.aspectLock = false
ui.fields.W.Text = "130"; ui.fields.W.FocusLost:Fire(false)
check(app.lastResize.w == 130 and app.lastResize.h == 100, "advanced width can change independently")
ui.fields.X.Focused = true; ui.fields.X.Text = "1234"; ui:updateSelection()
check(ui.fields.X.Text == "1234", "geometry updates preserve a focused draft")
ui.fields.X.Focused = false; ui.fields.X.Text = "nan"; ui.fields.X.FocusLost:Fire(false)
check(app.statusMessage == "Enter a finite numeric value.", "invalid numeric text receives feedback")
app.preferences.equalSize = true
app:selectMany({"a", "b"})
check(ui.fields.W.Text == "100" and ui.precisionHeading.Text:find("largest member"), "group member mode labels and displays the size basis")
ui.fields.H.Text = "120"; ui.fields.H.FocusLost:Fire(false)
check(app.lastResize.w == 100 and app.lastResize.h == 120, "independent member change preserves the other member axis")
app:select("a")

ui:setTab("Elements")
local elementsBody = ui.pageBodies.Elements
local previousOrder = 0
for _, child in ipairs(elementsBody:GetChildren()) do
    if child:IsA("GuiObject") then
        check(child.LayoutOrder > previousOrder and child.ZIndex > ui.workspace.ZIndex, "workspace content has explicit order and renders above its surface")
        previousOrder = child.LayoutOrder
    end
end
local contentLayout
for _, child in ipairs(elementsBody:GetChildren()) do if child:IsA("UIListLayout") then contentLayout = child end end
contentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Fire()
check(ui.pages.Elements.CanvasSize.Y.Offset > 175, "list layout drives the native scrollable viewport")
local rows, connections = listCalls, mock.activeConnections
ui:refreshElements(); ui:refreshElements()
check(listCalls == rows and mock.activeConnections == connections, "unchanged element revision avoids enumeration and callback churn")
ui:setOverlaps({record, record2})
check(ui.overlapList.Visible and ui:openSelectThrough(), "touch overlap opens the explicit layer picker")
check(ui.modalOpen and #ui.pickerRows == 2, "layer picker shows all valid candidates")
ui.pickerRows[2].preview.Activated:Fire()
check(ui.previewLayerKey == "b" and ui.pickerPreviewOutline.Visible and app.selection[1] == "a"
    and ui.pickerPreviewOutline.AbsolutePosition.X == second.AbsolutePosition.X,
    "preview draws the candidate outline without changing selection")
ui.pickerRows[2].preview.Activated:Fire()
check(ui.previewLayerKey == nil and not ui.pickerPreviewOutline.Visible and app.selection[1] == "a",
    "stopping preview leaves the previous selection unchanged")
ui.pickerRows[2].button.Activated:Fire()
check(app.selection[1] == "b" and not ui.modalOpen and not ui.workspace.Visible and ui.pickerPreviewOutline == nil,
    "choosing a deeper layer updates the selection immediately")
ui:setTab("Elements")

app:setLayerState("a", "ignored", true)
ui:setLayerFilter("Ignored")
check(ui.elementRows.a and not ui.elementRows.b and ui.elementRows.a.root.SelectLayer == nil,
    "ignored filter includes explicitly inspectable layers")
ui:setLayerFilter("Visible")
record2.visibility = "hidden"; app.discovery.revision = 2; ui:refreshElements()
check(not ui.elementRows.b, "visible browse filter excludes hidden layers")
ui:setLayerFilter("All accessible")
check(ui.elementRows.b ~= nil, "all accessible filter reveals hidden layers explicitly")
record2.visibility = nil
ui:setLayerFilter("Visible")

records = {}; app.discovery.revision = 3; ui:refreshElements()
check(#ui.elementConnections == 0 and not ui.overlapList.Visible, "removed browser rows and overlap references clear")
records = {record, record2}
for i = 1, 70 do
    local copy = {key = tostring(i), descriptor = {path = {{name = "Test " .. i}}}, object = second, editable = true}
    records[#records + 1] = copy
end
app.discovery.revision = 4; ui:refreshElements()
check(#ui.elementConnections == 22 and ui.pager.Visible, "large browser caps active rows through pagination")
ui.search.Text = "Test 70"
check(#ui.elementConnections == 1 and not ui.pager.Visible and ui.elementRows["70"], "search reaches results beyond the first result page")

app:clearSelection()
check(not ui.selectionBounds.Visible and visibleHandles(ui) == 0, "clearing selection removes geometry and active handles")
record.editable = false
ui:setWorkspace(false)
app:select("a")
check(ui.panel.AbsoluteSize.Y <= 56 and not ui.quickBody.Visible and visibleHandles(ui) == 0 and ui.quickHint.Text == "View details in Tools",
    "unsupported selection remains inspectable without resize affordances")
record.editable = true
function app:capabilitiesForSelection()
    local item = self.discovery:get(self.selection[1])
    if not item then return {} end
    if self:layerState(item.key).locked then return {locked = true} end
    return {move = item == record, resize = true, reset = true, visual = true,
        parentKey = item == record2 and record.key or nil, layout = item == record2}
end
record2.displayName = "Ability slot 2"
record2.capabilities = {move = {supported = false}, resize = {supported = true}}
app:select("b")
check(ui.quickName.Text == "Ability slot 2" and ui.sliderEnabled and ui.quickHint.Text == "Position set by layout",
    "compatible layout-owned control keeps its size editor and explains fixed position")
ui:setTab("Advanced")
check(ui.fields.X.TextEditable == false and ui.fields.W.TextEditable == true,
    "Advanced enables size without enabling layout-owned position")
ui:setWorkspace(false)
check(ui.quickMore.Text == "Select container", "layout-owned selection offers a direct route to its parent")
ui.quickMore.Activated:Fire()
check(app.selection[1] == record.key and ui.panel.Visible, "parent route returns to the canvas with the container selected")
app:setLayerState("a", "locked", true)
check(ui.quickMore.Text == "Unlock" and not ui.sliderEnabled and visibleHandles(ui) == 0,
    "locked layer shows Unlock and removes transformation affordances")
ui.quickMore.Activated:Fire()
check(not app:layerState("a").locked and ui.sliderEnabled, "Unlock restores compatible tools")
app:setLayerState("a", "ignored", false)
app.capabilitiesForSelection = nil

local barObject, glyphObject = Instance.new("Frame"), Instance.new("TextLabel")
barObject.Name, barObject.Parent = "SkillFrame", playerGui
barObject.Size, barObject.Position = UDim2.fromOffset(140, 55), UDim2.fromOffset(425, 166)
glyphObject.Name, glyphObject.Parent = "Text", target
glyphObject.Size, glyphObject.Position = UDim2.fromOffset(45, 21), UDim2.fromOffset(11, 8)
local bar = {key = "bar", object = barObject, displayName = "Ability bar", visibility = "container", editable = true,
    descriptor = {path = {{name = "SkillFrame"}}, class = "Frame"}}
local glyph = {key = "glyph", object = glyphObject, displayName = "Ability name", parentKey = record.key, editable = true,
    descriptor = {path = {{name = "Jump Mock"}, {name = "Text"}}, class = "TextLabel"}}
records[#records + 1], records[#records + 2] = bar, glyph
record.childKeys = {glyph.key}
local function scopeRecord(key)
    return key == glyph.key and "layer" or key == bar.key and "container" or "whole"
end
function app:selectionScopes(key)
    key = key or self.selection[1]
    return {current = scopeRecord(key), whole = record, layer = key == glyph.key and glyph or nil, container = bar}
end
function app:scopeLayers() return {glyph} end
function app:selectScope(scope, key)
    self:select(key or (scope == "container" and bar.key or record.key))
    return true
end
app:select(record.key)
check(ui.quickScopeButton.Visible and ui.quickScopeButton.Text == "Whole", "Quick Edit exposes the active edit scope")
function app:capabilitiesForSelection()
    return {move = false, resize = true, visual = true, reset = true, parentKey = bar.key, layout = true}
end
bar.displayName = "Hot Bar"
ui:selectionChanged()
check(ui.quickHint.Text == "Bar sets position" and ui.quickMore.Text == "Select entire bar",
    "managed control explains which layout positions it and offers its entire bar")
local formerX, formerY = view.X, view.Y
for _, dims in ipairs({{640, 360}, {360, 640}}) do
    view.X, view.Y = dims[1], dims[2]
    ui:layout()
    local action, body = Coordinates.rect(ui.quickMore), Coordinates.rect(ui.quickBody)
    check(ui.quickMore.Visible and action.w >= 44 and action.h >= 44 and action.y + action.h <= body.y + body.h,
        "managed bar action remains touch-sized and fully visible without scrolling")
end
view.X, view.Y = formerX, formerY
app.capabilitiesForSelection = nil
ui:selectionChanged(); ui:layout()
ui.quickScopeButton.Activated:Fire()
check(buttonByText(ui.modalGui, "Whole control") and buttonByText(ui.modalGui, "Entire container"), "scope menu distinguishes the control and container")
buttonByText(ui.modalGui, "Individual layer").Activated:Fire()
check(ui.dialogHeading.Text == "Choose an individual layer" and ui.pickerRows[1].record.key == glyph.key,
    "selecting an individual scope can choose among visible descendants")
ui.pickerRows[1].button.Activated:Fire()
check(app.selection[1] == glyph.key and ui.quickScopeButton.Text == "Layer", "explicit layer choice updates the scope label and selection")
ui.quickScopeButton.Activated:Fire()
buttonByText(ui.modalGui, "Entire container").Activated:Fire()
check(app.selection[1] == bar.key and ui.quickScopeButton.Text == "Container", "container scope stays within the same editing inspector")
record2.visibility = "hidden"
bar.visibility = "visible"
local lookupScope = app.selectionScopes
function app:selectionScopes(candidate)
    if candidate == bar.key then return {current = "layer", layer = bar} end
    return lookupScope(self, candidate)
end
local grouped = {record, bar, glyph, record2, controlScopes = {whole = record, layer = glyph, container = bar}}
ui:openSelectThrough(grouped)
local sections = {}
for _, object in ipairs(ui.modalGui:GetDescendants()) do
    if object:IsA("TextLabel") then sections[object.Text] = true end
end
check(sections.Controls and sections.Containers and sections["Individual layers"] and sections["Hidden or inspection only"],
    "Select Through groups controls, containers, layers, and hidden objects")
check(ui.pickerRows[1].record == record and ui.pickerRows[2].record == glyph and ui.pickerRows[3].record == bar,
    "Select Through keeps the contextual bar under Containers even when its own scope has no layout")
ui:closeModal()
record2.visibility = nil
app.selectionScopes, app.scopeLayers, app.selectScope = nil, nil, nil
record.childKeys = nil
app:select(record.key)
app.previewState = {}
ui:updateSelection()
check(not ui.sliderEnabled and visibleHandles(ui) == 0 and ui.quickHint.Text == "Profile preview",
    "profile preview disables editing gestures and size inputs")
app.previewState = nil

local box = ui:modal("Import", "Validate before preview", "{}", "Preview", function(value) return value == "{}" end)
check(ui.modalOpen and ui:pointInPanel(0, 0), "modal blocks all canvas input")
check(box.Text == "{}", "portable text remains available")
ui:closeModal()
local result
ui:confirmDone(function() result = "save" end, function() result = "discard" end)
buttonByText(ui.modalGui, "Continue editing").Activated:Fire()
check(not ui.modalOpen and result == nil, "continuing editing dismisses the prompt without mutating the app")
ui:confirmDone(function() result = "save" end, function() result = "discard" end)
buttonByText(ui.modalGui, "Save").Activated:Fire()
check(not ui.modalOpen and result == "save", "Done offers an explicit checkpoint action")
ui:confirmDone(function() result = "save" end, function() result = "discard" end)
buttonByText(ui.modalGui, "Discard").Activated:Fire()
check(not ui.modalOpen and result == "discard", "discard is explicit")
ui:setTab("Profiles")
local sampleProfile = {id = "profile-a", name = "Gameplay", scope = "place"}
app.profiles.list = function() return {sampleProfile} end
app.profiles.active = function() return sampleProfile end
ui:refreshProfiles()
check(ui.activeProfile.Text == "Gameplay" and ui.profileSummary.Text == "This place" and not ui.previewActions.Visible,
    "profile summary presents the active layout without idle preview controls")
local profileItem = ui.profileList:FindFirstChild("ListItem")
profileItem.Activated:Fire()
buttonByText(ui.modalGui, "Preview profile").Activated:Fire()
check(app.lastProfile[1] == "preview" and app.lastProfile[2] == sampleProfile.id, "saved profile rows expose contextual actions for that profile")
app.previewState = {}
ui:refreshProfiles()
check(ui.previewActions.Visible and not ui.newProfileButton.Visible, "preview presents Apply and Cancel before other profile actions")
app.previewState = nil
app.draftBlocked = "Recovery draft preserved because its baseline changed."; ui:refreshProfiles()
check(ui.draftSection.Visible and ui.previewDraft.Interactable == false,
    "recovery exposes discard for a stale draft without offering preview")

app.groups.Test = {record.descriptor, record2.descriptor}
ui:setTab("Groups")
local savedGroup = ui.groupList:FindFirstChild("ListItem")
savedGroup.Activated:Fire()
buttonByText(ui.modalGui, "Select group").Activated:Fire()
check(app.lastGroup[1] == "select" and app.lastGroup[2] == "Test" and not ui.workspace.Visible,
    "saved group row returns directly to the editing canvas")

ui:setOverlaps({record, record2})
ui:openSelectThrough()
ui.pickerRows[1].preview.Activated:Fire()
check(ui.previewLayerKey ~= nil, "transient candidate preview is open before reset cleanup")
ui:setBox({x = 300, y = 300, w = 20, h = 20})
ui:setGuides({{axis = "x", value = 200}})
app:clearSelection()
ui:clearSelectionFeedback()
check(#ui.overlapKeys == 0 and not ui.box.Visible and not ui.guideObjects[1].Visible and not ui.selectionBounds.Visible
    and not ui.modalOpen and ui.pickerPreviewOutline == nil,
    "reset cleanup clears selection outlines, picker preview, guides, and overlap candidates")

ui:setVisible(false)
check(not ui.modalOpen and not ui.overlay.Visible and #ui.selectionConnections == 0, "closing releases selection events and editing surfaces")
app.preferences.launcherHidden = true; ui:refresh()
check(not ui.launcher.Visible, "launcher can be hidden without destroying the editor")
app.preferences.launcherHidden = false; ui:refresh()
ui:moveLauncher(700, 345); ui:finishLauncherMove(false)
local launcher = Coordinates.rect(ui.launcher)
check(app.preferences.launcherX == 1 and launcher.x + launcher.w == ui.safeArea.x + ui.safeArea.w - 8, "launcher docks inside the nearest safe edge")
check(#app.logs == 0, "GUI callbacks completed without swallowed errors")
-- Exercise UI and Input together using the same GUI fixture as the layout checks.
local function checkGestureSurfaces()
    local Input = require("Input")
    local uis = services.UserInputService
    for _, name in ipairs({"InputBegan", "InputChanged", "InputEnded", "WindowFocusReleased"}) do uis[name] = signal() end
    function uis:IsKeyDown() return false end
    function uis:GetFocusedTextBox() return nil end
    function app:setEditing(editing) self.editing = editing; ui:setVisible(editing) end
    function app:Done() self:setEditing(false) end
    function app.discovery:hit(x, y)
        local p, s = target.AbsolutePosition, target.AbsoluteSize
        return x >= p.X and y >= p.Y and x <= p.X + s.X and y <= p.Y + s.Y and {record} or {}
    end
    function app:sizeRects(rects, w, h)
        local r = rects[1]
        return {{x = r.x, y = r.y, w = w, h = h}}
    end
    local started, committed, cancelled = 0, 0, 0
    function app:beginGesture()
        self.beforeGesture = {target.Position, target.Size}
        started = started + 1
        return true
    end
    function app:updateGesture(rects)
        local rect = rects[1]
        target.Position, target.Size = UDim2.fromOffset(rect.x, rect.y), UDim2.fromOffset(rect.w, rect.h)
        ui:updateSelection()
        return true
    end
    function app:endGesture() committed = committed + 1; ui:updateSelection() end
    function app:cancelGesture()
        cancelled = cancelled + 1
        target.Position, target.Size = self.beforeGesture[1], self.beforeGesture[2]
        ui:updateSelection()
    end

    local function press(object, x, y)
        local p, s = object.AbsolutePosition, object.AbsoluteSize
        local finger = {UserInputType = Enum.UserInputType.Touch, Position = vec(x or p.X + s.X / 2, y or p.Y + s.Y / 2)}
        object.InputBegan:Fire(finger)
        return finger
    end
    local function move(finger, dx, dy)
        finger.Position = vec(finger.Position.X + dx, finger.Position.Y + dy)
        uis.InputChanged:Fire(finger)
    end
    local function release(finger) uis.InputEnded:Fire(finger) end

    view.X, view.Y = 960, 440
    uis.PreferredInput = Enum.PreferredInput.Touch
    uis.OnScreenKeyboardVisible = false
    target.Position, target.Size = UDim2.fromOffset(50, 60), UDim2.fromOffset(100, 100)
    app.selection, app.preferences.launcherHidden, app.preferences.aspectLock = {}, false, false
    app.input = Input.new(app, ui, services)
    app:setEditing(false)
    release(press(ui.launcher))
    check(app.editing and ui.canvas.Visible and not ui.panel.Visible, "launcher opens a clear mobile editing canvas")
    release(press(ui.canvas, 100, 110))
    check(app.selection[1] == record.key and ui.panel.Visible and ui.sliderEnabled and started == 0,
        "canvas tap selects a target and opens Quick Edit without starting history")
    local finger = press(ui.canvas, 100, 110)
    move(finger, 30, 15)
    ui.toolsButton.Activated:Fire()
    check(not ui.workspace.Visible and app.input:isBusy(), "unrelated toolbar activation cannot interrupt an owned canvas touch")
    ui.percent:CaptureFocus(); ui.percent.Focused:Fire()
    check(not ui.percent:IsFocused() and app.input:isBusy(), "unrelated text focus leaves the owned canvas gesture in place")
    release(finger)
    check(target.AbsolutePosition.X == 80 and target.AbsolutePosition.Y == 75 and committed == 1,
        "canvas drag adjusts the selected target through one transaction")

    view.Y = 236
    ui:layout()
    local track = ui:sliderTrackRect()
    ui.quickBody.ScrollingEnabled = true
    finger = press(ui.slider, track.x + track.w * 84 / 184, track.y)
    move(finger, track.w * 32 / 184, 0)
    check(not ui.quickBody.ScrollingEnabled, "horizontal slider ownership pauses the overflowing native ScrollingFrame")
    release(finger)
    check(math.abs(target.AbsoluteSize.X - 132) < 0.001 and target.AbsolutePosition.X == 80 and committed == 2
        and ui.quickBody.ScrollingEnabled, "relative slider anchors size and restores native scrolling at release")

    view.Y = 440
    ui:layout()
    local handle = ui.touchHandle
    check(handle.gui.Visible, "touch handle remains available outside the selected geometry")
    finger = press(handle.gui)
    move(finger, handle.handle:find("e") and 15 or -15, handle.handle:find("s") and 15 or -15)
    release(finger)
    check(target.AbsoluteSize.X > 132 and committed == 3, "adaptive external handle resizes through the canvas controller")
    local prior = ui.panel.AbsolutePosition
    move(press(ui.inspectorGrip), 0, 36)
    check(ui.panel.AbsolutePosition.Y ~= prior.Y, "inspector grip repositions Quick Edit")
    uis.WindowFocusReleased:Fire()
    check(ui.panel.AbsolutePosition.Y == prior.Y and committed == 3 and cancelled == 0,
        "focus interruption restores inspector position without changing HUD history")
    ui:confirm("Gesture check", "Dialog shields the editing canvas", function() end)
    finger = press(ui.canvas, target.AbsolutePosition.X + 50, target.AbsolutePosition.Y + 50)
    move(finger, 40, 25)
    release(finger)
    check(committed == 3 and not app.input:isBusy(), "modal excludes new canvas gestures")
    ui:closeModal()
    ui.doneButton.Activated:Fire()
    check(not app.editing and not ui.canvas.Visible and ui.launcher.Visible, "Done returns gameplay input while keeping the launcher reachable")
    app.input:destroy()
    app.input = nil
end
checkGestureSurfaces()

local beforeDestroy = mock.destroyed
ui:destroy(); ui:destroy()
check(ui.gui.Destroyed and mock.destroyed > beforeDestroy, "destroy tears down GUI once")
check(mock.activeConnections == 0, "destroy releases every UI connection")
target:Destroy()
second:Destroy()
barObject:Destroy()

return checks
