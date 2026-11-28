-- One pointer owner across canvas and editor surfaces. Only a qualifying second
-- canvas touch can join that owner, for pinch. Geometry uses CoreUISafeInsets coordinates.
local Coordinates = require("Coordinates")
local Geometry = require("Geometry")
local Input = {}
Input.__index = Input
local HOLD_SECONDS = 0.5
local ROTATION_DEAD_ZONE = 6
local APPEARANCE_LABELS = {rotation = "Rotate selection", opacity = "Adjust opacity"}

local function touch(input)
    return input.UserInputType == Enum.UserInputType.Touch
end

local function primary(input)
    return touch(input) or input.UserInputType == Enum.UserInputType.MouseButton1
end

local function secondaryMouse(input)
    return input.UserInputType == Enum.UserInputType.MouseButton2
end

local function cancelled(input)
    return Enum.UserInputState ~= nil and input.UserInputState == Enum.UserInputState.Cancel
end

local function released(input)
    return Enum.UserInputState ~= nil and input.UserInputState == Enum.UserInputState.End
end

local function distance(a, b)
    local x, y = a.x - b.x, a.y - b.y
    return math.sqrt(x * x + y * y)
end

local function midpoint(a, b)
    return {x = (a.x + b.x) / 2, y = (a.y + b.y) / 2}
end

local function crossesRotationPivot(a, b, pivot)
    local dx, dy = b.x - a.x, b.y - a.y
    local length = dx * dx + dy * dy
    if length == 0 then return false end
    local t = ((pivot.x - a.x) * dx + (pivot.y - a.y) * dy) / length
    if t <= 0 or t >= 1 then return false end
    local x, y = a.x + t * dx - pivot.x, a.y + t * dy - pivot.y
    return x * x + y * y < ROTATION_DEAD_ZONE * ROTATION_DEAD_ZONE
end

local function contains(rect, p, margin)
    margin = margin or 0
    return rect and p.x >= rect.x - margin and p.y >= rect.y - margin
        and p.x <= rect.x + rect.w + margin and p.y <= rect.y + rect.h + margin
end

local function boxBetween(a, b)
    return {x = math.min(a.x, b.x), y = math.min(a.y, b.y), w = math.abs(a.x - b.x), h = math.abs(a.y - b.y)}
end

local function selected(app, key)
    for _, value in ipairs(app.selection) do
        if value == key then return true end
    end
    return false
end

local function changedRects(before, after)
    for i, rect in ipairs(before) do
        local nextRect = after[i]
        if nextRect and (math.abs(rect.x - nextRect.x) > .01 or math.abs(rect.y - nextRect.y) > .01
            or math.abs(rect.w - nextRect.w) > .01 or math.abs(rect.h - nextRect.h) > .01) then return true end
    end
    return false
end

local function sameKeys(one, other)
    if #one ~= #other then return false end
    for i, key in ipairs(one) do
        if key ~= other[i] then return false end
    end
    return true
end

