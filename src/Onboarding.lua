-- An isolated practice canvas uses the editor's pointer controller without any real HUD or profile references.
local Coordinates = require("Coordinates")
local Geometry = require("Geometry")
local Input = require("Input")
local Layout = require("UILayout")

local Onboarding = {}
Onboarding.__index = Onboarding

local lessons = {
    {id = "welcome", title = "Make your HUD your own", body = "Try a few edits on practice controls. Your game controls and saved layouts stay as they are."},
    {id = "select", title = "Tap to select", body = "Tap the practice Jump button. Its outline shows which control will change.", done = "Jump is selected. The outline follows the control."},
    {id = "move", title = "Drag to move", body = "Drag the selected button to a new spot in the practice area.", done = "You moved Jump. Its size stayed the same."},
    {id = "resize", title = "Make it fit", body = "Pinch the button, drag its corner handle, or slide Size. On desktop, use the handle or slider.", done = "You resized Jump. All three methods adjust the same control."},
    {id = "layers", title = "Pick a layer underneath", body = "Hold Jump still to open its layers. Pick Jump beneath the overlay. You can also tap Layers.", done = "You picked Jump through the overlay."},
    {id = "group", title = "Edit two controls together", body = "Optional. Tap Multi, select both practice controls, then tap Group.", done = "Grouped. Drag either selected control to move both."},
    {id = "finish", title = "Keep your changes", body = "Save stores your edits. Undo steps back. Done returns to play and offers Save or Discard if needed. Tap the Axis launcher to reopen. Automatic startup has its own setup in Help."},
}

local layer = 89
local function make(class, props, parent)
    local object = Instance.new(class)
    for name, value in pairs(props) do object[name] = value end
    if object:IsA("GuiObject") then object.Selectable = false end
    object.Parent = parent
    return object
end

local function round(parent, radius)
    make("UICorner", {CornerRadius = UDim.new(0, radius)}, parent)
end

