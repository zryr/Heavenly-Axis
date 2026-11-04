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
    }
end
Enum = {UserInputType = {Touch = "touch", MouseButton1 = "mouse1", MouseMovement = "mouseMove", Keyboard = "keyboard"}, KeyCode = {}}
for _, name in ipairs({"F8", "F9", "Z", "Y", "S", "B", "Escape", "Left", "Right", "Up", "Down",
    "LeftShift", "RightShift", "LeftControl", "RightControl", "LeftAlt", "RightAlt", "Unknown"}) do Enum.KeyCode[name] = name end
UDim2 = {fromOffset = function(x, y) return {x = x, y = y} end}
local Input = require("Input")
local function pointer(kind, x, y) return {UserInputType = kind, Position = {X = x, Y = y}} end
local function setup()
    local ui = {visible = true, handles = {}, gui = {AbsoluteSize = {X = 800, Y = 600}}}
    local function button(x, y, w, h)
        return {InputBegan = signal(), AbsolutePosition = {X = x, Y = y}, AbsoluteSize = {X = w, Y = h}, Visible = true}
    end
    ui.canvas = button(0, 0, 800, 600)
    ui.slider = button(300, 500, 200, 30)
    ui.launcher = button(0, 300, 44, 44)
    function ui:pointInPanel(x, y) return y >= 480 end
    function ui:setBox(value) self.lastBox = value end
    function ui:setGuides(value) self.lastGuides = value end
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
    app.discovery = {}
    function app.discovery:hit(x, y) if x <= 100 and y <= 100 then return {record} else return {} end end
    function app.discovery:list() return {record} end
    function app.discovery:get(key) return key == "a" and record or nil end
    local input = Input.new(app, ui, {UserInputService = uis})
    return app, ui, uis, input
end

local app, ui, uis, controller = setup()
local finger = pointer("touch", 20, 20)
ui.canvas.InputBegan:Fire(finger)
check(app.starts == 1, "drag begins exactly one transaction")
local other = pointer("touch", 25, 25)
uis.InputChanged:Fire(other)
uis.InputEnded:Fire(other)
check(app.rects.a.x == 0 and app.ends == 0, "unrelated touch cannot move or end a drag")
finger.Position = {X = 50, Y = 70}
uis.InputChanged:Fire(finger)
check(app.rects.a.x == 30 and app.rects.a.y == 50, "touch position drives drag directly")
uis.InputEnded:Fire(finger)
uis.InputEnded:Fire(finger)
check(app.ends == 1, "one completed drag is one history action")
controller:destroy()

app, ui, uis, controller = setup()
finger = pointer("touch", 10, 10)
local second = pointer("touch", 90, 90)
ui.canvas.InputBegan:Fire(finger)
ui.canvas.InputBegan:Fire(second)
second.Position = {X = 170, Y = 170}
uis.InputChanged:Fire(second)
check(close(app.rects.a.w, 200) and close(app.rects.a.x, -10), "pinch scales about initial finger midpoint")
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
uis.InputChanged:Fire(pointer("mouseMove", 400, 510))
uis.InputChanged:Fire(pointer("mouseMove", 450, 510))
uis.InputEnded:Fire(pointer("mouse1", 450, 510))
check(close(app.rects.a.w, 388) and app.starts == 1 and app.ends == 1, "continuous slider session creates one action")
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
ui.modalOpen = true
uis.modifiers.LeftControl = true
uis.InputBegan:Fire({UserInputType = "keyboard", KeyCode = "S"}, false)
ui.slider.InputBegan:Fire(pointer("touch", 350, 510))
check(not app.saves and app.starts == 0, "modal shields keyboard and behind-modal slider gestures")
controller:destroy()

return checks
