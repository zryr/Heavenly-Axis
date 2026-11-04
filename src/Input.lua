-- Heavenly Axis V3: shared touch/mouse gesture ownership.
-- Positions are InputObject.Position in physical screen pixels. The overlay uses
-- IgnoreGuiInset=true, so no per-event mouse/inset conversion is involved.
local Geometry = require("Geometry")
local Input = {}
Input.__index = Input

local function point(input)
    return {x = input.Position.X, y = input.Position.Y}
end
local function distance(a, b)
    local x, y = a.x - b.x, a.y - b.y
    return math.sqrt(x * x + y * y)
end
local function midpoint(a, b)
    return {x = (a.x + b.x) / 2, y = (a.y + b.y) / 2}
end
local function contains(rect, p, margin)
    margin = margin or 0
    return rect and p.x >= rect.x - margin and p.y >= rect.y - margin
        and p.x <= rect.x + rect.w + margin and p.y <= rect.y + rect.h + margin
end
local function selected(app, key)
    for _, value in ipairs(app.selection) do
        if value == key then return true end
    end
    return false
end
local function touch(input)
    return input.UserInputType == Enum.UserInputType.Touch
end
local function primary(input)
    return touch(input) or input.UserInputType == Enum.UserInputType.MouseButton1
end
local function cloneRects(rects)
    local result = {}
    for i, rect in ipairs(rects) do
        result[i] = {x = rect.x, y = rect.y, w = rect.w, h = rect.h}
    end
    return result
end