function Input.new(app, ui, services)
    local self = setmetatable({
        app = app, ui = ui, uis = services.UserInputService, connections = {},
        ignored = setmetatable({}, {__mode = "k"}),
    }, Input)
    local function connect(signal, callback)
        if signal then self.connections[#self.connections + 1] = signal:Connect(callback) end
    end
    connect(ui.canvas.InputBegan, function(input) self:_canvasBegin(input) end)
    for _, handle in ipairs(ui.handles) do
        connect(handle.gui.InputBegan, function(input) self:_canvasBegin(input) end)
    end
    if ui.rotationHandle then connect(ui.rotationHandle.gui.InputBegan, function(input) self:_canvasBegin(input) end) end
    if ui.slider then connect(ui.slider.InputBegan, function(input) self:_sliderBegin(input, "size") end) end
    for mode, slider in pairs(ui.visualSliders or {}) do
        connect(slider.InputBegan, function(input) self:_sliderBegin(input, mode) end)
    end
    for kind, grip in pairs({launcher = ui.launcher, inspector = ui.inspectorGrip,
        toolbar = ui.toolbarGrip, workspace = ui.workspaceGrip}) do
        connect(grip.InputBegan, function(input) self:_floatBegin(input, kind) end)
    end
    connect(self.uis.InputChanged, function(input) self:_changed(input) end)
    connect(self.uis.InputEnded, function(input) self:_ended(input) end)
    connect(self.uis.InputBegan, function(input, processed) self:_key(input, processed) end)
    connect(self.uis.WindowFocusReleased, function() self:cancel() end)
    return self
end

function Input:isBusy()
    return self.gesture ~= nil
end

function Input:isSelectThroughArmed()
    return self.selectThroughArmed == true
end

function Input:_setSelectThroughArmed(armed)
    if self:isSelectThroughArmed() == armed then return end
    self.selectThroughArmed = armed
    if self.ui.setSelectThroughArmed then self.ui:setSelectThroughArmed(armed) end
end

function Input:_blocked()
    return self.ui.modalOpen or self.ui.onboardingOpen
end

function Input:armSelectThrough()
    if self.destroyed or not self.app.editing or self:_blocked() or self.uis:GetFocusedTextBox() then return false end
    self:cancel()
    self:_setSelectThroughArmed(true)
    return true
end

function Input:selectionChanged()
    if not self.selectingForGesture then self:cancel() end
end

function Input:sliderRange(mode)
    local gesture = self.gesture
    if gesture and gesture.kind == "slider" and gesture.sliderMode == (mode or "size") then
        local model = gesture.sizeInfo or gesture.appearance
        return model.minimum, model.maximum
    end
end

function Input:_canStart(input, canvas)
    return not self.destroyed and (primary(input) or (canvas and secondaryMouse(input))) and not self.ignored[input]
        and not cancelled(input) and not released(input) and not self:_blocked() and not self.uis:GetFocusedTextBox()
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

function Input:_own(gesture, input)
    local ok, signal = pcall(function() return input:GetPropertyChangedSignal("UserInputState") end)
    if ok and signal then
        gesture.connections[#gesture.connections + 1] = signal:Connect(function()
            if self.gesture == gesture and cancelled(input) then self:_ended(input) end
        end)
    end
end

function Input:_claim(input, kind, p)
    local gesture = {kind = kind, primary = input, start = p, latest = p,
        threshold = touch(input) and 8 or 3, connections = {}}
    self.gesture = gesture
    self:_own(gesture, input)
    return gesture
end

function Input:_disown(gesture, ended)
    self.gesture = nil
    self:_cancelHold(gesture)
    for _, connection in ipairs(gesture.connections) do connection:Disconnect() end
    if touch(gesture.primary) and gesture.primary ~= ended then self.ignored[gesture.primary] = true end
    if gesture.secondary and gesture.secondary ~= ended then self.ignored[gesture.secondary] = true end
end

function Input:_cancelHold(gesture)
    local timer = gesture.hold
    gesture.hold = nil
    if timer and task and task.cancel then task.cancel(timer) end
end

function Input:_showThrough(hits, p)
    if self.app.openSelectThrough then self.app:openSelectThrough(hits, p)
    elseif self.ui.showThrough then self.ui:showThrough(hits, p) end
end

function Input:_startHold(gesture)
    if not touch(gesture.primary) or not task or not task.delay
        or not (self.app.openSelectThrough or self.ui.showThrough) then return end
    gesture.hold = task.delay(HOLD_SECONDS, function()
        gesture.hold = nil
        if self.gesture ~= gesture or gesture.kind ~= "canvas" or gesture.moved or not self.app.editing
            or not self:_canStart(gesture.primary) then return end
        local p = Coordinates.point(gesture.primary)
        if distance(gesture.start, p) >= gesture.threshold or self.ui:pointInPanel(p.x, p.y) then return end
        local hits = self:_canvasHits(p, true)
        if #hits == 0 then return end
        self:_disown(gesture)
        self:_showThrough(hits, p)
    end)
end

function Input:_handleAt(p, tool)
    if tool == "rotate" then
        local rotation = self.ui.rotationHandle
        if rotation and rotation.gui.Visible and contains(Coordinates.rect(rotation.gui), p) then return rotation end
        return nil
    end
    if tool ~= "size" then return nil end
    local nearest, score
    for _, handle in ipairs(self.ui.handles) do
        if handle.gui.Visible then
            local r = Coordinates.rect(handle.gui)
            if contains(r, p) then
                local d = distance(p, {x = r.x + r.w / 2, y = r.y + r.h / 2})
                if not score or d < score then nearest, score = handle, d end
            end
        end
    end
    return nearest
end

function Input:_canvasHits(p, explicit)
    local hits, preferred
    if self.app.canvasHits then hits, preferred = self.app:canvasHits(p.x, p.y, explicit)
    else hits, preferred = self.app.discovery:hit(p.x, p.y) end
    return hits, preferred == nil and hits[1] or (preferred or nil)
end

function Input:_operation(mode)
    if #self.app.selection < 2 then return mode end
    return mode == "move" and "groupMove" or "groupResize"
end

function Input:_tool()
    return self.ui.getTransformTool and self.ui:getTransformTool() or "size"
end

function Input:_supports(record, operation)
    if not record then return false end
    if not self.app.capability then return record.editable end
    local capability = self.app:capability(record.key, operation)
    return capability and capability.supported == true
end

function Input:_snapshot(gesture, mode)
    local operation = self:_operation(mode)
    local rects, keys, skipped = self.app:getRects(true, operation)
    if not rects or #rects == 0 then return false end
    gesture.rects, gesture.keys, gesture.skipped = rects, keys, skipped
    gesture.bounds, gesture.operation = Geometry.bounds(rects), operation
    self:_watchTargets(gesture, keys)
    return true
end

function Input:_watchTargets(gesture, keys)
    local discovery = self.app.discovery
    gesture.objects, gesture.parents, gesture.revision = {}, {}, discovery.revision
    for i, key in ipairs(keys) do
        local record = discovery:get(key)
        local object = record and record.object
        gesture.objects[i], gesture.parents[i] = object or false, object and object.Parent
    end
end

function Input:_snapshotAppearance(gesture, mode)
    if not self.app.appearanceInfo then return false end
    local scope = mode == "opacity" and self.ui.opacityScope or nil
    local model = self.app:appearanceInfo(mode, scope)
    if not model or not model.keys or #model.keys == 0 then return false end
    gesture.appearance, gesture.appearanceMode = model, mode
    gesture.keys, gesture.skipped = model.keys, model.skipped
    self:_watchTargets(gesture, gesture.keys)
    return true
end

function Input:_targetsValid(gesture)
    local discovery = self.app.discovery
    local changed = discovery.revision ~= gesture.revision
    for i, object in ipairs(gesture.objects) do
        if object then
            if object.Parent ~= gesture.parents[i] then return false end
            if changed then
                local record = discovery:get(gesture.keys[i])
                if not record or record.object ~= object then return false end
            end
        end
    end
    gesture.revision = discovery.revision
    return true
end

function Input:_prepareTransform(gesture, mode)
    local key = gesture.pinchKey
    if mode == "move" then key = gesture.dragKey end
    if key and not selected(self.app, key) then
        if gesture.additive then return false end
        self.selectingForGesture = true
        self.app:select(key, false)
        self.selectingForGesture = false
    end
    return self:_snapshot(gesture, mode)
end

function Input:_pinchBegin(gesture, input, p)
    if not touch(input) or not touch(gesture.primary) or input == gesture.primary or gesture.secondary
        or (gesture.kind ~= "canvas" and gesture.kind ~= "drag" and gesture.kind ~= "pinchPending") then return end
    if not gesture.pinchKey and not gesture.resizeGap then return end
    if gesture.additive and not gesture.resizeGap and not selected(self.app, gesture.pinchKey) then return end
    if distance(gesture.latest, p) < 12 then return end
    local operation = self:_operation("resize")
    local bounds = gesture.lastRects and Geometry.bounds(gesture.lastRects) or self.app:currentBounds(true, operation)
    if gesture.kind ~= "drag" and gesture.pinchKey and not selected(self.app, gesture.pinchKey) then
        local record = self.app.discovery:get(gesture.pinchKey)
        bounds = record and Coordinates.rect(record.object) or nil
    end
    if not contains(bounds, p, 16) then return end
    if gesture.lastRects then
        local _, keys = self.app:getRects(true, operation)
        -- A running drag may already have moved roots that a group resize must
        -- leave alone. Preserve the existing drag in that case.
        if not keys or not sameKeys(gesture.keys, keys) then return end
    end
    self:_cancelHold(gesture)
    gesture.secondStart = p
    gesture.pinchStart = gesture.latest
    gesture.pinchDistance = distance(gesture.latest, p)
    gesture.pinchCenter = midpoint(gesture.latest, p)
    gesture.secondary, gesture.secondLatest = input, p
    gesture.kind = "pinch"
    if gesture.lastRects then
        gesture.rects = gesture.lastRects
        gesture.bounds = Geometry.bounds(gesture.rects)
        gesture.operation = operation
        gesture.pinchReady = true
    end
    self:_own(gesture, input)
    self.ui:setGuides({})
end

function Input:_canvasBegin(input)
    if not self:_canStart(input, true) or not self.app.editing then return end
    local p = Coordinates.point(input)
    if self.ui:pointInPanel(p.x, p.y) then return end
    if self.gesture then self:_pinchBegin(self.gesture, input, p); return end
    if self:isSelectThroughArmed() or secondaryMouse(input) then
        self:_setSelectThroughArmed(false)
        self:_claim(input, "selectThrough", p)
        return
    end
    local tool = self:_tool()
    local handle = self:_handleAt(p, tool)
    if handle then
        local rotating = tool == "rotate"
        local gesture = self:_claim(input, rotating and "rotate" or "resize", p)
        gesture.handle = handle.handle
        local marker = touch(input) and Coordinates.rect(handle.marker)
        gesture.tapThrough = marker and not contains(marker, p)
        gesture.additive = self:_multi(input)
        if rotating then
            if not self:_snapshotAppearance(gesture, "rotation") or not gesture.appearance.pivot then
                self:_disown(gesture, input)
                return
            end
            gesture.arc = gesture.appearance.value
            gesture.arcPoint = p
            if distance(gesture.appearance.pivot, p) >= ROTATION_DEAD_ZONE then
                gesture.lastAngle = Geometry.angle(gesture.appearance.pivot, p)
            end
        elseif not self:_snapshot(gesture, "resize") then self:_disown(gesture, input) end
        return
    end
    local additive = self:_multi(input)
    if self.app.preferences.boxSelect then
        self:_claim(input, "box", p).additive = additive
        return
    end
    local hits, record = self:_canvasHits(p)
    if #hits > 0 and not touch(input) and (self:_modifier("LeftAlt") or self:_modifier("RightAlt")) then
        record = hits[1]
        for i, hit in ipairs(hits) do
            if selected(self.app, hit.key) then record = hits[i % #hits + 1]; break end
        end
    end
    local dragKey, pinchKey
    local moveOperation, resizeOperation = self:_operation("move"), self:_operation("resize")
    if self:_supports(record, selected(self.app, record and record.key) and moveOperation or "move") then dragKey = record.key end
    if self:_supports(record, selected(self.app, record and record.key) and resizeOperation or "resize") then pinchKey = record.key end
    local selectedDrag, selectedPinch
    for _, hit in ipairs(hits) do
        if selected(self.app, hit.key) then
            if not selectedDrag and self:_supports(hit, moveOperation) then selectedDrag = hit.key end
            if not selectedPinch and self:_supports(hit, resizeOperation) then selectedPinch = hit.key end
            if selectedDrag and selectedPinch then break end
        end
    end
    dragKey, pinchKey = selectedDrag or dragKey, selectedPinch or pinchKey
    local moveGap, resizeGap
    if not record and #self.app.selection > 1 then
        moveGap = contains(self.app:currentBounds(true, moveOperation), p)
        resizeGap = contains(self.app:currentBounds(true, resizeOperation), p)
    end
    if tool == "rotate" or tool == "opacity" then dragKey, pinchKey, moveGap, resizeGap = nil, nil, nil, nil end
    local kind = (record or dragKey or moveGap or resizeGap or touch(input)) and "canvas" or "box"
    local gesture = self:_claim(input, kind, p)
    gesture.selectionOnly = tool == "rotate" or tool == "opacity"
    gesture.additive, gesture.record, gesture.dragKey, gesture.pinchKey = additive, record, dragKey, pinchKey
    gesture.moveGap, gesture.resizeGap = moveGap, resizeGap
    gesture.hits = hits
    if kind == "canvas" then self:_startHold(gesture) end
end

function Input:_startTransaction(gesture, label)
    if not self:_targetsValid(gesture) then self:cancel(); return false end
    if not gesture.transaction then
        if self.app:beginGesture(label, gesture.skipped) == false then self:cancel(); return false end
        gesture.transaction = true
    end
    return true
end

function Input:_apply(gesture, rects, label)
    if not changedRects(gesture.lastRects or gesture.rects, rects) or not self:_startTransaction(gesture, label) then return end
    if self.app:updateGesture(rects, gesture.keys, gesture.operation) == false then
        self:cancel()
        return
    end
    gesture.lastRects = rects
end

function Input:_applyAppearance(gesture, value)
    local mode = gesture.appearanceMode
    if math.abs(value - (gesture.lastAppearance or gesture.appearance.value)) < .001
        or not self:_startTransaction(gesture, APPEARANCE_LABELS[mode]) then return end
    if self.app:updateAppearance(mode, value, gesture.appearance) == false then
        self:cancel()
        return
    end
    gesture.lastAppearance = value
end

function Input:_updateRotation(gesture, p)
    local pivot = gesture.appearance.pivot
    local previous = gesture.arcPoint
    gesture.arcPoint = p
    if distance(pivot, p) < ROTATION_DEAD_ZONE then gesture.lastAngle = nil; return end
    local angle = Geometry.angle(pivot, p)
    -- Rapid samples can straddle the pivot without reporting a sample inside
    -- the dead zone. Rebase direction instead of treating it as a half turn.
    if gesture.lastAngle and not crossesRotationPivot(previous, p, pivot) then
        gesture.arc = gesture.arc + Geometry.angleDelta(gesture.lastAngle, angle)
        self:_applyAppearance(gesture, gesture.arc)
    end
    gesture.lastAngle = angle
end

function Input:_updateDrag(gesture, p)
    local dx, dy = p.x - gesture.start.x, p.y - gesture.start.y
    local moved = Geometry.translate(gesture.bounds, dx, dy)
    local prefs = self.app.preferences
    local snapped, guides = Geometry.snap(moved, gesture.others, gesture.grid, prefs.snapThreshold or 6, prefs.snapping == true)
    self.ui:setGuides(guides)
    dx, dy = dx + snapped.x - moved.x, dy + snapped.y - moved.y
    local rects = {}
    for i, rect in ipairs(gesture.rects) do rects[i] = Geometry.translate(rect, dx, dy) end
    self:_apply(gesture, rects, "Move selection")
end

function Input:_updateResize(gesture, p)
    local prefs = self.app.preferences
    local center, lock = prefs.centerScale == true, prefs.aspectLock == true
    local resized = Geometry.resize(gesture.bounds, gesture.handle,
        p.x - gesture.start.x, p.y - gesture.start.y, lock, center)
    local rects
    if prefs.equalSize and #gesture.rects > 1 then
        rects = Geometry.adjustMembers(gesture.rects, gesture.bounds, resized, center, lock)
    else
        rects = Geometry.scale(gesture.rects, resized, center)
    end
    self:_apply(gesture, rects, "Resize selection")
end

function Input:_sliderBegin(input, mode)
    if not self:_canStart(input) or not self.app.editing or self.gesture then return end
    local size = mode == "size"
    if size and self.ui.sliderEnabled == false then return end
    local track
    if size then
        if self.ui.sliderTrackRect then track = self.ui:sliderTrackRect()
        else track = Coordinates.rect(self.ui.slider) end
    elseif self.ui.visualSliderTrackRect then track = self.ui:visualSliderTrackRect(mode) end
    if not track or track.w <= 0 then return end
    local p = Coordinates.point(input)
    local gesture = self:_claim(input, "slider", p)
    local info, value
    if size and self:_snapshot(gesture, "resize") then
        info = self.app:sizeInfo(gesture.bounds, gesture.rects, gesture.keys)
        if info and info.scale > 0 then gesture.sizeInfo, value = info, info.scale end
    elseif not size and self:_snapshotAppearance(gesture, mode) then
        info = gesture.appearance
        value = info.value
    end
    if value == nil or info.maximum <= info.minimum then self:_disown(gesture, input); return end
    gesture.sliderMode, gesture.track = mode, track
    local fraction = math.max(0, math.min(1, (value - info.minimum) / (info.maximum - info.minimum)))
    local thumbX = track.x + track.w * fraction
    gesture.thumb = math.abs(p.x - thumbX) <= (touch(input) and 22 or 8)
    gesture.grabOffset = gesture.thumb and (p.x - thumbX) or 0
end

function Input:_updateSlider(gesture, p)
    local info, track = gesture.sizeInfo or gesture.appearance, gesture.track
    local fraction = math.max(0, math.min(1, (p.x - gesture.grabOffset - track.x) / track.w))
    local value = info.minimum + fraction * (info.maximum - info.minimum)
    if gesture.appearance then self:_applyAppearance(gesture, value); return end
    local factor = value / info.scale
    local basis = info.size or info.bounds or gesture.bounds
    local rects = self.app:sizeRects(gesture.rects, basis.w * factor, basis.h * factor, false, info.size, "x")
    self:_apply(gesture, rects, "Size slider")
end

function Input:_updatePinch(gesture)
    local a, b = gesture.latest, gesture.secondLatest
    if not gesture.pinchReady then
        if math.max(distance(gesture.pinchStart, a), distance(gesture.secondStart, b)) < gesture.threshold then return end
        if not self:_prepareTransform(gesture, "resize") then self:cancel(); return end
        gesture.pinchReady = true
    end
    local center, bounds = midpoint(a, b), gesture.bounds
    if not gesture.pinchModel then
        local model = self.app:sizeInfo(bounds, gesture.rects, gesture.keys)
        gesture.pinchModel = {maximum = model and math.max(1, model.maximum / model.scale) or math.huge,
            size = model and model.size or bounds}
    end
    local scale = math.min(distance(a, b) / gesture.pinchDistance, gesture.pinchModel.maximum)
    local prefs = self.app.preferences
    local rects
    if prefs.equalSize and #gesture.rects > 1 then
        local size = gesture.pinchModel.size
        local w, h = size.w * (scale - 1), size.h * (scale - 1)
        local target = {x = bounds.x, y = bounds.y, w = bounds.w + w, h = bounds.h + h}
        rects = Geometry.adjustMembers(gesture.rects, bounds, target, prefs.centerScale == true, true, "x")
        for i, rect in ipairs(rects) do
            rects[i] = Geometry.translate(rect, center.x - gesture.pinchCenter.x, center.y - gesture.pinchCenter.y)
        end
    else
        for _, rect in ipairs(gesture.rects) do
            scale = math.max(scale, Geometry.MIN_SIZE / rect.w, Geometry.MIN_SIZE / rect.h)
        end
        local target = {x = center.x + (bounds.x - gesture.pinchCenter.x) * scale,
            y = center.y + (bounds.y - gesture.pinchCenter.y) * scale, w = bounds.w * scale, h = bounds.h * scale}
        rects = Geometry.scale(gesture.rects, target, false)
    end
    self:_apply(gesture, rects, "Pinch resize")
end

function Input:_floatBegin(input, kind)
    if not self:_canStart(input) or self.gesture or (kind ~= "launcher" and not self.app.editing) then return end
    local x, y
    if self.ui.surfacePosition then x, y = self.ui:surfacePosition(kind)
    elseif kind == "launcher" then
        local rect = Coordinates.rect(self.ui.launcher)
        if rect then x, y = rect.x, rect.y end
    elseif kind == "inspector" then x, y = self.ui:inspectorPosition() end
    if x == nil or y == nil then return end
    local gesture = self:_claim(input, "surface", Coordinates.point(input))
    gesture.surface, gesture.x, gesture.y = kind, x, y
end

function Input:_updateFloat(gesture, p)
    local x = gesture.x + p.x - gesture.start.x
    local y = gesture.y + p.y - gesture.start.y
    if self.ui.moveSurface then self.ui:moveSurface(gesture.surface, x, y)
    elseif gesture.surface == "launcher" then self.ui:moveLauncher(x, y)
    elseif gesture.surface == "inspector" then self.ui:moveInspector(x, y) end
end

function Input:_changed(input)
    local gesture = self.gesture
    if self.destroyed or not gesture then return end
    local owner = input == gesture.primary or input == gesture.secondary
    local mouseMove = not touch(gesture.primary) and input.UserInputType == Enum.UserInputType.MouseMovement
    if not owner and not mouseMove then return end
    if cancelled(input) then self:_ended(input); return end
    if self:_blocked() or (gesture.surface ~= "launcher" and not self.app.editing) then self:cancel(); return end
    local p = Coordinates.point(input)
    if input == gesture.secondary then gesture.secondLatest = p else gesture.latest = p end
    if gesture.kind == "pinch" then self:_updatePinch(gesture); return end
    if not gesture.moved and distance(gesture.start, p) >= gesture.threshold then
        gesture.moved = true
        self:_cancelHold(gesture)
    end
    if not gesture.moved then return end
    if gesture.kind == "canvas" then
        if gesture.selectionOnly then gesture.kind = "passive"; return end
        if (not gesture.dragKey and not gesture.moveGap) or not self:_prepareTransform(gesture, "move") then
            if gesture.record and self.app.capability and self.app.status and not gesture.additive then
                local capability = self.app:capability(gesture.record.key, "move")
                if capability and not capability.supported and capability.reason then self.app:status(capability.reason) end
            end
            gesture.kind = (gesture.pinchKey or gesture.resizeGap) and "pinchPending" or "passive"
            return
        end
        gesture.kind = "drag"
        local discovery = self.app.discovery
        gesture.others = discovery.alignmentRects and discovery:alignmentRects(gesture.keys, gesture.bounds, 64) or {}
        gesture.grid = self.ui.gridSpacing and self.ui:gridSpacing() or self.app.preferences.gridSize or 16
    end
    if gesture.kind == "drag" then self:_updateDrag(gesture, p)
    elseif gesture.kind == "resize" then self:_updateResize(gesture, p)
    elseif gesture.kind == "rotate" then self:_updateRotation(gesture, p)
    elseif gesture.kind == "slider" then
        local dx, dy = math.abs(p.x - gesture.start.x), math.abs(p.y - gesture.start.y)
        if not gesture.sliderMoved then
            if dy > dx then gesture.kind = "passive"; return end
            if dx < gesture.threshold then return end
            gesture.sliderMoved = true
            if self.ui.setSliderDragging then self.ui:setSliderDragging(true, gesture.sliderMode) end
        end
        self:_updateSlider(gesture, p)
    elseif gesture.surface then self:_updateFloat(gesture, p)
    elseif gesture.kind == "box" then self.ui:setBox(boxBetween(gesture.start, p)) end
end

function Input:_boxEnd(gesture)
    if not gesture.moved then
        if not gesture.additive then self.app:clearSelection() end
        return
    end
    local box = boxBetween(gesture.start, gesture.latest)
    local keys, seen = {}, {}
    if gesture.additive then
        for _, key in ipairs(self.app.selection) do keys[#keys + 1] = key; seen[key] = true end
    end
    local discovery = self.app.discovery
    for _, record in ipairs(discovery:list()) do
        local state = self.app.layerState and self.app:layerState(record.key)
        if record.editable and not seen[record.key] and not (state and state.ignored) then
            local r
            if discovery.visibleRect then r = discovery:visibleRect(record)
            else r = Coordinates.rect(record.object) end
            if r and r.x >= box.x and r.y >= box.y and r.x + r.w <= box.x + box.w and r.y + r.h <= box.y + box.h then
                keys[#keys + 1] = record.key
            end
        end
    end
    self.app:selectMany(keys)
end

function Input:_tap(gesture)
    if gesture.record then
        if gesture.additive or not selected(self.app, gesture.record.key) then
            self.app:select(gesture.record.key, gesture.additive)
        end
    elseif not gesture.moveGap and not gesture.resizeGap and not gesture.additive then
        self.app:clearSelection()
    end
    if self.ui.setOverlaps then self.ui:setOverlaps(gesture.hits) end
end

function Input:_toggleEditor()
    if self.app.editing and self.app.Done then return self.app:Done() end
    self.app:setEditing(not self.app.editing)
end

function Input:_finish(gesture, cancelledGesture)
    if gesture.sliderMoved and self.ui.setSliderDragging then self.ui:setSliderDragging(false, gesture.sliderMode) end
    local surface = gesture.surface
    if surface then
        if gesture.moved then
            if self.ui.finishSurfaceMove then self.ui:finishSurfaceMove(surface, cancelledGesture)
            elseif surface == "launcher" then self.ui:finishLauncherMove(cancelledGesture)
            elseif surface == "inspector" then self.ui:finishInspectorMove(cancelledGesture) end
        elseif surface == "launcher" and not cancelledGesture then self:_toggleEditor() end
    elseif cancelledGesture then
        if gesture.transaction then self.app:cancelGesture() end
    elseif gesture.kind == "box" then self:_boxEnd(gesture)
    elseif gesture.kind == "selectThrough" and not gesture.moved then
        local hits = self:_canvasHits(gesture.start, true)
        self:_showThrough(hits, gesture.start)
    elseif gesture.kind == "canvas" and not gesture.moved then self:_tap(gesture)
    elseif gesture.kind == "pinch" and not gesture.pinchReady and not gesture.moved then self:_tap(gesture)
    elseif gesture.tapThrough and not gesture.moved then
        gesture.hits, gesture.record = self:_canvasHits(gesture.start)
        if gesture.record then self:_tap(gesture) end
    end
    if not cancelledGesture and gesture.transaction then self.app:endGesture() end
    self.ui:setBox(nil)
    self.ui:setGuides({})
end

function Input:_ended(input)
    if self.destroyed then return end
    if self.ignored[input] then self.ignored[input] = nil; return end
    local gesture = self.gesture
    if not gesture then return end
    local owned = input == gesture.primary or input == gesture.secondary
        or (not touch(gesture.primary) and input.UserInputType == gesture.primary.UserInputType)
    if not owned then return end
    local wasCancelled = cancelled(input) or self:_blocked() or (gesture.surface ~= "launcher" and not self.app.editing)
        or (gesture.transaction == true and not self:_targetsValid(gesture))
    if not wasCancelled and touch(input) then
        local latest = input == gesture.secondary and gesture.secondLatest or gesture.latest
        if distance(Coordinates.point(input), latest) > 0 then
            self:_changed(input)
            if self.gesture ~= gesture then return end
        end
    end
    if not wasCancelled and gesture.kind == "slider" and not gesture.moved and not gesture.thumb then
        self:_updateSlider(gesture, gesture.latest)
        if self.gesture ~= gesture then return end
    end
    self:_disown(gesture, input)
    self:_finish(gesture, wasCancelled)
end

function Input:_key(input, processed)
    if self.destroyed or input.UserInputType ~= Enum.UserInputType.Keyboard
        or self.uis:GetFocusedTextBox() or self:_blocked() then return end
    local prefs = self.app.preferences
    local shortcut = Enum.KeyCode.F8
    local valid, configured = pcall(function() return Enum.KeyCode[prefs.shortcut or "F8"] end)
    if valid and configured and configured ~= Enum.KeyCode.Unknown then shortcut = configured end
    if input.KeyCode == shortcut then
        if not processed then self:cancel(); self:_toggleEditor() end
        return
    end
    if processed or not self.app.editing then return end
    local key = input.KeyCode
    if self.gesture then
        if key == Enum.KeyCode.Escape then self:cancel() end
        return
    end
    if key == Enum.KeyCode.Escape and self:isSelectThroughArmed() then self:_setSelectThroughArmed(false); return end
    local control = self:_modifier("LeftControl") or self:_modifier("RightControl")
    local shift = self:_modifier("LeftShift") or self:_modifier("RightShift")
    if control then
        if key == Enum.KeyCode.Z then
            if shift then self.app:redo() else self.app:undo() end
        elseif key == Enum.KeyCode.Y then self.app:redo()
        elseif key == Enum.KeyCode.S then self.app:save() end
        return
    end
    if key == Enum.KeyCode.Escape then self.app:clearSelection()
    elseif key == Enum.KeyCode.B then self.app:setPreference("boxSelect", not prefs.boxSelect)
    elseif key == Enum.KeyCode.Left then self.app:move(-(shift and 10 or prefs.step or 1), 0)
    elseif key == Enum.KeyCode.Right then self.app:move(shift and 10 or prefs.step or 1, 0)
    elseif key == Enum.KeyCode.Up then self.app:move(0, -(shift and 10 or prefs.step or 1))
    elseif key == Enum.KeyCode.Down then self.app:move(0, shift and 10 or prefs.step or 1) end
end

function Input:cancel()
    self:_setSelectThroughArmed(false)
    local gesture = self.gesture
    if not gesture then return end
    self:_disown(gesture)
    self:_finish(gesture, true)
end

function Input:destroy()
    if self.destroyed then return end
    self.destroyed = true
    self:cancel()
    for _, connection in ipairs(self.connections) do connection:Disconnect() end
    self.connections = {}
    self.ignored = {}
end

return Input
