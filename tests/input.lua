-- Gestures exercised with identity-preserving InputObjects; no executor claims.
local Geometry = require("Geometry")
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local function close(a, b) return math.abs(a - b) < 0.001 end
local function signal()
    local callbacks = {}
    return {
        Connect = function(_, callback)
            local entry = {callback = callback, active = true}
            callbacks[#callbacks + 1] = entry
            return {Disconnect = function() entry.active = false end}
        end,
        Fire = function(_, ...)
            for _, entry in ipairs(callbacks) do if entry.active then entry.callback(...) end end
        end,
        Count = function()
            local count = 0
            for _, entry in ipairs(callbacks) do if entry.active then count = count + 1 end end
            return count
        end,
    }
end
Enum = {UserInputType = {Touch = "touch", MouseButton1 = "mouse1", MouseButton2 = "mouse2", MouseMovement = "mouseMove", Keyboard = "keyboard"},
    UserInputState = {Cancel = "cancel", End = "end"}, KeyCode = {}}
for _, name in ipairs({"F8", "F9", "Z", "Y", "S", "B", "Escape", "Left", "Right", "Up", "Down",
    "LeftShift", "RightShift", "LeftControl", "RightControl", "LeftAlt", "RightAlt", "Unknown"}) do Enum.KeyCode[name] = name end
UDim2 = {fromOffset = function(x, y) return {x = x, y = y} end}
local Input = require("Input")
local function pointer(kind, x, y)
    local input = {UserInputType = kind, Position = {X = x, Y = y}, StateChanged = signal()}
    function input:GetPropertyChangedSignal(property)
        assert(property == "UserInputState")
        return self.StateChanged
    end
    return input
end
local function setup()
    local ui = {visible = true, handles = {}, gui = {AbsoluteSize = {X = 800, Y = 600}}}
    local function button(x, y, w, h)
        return {InputBegan = signal(), AbsolutePosition = {X = x, Y = y}, AbsoluteSize = {X = w, Y = h}, Visible = true}
    end
    ui.canvas = button(0, 0, 800, 600)
    ui.slider = button(300, 500, 200, 30)
    ui.launcher = button(0, 300, 44, 44)
    ui.inspectorGrip = button(310, 480, 180, 20)
    ui.handles[1] = {gui = button(107, 107, 44, 44), handle = "se"}
    function ui:pointInPanel(x, y) return self.modalOpen or y >= 480 or (x <= 44 and y >= 300 and y <= 344) end
    function ui:inspectorPosition() return 300, 480 end
    function ui:moveInspector(x, y) self.inspectPos = {x = x, y = y} end
    function ui:finishInspectorMove(abort) self.inspectorFinished = {cancelled = abort} end
    function ui:moveLauncher(x, y) self.launcherPos = {x = x, y = y} end
    function ui:finishLauncherMove(abort) self.launcherFinished = {cancelled = abort} end
    function ui:setSliderDragging(dragging) self.sliderDragging = dragging end
    function ui:setBox(value) self.lastBox = value end
    function ui:setGuides(value) self.lastGuides = value end
    function ui:setOverlaps(value) self.overlaps = value end
    local uis = {InputChanged = signal(), InputEnded = signal(), InputBegan = signal(),
        WindowFocusReleased = signal(), modifiers = {}}
    function uis:IsKeyDown(key) return self.modifiers[key] == true end
    function uis:GetFocusedTextBox() return self.focused end
    local app = {editing = true, preferences = {}, selection = {"a"}, starts = 0, ends = 0, cancels = 0,
        rects = {a = {x = 0, y = 0, w = 100, h = 100}}}
    function app:getRects()
        local rects, keys = {}, {}
        for _, key in ipairs(self.selection) do
            if self.rects[key] then rects[#rects + 1] = self.rects[key]; keys[#keys + 1] = key end
        end
        return rects, keys
    end
    function app:currentBounds() return Geometry.bounds(self:getRects()) end
    function app:sizeInfo()
        local bounds = self:currentBounds()
        if bounds then return {minimum = 50, maximum = 200, scale = bounds.w, bounds = bounds} end
    end
    function app:sizeRects(rects, w, h, center, _, axis)
        self.sliderAxis = axis
        local bounds = Geometry.bounds(rects)
        return Geometry.scale(rects, {x = bounds.x, y = bounds.y, w = w, h = h}, center)
    end
    function app:beginGesture() self.starts = self.starts + 1; self.before = {x = self.rects.a.x, y = self.rects.a.y, w = self.rects.a.w, h = self.rects.a.h} end
    function app:updateGesture(rects, keys) for i, key in ipairs(keys) do self.rects[key] = rects[i] end end
    function app:endGesture() self.ends = self.ends + 1 end
    function app:cancelGesture() self.cancels = self.cancels + 1; self.rects.a = self.before end
    function app:select(key, toggle)
        if toggle and self.selection[1] == key then self.selection = {} else self.selection = {key} end
    end
    function app:selectMany(keys) self.selection = keys end
    function app:clearSelection() self.selection = {} end
    function app:setPreference(key, value) self.preferences[key] = value end
    function app:setEditing(value) self.editing = value end
    function app:undo() self.undos = (self.undos or 0) + 1 end
    function app:redo() self.redos = (self.redos or 0) + 1 end
    function app:save() self.saves = (self.saves or 0) + 1 end
    function app:move(x, y) self.moves = {x, y} end
    local record = {key = "a", editable = true, object = {Parent = nil, AbsolutePosition = {X = 0, Y = 0}, AbsoluteSize = {X = 100, Y = 100}}}
    app.discovery = {alignmentCalls = 0}
    function app.discovery:hit(x, y) if x <= 100 and y <= 100 then return {record} else return {} end end
    function app.discovery:list() return {record} end
    function app.discovery:get(key) return key == "a" and record or nil end
    function app.discovery:alignmentRects()
        self.alignmentCalls = self.alignmentCalls + 1
        return {}
    end
    local input = Input.new(app, ui, {UserInputService = uis})
    return app, ui, uis, input
end

local app, ui, uis, controller = setup()
local finger = pointer("touch", 20, 20)
ui.canvas.InputBegan:Fire(finger)
check(app.starts == 0 and controller:isBusy(), "press owns the canvas without starting a transaction")
finger.Position = {X = 23, Y = 23}
uis.InputChanged:Fire(finger)
check(app.starts == 0 and app.rects.a.x == 0, "tap jitter stays below the touch movement threshold")
local other = pointer("touch", 25, 25)
uis.InputChanged:Fire(other)
uis.InputEnded:Fire(other)
check(app.rects.a.x == 0 and app.ends == 0, "unrelated touch cannot move or end a drag")
finger.Position = {X = 50, Y = 70}
uis.InputChanged:Fire(finger)
check(app.rects.a.x == 30 and app.rects.a.y == 50, "touch position drives drag directly")
uis.InputChanged:Fire(finger)
check(app.starts == 1 and app.discovery.alignmentCalls == 1, "one drag snapshots alignment targets once")
uis.InputEnded:Fire(finger)
uis.InputEnded:Fire(finger)
check(app.ends == 1, "one completed drag is one history action")
check(finger.StateChanged:Count() == 0, "end disconnects the pointer state watcher")
controller:destroy()

app, ui, uis, controller = setup()
finger = pointer("touch", 20, 20)
finger.UserInputState = Enum.UserInputState.End
uis.InputEnded:Fire(finger)
ui.canvas.InputBegan:Fire(finger)
check(not controller:isBusy(), "a delayed GUI begin for an already-ended pointer cannot strand ownership")
controller:destroy()

app, ui, uis, controller = setup()
finger = pointer("touch", 20, 20)
ui.canvas.InputBegan:Fire(finger)
finger.Position = {X = 35, Y = 38}
uis.InputEnded:Fire(finger)
check(app.starts == 1 and app.ends == 1 and app.rects.a.x == 15 and app.rects.a.y == 18,
    "a final touch position omitted from InputChanged finalizes a fast drag")
controller:destroy()

app, ui, uis, controller = setup()
finger = pointer("touch", 10, 10)
local second = pointer("touch", 90, 90)
ui.canvas.InputBegan:Fire(finger)
ui.canvas.InputBegan:Fire(second)
second.Position = {X = 170, Y = 170}
uis.InputChanged:Fire(second)
check(close(app.rects.a.w, 200) and close(app.rects.a.x, -10), "pinch scales about initial finger midpoint")
second.Position = {X = 380, Y = 380}
uis.InputChanged:Fire(second)
check(close(app.rects.a.w, 200), "pinch growth stays within the viewport-aware sizing range established at gesture start")
uis.InputEnded:Fire(second)
finger.Position = {X = 50, Y = 50}
uis.InputChanged:Fire(finger)
check(app.starts == 1 and app.ends == 1 and close(app.rects.a.w, 200), "pinch commits once and remaining finger cannot continue")
uis.InputEnded:Fire(finger)
controller:destroy()

app, ui, uis, controller = setup()
finger = pointer("touch", 10, 10)
ui.canvas.InputBegan:Fire(finger)
finger.Position = {X = 50, Y = 50}
uis.InputChanged:Fire(finger)
uis.WindowFocusReleased:Fire()
check(app.rects.a.x == 0 and app.cancels == 1 and app.ends == 0, "focus loss rolls back unfinished gesture")
controller:destroy()

app, ui, uis, controller = setup()
app.preferences.multiSelect = true
finger = pointer("touch", 10, 10)
ui.canvas.InputBegan:Fire(finger)
uis.InputEnded:Fire(finger)
check(#app.selection == 0 and app.starts == 0, "multi-select tap toggles without transform history")
controller:destroy()

app, ui, uis, controller = setup()
app.preferences.multiSelect = true
finger = pointer("touch", 10, 10)
ui.canvas.InputBegan:Fire(finger)
finger.Position = {X = 50, Y = 50}
uis.InputChanged:Fire(finger)
uis.InputEnded:Fire(finger)
check(app.starts == 1 and app.ends == 1 and app.rects.a.x == 40, "multi-select selected target can drag the entire selection")
controller:destroy()

app, ui, uis, controller = setup()
local mouse = pointer("mouse1", 350, 510)
ui.slider.InputBegan:Fire(mouse)
check(app.rects.a.w == 100 and app.starts == 0, "slider press does not jump before a tap or drag is recognized")
uis.InputChanged:Fire(pointer("mouseMove", 400, 510))
uis.InputChanged:Fire(pointer("mouseMove", 450, 510))
uis.InputEnded:Fire(pointer("mouse1", 450, 510))
check(close(app.rects.a.w, 162.5) and app.starts == 1 and app.ends == 1 and app.sliderAxis == "x",
    "relative slider drag requests the width axis and creates one action")
controller:destroy()

app, ui, uis, controller = setup()
uis.modifiers.LeftControl = true
uis.InputBegan:Fire({UserInputType = "keyboard", KeyCode = "Z"}, false)
check(app.undos == 1, "Ctrl+Z edits history while editor open")
uis.focused = {}
uis.InputBegan:Fire({UserInputType = "keyboard", KeyCode = "Z"}, false)
check(app.undos == 1, "typing into focused input never invokes editor shortcuts")
uis.focused = nil
app.editing = false
uis.InputBegan:Fire({UserInputType = "keyboard", KeyCode = "Z"}, false)
check(app.undos == 1, "gameplay shortcuts remain untouched while editor closed")
uis.InputBegan:Fire({UserInputType = "keyboard", KeyCode = "F8"}, false)
check(app.editing, "shortcut recovers closed editor")
controller:destroy()
uis.InputBegan:Fire({UserInputType = "keyboard", KeyCode = "F8"}, false)
check(app.editing, "destroy disconnects global input handlers")

app, ui, uis, controller = setup()
app.editing = false
app.preferences.shortcut = "UnavailableImportedKey"
setmetatable(Enum.KeyCode, {__index = function(_, name) error(name .. " is not a valid Enum.KeyCode member") end})
local keyOK = pcall(function() uis.InputBegan:Fire({UserInputType = "keyboard", KeyCode = "F8"}, false) end)
check(keyOK and app.editing, "invalid imported enum member cannot disable F8 editor recovery")
app.preferences.shortcut = "F9"
uis.InputBegan:Fire({UserInputType = "keyboard", KeyCode = "F9"}, false)
check(not app.editing, "valid configured shortcut still works with Roblox-style throwing enum access")
setmetatable(Enum.KeyCode, nil)
controller:destroy()

app, ui, uis, controller = setup()
function app:beginGesture() return false end
finger = pointer("touch", 10, 10)
ui.canvas.InputBegan:Fire(finger)
finger.Position = {X = 50, Y = 50}
uis.InputChanged:Fire(finger)
uis.InputEnded:Fire(finger)
check(app.rects.a.x == 0 and app.ends == 0, "refused transaction cannot mutate or commit another owner")
controller:destroy()

app, ui, uis, controller = setup()
local beginGesture, endGesture = app.beginGesture, app.endGesture
function app:beginGesture(...)
    if self.settling then return false end
    return beginGesture(self, ...)
end
function app:endGesture()
    endGesture(self)
    self.settling = true
end
local function quickDrag(from, to)
    local input = pointer("touch", from, 20)
    ui.canvas.InputBegan:Fire(input)
    input.Position = {X = to, Y = 20}
    uis.InputChanged:Fire(input)
    uis.InputEnded:Fire(input)
end
quickDrag(20, 35)
quickDrag(40, 55)
check(app.rects.a.x == 15 and app.starts == 1 and app.ends == 1 and app.cancels == 0 and not controller:isBusy(),
    "a rapid follow-up while the prior transaction is verifying neither alters nor rolls back that transaction")
app.settling = false
quickDrag(40, 55)
check(app.rects.a.x == 30 and app.starts == 2 and app.ends == 2, "a fresh pointer succeeds once verification releases the transaction")
controller:destroy()

app, ui, uis, controller = setup()
app.preferences.centerScale = true
finger = pointer("touch", 10, 10)
second = pointer("touch", 90, 90)
ui.canvas.InputBegan:Fire(finger)
ui.canvas.InputBegan:Fire(second)
second.Position = {X = 170, Y = 170}
uis.InputChanged:Fire(second)
check(close(app.rects.a.x, -10), "pinch midpoint remains attached even with center-scale preference")
second.Position = {X = 10.1, Y = 10.1}
uis.InputChanged:Fire(second)
check(app.rects.a.w >= 16 and app.rects.a.h >= 16, "pinch cannot produce impractical dimensions")
controller:destroy()

app, ui, uis, controller = setup()
app.preferences.equalSize = true
app.selection = {"a", "b"}
app.rects.b = {x = 560, y = 0, w = 60, h = 160}
function app:sizeInfo() return {minimum = 50, maximum = 200, scale = 100, size = {w = 100, h = 160}} end
finger, second = pointer("touch", 10, 10), pointer("touch", 50, 50)
ui.canvas.InputBegan:Fire(finger)
ui.canvas.InputBegan:Fire(second)
second.Position = {X = 70, Y = 70}
uis.InputChanged:Fire(second)
uis.InputEnded:Fire(second)
check(close(app.rects.a.w, 150) and close(app.rects.b.w, 110) and close(app.rects.b.w / app.rects.b.h, 60 / 160),
    "independent group pinch applies equal width changes and keeps each member's aspect ratio")
controller:destroy()

app, ui, uis, controller = setup()
ui.modalOpen = true
uis.modifiers.LeftControl = true
uis.InputBegan:Fire({UserInputType = "keyboard", KeyCode = "S"}, false)
ui.slider.InputBegan:Fire(pointer("touch", 350, 510))
check(not app.saves and app.starts == 0, "modal shields keyboard and behind-modal slider gestures")
controller:destroy()

app, ui, uis, controller = setup()
app.selection = {}
finger = pointer("touch", 10, 10)
ui.canvas.InputBegan:Fire(finger)
finger.Position = {X = 14, Y = 14}
uis.InputChanged:Fire(finger)
uis.InputEnded:Fire(finger)
check(app.selection[1] == "a" and app.starts == 0 and #ui.overlaps == 1, "tap latches selection and overlap choices without history")
controller:destroy()

app, ui, uis, controller = setup()
function app.discovery:hit() return {self:get("a")}, false end
finger = pointer("touch", 30, 25)
ui.canvas.InputBegan:Fire(finger)
uis.InputEnded:Fire(finger)
check(#app.selection == 0 and #ui.overlaps == 1 and app.starts == 0,
    "tapping transparent structure clears selection and retains the explicit overlap candidate")
uis.modifiers.LeftAlt = true
mouse = pointer("mouse1", 30, 25)
ui.canvas.InputBegan:Fire(mouse)
uis.InputEnded:Fire(mouse)
check(app.selection[1] == "a", "desktop Alt can explicitly select a transparent structural candidate")
controller:destroy()

app, ui, uis, controller = setup()
finger = pointer("touch", 375, 510)
ui.slider.InputBegan:Fire(finger)
uis.InputEnded:Fire(finger)
check(app.starts == 0 and app.rects.a.w == 100, "offset thumb tap is a no-op")
finger = pointer("touch", 375, 510)
ui.slider.InputBegan:Fire(finger)
finger.Position = {X = 415, Y = 510}
uis.InputChanged:Fire(finger)
local lower, upper = controller:sliderRange()
check(lower == 50 and upper == 200 and ui.sliderDragging, "horizontal ownership anchors range and pauses competing scrolling")
uis.InputEnded:Fire(finger)
check(app.ends == 1 and close(app.rects.a.w, 130) and app.rects.a.x == 0 and app.rects.a.y == 0,
    "thumb drag preserves grab offset and resize stays anchored at its top-left")
check(controller:sliderRange() == nil and ui.sliderDragging == false, "released slider restores native scrolling and the selection range")
finger = pointer("touch", 490, 510)
ui.slider.InputBegan:Fire(finger)
uis.InputEnded:Fire(finger)
check(app.ends == 2 and close(app.rects.a.w, 192.5), "track tap maps to the same relative range")
finger = pointer("touch", 340, 510)
ui.slider.InputBegan:Fire(finger)
finger.Position = {X = 350, Y = 550}
uis.InputChanged:Fire(finger)
uis.InputEnded:Fire(finger)
check(app.ends == 2 and close(app.rects.a.w, 192.5) and ui.sliderDragging == false,
    "vertical scrolling from the slider neither resizes nor pauses native scrolling")
finger = pointer("touch", 445, 510)
ui.slider.InputBegan:Fire(finger)
finger.Position = {X = 405, Y = 511}
uis.InputChanged:Fire(finger)
check(ui.sliderDragging and app.rects.a.w < 192.5, "accepted slider drag locks scrolling while updating the selection")
uis.WindowFocusReleased:Fire()
check(ui.sliderDragging == false and app.cancels == 1 and close(app.rects.a.w, 192.5),
    "cancel restores scrollbar and the selection's pre-drag size")
controller:destroy()

app, ui, uis, controller = setup()
finger = pointer("touch", 15, 15)
ui.canvas.InputBegan:Fire(finger)
finger.Position = {X = 45, Y = 45}
uis.InputChanged:Fire(finger)
second = pointer("touch", 90, 90)
ui.canvas.InputBegan:Fire(second)
uis.InputChanged:Fire(second)
check(app.starts == 1 and close(app.rects.a.w, 100) and close(app.rects.a.x, 30), "pinch promotion starts from last tracked drag geometry")
second.Position = {X = 135, Y = 135}
uis.InputChanged:Fire(second)
check(close(app.rects.a.w, 200) and close(app.rects.a.x, 15), "promoted pinch scales around the current two-finger midpoint")
second.UserInputState = Enum.UserInputState.Cancel
second.StateChanged:Fire()
check(app.cancels == 1 and app.ends == 0 and app.rects.a.x == 0 and app.rects.a.w == 100,
    "cancel signal rolls back an interrupted drag-to-pinch even without InputEnded")
check(second.StateChanged:Count() == 0 and finger.StateChanged:Count() == 0, "cancel disconnects both pinch watchers")
controller:destroy()

app, ui, uis, controller = setup()
finger = pointer("touch", 120, 120)
ui.canvas.InputBegan:Fire(finger)
ui.handles[1].gui.InputBegan:Fire(finger)
finger.Position = {X = 140, Y = 150}
uis.InputChanged:Fire(finger)
uis.InputEnded:Fire(finger)
check(app.starts == 1 and app.ends == 1 and app.rects.a.w == 120 and app.rects.a.h == 130 and app.rects.a.x == 0,
    "external handle has one resize owner regardless of canvas and handle signal order")
controller:destroy()

app, ui, uis, controller = setup()
local handle = ui.handles[1]
handle.marker = {AbsolutePosition = {X = 123, Y = 123}, AbsoluteSize = {X = 12, Y = 12}}
local adjacent = {key = "b", editable = true}
function app.discovery:hit() return {adjacent}, adjacent end
finger = pointer("touch", 129, 129)
handle.gui.InputBegan:Fire(finger)
uis.InputEnded:Fire(finger)
check(app.selection[1] == "a" and app.starts == 0, "tapping the visible resize marker leaves the selection unchanged")
finger = pointer("touch", 111, 111)
handle.gui.InputBegan:Fire(finger)
uis.InputEnded:Fire(finger)
check(app.selection[1] == "b" and app.starts == 0, "tapping a HUD control under invisible handle padding selects it")
app.selection = {"a"}
finger = pointer("touch", 111, 111)
handle.gui.InputBegan:Fire(finger)
finger.Position = {X = 131, Y = 141}
uis.InputChanged:Fire(finger)
uis.InputEnded:Fire(finger)
check(app.selection[1] == "a" and app.ends == 1 and app.rects.a.w == 120 and app.rects.a.h == 130,
    "dragging from the same generous handle padding still resizes its original target")
controller:destroy()

app, ui, uis, controller = setup()
finger = pointer("touch", 340, 490)
ui.canvas.InputBegan:Fire(finger)
ui.inspectorGrip.InputBegan:Fire(finger)
other = pointer("touch", 10, 10)
ui.canvas.InputBegan:Fire(other)
other.Position = {X = 30, Y = 40}
uis.InputChanged:Fire(other)
uis.InputEnded:Fire(other)
finger.Position = {X = 300, Y = 470}
uis.InputChanged:Fire(finger)
uis.InputEnded:Fire(finger)
check(ui.inspectPos.x == 260 and ui.inspectPos.y == 460 and ui.inspectorFinished.cancelled == false
    and app.starts == 0 and app.rects.a.x == 0, "inspector drag owns its finger independently of the canvas")
finger = pointer("touch", 10, 310)
ui.launcher.InputBegan:Fire(finger)
finger.Position = {X = 40, Y = 350}
uis.InputChanged:Fire(finger)
controller:cancel()
check(ui.launcherPos.x == 30 and ui.launcherPos.y == 340 and ui.launcherFinished.cancelled == true and app.editing,
    "launcher cancellation hands placement rollback to UI without toggling editing")
finger = pointer("touch", 10, 310)
ui.launcher.InputBegan:Fire(finger)
uis.InputEnded:Fire(finger)
check(not app.editing, "launcher tap closes the editor")
controller:destroy()

app, ui, uis, controller = setup()
function app:updateGesture() return false end
finger = pointer("touch", 10, 10)
ui.canvas.InputBegan:Fire(finger)
finger.Position = {X = 40, Y = 40}
uis.InputChanged:Fire(finger)
uis.InputEnded:Fire(finger)
check(app.starts == 1 and app.cancels == 1 and app.ends == 0 and not controller:isBusy(),
    "rejected pointer update closes only its own transaction without committing history")
controller:destroy()

app, ui, uis, controller = setup()
app.preferences.boxSelect = true
finger = pointer("touch", -5, -5)
ui.canvas.InputBegan:Fire(finger)
finger.Position = {X = 104, Y = 104}
uis.InputChanged:Fire(finger)
check(ui.lastBox.x == -5 and ui.lastBox.w == 109, "touch box selection preserves canonical negative origin")
uis.InputEnded:Fire(finger)
check(app.selection[1] == "a" and app.starts == 0 and ui.lastBox == nil, "touch box selects a contained element without transform history")
controller:destroy()

local function elapsedHold()
    local pending = {}
    task = {
        delay = function(seconds, callback)
            assert(seconds >= 0.35 and seconds <= 0.65)
            local token = {callback = callback, active = true}
            pending[#pending + 1] = token
            return token
        end,
        cancel = function(token) token.active = false end,
    }
    return function()
        local count = 0
        local ready = pending
        pending = {}
        for _, token in ipairs(ready) do
            if token.active then count = count + 1; token.callback() end
        end
        return count
    end
end

local function setupThrough()
    local elapsed = elapsedHold()
    local app, ui, uis, input = setup()
    local ordinary = app.discovery:get("a")
    local deeper = {key = "ignored-layer", editable = true}
    function app:canvasHits(x, y, explicit)
        if explicit then return {ordinary, deeper}, ordinary end
        return self.discovery:hit(x, y)
    end
    function app:openSelectThrough(hits, point)
        self.throughCount = (self.throughCount or 0) + 1
        self.through = {hits = hits, point = point}
    end
    function ui:setSelectThroughArmed(armed) self.throughArmed = armed end
    return app, ui, uis, input, elapsed
end

local elapsed
app, ui, uis, controller, elapsed = setupThrough()
app.selection = {}
finger = pointer("touch", 20, 20)
ui.canvas.InputBegan:Fire(finger)
uis.InputEnded:Fire(finger)
check(app.selection[1] == "a" and elapsed() == 0 and not app.through,
    "ordinary release selects immediately and cancels its hold timer")
controller:destroy()

app, ui, uis, controller, elapsed = setupThrough()
app.selection = {}
finger = pointer("touch", 20, 20)
ui.canvas.InputBegan:Fire(finger)
finger.Position = {X = 23, Y = 22}
uis.InputChanged:Fire(finger)
check(elapsed() == 1 and app.through.hits[2].key == "ignored-layer" and app.through.point.x == 23,
    "long press queries current explicit hits at the relaxed finger point")
finger.UserInputState = Enum.UserInputState.End
uis.InputEnded:Fire(finger)
ui.canvas.InputBegan:Fire(finger)
check(app.throughCount == 1 and elapsed() == 0 and #app.selection == 0 and app.starts == 0,
    "long press hands off once without tapping, resizing, or adding history")
controller:cancel()
controller:destroy()

app, ui, uis, controller, elapsed = setupThrough()
finger = pointer("touch", 20, 20)
ui.canvas.InputBegan:Fire(finger)
finger.Position = {X = 45, Y = 60}
uis.InputChanged:Fire(finger)
check(elapsed() == 0 and not app.through and app.rects.a.x == 25,
    "movement cancels a pending long press and still moves immediately")
ui.modalOpen = true
uis.InputEnded:Fire(finger)
check(app.cancels == 1 and app.ends == 0 and app.rects.a.x == 0 and not controller:isBusy(),
    "a modal opening during a drag rolls back even if release reaches the original owner")
controller:destroy()

app, ui, uis, controller, elapsed = setupThrough()
finger = pointer("touch", 20, 20)
ui.canvas.InputBegan:Fire(finger)
other = pointer("touch", 255, 220)
ui.canvas.InputBegan:Fire(other)
uis.InputEnded:Fire(other)
check(elapsed() == 1 and app.throughCount == 1 and app.starts == 0,
    "a second finger outside the selection cannot steal the pending hold")
controller:destroy()

app, ui, uis, controller, elapsed = setupThrough()
finger, second = pointer("touch", 20, 20), pointer("touch", 65, 65)
ui.canvas.InputBegan:Fire(finger)
ui.canvas.InputBegan:Fire(second)
check(elapsed() == 0 and not app.through, "a second finger admitted to pinch cancels the hold timer")
other = pointer("touch", 47, 47)
ui.canvas.InputBegan:Fire(other)
other.Position = {X = 90, Y = 90}
uis.InputChanged:Fire(other)
uis.InputEnded:Fire(other)
check(app.starts == 0 and controller:isBusy(), "a third touch cannot move or end a pinch")
second.Position = {X = 85, Y = 85}
uis.InputChanged:Fire(second)
uis.InputEnded:Fire(finger)
local width = app.rects.a.w
second.Position = {X = 100, Y = 100}
uis.InputChanged:Fire(second)
uis.InputEnded:Fire(second)
check(app.starts == 1 and app.ends == 1 and width > 100 and app.rects.a.w == width,
    "releasing the first pinch finger commits and suppresses movement from the second")
controller:destroy()

app, ui, uis, controller, elapsed = setupThrough()
check(controller:armSelectThrough() and ui.throughArmed, "explicit Select Through can arm itself for one canvas tap")
finger = pointer("touch", 350, 510)
ui.canvas.InputBegan:Fire(finger)
uis.InputEnded:Fire(finger)
check(controller:isSelectThroughArmed() and not app.through, "inspector taps do not consume the armed canvas action")
finger = pointer("touch", 129, 129)
ui.handles[1].gui.InputBegan:Fire(finger)
uis.InputEnded:Fire(finger)
check(not controller:isSelectThroughArmed() and not ui.throughArmed and app.through.point.x == 129 and app.starts == 0,
    "the armed tap opens the picker once even over a resize handle without transforming it")
check(controller:armSelectThrough(), "the picker can be armed again")
finger = pointer("touch", 30, 30)
ui.canvas.InputBegan:Fire(finger)
finger.Position = {X = 90, Y = 95}
uis.InputChanged:Fire(finger)
uis.InputEnded:Fire(finger)
check(not controller:isSelectThroughArmed() and app.throughCount == 1 and app.starts == 0,
    "a swipe cancels the explicit tap instead of opening or moving unexpectedly")
controller:armSelectThrough()
uis.WindowFocusReleased:Fire()
check(not controller:isSelectThroughArmed(), "focus loss disarms the explicit tool")
ui.onboardingOpen = true
check(not controller:armSelectThrough(), "onboarding shields the real editor from new gestures")
ui.canvas.InputBegan:Fire(pointer("touch", 20, 20))
check(not controller:isBusy() and elapsed() == 0, "touches on tutorial surfaces cannot arm an editor hold")
controller:destroy()

app, ui, uis, controller, elapsed = setupThrough()
mouse = pointer("mouse2", 20, 20)
ui.canvas.InputBegan:Fire(mouse)
uis.InputEnded:Fire(pointer("mouse1", 20, 20))
check(controller:isBusy() and not app.through, "left mouse release cannot complete a right-click picker")
uis.InputEnded:Fire(mouse)
check(app.throughCount == 1 and app.starts == 0, "right click opens Select Through without altering selection or history")
controller:destroy()

app, ui, uis, controller, elapsed = setupThrough()
finger = pointer("touch", 20, 20)
ui.canvas.InputBegan:Fire(finger)
controller:cancel()
check(elapsed() == 0 and not app.through and finger.StateChanged:Count() == 0,
    "viewport-style cancellation clears pending hold and input watcher")
uis.InputEnded:Fire(finger)
finger = pointer("touch", 20, 20)
ui.canvas.InputBegan:Fire(finger)
finger.Position = {X = 65, Y = 70}
uis.InputChanged:Fire(finger)
controller:selectionChanged()
check(app.cancels == 1 and not controller:isBusy() and app.ends == 0,
    "external selection change cancels the existing pointer transaction")
controller:destroy()

app, ui, uis, controller, elapsed = setupThrough()
app.selection = {}
local selectTarget = app.select
function app:select(key, additive)
    selectTarget(self, key, additive)
    controller:selectionChanged()
end
finger = pointer("touch", 20, 20)
ui.canvas.InputBegan:Fire(finger)
finger.Position = {X = 65, Y = 70}
uis.InputChanged:Fire(finger)
uis.InputEnded:Fire(finger)
check(app.selection[1] == "a" and app.ends == 1 and app.cancels == 0,
    "a drag that selects its own target keeps the gesture owner through the App selection callback")
for _ = 1, 30 do
    finger = pointer("touch", 20, 20)
    ui.canvas.InputBegan:Fire(finger)
    uis.InputEnded:Fire(finger)
end
check(elapsed() == 0 and not controller:isBusy() and finger.StateChanged:Count() == 0,
    "repeated short touches leave no pending timers or state watchers")
controller:destroy()

app, ui, uis, controller = setup()
finger = pointer("touch", 20, 20)
ui.canvas.InputBegan:Fire(finger)
finger.Position = {X = 60, Y = 60}
uis.InputChanged:Fire(finger)
local record = app.discovery:get("a")
record.object = {AbsolutePosition = {X = 0, Y = 0}, AbsoluteSize = {X = 100, Y = 100}}
app.discovery.revision = 2
uis.InputEnded:Fire(finger)
check(app.cancels == 1 and app.ends == 0 and not controller:isBusy(),
    "identity-key recreation during a drag cannot commit edits against a replacement instance")
controller:destroy()

app, ui, uis, controller = setup()
function app:capability(_, operation)
    return {supported = operation == "resize", reason = "Layout controls this position."}
end
function app:getRects(_, operation)
    if operation == "move" then return {}, {}, 1 end
    if #self.selection == 0 then return {}, {} end
    return {self.rects.a}, {"a"}
end
local updateGesture = app.updateGesture
function app:updateGesture(rects, keys, operation)
    self.lastOperation = operation
    updateGesture(self, rects, keys)
end
function app:status(reason) self.lastStatus = reason end
finger = pointer("touch", 20, 20)
ui.canvas.InputBegan:Fire(finger)
finger.Position = {X = 31, Y = 32}
uis.InputChanged:Fire(finger)
check(app.starts == 0 and app.lastStatus == "Layout controls this position.",
    "attempting to drag a layout-position-owned element leaves geometry intact and explains why")
second = pointer("touch", 70, 70)
ui.canvas.InputBegan:Fire(second)
second.Position = {X = 85, Y = 85}
uis.InputChanged:Fire(second)
uis.InputEnded:Fire(second)
check(app.starts == 1 and app.ends == 1 and app.lastOperation == "resize" and app.rects.a.w > 100,
    "size-only compatibility still accepts pinch after a no-op move")
controller:destroy()

app, ui, uis, controller = setup()
app.selection = {"a", "b"}
app.rects.b = {x = 115, y = 15, w = 50, h = 50}
function app:getRects(_, operation)
    if operation == "groupResize" then return {self.rects.a}, {"a"}, 1 end
    return {self.rects.a, self.rects.b}, {"a", "b"}
end
updateGesture = app.updateGesture
function app:updateGesture(rects, keys, operation)
    self.lastOperation = operation
    updateGesture(self, rects, keys)
end
finger, second = pointer("touch", 30, 30), pointer("touch", 70, 70)
ui.canvas.InputBegan:Fire(finger)
finger.Position = {X = 50, Y = 60}
uis.InputChanged:Fire(finger)
ui.canvas.InputBegan:Fire(second)
second.Position = {X = 95, Y = 95}
uis.InputChanged:Fire(second)
uis.InputEnded:Fire(second)
check(controller:isBusy() and app.lastOperation == "groupMove" and app.rects.b.x == 135 and app.rects.a.w == 100,
    "a moved group retains drag ownership if its eligible resize roots differ")
uis.InputEnded:Fire(finger)
check(app.starts == 1 and app.ends == 1 and not controller:isBusy(), "mixed compatibility group drag commits once")
controller:destroy()
task = nil

return checks