function Input.new(app, ui, services)
    local self = setmetatable({
        app = app, ui = ui, services = services, connections = {},
        gesture = nil, launcherGesture = nil, suppressed = {}, destroyed = false,
    }, Input)
    self.uis = services.UserInputService
    local function connect(signal, callback)
        self.connections[#self.connections + 1] = signal:Connect(callback)
    end
    connect(ui.canvas.InputBegan, function(input) self:_canvasBegin(input) end)
    for _, handle in ipairs(ui.handles) do
        connect(handle.gui.InputBegan, function(input)
            self:_transformBegin(input, "resize", handle.handle)
        end)
    end
    if ui.slider then
        connect(ui.slider.InputBegan, function(input) self:_transformBegin(input, "slider") end)
    end
    if ui.launcher then
        connect(ui.launcher.InputBegan, function(input) self:_launcherBegin(input) end)
    end
    connect(self.uis.InputChanged, function(input) self:_changed(input) end)
    connect(self.uis.InputEnded, function(input) self:_ended(input) end)
    connect(self.uis.InputBegan, function(input, processed) self:_key(input, processed) end)
    connect(self.uis.WindowFocusReleased, function() self:cancel() end)
    return self
end

function Input:_modifier(name)
    local key = Enum.KeyCode[name]
    return key and self.uis:IsKeyDown(key)
end
function Input:_multi(input)
    return self.app.preferences.multiSelect == true or (not touch(input)
        and (self:_modifier("LeftShift") or self:_modifier("RightShift")
            or self:_modifier("LeftControl") or self:_modifier("RightControl")))
end
function Input:_owner(input, gesture)
    if not gesture then return false end
    if touch(gesture.primary) then return input == gesture.primary or input == gesture.secondary end
    return input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.MouseButton1
end
function Input:_snapshot(kind, input, handle)
    local rects, keys = self.app:getRects()
    if #rects == 0 then return nil end
    return {
        kind = kind, primary = input, start = point(input), latest = point(input),
        rects = cloneRects(rects), keys = keys, bounds = Geometry.bounds(rects),
        handle = handle, points = {[input] = point(input)}, transaction = false,
        -- Cache alignment targets once per gesture, never rescan hierarchy at
        -- pointer-event frequency on mobile.
        others = (kind == "drag" or kind == "pending") and self:_otherRects(keys) or {},
    }
end
function Input:_beginTransaction(gesture, label)
    if not gesture.transaction then
        if self.app:beginGesture(label) == false then
            gesture.blocked = true
            return false
        end
        gesture.transaction = true
    end
    return true
end

function Input:_canvasBegin(input)
    if self.destroyed or not primary(input) or not self.app.editing
        or self.ui:pointInPanel(input.Position.X, input.Position.Y) then return end
    local p = point(input)
    -- GuiObject delivery order is not guaranteed. Do not let the canvas start
    -- a second gesture when the pointer belongs to an overlay handle.
    for _, handle in ipairs(self.ui.handles) do
        local gui = handle.gui
        if gui.Visible then
            local pos, size = gui.AbsolutePosition, gui.AbsoluteSize
            if contains({x = pos.X, y = pos.Y, w = size.X, h = size.Y}, p) then return end
        end
    end
    local current = self.gesture
    if current then
        -- A second finger belongs to this gesture only when it starts on the
        -- selected bounds. Unrelated fingers cannot move or end the owner.
        if touch(input) and touch(current.primary) and not current.secondary
            and (current.kind == "drag" or current.kind == "pending")
            and contains(self.app:currentBounds(), p, 16) then
            if not self:_beginTransaction(current, "Pinch resize") then return end
            local rects, keys = self.app:getRects()
            current.rects, current.keys = cloneRects(rects), keys
            current.bounds = Geometry.bounds(rects)
            current.secondary = input
            current.points[input] = p
            current.kind = "pinch"
            local first = current.points[current.primary]
            current.pinchDistance = math.max(1, distance(first, p))
            current.pinchCenter = midpoint(first, p)
        end
        return
    end
    local hits = self.app.discovery:hit(p.x, p.y)
    local record = hits[1]
    if #hits > 1 and (self:_modifier("LeftAlt") or self:_modifier("RightAlt")) then
        local index = 1
        for i, hit in ipairs(hits) do
            if selected(self.app, hit.key) then index = i % #hits + 1; break end
        end
        record = hits[index]
    end
    if self.app.preferences.boxSelect and not touch(input) then record = nil end
    if not record then
        -- Drag a gap inside a combined selection to move the entire group.
        if contains(self.app:currentBounds(), p) and not self.app.preferences.boxSelect then
            self.gesture = self:_snapshot("drag", input)
            if self.gesture then self:_beginTransaction(self.gesture, "Move selection") end
        else
            self.gesture = {kind = "box", primary = input, start = p, latest = p,
                additive = self:_multi(input), points = {[input] = p}}
            self.ui:setBox({x = p.x, y = p.y, w = 0, h = 0})
        end
        return
    end
    if self:_multi(input) then
        -- Taps toggle selection; dragging an already-selected target moves the
        -- selection. Delaying the toggle preserves useful mobile multi-select.
        self.gesture = self:_snapshot("pending", input)
            or {kind = "pending", primary = input, start = p, latest = p,
                rects = {}, keys = {}, points = {[input] = p}}
        self.gesture.tapKey = record.key
        self.gesture.wasSelected = selected(self.app, record.key)
        return
    end
    if not selected(self.app, record.key) then self.app:select(record.key, false) end
    self.gesture = self:_snapshot("drag", input)
    if self.gesture then self:_beginTransaction(self.gesture, "Move selection") end
end

function Input:_transformBegin(input, kind, handle)
    if self.destroyed or not primary(input) or not self.app.editing or self.gesture
        or self.ui.modalOpen then return end
    if kind ~= "slider" and self.ui:pointInPanel(input.Position.X, input.Position.Y) then return end
    local gesture = self:_snapshot(kind, input, handle)
    if not gesture then return end
    self.gesture = gesture
    self:_beginTransaction(gesture, kind == "slider" and "Size slider" or "Resize selection")
    if kind == "slider" then self:_update(gesture, point(input)) end
end

function Input:_otherRects(keys)
    local exclude, result = {}, {}
    for _, key in ipairs(keys) do exclude[key] = true end
    local selectedObjects = {}
    for _, key in ipairs(keys) do
        local record = self.app.discovery:get(key)
        if record then selectedObjects[record.object] = true end
    end
    for _, record in ipairs(self.app.discovery:list()) do
        if not exclude[record.key] then
            local ok, rect = pcall(function()
                local parent = record.object.Parent
                while parent do
                    if selectedObjects[parent] then return nil end
                    parent = parent.Parent
                end
                local pos, size = record.object.AbsolutePosition, record.object.AbsoluteSize
                return {x = pos.X, y = pos.Y, w = size.X, h = size.Y}
            end)
            if ok and rect then result[#result + 1] = rect end
        end
    end
    return result
end

function Input:_scaled(gesture, bounds, preserveOrigin)
    if not self.app.preferences.equalSize or #gesture.rects < 2 then
        return Geometry.scale(gesture.rects, bounds, not preserveOrigin and self.app.preferences.centerScale)
    end
    -- Equal-size mode keeps each member's location; the first root supplies the
    -- common aspect ratio. Proportional mode scales the full relative layout.
    local first = gesture.rects[1]
    local sx, sy = bounds.w / math.max(16, gesture.bounds.w), bounds.h / math.max(16, gesture.bounds.h)
    local w, h = math.max(16, first.w * sx), math.max(16, first.h * sy)
    local result = {}
    for i, rect in ipairs(gesture.rects) do
        local x, y = rect.x, rect.y
        if self.app.preferences.centerScale then x, y = x + (rect.w - w) / 2, y + (rect.h - h) / 2 end
        result[i] = {x = x, y = y, w = w, h = h}
    end
    return result
end

function Input:_update(gesture, p)
    if gesture.blocked then return end
    local prefs = self.app.preferences
    if gesture.kind == "pending" then
        if gesture.wasSelected and distance(gesture.start, p) > 7 then
            gesture.kind = "drag"
            if not self:_beginTransaction(gesture, "Move selection") then return end
        else return end
    end
    if gesture.kind == "box" then
        self.ui:setBox({x = math.min(gesture.start.x, p.x), y = math.min(gesture.start.y, p.y),
            w = math.abs(p.x - gesture.start.x), h = math.abs(p.y - gesture.start.y)})
        return
    end
    local rects
    if gesture.kind == "drag" then
        local dx, dy = p.x - gesture.start.x, p.y - gesture.start.y
        local moved = Geometry.translate(gesture.bounds, dx, dy)
        local snapped, guides = Geometry.snap(moved, gesture.others or {},
            prefs.gridSize or 16, prefs.snapThreshold or 6, prefs.snapping == true)
        self.ui:setGuides(guides or {})
        dx, dy = dx + snapped.x - moved.x, dy + snapped.y - moved.y
        rects = {}
        for i, rect in ipairs(gesture.rects) do rects[i] = Geometry.translate(rect, dx, dy) end
    elseif gesture.kind == "resize" then
        local resized = Geometry.resize(gesture.bounds, gesture.handle,
            p.x - gesture.start.x, p.y - gesture.start.y,
            prefs.aspectLock == true, prefs.centerScale == true)
        rects = self:_scaled(gesture, resized)
    elseif gesture.kind == "slider" then
        local track = self.ui.slider
        local width = math.max(1, track.AbsoluteSize.X)
        local fraction = math.max(0, math.min(1, (p.x - track.AbsolutePosition.X) / width))
        local target = 16 + fraction * 496
        local factor = target / math.max(16, gesture.bounds.w, gesture.bounds.h)
        local bounds = {x = gesture.bounds.x, y = gesture.bounds.y,
            w = math.max(16, gesture.bounds.w * factor), h = math.max(16, gesture.bounds.h * factor)}
        if prefs.centerScale then
            bounds.x = bounds.x + (gesture.bounds.w - bounds.w) / 2
            bounds.y = bounds.y + (gesture.bounds.h - bounds.h) / 2
        end
        rects = self:_scaled(gesture, bounds)
    elseif gesture.kind == "pinch" then
        local a, b = gesture.points[gesture.primary], gesture.points[gesture.secondary]
        if not a or not b then return end
        local factor = distance(a, b) / gesture.pinchDistance
        local center = midpoint(a, b)
        local minimum = 0.01
        for _, rect in ipairs(gesture.rects) do
            minimum = math.max(minimum, 16 / math.max(1, rect.w), 16 / math.max(1, rect.h))
        end
        factor = math.max(factor, minimum)
        -- Pinching always scales about the initial two-finger midpoint and
        -- follows its translation; this keeps both fingers attached naturally.
        local bounds = {x = center.x + (gesture.bounds.x - gesture.pinchCenter.x) * factor,
            y = center.y + (gesture.bounds.y - gesture.pinchCenter.y) * factor,
            w = gesture.bounds.w * factor, h = gesture.bounds.h * factor}
        rects = self:_scaled(gesture, bounds, true)
    end
    if rects then self.app:updateGesture(rects, gesture.keys) end
end

function Input:_launcherBegin(input)
    if self.destroyed or not primary(input) or self.launcherGesture or self.gesture
        or self.ui.modalOpen then return end
    local pos = self.ui.launcher.AbsolutePosition
    self.ui.launcherDragging = true
    self.launcherGesture = {primary = input, start = point(input), latest = point(input),
        x = pos.X, y = pos.Y, moved = false}
end
function Input:_moveLauncher(gesture, p)
    gesture.latest = p
    if distance(gesture.start, p) > 7 then gesture.moved = true end
    if not gesture.moved then return end
    local size = self.ui.gui.AbsoluteSize
    local launcherSize = self.ui.launcher.AbsoluteSize
    local x = math.max(0, math.min(size.X - launcherSize.X, gesture.x + p.x - gesture.start.x))
    local y = math.max(0, math.min(size.Y - launcherSize.Y, gesture.y + p.y - gesture.start.y))
    self.ui.launcher.Position = UDim2.fromOffset(x, y)
end
function Input:_changed(input)
    if self.destroyed then return end
    if self.launcherGesture and self:_owner(input, self.launcherGesture) then
        self:_moveLauncher(self.launcherGesture, point(input))
    end
    local gesture = self.gesture
    if not gesture or not self:_owner(input, gesture) then return end
    if not self.app.editing then self:cancel(); return end
    local p = point(input)
    gesture.latest = p
    if touch(input) then gesture.points[input] = p else gesture.points[gesture.primary] = p end
    self:_update(gesture, p)
end

function Input:_boxEnd(gesture)
    local x, y = math.min(gesture.start.x, gesture.latest.x), math.min(gesture.start.y, gesture.latest.y)
    local w, h = math.abs(gesture.start.x - gesture.latest.x), math.abs(gesture.start.y - gesture.latest.y)
    if w < 6 and h < 6 then
        if not gesture.additive then self.app:clearSelection() end
        return
    end
    local keys, seen = {}, {}
    if gesture.additive then
        for _, key in ipairs(self.app.selection) do keys[#keys + 1] = key; seen[key] = true end
    end
    for _, record in ipairs(self.app.discovery:list()) do
        local ok, inside = pcall(function()
            local pos, size = record.object.AbsolutePosition, record.object.AbsoluteSize
            return pos.X >= x and pos.Y >= y and pos.X + size.X <= x + w and pos.Y + size.Y <= y + h
        end)
        if ok and inside and not seen[record.key] and record.editable then
            keys[#keys + 1] = record.key; seen[record.key] = true
        end
    end
    self.app:selectMany(keys)
end
function Input:_ended(input)
    if self.destroyed then return end
    if self.suppressed[input] then self.suppressed[input] = nil; return end
    local launcher = self.launcherGesture
    if launcher and (input == launcher.primary or (not touch(launcher.primary)
        and input.UserInputType == Enum.UserInputType.MouseButton1)) then
        self.launcherGesture = nil
        self.ui.launcherDragging = false
        if launcher.moved then
            local view = self.ui.gui.AbsoluteSize
            local size = self.ui.launcher.AbsoluteSize
            local pos = self.ui.launcher.AbsolutePosition
            local x = pos.X + size.X / 2 < view.X / 2 and 0 or math.max(0, view.X - size.X)
            local y = math.max(0, math.min(view.Y - size.Y, pos.Y))
            self.app:setPreference("launcherX", view.X > size.X and x / (view.X - size.X) or 0)
            self.app:setPreference("launcherY", view.Y > size.Y and y / (view.Y - size.Y) or 0)
        else
            self.app:setEditing(not self.app.editing)
        end
    end
    local gesture = self.gesture
    if not gesture then return end
    local owned = input == gesture.primary or input == gesture.secondary
        or (not touch(gesture.primary) and input.UserInputType == Enum.UserInputType.MouseButton1)
    if not owned then return end
    if gesture.kind == "pinch" then
        local remaining = input == gesture.primary and gesture.secondary or gesture.primary
        self.suppressed[remaining] = true
    end
    self.gesture = nil
    if gesture.kind == "box" then self:_boxEnd(gesture)
    elseif gesture.kind == "pending" then self.app:select(gesture.tapKey, true)
    elseif gesture.transaction then self.app:endGesture() end
    self.ui:setBox(nil)
    self.ui:setGuides({})
end

function Input:_key(input, processed)
    if self.destroyed or input.UserInputType ~= Enum.UserInputType.Keyboard
        or self.uis:GetFocusedTextBox() then return end
    if self.ui.modalOpen then return end
    local prefs = self.app.preferences
    local shortcut = Enum.KeyCode.F8
    local valid, configured = pcall(function() return Enum.KeyCode[prefs.shortcut or "F8"] end)
    if valid and configured and configured ~= Enum.KeyCode.Unknown then shortcut = configured end
    if input.KeyCode == shortcut then
        if not processed then
            if self.app.editing then self:cancel() end
            self.app:setEditing(not self.app.editing)
        end
        return
    end
    if processed or not self.app.editing then return end
    local key = input.KeyCode
    if self.gesture then
        if key == Enum.KeyCode.Escape then self:cancel() end
        return
    end
    local control = self:_modifier("LeftControl") or self:_modifier("RightControl")
    local shift = self:_modifier("LeftShift") or self:_modifier("RightShift")
    if control then
        if key == Enum.KeyCode.Z then
            if shift then self.app:redo() else self.app:undo() end
        elseif key == Enum.KeyCode.Y then self.app:redo()
        elseif key == Enum.KeyCode.S then self.app:save() end
        return
    end
    if key == Enum.KeyCode.Escape then
        if self.gesture then self:cancel() else self.app:clearSelection() end
    elseif key == Enum.KeyCode.B then self.app:setPreference("boxSelect", not prefs.boxSelect)
    elseif key == Enum.KeyCode.Left then self.app:move(-(shift and 10 or prefs.step or 1), 0)
    elseif key == Enum.KeyCode.Right then self.app:move(shift and 10 or prefs.step or 1, 0)
    elseif key == Enum.KeyCode.Up then self.app:move(0, -(shift and 10 or prefs.step or 1))
    elseif key == Enum.KeyCode.Down then self.app:move(0, shift and 10 or prefs.step or 1) end
end

function Input:cancel()
    local gesture = self.gesture
    self.gesture, self.launcherGesture, self.suppressed = nil, nil, {}
    self.ui.launcherDragging = false
    if self.ui.positionLauncher then self.ui:positionLauncher() end
    if gesture and gesture.transaction then self.app:cancelGesture() end
    self.ui:setBox(nil)
    self.ui:setGuides({})
end
function Input:destroy()
    if self.destroyed then return end
    self:cancel()
    self.destroyed = true
    for _, connection in ipairs(self.connections) do connection:Disconnect() end
    self.connections = {}
end

return Input
