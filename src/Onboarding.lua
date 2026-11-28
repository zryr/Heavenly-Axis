-- An isolated practice canvas uses the editor's pointer controller without any real HUD or profile references.
local Coordinates = require("Coordinates")
local Design = require("Design")
local Geometry = require("Geometry")
local Input = require("Input")
local Layout = require("UILayout")
local Lucide = require("Lucide")
local Reference = require("ActionReference")

local Onboarding = {}
Onboarding.__index = Onboarding

local function lesson(id, title, action, body, done, highlights)
    return {id = id, title = title, action = action, body = body, done = done, highlights = highlights}
end

local panel = lesson("panel", "Make room to edit", "dragPanel", "Drag the sample inspector by its grip. Move it beside Jump so the control stays visible.",
    "The inspector moved. Jump stayed in place.", {"quickEdit"})
local selectJump = lesson("select", "Tap to select", "select", "Tap practice Jump. Its outline shows which control will change.",
    "Jump is selected. The outline follows the control.")
local moveJump = lesson("move", "Drag to move", "move", "Drag the selected button to an open spot in the practice area.", "You moved Jump without changing its size.")
local resizeJump = lesson("resize", "Resize a control", "size", "Start with two fingers on or near Jump. Spread to grow, pinch together to shrink. Lift either finger to finish.",
    "You resized Jump. The Size slider and corner handle work too.")
local save = lesson("finish", "Save and return to play", "save",
    "Save keeps your edits when storage is available. Done returns to play, and the Axis mark reopens the editor. Help covers separate automatic startup setup.",
    nil, {"save", "done"})

local quick = {
    lesson("welcome", "Practice editing a control", "launcher", "Try moving and resizing a practice control. Then save and return to gameplay.", nil, {"launcher", "toolbar"}),
    panel, selectJump, moveJump, resizeJump, save,
}

local tour = {
    {1, lesson("intro", "Your tools at a glance", "toolbar", "Open the editor from the Axis launcher. In Quick Edit, the four arrows move, the corner arrows resize, the curved arrow rotates, and the droplet changes opacity. Save keeps edits. Done returns to the game.", nil, {"launcher", "toolbar", "done"})},
    {1, panel},
    {1, lesson("workspace", "Find more in Tools", "tools", "Tools contains Layers, Groups, Profiles, Settings, and Help. Collapse Quick Edit to uncover a control. Canvas takes you back to editing.", nil,
        {"tools", "layers", "groups", "profiles", "settings", "help", "collapse"})},
    {2, selectJump},
    {2, lesson("layers", "Pick a layer underneath", "selectThrough", "Hold still on Jump, then choose it beneath the overlay. You can also tap Layers.", "You selected Jump through the overlay.", {"selectThrough"})},
    {2, lesson("scope", "Pick an edit scope", "selectionScope", "Pinch a whole ability to resize it. Pick Individual layer for a badge, or Entire container for the bar.",
        "You resized a complete ability and found its separate visual layers and the entire bar.", {"quickEdit", "layers"})},
    {3, moveJump},
    {3, resizeJump},
    {4, lesson("rotate", "Turn a control", "rotate", "Drag the curved handle around Jump or move the angle slider. The angle steps make small changes. Reset returns the original angle.", "You turned Jump around its center.", {"rotate"})},
    {4, lesson("opacity", "Fade a control", "opacity", "Adjust Opacity from 0 to 100%. Element only fades the control itself. Include contents also fades supported visuals inside it. Find a fully faded control through Layers.", "You changed the practice control's visible opacity.", {"opacity"})},
    {5, lesson("group", "Group unrelated controls", "quickGroup", "Tap Multi, select Jump and Dash, then tap Quick Group. They can move together even when they belong to different parts of the HUD.", "Grouped. Drag either selected control to move both.", {"groups"})},
    {5, lesson("groupOptions", "Adjust a group or a member", "groups", "Name groups for reuse. Resize the group together or apply the same size change to each member. Groups lets you pick individual members, align, distribute, or ungroup them.", nil, {"groups"})},
    {6, lesson("checkpoints", "Work from a checkpoint", "save", "Save establishes a checkpoint. Undo and Redo step through edits. Done offers Save or Discard if needed. Import and export are in Profiles.", nil, {"save", "undo", "redo", "profiles"})},
    {6, lesson("reset", "Restore original settings", "resetElement", "Reset this practice control. Reset All Changes previews the affected edits. Reset Editor Layout moves only Heavenly Axis panels. Safe Mode suspends saved adjustments and keeps your profiles.", "Practice values restored. Saved profiles were left alone.")},
    {7, lesson("compatibility", "Move the ability bar", "compatibility", "The containing bar sets each slot. Tap Select entire bar, then drag it to move all abilities together.",
        "The bar moved. Its abilities stayed in their assigned slots.", {"quickEdit"})},
    {7, save},
}

local chapterNames = {"Editor navigation", "Selection", "Moving and resizing", "Rotation and opacity", "Groups", "Saving and recovery", "Compatibility"}

local layer = 89
local C, F, T = Design.colors, Design.font, Design.text
local touch = Design.touch.minimum
local abilityNames = {"Dash", "Guard", "Burst"}
local abilityIcons = {"move", "shield", "zap"}
local abilityParts = {"Badge", "Icon", "Label", "Overlay"}
local scopeNames = {whole = "Whole control", layer = "Individual layer", container = "Entire container"}
local scopeModes = {"whole", "layer", "container"}
local managedHelp = "The bar sets where this ability sits. Tap Select entire bar, then drag the bar."
local function make(class, props, parent)
    local object = Instance.new(class)
    for name, value in pairs(props) do object[name] = value end
    if object:IsA("GuiObject") then object.Selectable = false end
    object.Parent = parent
    return object
end

local function label(parent, name, size, color, bold, z)
    return make("TextLabel", {Name = name, Text = "", BackgroundTransparency = 1, BorderSizePixel = 0,
        Font = bold and F.strong or F.body, TextSize = size, TextColor3 = color,
        TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top, ZIndex = z}, parent)
end

local function place(object, rect)
    local x, y = Coordinates.screenToLocal(rect.x, rect.y, object.Parent)
    object.Position, object.Size = UDim2.fromOffset(x, y), UDim2.fromOffset(rect.w, rect.h)
end

local function same(first, second)
    return first and second and first.x == second.x and first.y == second.y and first.w == second.w and first.h == second.h
end