local function stroke(parent, color, thickness)
    return make("UIStroke", {Color = color, Thickness = thickness or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, parent)
end

local function label(parent, name, size, color, bold, z)
    return make("TextLabel", {Name = name, Text = "", BackgroundTransparency = 1, BorderSizePixel = 0,
        Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham, TextSize = size, TextColor3 = color,
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
    return setmetatable({parent = parent, services = services, callbacks = callbacks or {}, connections = {}, active = false}, Onboarding)
end

function Onboarding:_notify()
    if self.callbacks.changed then self.callbacks.changed() end
end

function Onboarding:isActive()
    return self.active
end

function Onboarding:protectedRects()
    return self.active and {self.coachRect, self.padRect} or {}
end

function Onboarding:_connect(signal, callback)
    self.connections[#self.connections + 1] = signal:Connect(callback)
end

function Onboarding:_button(parent, name, text, primary, callback)
    local p = self.palette
    local button = make("TextButton", {Name = name, Text = text, BorderSizePixel = 0, TextSize = 13,
        TextColor3 = primary and p.ink or p.text, BackgroundColor3 = primary and p.accent or p.raised,
        AutoButtonColor = true, TextTruncate = Enum.TextTruncate.AtEnd, Font = Enum.Font.GothamBold, ZIndex = layer + 4}, parent)
    round(button, 9)
    if callback then self:_connect(button.Activated, function()
        if self.active and (button == self.skip or not self.input or not self.input:isBusy()) then callback() end
    end) end
    return button
end

function Onboarding:_target(name)
    local p = self.palette
    local frame = make("Frame", {Name = "Practice" .. name, BackgroundColor3 = p.control, BorderSizePixel = 0,
        ZIndex = layer + 3, Active = false}, self.canvas)
    pcall(function() frame.Interactable = false end)
    round(frame, 14)
    local edge = stroke(frame, p.border, 2)
    local text = label(frame, "Name", 14, p.text, true, layer + 4)
    text.Size, text.Text = UDim2.fromScale(1, 1), name
    text.TextXAlignment, text.TextYAlignment = Enum.TextXAlignment.Center, Enum.TextYAlignment.Center
    return {key = name, object = frame, edge = edge, editable = true}
end

function Onboarding:_mount()
    local p = {surface = Color3.fromRGB(15, 26, 36), raised = Color3.fromRGB(29, 47, 59),
        ink = Color3.fromRGB(8, 30, 39), text = Color3.fromRGB(239, 247, 250),
        body = Color3.fromRGB(183, 204, 216), accent = Color3.fromRGB(116, 233, 236),
        border = Color3.fromRGB(59, 87, 105), control = Color3.fromRGB(39, 83, 99)}
    self.palette = p
    self.shield = make("TextButton", {Name = "PracticeShield", Text = "", Active = true, AutoButtonColor = false,
        BackgroundColor3 = Color3.fromRGB(4, 13, 20), BackgroundTransparency = .31,
        BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = layer}, self.parent)
    self.coach = make("Frame", {Name = "TutorialCoach", BackgroundColor3 = p.surface, BorderSizePixel = 0,
        ClipsDescendants = true, ZIndex = layer + 1}, self.shield)
    round(self.coach, 14)
    stroke(self.coach, p.border)
    self.progress = label(self.coach, "Progress", 11, p.accent, true, layer + 2)
    self.progress.Position, self.progress.Size = UDim2.fromOffset(14, 12), UDim2.new(1, -28, 0, 16)
    self.heading = label(self.coach, "Heading", 20, p.text, true, layer + 2)
    self.heading.Position, self.heading.Size = UDim2.fromOffset(14, 32), UDim2.new(1, -28, 0, 28)
    self.heading.TextWrapped = false
    self.instructions = make("ScrollingFrame", {Name = "Instructions", Position = UDim2.fromOffset(14, 62),
        Size = UDim2.new(1, -28, 1, -120), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 2, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = layer + 2}, self.coach)
    self.description = label(self.instructions, "Description", 13, p.body, false, layer + 3)
    self.description.Size = UDim2.new(1, -6, 0, 18)
    self.description.AutomaticSize = Enum.AutomaticSize.Y
    self.description.TextTruncate = Enum.TextTruncate.None
    self.skip = self:_button(self.coach, "Skip", "Skip", false, function() self:_finish("skipped") end)
    self.skip.Position, self.skip.Size = UDim2.new(0, 14, 1, -53), UDim2.fromOffset(70, 44)
    self.next = self:_button(self.coach, "Next", "Start", true, function() self:_advance() end)
    self.next.Position, self.next.Size = UDim2.new(1, -108, 1, -53), UDim2.fromOffset(94, 44)

    self.pad = make("Frame", {Name = "PracticePad", BackgroundColor3 = p.surface, BorderSizePixel = 0, ZIndex = layer + 1}, self.shield)
    round(self.pad, 14)
    stroke(self.pad, p.border)
    local padTitle = label(self.pad, "PracticeLabel", 12, p.body, true, layer + 2)
    padTitle.Text, padTitle.Position, padTitle.Size = "Practice canvas", UDim2.fromOffset(12, 9), UDim2.new(1, -24, 0, 16)
    self.canvas = make("TextButton", {Name = "PracticeSurface", Text = "", Active = true, AutoButtonColor = false,
        BackgroundColor3 = p.ink, BorderSizePixel = 0, ClipsDescendants = true, ZIndex = layer + 2}, self.pad)
    round(self.canvas, 10)
    self.targets = {Jump = self:_target("Jump"), Move = self:_target("Move")}
    self.overlay = make("Frame", {Name = "TransparentPracticeLayer", BackgroundColor3 = p.accent,
        BackgroundTransparency = .91, BorderSizePixel = 0, ZIndex = layer + 5, Visible = false}, self.canvas)
    pcall(function() self.overlay.Interactable = false end)
    round(self.overlay, 8)
    stroke(self.overlay, p.border)
    self.overlayRecord = {key = "Overlay", object = self.overlay, editable = false}
    self.handle = make("TextButton", {Name = "PracticeResize", Text = "", AutoButtonColor = false,
        BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = layer + 6, Visible = false}, self.canvas)
    self.marker = make("Frame", {Name = "Marker", AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5),
        Size = UDim2.fromOffset(13, 13), BorderSizePixel = 0, BackgroundColor3 = p.accent, ZIndex = layer + 7}, self.handle)
    round(self.marker, 3)
    self.controls = make("Frame", {Name = "PracticeTools", BackgroundTransparency = 1, ZIndex = layer + 2}, self.pad)
    self.controls.Position, self.controls.Size = UDim2.new(0, 10, 1, -52), UDim2.new(1, -20, 0, 44)
    self.slider = self:_button(self.controls, "PracticeSize", "", false)
    self.slider.Size = UDim2.fromScale(1, 1)
    local sizeLabel = label(self.slider, "SizeLabel", 12, p.text, true, layer + 5)
    sizeLabel.Text, sizeLabel.Position, sizeLabel.Size = "Size", UDim2.fromOffset(12, 15), UDim2.fromOffset(44, 18)
    self.track = make("Frame", {Name = "Track", BackgroundColor3 = p.border, BorderSizePixel = 0,
        Position = UDim2.fromOffset(58, 20), Size = UDim2.new(1, -75, 0, 4), ZIndex = layer + 5}, self.slider)
    round(self.track, 2)
    self.thumb = make("Frame", {Name = "Thumb", AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.4, .5),
        Size = UDim2.fromOffset(15, 15), BackgroundColor3 = p.accent, BorderSizePixel = 0, ZIndex = layer + 6}, self.track)
    round(self.thumb, 8)
    self.layers = self:_button(self.controls, "PracticeLayers", "Layers", false, function()
        self:_showLayers({self.overlayRecord, self.targets.Jump})
    end)
    self.layers.Size = UDim2.fromScale(1, 1)
    self.chooseOverlay = self:_button(self.controls, "ChooseOverlay", "Overlay", false, function()
        self.description.Text = "Pick Jump to select the control beneath that layer."
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
    self.group = self:_button(self.controls, "PracticeGroup", "Group", true, function()
        if #self.app.selection > 1 then self:_completeLesson()
        else self.description.Text = "Tap Multi, then tap both practice controls before grouping them." end
    end)
    for _, button in ipairs({self.chooseOverlay, self.multi}) do button.Size = UDim2.new(.5, -3, 1, 0) end
    for _, button in ipairs({self.chooseJump, self.group}) do
        button.Position, button.Size = UDim2.new(.5, 3, 0, 0), UDim2.new(.5, -3, 1, 0)
    end
end

function Onboarding:_completeLesson()
    local lesson = self.lesson
    if not self.lessonComplete and lesson.done then
        self.lessonComplete = true
        self.description.Text = lesson.done
        self.description.TextColor3 = self.palette.accent
    end
end

function Onboarding:_drawTools()
    local id = self.lesson.id
    self.slider.Visible = id == "resize"
    self.layers.Visible = id == "layers" and not self.layerPicker
    self.chooseOverlay.Visible, self.chooseJump.Visible = self.layerPicker == true, self.layerPicker == true
    self.multi.Visible, self.group.Visible = id == "group", id == "group"
end

function Onboarding:_showLayers(hits)
    if self.lesson.id ~= "layers" or #hits < 2 then return false end
    self.layerPicker = true
    self.description.Text = "Choose the control you want to edit."
    self:_drawTools()
    return true
end

local function selected(keys, value)
    for index, key in ipairs(keys) do if key == value then return index end end
end

function Onboarding:_select(key, additive)
    if additive then
        local index = selected(self.app.selection, key)
        if index then table.remove(self.app.selection, index) else self.app.selection[#self.app.selection + 1] = key end
    else self.app.selection = key and {key} or {} end
    if key == "Jump" and self.lesson.id == "select" then self:_completeLesson() end
    self:_drawTargets()
end

function Onboarding:_sizeInfo()
    local jump, canvas = self.rects.Jump, self.canvasRect
    if not jump or not canvas then return nil end
    local maximum = math.min(canvas.w - 12, canvas.h - 8)
    if maximum <= 38 then return nil end
    return {scale = jump.w, minimum = 38, maximum = maximum, size = jump}
end

function Onboarding:_drawTargets()
    local canvas = self.canvasRect
    if not canvas then return end
    local p, keys = self.palette, self.app.selection
    for key, target in pairs(self.targets) do
        local rect = self.rects[key]
        target.object.Visible = rect ~= nil
        if rect then
            target.object.Position, target.object.Size = UDim2.fromOffset(rect.x - canvas.x, rect.y - canvas.y), UDim2.fromOffset(rect.w, rect.h)
            target.edge.Color = selected(keys, key) and p.accent or p.border
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
        if x + 44 <= canvas.x + canvas.w and y >= canvas.y and y + 44 <= canvas.y + canvas.h then
            self.handle.Position, self.handle.Size = UDim2.fromOffset(x - canvas.x, y - canvas.y), UDim2.fromOffset(44, 44)
            self.handle.Visible = true
        end
    end
    local info = self:_sizeInfo()
    if info then self.thumb.Position = UDim2.fromScale(math.max(0, math.min(1, (info.scale - info.minimum) / (info.maximum - info.minimum))), .5) end
end

function Onboarding:_createInput()
    local owner = self
    local app = {selection = {}, editing = true, preferences = {aspectLock = true, gridSize = 24}}
    app.discovery = {}
    function app:canvasHits(x, y)
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
    function app.discovery:get(key) return owner.targets[key] end
    function app.discovery:list() return {owner.targets.Jump, owner.targets.Move} end
    function app:getRects()
        local rects, keys = {}, {}
        for _, key in ipairs(self.selection) do
            if owner.rects[key] then rects[#rects + 1], keys[#keys + 1] = owner.rects[key], key end
        end
        return rects, keys, 0
    end
    function app:currentBounds() return Geometry.bounds(self:getRects()) end
    function app:select(key, additive) owner:_select(key, additive) end
    function app:clearSelection() owner:_select(nil) end
    function app:selectMany(keys) self.selection = keys; owner:_drawTargets() end
    function app:sizeInfo() return owner:_sizeInfo() end
    function app:sizeRects(rects, w, h)
        local bounds = Geometry.bounds(rects)
        return Geometry.scale(rects, {x = bounds.x, y = bounds.y, w = w, h = h}, false)
    end
    function app:beginGesture()
        owner.before = {Jump = owner.rects.Jump, Move = owner.rects.Move}
        return true
    end
    function app:updateGesture(rects, keys)
        for index, key in ipairs(keys) do
            owner.rects[key] = Layout.place(rects[index], owner.canvasRect, rects[index].x, rects[index].y)
        end
        owner:_drawTargets()
        return true
    end
    function app:cancelGesture()
        if owner.before then owner.rects, owner.before = owner.before, nil; owner:_drawTargets() end
    end
    function app:endGesture()
        local before, after = owner.before and owner.before.Jump, owner.rects.Jump
        owner.before = nil
        if before and after then
            if (owner.lesson.id == "move" and (math.abs(before.x - after.x) > 5 or math.abs(before.y - after.y) > 5))
                or (owner.lesson.id == "resize" and math.abs(before.w - after.w) > 2) then owner:_completeLesson() end
        end
    end

    local practiceUI = {canvas = self.canvas, slider = self.slider, handles = {{gui = self.handle, marker = self.marker, handle = "se"}}}
    function practiceUI:pointInPanel(x, y) return not Coordinates.contains(owner.canvasRect, x, y) end
    function practiceUI:setBox() end
    function practiceUI:setGuides() end
    function practiceUI:sliderTrackRect() return owner.slider.Visible and Coordinates.rect(owner.track) or nil end
    local actual = self.services.UserInputService
    local practiceInput = {InputChanged = actual.InputChanged, InputEnded = actual.InputEnded, WindowFocusReleased = actual.WindowFocusReleased}
    function practiceInput:IsKeyDown(key) return actual:IsKeyDown(key) end
    function practiceInput:GetFocusedTextBox() return actual:GetFocusedTextBox() end
    self.app = app
    self.input = Input.new(app, practiceUI, {UserInputService = practiceInput})
end

function Onboarding:_layout()
    local area, id = self.area, self.lesson.id
    if not area or area.w < 160 or area.h < 54 then self.shield.Visible = false; self.coachRect, self.padRect = nil, nil; return end
    self.shield.Visible = true
    local landscape = area.w >= 466 and area.w >= area.h * 1.12
    local practice = self.step ~= 1 and self.step ~= #lessons and area.h >= (landscape and 190 or 278)
    landscape = landscape and practice
    local totalWidth = math.min(area.w, landscape and 720 or 420)
    local coachWidth = landscape and math.min(310, math.floor(totalWidth * .43)) or totalWidth
    local coachHeight = math.min(area.h, practice and 180 or 216)
    local padHeight, padWidth = 0, 0
    if practice then
        padWidth = landscape and totalWidth - coachWidth - 10 or totalWidth
        padHeight = landscape and math.min(242, area.h) or math.min(245, math.floor(area.h * .56))
        if not landscape then coachHeight = math.min(coachHeight, area.h - padHeight - 10) end
    end
    local fullHeight = landscape and math.max(coachHeight, padHeight) or coachHeight + (practice and padHeight + 10 or 0)
    local x, y = area.x + math.floor((area.w - totalWidth) / 2), area.y + math.floor((area.h - fullHeight) / 2)
    self.coachRect = {x = x, y = y, w = coachWidth, h = coachHeight}
    place(self.coach, self.coachRect)
    local skipWidth = math.min(70, math.floor((coachWidth - 36) * .46))
    local nextWidth = math.min(94, coachWidth - 36 - skipWidth)
    self.skip.Size = UDim2.fromOffset(skipWidth, 44)
    self.next.Position, self.next.Size = UDim2.new(1, -14 - nextWidth, 1, -53), UDim2.fromOffset(nextWidth, 44)
    self.progress.Visible, self.heading.Visible, self.instructions.Visible = coachHeight >= 108, coachHeight >= 108, coachHeight >= 140
    self.pad.Visible = practice
    self.padRect, self.canvasRect = nil, nil
    if not practice then self.rects = {}; return end
    self.padRect = {x = landscape and x + coachWidth + 10 or x, y = landscape and y or y + coachHeight + 10, w = padWidth, h = padHeight}
    place(self.pad, self.padRect)
    local controls = id == "resize" or id == "layers" or id == "group"
    self.controls.Visible = controls
    local height = padHeight - (controls and 85 or 42)
    self.canvasRect = {x = self.padRect.x + 10, y = self.padRect.y + 31, w = padWidth - 20, h = height}
    self.canvas.Position, self.canvas.Size = UDim2.fromOffset(10, 31), UDim2.fromOffset(padWidth - 20, height)
    self:_drawTools()
end

function Onboarding:_relocate(oldCanvas)
    local canvas = self.canvasRect
    if not canvas then self.rects = {}; return end
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
    self:_drawTargets()
end

function Onboarding:layout(area)
    local oldArea, oldCanvas = self.area, self.canvasRect
    self.area = area
    if not self.active then return end
    if not same(oldArea, area) and self.input then self.input:cancel() end
    self:_layout()
    self:_relocate(oldCanvas)
end

function Onboarding:_go(step)
    self.input:cancel()
    self.step, self.lesson, self.lessonComplete, self.layerPicker = step, lessons[step], false, false
    local lesson = self.lesson
    self.progress.Text = step == 1 and "HEAVENLY AXIS" or string.format("PRACTICE  %d/%d", step - 1, #lessons - 1)
    self.heading.Text, self.description.Text = lesson.title, lesson.body
    self.description.TextColor3 = self.palette.body
    self.next.Text = step == 1 and "Start" or (step == #lessons and "Finish" or "Next")
    self.app.preferences.multiSelect, self.multi.Text = false, "Multi"
    self.app.openSelectThrough = lesson.id == "layers" and function(_, hits) return self:_showLayers(hits) end or nil
    self.app.selection = (lesson.id == "move" or lesson.id == "resize") and {"Jump"} or {}
    self:_layout()
    self:_relocate()
    self:_notify()
end

function Onboarding:start()
    if self.dead or self.active then return false end
    self.active, self.rects = true, {}
    self:_mount()
    self:_createInput()
    self:_go(1)
    return true
end

function Onboarding:_advance()
    if self.step == #lessons then self:_finish("completed") else self:_go(self.step + 1) end
end

function Onboarding:_finish(outcome)
    self:close()
    if self.callbacks.finished then self.callbacks.finished(outcome) end
end

function Onboarding:close()
    if not self.active then return end
    self.active = false
    self.input:destroy()
    for _, connection in ipairs(self.connections) do connection:Disconnect() end
    self.connections = {}
    self.shield:Destroy()
    self.input, self.app, self.shield, self.coachRect, self.padRect, self.canvasRect = nil, nil, nil, nil, nil, nil
    self.before, self.rects = nil, nil
    self:_notify()
end

function Onboarding:destroy()
    if self.dead then return end
    self:close()
    self.dead = true
    self.callbacks, self.area = {}, nil
end

return Onboarding