function Onboarding.new(parent, services, callbacks)
    return setmetatable({parent = parent, services = services, callbacks = callbacks or {}, connections = {}, progressByMode = {}, active = false}, Onboarding)
end

function Onboarding:_notify()
    if self.callbacks.changed then self.callbacks.changed() end
end

function Onboarding:isActive()
    return self.active
end

function Onboarding:protectedRects()
    if not self.active then return {} end
    local results = {self.coachRect}
    if self.padRect then results[#results + 1] = self.padRect end
    for _, rect in ipairs(self.highlightRects or {}) do results[#results + 1] = rect end
    return results
end

function Onboarding:_resumeStep(mode)
    local step = self.progressByMode[mode]
    if step == nil and self.callbacks.readProgress then step = self.callbacks.readProgress(mode) end
    local maximum = mode == "tour" and #tour or #quick
    if type(step) == "number" and step % 1 == 0 and step > 1 and step <= maximum then return step end
end

function Onboarding:hasProgress(mode)
    return self:_resumeStep(mode == "tour" and "tour" or "quick") ~= nil
end

function Onboarding:_connect(signal, callback)
    self.connections[#self.connections + 1] = signal:Connect(callback)
end

function Onboarding:_button(parent, name, text, primary, callback)
    local button = make("TextButton", {Name = name, Text = text, BorderSizePixel = 0, TextSize = T.control,
        TextColor3 = primary and C.ink or C.text, BackgroundColor3 = primary and C.cyan or C.raised,
        AutoButtonColor = true, TextTruncate = Enum.TextTruncate.AtEnd, Font = F.strong, ZIndex = layer + 4}, parent)
    Design.round(button)
    if callback then self:_connect(button.Activated, function()
        if self.active and (button == self.skip or not self.input or not self.input:isBusy()) then callback() end
    end) end
    return button
end

function Onboarding:_target(name)
    local frame = make("Frame", {Name = "Practice" .. name, BackgroundColor3 = C.control, BorderSizePixel = 0,
        ZIndex = layer + 3, Active = false}, self.canvas)
    pcall(function() frame.Interactable = false end)
    Design.round(frame, Design.radius.surface)
    local edge = Design.stroke(frame, C.border, 2, .16)
    local text = label(frame, "Name", T.body, C.text, true, layer + 4)
    text.Size, text.Text = UDim2.fromScale(1, 1), name
    text.TextXAlignment, text.TextYAlignment = Enum.TextXAlignment.Center, Enum.TextYAlignment.Center
    return {key = name, object = frame, edge = edge, text = text, editable = true}
end

function Onboarding:_abilityPart(key, name, scope, parentKey, depth, color, caption, icon)
    local parent = parentKey and self.targets[parentKey].object or self.canvas
    local object = make("Frame", {Name = "Practice" .. key, Visible = false, BorderSizePixel = 0,
        BackgroundColor3 = color or C.field, BackgroundTransparency = color and 0 or 1,
        ZIndex = layer + depth, Active = false}, parent)
    pcall(function() object.Interactable = false end)
    Design.round(object, scope == "layer" and 5 or Design.radius.control)
    local edge = Design.stroke(object, C.border, 1.5, scope == "layer" and 1 or .4)
    local part = {key = key, name = name, scope = scope, parentKey = parentKey, object = object, edge = edge, editable = true}
    self.targets[key] = part
    if caption then
        local text = label(object, "Caption", T.caption, C.text, true, layer + depth + 1)
        text.Text, text.Size, text.TextScaled = caption, UDim2.fromScale(1, 1), true
        text.TextXAlignment, text.TextYAlignment = Enum.TextXAlignment.Center, Enum.TextYAlignment.Center
        text.TextWrapped = false
    elseif icon then
        local glyph = Lucide.mount(object, icon, {size = 20, color = C.cyan,
            position = UDim2.fromScale(.5, .5), anchor = Vector2.new(.5, .5), zIndex = layer + depth + 1})
        if glyph then part.iconScale = make("UIScale", {Scale = 1}, glyph) end
    end
end

function Onboarding:_mountAbilities()
    self:_abilityPart("AbilityBar", "Ability bar", "container", nil, 3, C.raised)
    for index, name in ipairs(abilityNames) do
        local key = "Ability" .. index
        self:_abilityPart(key, name, "whole", "AbilityBar", 4, C.control)
        self:_abilityPart(key .. "Badge", name .. " number", "layer", key, 5, C.ink, tostring(index))
        self:_abilityPart(key .. "Icon", name .. " icon", "layer", key, 5, nil, nil, abilityIcons[index])
        self:_abilityPart(key .. "Label", name .. " label", "layer", key, 5, nil, name)
        self:_abilityPart(key .. "Overlay", name .. " accent", "layer", key, 5, C.cyan)
        self.targets[key .. "Overlay"].object.BackgroundTransparency = .55
    end
end

function Onboarding:_meter(name, caption)
    local slider = self:_button(self.controls, name, "", false)
    slider.Size = UDim2.fromScale(1, 1)
    local title = label(slider, "Label", T.control, C.text, true, layer + 5)
    title.Text, title.Position, title.Size = caption, UDim2.fromOffset(10, 15), UDim2.fromOffset(50, 18)
    local track = make("Frame", {Name = "Track", BackgroundColor3 = C.border, BorderSizePixel = 0,
        Position = UDim2.fromOffset(64, 20), Size = UDim2.new(1, -78, 0, 4), ZIndex = layer + 5}, slider)
    Design.round(track, 2)
    local thumb = make("Frame", {Name = "Thumb", AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.4, .5),
        Size = UDim2.fromOffset(15, 15), BackgroundColor3 = C.cyan, ZIndex = layer + 6}, track)
    Design.round(thumb, 8)
    return slider, track, thumb, title
end

function Onboarding:_mount()
    self.shield = make("TextButton", {Name = "PracticeShield", Text = "", Active = true, AutoButtonColor = false,
        BackgroundColor3 = C.scrim, BackgroundTransparency = .31,
        BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = layer}, self.parent)
    self.coach = make("Frame", {Name = "TutorialCoach", BackgroundColor3 = C.surface, BorderSizePixel = 0,
        ClipsDescendants = true, ZIndex = layer + 1}, self.shield)
    Design.round(self.coach, Design.radius.dialog)
    Design.stroke(self.coach, C.border)
    self.progress = label(self.coach, "Progress", T.caption, C.cyan, true, layer + 2)
    self.progress.Position, self.progress.Size = UDim2.fromOffset(14, 12), UDim2.new(1, -28, 0, 16)
    self.heading = label(self.coach, "Heading", T.title, C.text, true, layer + 2)
    self.heading.Position, self.heading.Size = UDim2.fromOffset(14, 32), UDim2.new(1, -28, 0, 28)
    self.heading.TextWrapped = false
    self.instructions = make("ScrollingFrame", {Name = "Instructions", Position = UDim2.fromOffset(14, 62),
        Size = UDim2.new(1, -28, 1, -120), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 2, CanvasSize = UDim2.new(),
        ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = layer + 2}, self.coach)
    self.description = label(self.instructions, "Description", T.body, C.subtleText, false, layer + 3)
    self.description.TextTruncate = Enum.TextTruncate.None
    self.skip = self:_button(self.coach, "Skip", "Skip", false, function() self:_finish("skipped") end)
    self.skip.Position, self.skip.Size = UDim2.new(0, 14, 1, -53), UDim2.fromOffset(70, touch)
    self.back = self:_button(self.coach, "Back", "Back", false, function() self:_go(self.step - 1) end)
    self.next = self:_button(self.coach, "Next", "Start", true, function() self:_advance() end)
    self.next.Position, self.next.Size = UDim2.new(1, -108, 1, -53), UDim2.fromOffset(94, touch)
    self.tour = self:_button(self.coach, "GuidedTour", "Open Guided Tour", false, function()
        self:_finish("completed")
        self:start("tour", true)
    end)
    self.tour.Position, self.tour.Size = UDim2.new(0, 12, 1, -100), UDim2.new(1, -24, 0, touch)
    self.highlightFrames = {}

    self.pad = make("Frame", {Name = "PracticePad", BackgroundColor3 = C.surface, BorderSizePixel = 0, ZIndex = layer + 1}, self.shield)
    Design.round(self.pad, Design.radius.dialog)
    Design.stroke(self.pad, C.border)
    self.padTitle = label(self.pad, "PracticeLabel", T.control, C.subtleText, true, layer + 2)
    self.padTitle.Position, self.padTitle.Size = UDim2.fromOffset(12, 9), UDim2.new(1, -24, 0, 16)
    self.canvas = make("TextButton", {Name = "PracticeSurface", Text = "", Active = true, AutoButtonColor = false,
        BackgroundColor3 = C.field, BorderSizePixel = 0, ClipsDescendants = true, ZIndex = layer + 2}, self.pad)
    Design.round(self.canvas, Design.radius.surface)
    self.targets = {Jump = self:_target("Jump"), Move = self:_target("Move")}
    self.targets.Move.text.Text = "Dash"
    self.overlay = make("Frame", {Name = "TransparentPracticeLayer", BackgroundColor3 = C.cyan,
        BackgroundTransparency = .91, BorderSizePixel = 0, ZIndex = layer + 5, Visible = false}, self.canvas)
    pcall(function() self.overlay.Interactable = false end)
    Design.round(self.overlay)
    Design.stroke(self.overlay, C.border)
    self.overlayRecord = {key = "Overlay", object = self.overlay, editable = false}
    self.handle = make("TextButton", {Name = "PracticeResize", Text = "", AutoButtonColor = false,
        BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = layer + 6, Visible = false}, self.canvas)
    self.marker = make("Frame", {Name = "Marker", AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5),
        Size = UDim2.fromOffset(13, 13), BorderSizePixel = 0, BackgroundColor3 = C.cyan, ZIndex = layer + 7}, self.handle)
    Design.round(self.marker, Design.radius.marker)
    local rotate = self:_button(self.canvas, "PracticeRotation", "", false)
    rotate.BackgroundTransparency = 1
    local rotateMarker = make("Frame", {Name = "RotationMarker", BackgroundColor3 = C.cyan, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.fromOffset(23, 23), ZIndex = layer + 7}, rotate)
    Design.round(rotateMarker, 12)
    Lucide.mount(rotateMarker, "rotate-cw", {size = 15, color = C.ink, position = UDim2.fromScale(.5, .5),
        anchor = Vector2.new(.5, .5), zIndex = layer + 8})
    self.rotationHandle = {gui = rotate, marker = rotateMarker}

    self.practicePanel = make("Frame", {Name = "PracticeInspector", BackgroundColor3 = C.raised,
        BorderSizePixel = 0, ZIndex = layer + 6}, self.canvas)
    Design.round(self.practicePanel, Design.radius.surface)
    Design.stroke(self.practicePanel, C.border)
    self.practiceGrip = self:_button(self.practicePanel, "PracticeGrip", "Grab inspector", false)
    self.practiceGrip.Size, self.practiceGrip.ZIndex = UDim2.fromScale(1, 1), layer + 7
    self.controls = make("Frame", {Name = "PracticeTools", BackgroundTransparency = 1, ZIndex = layer + 2}, self.pad)
    self.controls.Position, self.controls.Size = UDim2.new(0, 10, 1, -52), UDim2.new(1, -20, 0, touch)
    self.slider, self.track, self.thumb = self:_meter("PracticeSize", "Size")
    self.angleSlider, self.angleTrack, self.angleThumb, self.angleLabel = self:_meter("PracticeAngle", "Angle")
    self.opacitySlider, self.opacityTrack, self.opacityThumb, self.opacityLabel = self:_meter("PracticeOpacity", "Opacity")
    self.opacitySlider.Size = UDim2.new(1, -96, 1, 0)
    self.scopeButton = self:_button(self.controls, "PracticeOpacityScope", "Element only", false, function()
        local contents = self.practiceUI.opacityScope ~= "contents"
        self.practiceUI.opacityScope = contents and "contents" or "element"
        self.scopeButton.Text = contents and "Include contents" or "Element only"
        self:_drawTargets()
    end)
    self.scopeButton.TextWrapped, self.scopeButton.TextTruncate = true, Enum.TextTruncate.None
    self.scopeButton.Position, self.scopeButton.Size = UDim2.new(1, -90, 0, 0), UDim2.fromOffset(90, touch)
    self.resetButton = self:_button(self.controls, "ResetPractice", "Reset practice", true, function()
        self.angle, self.opacity = 0, 100
        self:_relocate()
        self:_completeLesson()
    end)
    self.resetButton.Size = UDim2.fromScale(1, 1)
    self.layers = self:_button(self.controls, "PracticeLayers", "Layers", false, function()
        self:_showLayers({self.overlayRecord, self.targets.Jump})
    end)
    self.layers.Size = UDim2.fromScale(1, 1)
    self.chooseOverlay = self:_button(self.controls, "ChooseOverlay", "Overlay", false, function()
        self:_describe("Pick Jump to select the control beneath that layer.")
    end)
    self.chooseJump = self:_button(self.controls, "ChooseJump", "Jump", true, function()
        self:_select("Jump")
        self.layerPicker = false
        self:_completeLesson()
        self:_drawTools()
    end)
    self.multi = self:_button(self.controls, "PracticeMulti", "Multi", false, function()
        self.app.preferences.multiSelect = not self.app.preferences.multiSelect
        self.multi.Text = self.app.preferences.multiSelect and "Multi on" or "Multi"
    end)
    self.group = self:_button(self.controls, "PracticeGroup", "Quick Group", true, function()
        if #self.app.selection > 1 then self:_completeLesson()
        else self:_describe("Tap Multi, then tap both practice controls before grouping them.") end
    end)
    for _, button in ipairs({self.chooseOverlay, self.multi}) do button.Size = UDim2.new(.5, -3, 1, 0) end
    for _, button in ipairs({self.chooseJump, self.group}) do
        button.Position, button.Size = UDim2.new(.5, 3, 0, 0), UDim2.new(.5, -3, 1, 0)
    end
    self.selectionScopeButtons = {}
    for index, scope in ipairs(scopeModes) do
        local button = self:_button(self.controls, "PracticeScope_" .. scope, scopeNames[scope]:gsub(" ", "\n"), false,
            function() self:_setPracticeScope(scope) end)
        button.TextWrapped, button.TextTruncate = true, Enum.TextTruncate.None
        button.Position = UDim2.new((index - 1) / 3, 2, 0, 0)
        button.Size = UDim2.new(1 / 3, -4, 1, 0)
        self.selectionScopeButtons[scope] = button
    end
    self.selectBar = self:_button(self.controls, "PracticeSelectBar", "Select entire bar", false, function()
        self.scopeMode = "container"
        self:_select("AbilityBar")
    end)
    self.selectBar.Size = UDim2.fromScale(1, 1)
end

function Onboarding:_describe(text)
    self.description.Text = text
    local width = self.descriptionWidth
    if not width then return end
    if width == self.measuredDescriptionWidth and text == self.measuredDescription then return end
    self.measuredDescriptionWidth, self.measuredDescription = width, text
    local textService = self.services.TextService
    local ok, measured = pcall(function()
        return textService:GetTextSize(text, T.body, F.body, Vector2.new(width, 10000)).Y
    end)
    local height = ok and type(measured) == "number" and measured >= 0 and measured < 10000 and math.ceil(measured) + 4
    if not height then
        local lines, used, capacity = 1, 0, math.max(1, math.floor(width / (T.body * .55)))
        for word in text:gmatch("%S+") do
            if used > 0 and used + #word + 1 > capacity then lines, used = lines + 1, 0 end
            used = used + #word + 1
        end
        height = lines * (T.body + 4)
    end
    self.description.Size = UDim2.fromOffset(width, height)
    self.instructions.CanvasSize = UDim2.fromOffset(0, height)
end

function Onboarding:_completeLesson()
    local lesson = self.lesson
    if not self.lessonComplete and lesson.done then
        self.lessonComplete = true
        self:_describe(lesson.done)
        self.description.TextColor3 = C.cyan
    end
end

function Onboarding:_drawTools()
    local id = self.lesson.id
    self.slider.Visible = id == "resize"
    self.angleSlider.Visible = id == "rotate"
    self.opacitySlider.Visible, self.scopeButton.Visible = id == "opacity", id == "opacity"
    self.resetButton.Visible = id == "reset"
    self.layers.Visible = id == "layers" and not self.layerPicker
    self.chooseOverlay.Visible, self.chooseJump.Visible = self.layerPicker == true, self.layerPicker == true
    self.multi.Visible, self.group.Visible = id == "group", id == "group"
    for scope, button in pairs(self.selectionScopeButtons) do
        button.Visible = id == "scope"
        local active = self.scopeMode == scope
        button.BackgroundColor3, button.TextColor3 = active and C.selected or C.raised, active and C.cyan or C.text
    end
    self.selectBar.Visible = id == "compatibility"
end

function Onboarding:_showLayers(hits)
    if self.lesson.id ~= "layers" or #hits < 2 then return false end
    self.layerPicker = true
    self:_describe("Choose the control you want to edit.")
    self:_drawTools()
    return true
end

local function selected(keys, value)
    for index, key in ipairs(keys) do if key == value then return index end end
end

function Onboarding:_scopeComplete()
    local seen = self.scopeSeen
    if seen.whole and seen.layer and seen.container and self.scopeResized then self:_completeLesson() end
end

function Onboarding:_setPracticeScope(scope)
    if self.scopeMode ~= scope then
        self.input:cancel()
        self.scopeMode = scope
        self.app.selection = {}
    end
    if not self.lessonComplete then
        local hints = {
            whole = "Tap an ability. The large outline includes its number, icon, label, and decoration. Then pinch to resize them together.",
            layer = "Tap a number, icon, or label. Drag the small outline to adjust just that layer.",
            container = "Tap anywhere on the bar. Drag inside the outer outline to move all three abilities together.",
        }
        self:_describe(hints[scope])
    end
    self:_drawTools()
    self:_drawTargets()
end

function Onboarding:_select(key, additive)
    if additive then
        local index = selected(self.app.selection, key)
        if index then table.remove(self.app.selection, index) else self.app.selection[#self.app.selection + 1] = key end
    else self.app.selection = key and {key} or {} end
    if key == "Jump" and self.lesson.id == "select" then self:_completeLesson() end
    local target = self.targets[key]
    if target and target.scope and self.lesson.id == "scope" then
        self.scopeSeen[target.scope] = true
        self:_scopeComplete()
    elseif target and self.lesson.id == "compatibility" and not self.lessonComplete then
        self:_describe(key == "AbilityBar" and "Drag the bar to an open spot. All abilities will keep their slots." or managedHelp)
    end
    self:_drawTargets()
end

function Onboarding:_sizeInfo(rect)
    local target, canvas = rect or self.rects.Jump, self.canvasRect
    if not target or not canvas then return nil end
    local maximum = math.min(canvas.w - 12, canvas.h - 8)
    if maximum <= 38 then return nil end
    return {scale = target.w, minimum = 38, maximum = maximum, size = target}
end

function Onboarding:_abilityHits(x, y)
    local bar = self.targets.AbilityBar
    local barHit = Coordinates.contains(self.rects.AbilityBar, x, y)
    for index in ipairs(abilityNames) do
        local ability = "Ability" .. index
        if self.scopeMode ~= "layer" and Coordinates.contains(self.rects[ability], x, y) then
            local target = self.scopeMode == "container" and bar or self.targets[ability]
            return {target}, target
        end
        for _, part in ipairs(abilityParts) do
            local key = ability .. part
            if Coordinates.contains(self.rects[key], x, y) then
                local target = self.scopeMode == "container" and bar or self.targets[self.scopeMode == "layer" and key or ability]
                return {target}, target
            end
        end
    end
    if barHit and self.scopeMode == "container" then return {bar}, bar end
    return {}, false
end

function Onboarding:_drawTargets()
    local canvas = self.canvasRect
    if not canvas then return end
    local keys = self.app.selection
    local focused = self.targets[keys[1]]
    self.padTitle.Text = focused and focused.scope and (focused.name .. " · " .. scopeNames[focused.scope]) or "Practice canvas"
    for key, target in pairs(self.targets) do
        local rect = self.rects[key]
        if target.object.Visible ~= (rect ~= nil) then target.object.Visible = rect ~= nil end
        if rect then
            local origin = target.parentKey and self.rects[target.parentKey] or canvas
            target.object.Position = UDim2.fromOffset(rect.x - origin.x, rect.y - origin.y)
            target.object.Size = UDim2.fromOffset(rect.w, rect.h)
            local active = selected(keys, key)
            target.edge.Color = active and C.cyan or C.border
            if target.scope then
                target.edge.Transparency = active and 0 or (target.scope == "layer" and 1 or .4)
                if target.iconScale then target.iconScale.Scale = math.max(.55, math.min(1.65, math.min(rect.w, rect.h) / 22)) end
            else
                target.object.Rotation = key == "Jump" and self.angle or 0
                target.object.BackgroundTransparency = key == "Jump" and 1 - self.opacity / 100 or 0
                target.text.TextTransparency = key == "Jump" and self.practiceUI.opacityScope == "contents" and 1 - self.opacity / 100 or 0
            end
        end
    end
    local jump = self.rects.Jump
    self.overlay.Visible = self.lesson.id == "layers" and jump ~= nil
    if self.overlay.Visible then
        self.overlay.Position = UDim2.fromOffset(jump.x - canvas.x - 12, jump.y - canvas.y - 8)
        self.overlay.Size = UDim2.fromOffset(jump.w + 24, jump.h + 16)
    end
    local resize = self.lesson.id == "resize" and selected(keys, "Jump") and jump
    self.handle.Visible = false
    if resize then
        local x, y = jump.x + jump.w + 2, jump.y + jump.h - 26
        if x + touch <= canvas.x + canvas.w and y >= canvas.y and y + touch <= canvas.y + canvas.h then
            self.handle.Position, self.handle.Size = UDim2.fromOffset(x - canvas.x, y - canvas.y), UDim2.fromOffset(touch, touch)
            self.handle.Visible = true
        end
    end
    local rotate = self.rotationHandle.gui
    rotate.Visible = false
    if self.lesson.id == "rotate" and selected(keys, "Jump") and jump then
        local x, y = jump.x + jump.w + 6, jump.y - 16
        if x + touch <= canvas.x + canvas.w then
            y = math.max(canvas.y, math.min(y, canvas.y + canvas.h - touch))
            rotate.Position, rotate.Size = UDim2.fromOffset(x - canvas.x, y - canvas.y), UDim2.fromOffset(touch, touch)
            rotate.Visible = true
        end
    end
    self.practicePanel.Visible = self.lesson.id == "panel" and self.sampleRect ~= nil
    if self.practicePanel.Visible then
        local sample = self.sampleRect
        self.practicePanel.Position = UDim2.fromOffset(sample.x - canvas.x, sample.y - canvas.y)
        self.practicePanel.Size = UDim2.fromOffset(sample.w, sample.h)
    end
    local info = self:_sizeInfo()
    if info then self.thumb.Position = UDim2.fromScale(math.max(0, math.min(1, (info.scale - info.minimum) / (info.maximum - info.minimum))), .5) end
    self.angleThumb.Position = UDim2.fromScale(math.max(0, math.min(1, (self.angle + 180) / 360)), .5)
    self.opacityThumb.Position = UDim2.fromScale(self.opacity / 100, .5)
    self.angleLabel.Text = string.format("%d°", math.floor(self.angle + .5))
    self.opacityLabel.Text = string.format("%d%%", math.floor(self.opacity + .5))
end

local function relativeRect(child, before, after)
    local sx, sy = after.w / before.w, after.h / before.h
    return {x = after.x + (child.x - before.x) * sx, y = after.y + (child.y - before.y) * sy,
        w = child.w * sx, h = child.h * sy}
end

function Onboarding:_movePracticeTarget(key, rect)
    local original = self.before.rects[key]
    local placed = Layout.place(rect, self.canvasRect, rect.x, rect.y)
    self.rects[key] = placed
    if not self.targets[key].scope then return end
    for partKey, part in pairs(self.targets) do
        local parent = part.parentKey
        while parent do
            if parent == key then
                local child = self.before.rects[partKey]
                if child then self.rects[partKey] = relativeRect(child, original, placed) end
                break
            end
            parent = self.targets[parent].parentKey
        end
    end
end

function Onboarding:_createInput()
    local owner = self
    local app = {selection = {}, editing = true, preferences = {aspectLock = true, gridSize = 24}}
    app.discovery = {}
    function app:canvasHits(x, y)
        if owner.lesson.id == "scope" or owner.lesson.id == "compatibility" then return owner:_abilityHits(x, y) end
        local hits, primary = {}, nil
        for _, key in ipairs({"Jump", "Move"}) do
            if Coordinates.contains(owner.rects[key], x, y) then hits[#hits + 1] = owner.targets[key]; primary = primary or owner.targets[key] end
        end
        if owner.lesson.id == "layers" and Coordinates.contains(Coordinates.rect(owner.overlay), x, y) then
            table.insert(hits, 1, owner.overlayRecord)
        end
        return hits, primary or false
    end
    function app.discovery:hit(x, y) return app:canvasHits(x, y, false) end
    function app.discovery:get(key) return owner.targets[key] or (key == "Overlay" and owner.overlayRecord or nil) end
    function app.discovery:list() return {owner.targets.Jump, owner.targets.Move} end
    function app:capability(key)
        local managed = owner.lesson.id == "compatibility" and key ~= "AbilityBar"
        local record = self.discovery:get(key)
        return {supported = not managed and record and record.editable == true, reason = managed and managedHelp or nil}
    end
    function app:status(text) owner:_describe(text) end
    function app:getRects(_, operation)
        local rects, keys, skipped = {}, {}, 0
        for _, key in ipairs(self.selection) do
            local rect = owner.rects[key]
            if rect and (not operation or self:capability(key).supported) then
                rects[#rects + 1], keys[#keys + 1] = rect, key
            else
                skipped = skipped + 1
            end
        end
        return rects, keys, skipped
    end
    function app:currentBounds() return Geometry.bounds(self:getRects()) end
    function app:select(key, additive) owner:_select(key, additive) end
    function app:clearSelection() owner:_select(nil) end
    function app:selectMany(keys) self.selection = keys; owner:_drawTargets() end
    function app:sizeInfo(bounds) return owner:_sizeInfo(bounds) end
    function app:sizeRects(rects, w, h)
        local bounds = Geometry.bounds(rects)
        return Geometry.scale(rects, {x = bounds.x, y = bounds.y, w = w, h = h}, false)
    end
    function app:appearanceInfo(kind, scope)
        local jump = owner.rects.Jump
        if not jump or self.selection[1] ~= "Jump" then return nil end
        return {value = kind == "rotation" and owner.angle or owner.opacity, minimum = kind == "rotation" and -180 or 0,
            maximum = kind == "rotation" and 180 or 100, keys = {"Jump"}, skipped = 0, scope = scope,
            pivot = {x = jump.x + jump.w / 2, y = jump.y + jump.h / 2}}
    end
    function app:updateAppearance(kind, value)
        if kind == "rotation" then
            owner.angle = value >= -180 and value <= 180 and value or (value + 180) % 360 - 180
        else owner.opacity = math.max(0, math.min(100, value)) end
        owner:_drawTargets()
        return true
    end
    function app:beginGesture(label)
        local rects = {}
        for key, rect in pairs(owner.rects) do rects[key] = rect end
        owner.before = {rects = rects, angle = owner.angle, opacity = owner.opacity, label = label}
        return true
    end
    function app:updateGesture(rects, keys)
        for index, key in ipairs(keys) do owner:_movePracticeTarget(key, rects[index]) end
        owner:_drawTargets()
        return true
    end
    function app:cancelGesture()
        local before = owner.before
        if before then
            owner.rects, owner.angle, owner.opacity, owner.before = before.rects, before.angle, before.opacity, nil
            owner:_drawTargets()
        end
    end
    function app:endGesture()
        local state = owner.before
        owner.before = nil
        if not state then return end
        local before, after = state.rects.Jump, owner.rects.Jump
        if before and after then
            if (owner.lesson.id == "move" and (math.abs(before.x - after.x) > 5 or math.abs(before.y - after.y) > 5))
                or (owner.lesson.id == "resize" and math.abs(before.w - after.w) > 2)
                or (owner.lesson.id == "rotate" and math.abs(state.angle - owner.angle) > 2)
                or (owner.lesson.id == "opacity" and math.abs(state.opacity - owner.opacity) > 2) then owner:_completeLesson() end
        end
        if owner.lesson.id == "scope" and state.label == "Pinch resize" then
            local key = self.selection[1]
            if key and state.rects[key] and owner.targets[key].scope == "whole"
                and math.abs(state.rects[key].w - owner.rects[key].w) > 2 then
                owner.scopeResized = true
                owner:_scopeComplete()
            end
        elseif owner.lesson.id == "compatibility" and not same(state.rects.AbilityBar, owner.rects.AbilityBar) then
            owner:_completeLesson()
        end
    end

    local practiceUI = {canvas = self.canvas, slider = self.slider, handles = {{gui = self.handle, marker = self.marker, handle = "se"}},
        rotationHandle = self.rotationHandle, visualSliders = {rotation = self.angleSlider, opacity = self.opacitySlider},
        opacityScope = "element", inspectorGrip = self.practiceGrip}
    function practiceUI:pointInPanel(x, y) return not Coordinates.contains(owner.canvasRect, x, y) end
    function practiceUI:setBox() end
    function practiceUI:setGuides() end
    function practiceUI:sliderTrackRect() return owner.slider.Visible and Coordinates.rect(owner.track) or nil end
    function practiceUI:visualSliderTrackRect(kind)
        local track = kind == "rotation" and owner.angleTrack or owner.opacityTrack
        return track.Parent.Visible and Coordinates.rect(track) or nil
    end
    function practiceUI:getTransformTool()
        local mode = owner.lesson.id
        return mode == "resize" and "size" or (mode == "rotate" or mode == "opacity") and mode or "move"
    end
    function practiceUI:surfacePosition()
        local rect = owner.sampleRect
        if rect then return rect.x, rect.y end
    end
    function practiceUI:moveSurface(_, x, y)
        owner.sampleStart = owner.sampleStart or owner.sampleRect
        owner.sampleRect = Layout.place(owner.sampleRect, owner.canvasRect, x, y)
        owner:_drawTargets()
    end
    function practiceUI:finishSurfaceMove(_, cancelled)
        local before = owner.sampleStart
        if cancelled and before then owner.sampleRect = before; owner:_drawTargets()
        elseif before and not same(before, owner.sampleRect) then owner:_completeLesson() end
        owner.sampleStart = nil
    end
    local actual = self.services.UserInputService
    local practiceInput = {InputChanged = actual.InputChanged, InputEnded = actual.InputEnded, WindowFocusReleased = actual.WindowFocusReleased}
    function practiceInput:IsKeyDown(key) return actual:IsKeyDown(key) end
    function practiceInput:GetFocusedTextBox() return actual:GetFocusedTextBox() end
    self.app, self.practiceUI = app, practiceUI
    self.input = Input.new(app, practiceUI, {UserInputService = practiceInput})
end

function Onboarding:_highlightTargets(area)
    local found = {}
    if self.callbacks.highlight then
        for _, id in ipairs(self.lesson.highlights or {}) do
            local target = self.callbacks.highlight(id)
            local rect = type(target) == "table" and target.x and target or Coordinates.rect(target)
            if rect and Coordinates.intersection(rect, area) then found[#found + 1] = rect end
        end
    end
    self.highlightRects = found
    for index, rect in ipairs(found) do
        local object = self.highlightFrames[index]
        if not object then
            object = make("Frame", {Name = "EditorHighlight", BackgroundTransparency = 1, Active = false, ZIndex = layer + 1}, self.shield)
            pcall(function() object.Interactable = false end)
            Design.stroke(object, C.cyan, 2, .14)
            Design.round(object, 8)
            self.highlightFrames[index] = object
        end
        place(object, rect)
        object.Visible = true
    end
    for index = #found + 1, #self.highlightFrames do self.highlightFrames[index].Visible = false end
end

function Onboarding:_layout()
    local area, id = self.area, self.lesson.id
    if not area or area.w < 160 or area.h < 54 then self.shield.Visible = false; self.coachRect, self.padRect = nil, nil; return end
    self.shield.Visible = true
    self:_highlightTargets(area)
    local landscape = area.w >= 466 and area.w >= area.h * 1.12
    local abilities = id == "scope" or id == "compatibility"
    local practice = self.lesson.done ~= nil and area.h >= (landscape and 190 or 278) and (not abilities or area.w >= 226)
    if self.lesson.done and practice ~= self.practiceAvailable and not self.lessonComplete then
        self:_describe(practice and self.lesson.body or "Make more room to try this exercise, or tap Next to continue.")
    end
    self.practiceAvailable = practice
    landscape = landscape and practice
    local totalWidth = math.min(area.w, landscape and 720 or 420)
    local coachWidth = landscape and math.min(310, math.floor(totalWidth * .43)) or totalWidth
    local offerTour = self.mode == "quick" and self.step == #quick and area.h >= 174
    local coachHeight = math.min(area.h, practice and 186 or (offerTour and 242 or 216))
    local padHeight, padWidth = 0, 0
    if practice then
        padWidth = landscape and totalWidth - coachWidth - 10 or totalWidth
        padHeight = landscape and math.min(242, area.h) or math.min(245, math.floor(area.h * .56))
        if not landscape then coachHeight = math.min(coachHeight, area.h - padHeight - 10) end
    end
    local fullHeight = landscape and math.max(coachHeight, padHeight) or coachHeight + (practice and padHeight + 10 or 0)
    local x, y = area.x + math.floor((area.w - totalWidth) / 2), area.y + math.floor((area.h - fullHeight) / 2)
    self.coachRect = {x = x, y = y, w = coachWidth, h = coachHeight}
    if not practice then
        for _, candidateY in ipairs({y, area.y + area.h - coachHeight, area.y}) do
            local candidate = {x = x, y = candidateY, w = coachWidth, h = coachHeight}
            local clear = true
            for _, target in ipairs(self.highlightRects) do if Layout.intersects(candidate, target) then clear = false; break end end
            if clear then self.coachRect = candidate; break end
        end
    end
    place(self.coach, self.coachRect)
    local width = math.min(88, math.floor((coachWidth - 20 - 8) / 3))
    self.skip.Position, self.skip.Size = UDim2.new(0, 10, 1, -53), UDim2.fromOffset(width, touch)
    self.back.Position, self.back.Size = UDim2.new(.5, -width / 2, 1, -53), UDim2.fromOffset(width, touch)
    self.next.Position, self.next.Size = UDim2.new(1, -10 - width, 1, -53), UDim2.fromOffset(width, touch)
    self.tour.Visible, self.back.Visible = offerTour, self.step > 1
    self.instructions.Size = UDim2.new(1, -28, 1, offerTour and -166 or -120)
    self.descriptionWidth = math.max(1, coachWidth - 34)
    self:_describe(self.description.Text)
    self.progress.Visible, self.heading.Visible, self.instructions.Visible = coachHeight >= 108, coachHeight >= 108, coachHeight >= 140
    self.pad.Visible = practice
    self.padRect, self.canvasRect = nil, nil
    if not practice then self.rects = {}; return end
    self.padRect = {x = landscape and x + coachWidth + 10 or x, y = landscape and y or y + coachHeight + 10, w = padWidth, h = padHeight}
    place(self.pad, self.padRect)
    local controls = abilities or id == "resize" or id == "layers" or id == "group" or id == "rotate" or id == "opacity" or id == "reset"
    self.controls.Visible = controls
    local height = padHeight - (controls and 85 or 42)
    self.canvasRect = {x = self.padRect.x + 10, y = self.padRect.y + 31, w = padWidth - 20, h = height}
    self.canvas.Position, self.canvas.Size = UDim2.fromOffset(10, 31), UDim2.fromOffset(padWidth - 20, height)
    self:_drawTools()
end

function Onboarding:_relocateAbilities(oldCanvas)
    local canvas = self.canvasRect
    local previous = oldCanvas and self.rects.AbilityBar
    if previous then
        local x = canvas.x + (previous.x - oldCanvas.x) / oldCanvas.w * canvas.w
        local y = canvas.y + (previous.y - oldCanvas.y) / oldCanvas.h * canvas.h
        local bar = Layout.place(previous, canvas, x, y)
        local placed = {AbilityBar = bar}
        for key, rect in pairs(self.rects) do
            if key ~= "AbilityBar" then placed[key] = relativeRect(rect, previous, bar) end
        end
        self.rects = placed
        return
    end
    local w = math.min(242, canvas.w - 26)
    local h = math.min(90, math.floor(canvas.h * .65))
    local bar = {x = canvas.x + (canvas.w - w) / 2, y = canvas.y + (canvas.h - h) / 2, w = w, h = h}
    local result = {AbilityBar = bar}
    local width = (bar.w - 32) / 3
    for index in ipairs(abilityNames) do
        local key = "Ability" .. index
        local card = {x = bar.x + 8 + (index - 1) * (width + 8), y = bar.y + 8, w = width, h = bar.h - 16}
        local badgeH = math.min(16, card.h * .30)
        local iconSize = math.min(23, card.h * .40)
        result[key] = card
        result[key .. "Badge"] = {x = card.x + 4, y = card.y + 4, w = 19, h = badgeH}
        result[key .. "Icon"] = {x = card.x + (card.w - iconSize) * .55, y = card.y + card.h * .25, w = iconSize, h = iconSize}
        result[key .. "Label"] = {x = card.x + 5, y = card.y + card.h - 17, w = card.w - 10, h = 14}
        result[key .. "Overlay"] = {x = card.x + card.w - 7, y = card.y + 6, w = 3, h = card.h * .59}
    end
    self.rects = result
end

function Onboarding:_relocate(oldCanvas)
    local canvas = self.canvasRect
    if not canvas then self.rects = {}; return end
    if self.lesson.id == "scope" or self.lesson.id == "compatibility" then
        self:_relocateAbilities(oldCanvas)
        self:_drawTargets()
        return
    end
    local targetSize = math.min(64, math.max(16, math.floor(canvas.h * .56)))
    local nextRects = {}
    for _, key in ipairs(self.lesson.id == "group" and {"Jump", "Move"} or {"Jump"}) do
        local previous = oldCanvas and self.rects[key]
        local fraction = key == "Move" and .73 or (self.lesson.id == "group" and .27 or .47)
        local x = canvas.x + canvas.w * fraction - targetSize / 2
        local y = canvas.y + canvas.h * .43 - targetSize / 2
        if previous then
            x = canvas.x + (previous.x - oldCanvas.x) / oldCanvas.w * canvas.w
            y = canvas.y + (previous.y - oldCanvas.y) / oldCanvas.h * canvas.h
        end
        nextRects[key] = Layout.place(previous or {w = targetSize, h = targetSize}, canvas, x, y)
    end
    self.rects = nextRects
    if self.lesson.id == "panel" then
        local sample = oldCanvas and self.sampleRect
        local jump = nextRects.Jump
        local x, y = jump.x - 24, jump.y - 30
        if sample then x, y = canvas.x + (sample.x - oldCanvas.x), canvas.y + (sample.y - oldCanvas.y) end
        self.sampleRect = Layout.place(sample or {w = 118, h = touch}, canvas, x, y)
    end
    self:_drawTargets()
end

function Onboarding:layout(area)
    local oldArea, oldCanvas = self.area, self.canvasRect
    self.area = area
    if not self.active then return end
    if not area or area.w < 160 or area.h < 54 then self:close(); return end
    if not same(oldArea, area) and self.input then self.input:cancel() end
    self:_layout()
    self:_relocate(oldCanvas)
end

function Onboarding:_go(step)
    self.input:cancel()
    local chapter = self.mode == "tour" and self.route[step][1] or nil
    self.step, self.lesson, self.lessonComplete, self.layerPicker = step, chapter and self.route[step][2] or self.route[step], false, false
    self.progressByMode[self.mode] = step
    local lesson = self.lesson
    local action = Reference.get(lesson.action)
    if (lesson.id == "scope" or lesson.id == "compatibility") and not self.targets.AbilityBar then self:_mountAbilities() end
    if self.lessonIcon then self.lessonIcon:Destroy() end
    self.lessonIcon = action.icon and Lucide.mount(self.coach, action.icon,
        {size = 18, color = C.cyan, position = UDim2.fromOffset(14, 35), anchor = Vector2.new(0, 0), zIndex = layer + 3}) or nil
    local headingLeft = self.lessonIcon and 40 or 14
    self.heading.Position, self.heading.Size = UDim2.fromOffset(headingLeft, 32), UDim2.new(1, -headingLeft - 14, 0, 28)
    self.progress.Text = chapter and string.format("%d / 7  •  %s", chapter, chapterNames[chapter])
        or string.format("QUICK START  %d / %d", step, #self.route)
    self.heading.Text = lesson.title or action.label
    self:_describe(lesson.body or action.how)
    self.instructions.CanvasPosition = Vector2.new(0, 0)
    self.description.TextColor3 = C.subtleText
    self.next.Text = self.mode == "quick" and step == 1 and "Start" or (step == #self.route and "Finish" or "Next")
    self.app.preferences.multiSelect, self.multi.Text = false, "Multi"
    self.app.openSelectThrough = lesson.id == "layers" and function(_, hits) return self:_showLayers(hits) end or nil
    self.angle, self.opacity = lesson.id == "reset" and 28 or 0, lesson.id == "reset" and 55 or 100
    self.scopeMode, self.scopeSeen, self.scopeResized = "whole", {}, false
    self.practiceUI.opacityScope, self.scopeButton.Text = "element", "Element only"
    self.sampleRect, self.sampleStart, self.practiceAvailable = nil, nil, nil
    local hasSelection = lesson.id == "move" or lesson.id == "resize" or lesson.id == "rotate" or lesson.id == "opacity" or lesson.id == "reset"
    self.app.selection = hasSelection and {"Jump"} or {}
    self:_layout()
    self:_relocate()
    self:_notify()
end

function Onboarding:start(mode, resume)
    if self.dead or self.active then return false end
    self.mode = mode == "tour" and "tour" or "quick"
    self.route = self.mode == "tour" and tour or quick
    local step = resume and self:_resumeStep(self.mode) or 1
    self.active, self.rects = true, {}
    self.descriptionWidth, self.measuredDescriptionWidth, self.measuredDescription = nil, nil, nil
    self:_mount()
    self:_createInput()
    self:_go(step or 1)
    return true
end

function Onboarding:_advance()
    if self.step == #self.route then self:_finish("completed") else self:_go(self.step + 1) end
end

function Onboarding:_finish(outcome)
    local mode = self.mode
    self:close(outcome)
    if self.callbacks.finished then self.callbacks.finished(outcome, mode) end
end

function Onboarding:close(outcome)
    if not self.active then return end
    local mode = self.mode
    local progress = outcome ~= "completed" and self.step > 1 and self.step or nil
    self.progressByMode[mode] = progress or false
    self.active = false
    self.input:destroy()
    for _, connection in ipairs(self.connections) do connection:Disconnect() end
    self.connections = {}
    self.shield:Destroy()
    self.input, self.app, self.practiceUI, self.shield, self.coachRect, self.padRect, self.canvasRect = nil, nil, nil, nil, nil, nil, nil
    self.before, self.rects, self.highlightRects, self.highlightFrames = nil, nil, nil, nil
    self.lessonIcon, self.targets, self.selectionScopeButtons, self.selectBar, self.padTitle = nil, nil, nil, nil, nil
    self:_notify()
    if self.callbacks.saveProgress then self.callbacks.saveProgress(mode, progress) end
end

function Onboarding:destroy()
    if self.dead then return end
    self:close()
    self.dead = true
    self.callbacks, self.area = {}, nil
end

return Onboarding
