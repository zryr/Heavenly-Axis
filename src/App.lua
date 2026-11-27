-- Heavenly Axis V3. Original project by Syshi; V2 inspired by Danechka.
local Util = require("Util")
local Geometry = require("Geometry")
local Coordinates = require("Coordinates")
local Config = require("Config")
local Identity = require("Identity")
local History = require("History")
local Capabilities = require("Capabilities")
local Storage = require("Storage")
local Profiles = require("Profiles")
local Discovery = require("Discovery")
local Transform = require("Transform")

local App = {}
App.__index = App
App.VERSION = "3.1.1"
local defaults = {
    grid = true, snapping = false, gridSize = 24, snapThreshold = 6,
    multiSelect = false, boxSelect = false, aspectLock = true,
    centerScale = false, equalSize = false, step = 1, shortcut = "F8",
    launcherHidden = false, launcherX = 0.02, launcherY = 0.35,
}

local function viewport(services)
    local camera = services.Workspace.CurrentCamera
    local size = camera and camera.ViewportSize or Vector2.new(800, 600)
    return size.X, size.Y
end
local function exists(object)
    local ok, parent = pcall(function() return object.Parent end)
    return ok and parent ~= nil
end

local function resolvedState(layout, preferences, groups)
    local state = {layout = Util.copy(layout or {}), groups = Util.copy(groups or {}), preferences = Util.copy(defaults)}
    for key, value in pairs(preferences or {}) do state.preferences[key] = value end
    return state
end

local function sameContext(a, b)
    return a and b and a.experience == b.experience and a.place == b.place
        and a.device == b.device and a.orientation == b.orientation
end

function App.new(env, services, playerGui, options)
    local self = setmetatable({}, App)
    self.env, self.services, self.playerGui = env, services, playerGui
    if type(env.__HEAVENLY_AXIS_V3) == "table" and env.__HEAVENLY_AXIS_V3.initializing then
        env.__HEAVENLY_AXIS_V3.partial = self
    end
    self.options = options or {}
    self.version = App.VERSION
    self.alive, self.editing, self.dirty = true, false, false
    self.logs, self.connections, self.selection = {}, {}, {}
    self.layout, self.groups, self.preferences = {}, {}, Util.copy(defaults)
    self.history = History.new(80)
    self.startedAt = os.time()
    self.context = {
        experience = tostring(game.GameId), place = tostring(game.PlaceId),
        device = services.UserInputService.TouchEnabled and "touch" or "desktop",
    }
    local w, h = viewport(services)
    self.context.orientation = w >= h and "landscape" or "portrait"
    local function log(message) self:log(message) end
    self.capabilities = Capabilities.detect(env, services)
    self.storage = Storage.new(self.capabilities, services.HttpService, log, self.context)
    local data, loadError = self.storage:load()
    if loadError then self:log(loadError) end
    self.profiles = Profiles.new(data or Config.empty(), self.storage, self.context, log)
    local initial = resolvedState(self.profiles:resolve())
    self.layout, self.groups, self.preferences = initial.layout, initial.groups, initial.preferences
    self.discovery = Discovery.new(playerGui, nil, log, services.GuiService)
    self.transform = Transform.new(self.discovery, log)
    if self.options.SafeMode then
        self.suspendedState = {layout = Util.copy(self.layout), groups = Util.copy(self.groups), preferences = Util.copy(self.preferences)}
        self.profiles:suspend(true)
        self.transform.safe = true
    end
    self.transform.onChanged = function()
        if not self.alive then return end
        self.runtimeRevision = (self.runtimeRevision or 0) + 1
        self:log("A runtime layout application was rolled back. Saved settings are preserved.")
        if self.ui then self:status("A layout adjustment could not be applied. See Diagnostics.") end
        self:changed()
    end
    self.discovery:start(function(reason) self:_discoveryChanged(reason) end)
    self:_applyLayout(self.layout, true)
    self.savedProfilesData = Util.copy(self.profiles.data)
    self.savedState = self:getState()
    self.editBaseline = Util.copy(self.savedState)
    self.history:checkpoint(self.savedState)
    self:_loadDraft(self.context)
    self:_watchViewport()
    self:log("Initialized Heavenly Axis " .. self.version .. "; accessible PlayerGui objects only.")
    self:log("Control visuals are editable where accessible; functional jump/joystick touch regions are unverified.")
    for name, capability in pairs(self.capabilities) do
        if type(capability) == "table" and capability.status then
            self:log(name .. ": " .. capability.status .. " — " .. tostring(capability.detail or ""))
        end
    end
    if self.options.SafeMode then self:safeMode() end
    if not self.options.LoaderOnly and not self.options.SafeMode then self:Open() end
    return self
end

function App:log(message)
    if not self.logs then return end
    self.logs[#self.logs + 1] = tostring(message):sub(1, 320)
    if #self.logs > 100 then table.remove(self.logs, 1) end
end
function App:status(message)
    self.statusMessage = tostring(message)
    self:log(message)
    if self.ui then self.ui:status(self.statusMessage) end
end
function App:_applyLayout(layout, replace, onlyNew)
    if self.profiles.suspended then return 0, 0 end
    local ok, count, skipped = pcall(function()
        return self.transform:apply(layout, { replace = replace, experimental = true, onlyNew = onlyNew })
    end)
    if not ok then self:log("Layout application failed; use Safe Mode to recover."); return 0, 1 end
    self.application = { applied = count or 0, skipped = skipped or 0 }
    return count, skipped
end
function App:_discoveryChanged(reason)
    if not self.alive then return end
    if reason ~= "presentation" then self.discoveryRestorationRequested = true end
    if self.discoveryPending then return end
    self.discoveryPending = true
    task.delay(0.12, function()
        self.discoveryPending = false
        if not self.alive then return end
        if self.discoveryRestorationRequested then
            self.discoveryRestorationRequested = nil
            if not self.gesture and not self.finishingGesture then self:_applyLayout(self.layout, false, true)
            else self.restoreAfterGesture = true end
        end
        local selected = {}
        for _, key in ipairs(self.selection) do
            local record = self.discovery:get(key)
            if record and exists(record.object) then selected[#selected + 1] = key end
        end
        if #selected ~= #self.selection then
            if self.input then self.input:cancel() else self:cancelGesture() end
            self.selection = selected
            self.sizeReference = nil
        end
        self.unmatched = self.transform:matches(self.layout)
        if self.ui then self.ui:refresh() end
    end)
end
function App:_currentEditContext()
    return self.editContext or self.context
end
function App:_loadDraft(context)
    self.draftLoadRevision = (self.draftLoadRevision or 0) + 1
    local revision = self.draftLoadRevision
    context = Util.copy(context)
    local draft, reason, blocked = self.storage:loadDraft(context)
    if not self.alive or revision ~= self.draftLoadRevision or not sameContext(context, self:_currentEditContext()) then return end
    self.draft, self.recoveredDraft, self.draftBlocked = nil, nil, nil
    if reason then self:log(reason) end
    if blocked then self.draftBlocked = reason; return end
    if not draft or not sameContext(draft.context, context) then return end
    if draft.reference and not self.profiles:matchesDraftReference(draft.reference, context) then
        self.draftBlocked = "Recovery draft preserved because its saved profile or baseline changed."
        self:log(self.draftBlocked)
        return
    end
    self.draft = draft
    self:log("An unsaved draft is ready to preview in Recovery.")
end
function App:_adoptContext()
    self.editContext = nil
    self.profiles:setEditTarget(nil, self.context)
    self.savedEditTarget = nil
    self.launcherOverrides = nil
    local state = resolvedState(self.profiles:resolve(self.context))
    self:loadState(state)
    self.savedState = self:getState()
    self.editBaseline = Util.copy(self.savedState)
    self.history = History.new(80)
    self.history:checkpoint(self.savedState)
    self:_loadDraft(self.context)
end
function App:_watchViewport()
    local function resize()
        if not self.alive then return end
        if self.input then self.input:cancel() else self:cancelGesture() end
        local w, h = viewport(self.services)
        local orientation = w >= h and "landscape" or "portrait"
        if orientation ~= self.context.orientation then
            if self.previewState then self:profile("cancel") end
            local previous = Util.copy(self:_currentEditContext())
            local wasDirty = self.profileChanged or self.dirty or self.finishingGesture or self.saving
            self.context.orientation = orientation
            if not wasDirty and not self.profiles.suspended then
                self:_adoptContext()
                self:log("Applied " .. orientation .. " profile precedence.")
            else
                self.editContext = not sameContext(previous, self.context) and previous or nil
                if self.editContext and not self.profiles.suspended then
                    self:status("Editing the " .. previous.orientation .. " layout. Save or discard to switch layouts.")
                end
            end
        end
        if self.ui then
            if self.ui.viewportChanged then self.ui:viewportChanged() else self.ui:refresh() end
        end
    end
    local cameraConnection
    local function bindCamera()
        if cameraConnection then cameraConnection:Disconnect() end
        local camera = self.services.Workspace.CurrentCamera
        if camera then cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(resize) end
        resize()
    end
    self.connections[#self.connections + 1] = self.services.Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
    self.connections[#self.connections + 1] = { Disconnect = function() if cameraConnection then cameraConnection:Disconnect() end end }
    bindCamera()
end
function App:getState()
    if self.profiles.suspended and self.suspendedState then return Util.copy(self.suspendedState) end
    local layout = Util.copy(self.layout)
    for key, entry in pairs(self.transform:capture()) do layout[key] = entry end
    local preferences = Util.copy(self.preferences)
    for key, value in pairs(self.toolDefaults or {}) do preferences[key] = value end
    return {layout = layout, groups = Util.copy(self.groups), preferences = preferences}
end
function App:_setState(state, keepLauncher)
    state = resolvedState(state.layout, state.preferences, state.groups)
    self.layout, self.groups, self.preferences = state.layout, state.groups, state.preferences
    if keepLauncher then
        for key, value in pairs(self.launcherOverrides or {}) do self.preferences[key] = value end
        for key in pairs(self.toolModes or {}) do self.toolDefaults[key] = self.preferences[key] end
        for key, value in pairs(self.toolModes or {}) do self.preferences[key] = value end
    else
        self.launcherOverrides, self.toolModes, self.toolDefaults = nil, nil, nil
        self.sizeReference = nil
    end
end
function App:loadState(state, keepLauncher)
    self:_setState(state, keepLauncher)
    self:_applyLayout(self.layout, true)
    self.unmatched = self.transform:matches(self.layout)
end
function App:_writeDraft()
    local state = self:getState()
    local context = Util.copy(self:_currentEditContext())
    state.context = context
    state.reference = self.profiles:draftReference(context)
    return self.storage:draft(state, context)
end
function App:_invalidateDraftTimer()
    self.draftGeneration = (self.draftGeneration or 0) + 1
    if self.draftTimer and task.cancel then pcall(task.cancel, self.draftTimer) end
    self.draftTimer = nil
end
function App:_draftLater()
    if self.capabilities.storage.status == "Unsupported" or self.previewState or self.profiles.suspended
        or self.draftBlocked or (self.draft and not self.recoveredDraft) then return end
    self:_invalidateDraftTimer()
    local generation = self.draftGeneration
    self.draftTimer = task.delay(1, function()
        if generation ~= self.draftGeneration then return end
        self.draftTimer = nil
        if not self.alive or self.saving or self.saveWaiting or self.gesture or self.finishingGesture or not self.dirty then return end
        if self.previewState or self.profiles.suspended or self.draftBlocked or (self.draft and not self.recoveredDraft) then return end
        local ok, message = self:_writeDraft()
        if not ok and self.capabilities.storage.status ~= "Unsupported" then self:log(message) end
    end)
end
function App:changed()
    if not self.alive then return end
    self.dirty = self.profileChanged == true or self.history:dirty(self:getState())
    self.unmatched = self.transform:matches(self.layout)
    if self.ui then self.ui:refresh() end
    if self.dirty then self:_draftLater() end
end
function App:_selectionChanged()
    self.sizeReference = nil
    if self.ui then
        if self.ui.selectionChanged then self.ui:selectionChanged() else self.ui:refresh() end
    end
end
function App:select(key, toggle)
    if not key then return self:clearSelection() end
    local record = self.discovery:get(key)
    if not record then return self:status("Element no longer available. Use the list to select another.") end
    if toggle or self.preferences.multiSelect then
        local selected = Util.copy(self.selection)
        for index, old in ipairs(selected) do
            if old == key then table.remove(selected, index); self.selection = selected; self:_selectionChanged(); return end
        end
        selected[#selected + 1] = key
        self.selection = selected
    elseif #self.selection == 1 and self.selection[1] == key then return
    else self.selection = {key} end
    if not record.editable then self:status(record.reason or "Unsupported element.") end
    self:_selectionChanged()
end
function App:selectMany(keys)
    local selection, seen = {}, {}
    for _, key in ipairs(keys) do
        if not seen[key] and self.discovery:get(key) then selection[#selection + 1] = key; seen[key] = true end
    end
    if Util.equal(selection, self.selection) then return end
    self.selection = selection
    self:_selectionChanged()
end
function App:clearSelection() self:selectMany({}) end
function App:getRects(editableOnly) return self.transform:selectionRects(self.selection, editableOnly) end
function App:currentBounds(editableOnly)
    local rects = self:getRects(editableOnly)
    return Geometry.bounds(rects)
end
function App:beginGesture(label, skipped)
    if self.previewState then self:status("Apply or cancel the profile preview before editing."); return false end
    if self.profiles.suspended then self:status("Profiles are suspended. Resume application before editing."); return false end
    if self.gesture then return false end
    if self.finishingGesture or self.saving or (self.transform.beginTransaction and self.transform:beginTransaction() == false) then
        self:status("Finishing the previous adjustment. Try again in a moment.")
        return false
    end
    self.gesture = {before = self:getState(), label = label or "Transform", skipped = skipped}
    return true
end
function App:updateGesture(rects, keys)
    if not self.gesture then return false end
    local ok, reason = self.transform:setRects(keys or self.selection, rects)
    if not ok then self:status(reason or "Transformation is unsupported."); return false end
    if self.ui then
        if self.ui.requestSelectionUpdate then self.ui:requestSelectionUpdate() else self.ui:updateSelection() end
    end
    return true
end
function App:_afterInteraction(ok, reason)
    if self.restoreAfterGesture then
        self.restoreAfterGesture = nil
        self:_applyLayout(self.layout, false, true)
    end
    self:changed()
    if self.editContext and not self.dirty and not self.profiles.suspended then self:_adoptContext(); self:changed() end
    local pendingSave, pendingDone = self.gestureSave, self.doneWaiting
    self.gestureSave, self.doneWaiting = nil, nil
    if pendingSave then
        if ok then self:save(pendingSave) else pendingSave(false, reason) end
    end
    if pendingDone and self.editing then self:Done() end
end
function App:endGesture()
    if not self.gesture then return false end
    local gesture = self.gesture
    self.gesture = nil
    self.finishingGesture = gesture
    local function complete(ok, reason)
        if self.finishingGesture ~= gesture then return end
        self.finishingGesture = nil
        if not self.alive then return end
        if ok then
            local after = self:getState()
            self.layout = after.layout
            local recorded = self.history:push(gesture.before, after, gesture.label)
            if (gesture.skipped or 0) > 0 then
                self:status(tostring(gesture.skipped) .. " unavailable or incompatible elements skipped.")
            elseif recorded then
                local bounds = self:currentBounds(true)
                local w, h = viewport(self.services)
                local safe = Coordinates.safeRect(self.services.GuiService, w, h)
                if bounds and not Coordinates.intersection(bounds, safe) then
                    self:status("Selection is offscreen. Use Recover in Tools to bring it back.")
                end
            end
        else
            self:status(reason or "The adjustment could not be verified and was rolled back.")
        end
        self:_afterInteraction(ok, reason)
    end
    if not self.transform.endTransaction or self.transform:endTransaction(complete) ~= true then complete(true) end
    return true
end
function App:cancelGesture()
    if not self.gesture then return end
    local state = self.gesture.before
    self.gesture = nil
    if not self.transform.cancelTransaction or self.transform:cancelTransaction() ~= true then self:loadState(state, true) end
    if self.restoreAfterGesture then
        self.restoreAfterGesture = nil
        self:_applyLayout(self.layout, false, true)
    end
    self:changed()
end
function App:_rectAction(label, callback)
    local rects, keys, skipped = self:getRects(true)
    if #keys == 0 then return self:status("Select an editable element first.") end
    if not self:beginGesture(label, skipped) then return end
    local ok, result = pcall(callback, rects)
    if ok and result and self:updateGesture(result, keys) then return self:endGesture() end
    self:cancelGesture()
    if not ok or not result then self:status("Invalid transformation; layout retained.") end
end
function App:move(dx, dy)
    if not Util.finite(dx) or not Util.finite(dy) then return end
    self:_rectAction("Move", function(rects)
        local moved = {}
        for index, rect in ipairs(rects) do moved[index] = Geometry.translate(rect, dx, dy) end
        return moved
    end)
end
local function resizeBasis(rects, bounds, individual)
    if not individual then return bounds end
    local width, height = 0, 0
    for _, rect in ipairs(rects) do
        width, height = math.max(width, rect.w), math.max(height, rect.h)
    end
    return {w = width, h = height}
end

function App:sizeRects(rects, width, height, center, basis, aspectAxis)
    local bounds = Geometry.bounds(rects)
    if not bounds then return {} end
    local individual = self.preferences.equalSize and #rects > 1
    basis = basis or resizeBasis(rects, bounds, individual)
    if self.preferences.aspectLock then
        local fx, fy = width / basis.w, height / basis.h
        aspectAxis = aspectAxis or (math.abs(fx - 1) >= math.abs(fy - 1) and "x" or "y")
        local factor = aspectAxis == "x" and fx or fy
        width, height = basis.w * factor, basis.h * factor
    end
    local target = {x = bounds.x, y = bounds.y, w = bounds.w + (width - basis.w), h = bounds.h + (height - basis.h)}
    if individual then return Geometry.adjustMembers(rects, bounds, target, center, self.preferences.aspectLock, aspectAxis) end
    return Geometry.scale(rects, target, center)
end

function App:sizeInfo(bounds, rects, keys)
    if not rects or not keys then rects, keys = self:getRects(true); bounds = nil end
    bounds = bounds or Geometry.bounds(rects)
    if not bounds or bounds.w <= 0 or bounds.h <= 0 then return nil end
    local individual = self.preferences.equalSize and #rects > 1
    local size = resizeBasis(rects, bounds, individual)
    local signature = table.concat(keys, "\n") .. (individual and "\nindividual" or "\nproportional")
    local reference = self.sizeReference
    if not reference or reference.signature ~= signature then
        local record = #keys == 1 and self.discovery:get(keys[1])
        local original = record and record.baselineRect
        local baseline = Geometry.valid(original) and original or size
        reference = {signature = signature, w = baseline.w, h = baseline.h, original = baseline == original}
        self.sizeReference = reference
    end
    local scale = 100 * size.w / reference.w
    local minimumFactor = 0
    for _, rect in ipairs(rects) do
        local fx, fy = Geometry.MIN_SIZE / rect.w, Geometry.MIN_SIZE / rect.h
        if individual then
            fx, fy = 1 + (Geometry.MIN_SIZE - rect.w) / size.w, 1 + (Geometry.MIN_SIZE - rect.h) / size.h
        end
        minimumFactor = math.max(minimumFactor, fx, fy)
    end
    local viewW, viewH = viewport(self.services)
    local maximum = math.max(scale, 150, math.min(400, 100 * math.min(viewW / reference.w, viewH / reference.h)))
    return {scale = scale, minimum = math.min(scale, scale * minimumFactor), maximum = maximum,
        baseline = reference, original = reference.original, size = size, bounds = bounds}
end

function App:setSizePercent(percent)
    local info = self:sizeInfo()
    if not info then return self:status("Select an editable element first.") end
    if not Util.finite(percent) or percent < 1 or percent > 10000 then return self:status("Enter a size from 1% to 10000%.") end
    local factor = math.max(percent, info.minimum) / info.scale
    return self:resize(info.size.w * factor, info.size.h * factor, false, "x")
end

function App:stepSize(delta)
    local info = self:sizeInfo()
    if not info or not Util.finite(delta) or delta == 0 then return end
    -- Small controls need at least one layout unit before Roblox can visibly round the change.
    local amount = math.max(math.abs(delta), info.scale / info.size.w)
    local nextScale = info.scale + (delta > 0 and amount or -amount)
    return self:setSizePercent(math.max(1, info.minimum, nextScale))
end

function App:resize(width, height, center, aspectAxis)
    if not Util.finite(width) or not Util.finite(height) or width < Geometry.MIN_SIZE or height < Geometry.MIN_SIZE
        or width > 100000 or height > 100000 then
        return self:status("Enter width and height between 16 and 100000 pixels.")
    end
    if center == nil then center = self.preferences.centerScale end
    self:_rectAction("Resize", function(rects)
        return self:sizeRects(rects, width, height, center, nil, aspectAxis)
    end)
end
function App:scale(factor)
    if not Util.finite(factor) or factor <= 0 or factor > 100 then return self:status("Invalid scale.") end
    local info = self:sizeInfo()
    if info then self:setSizePercent(info.scale * factor) end
end
function App:geometry(mode, value)
    if mode == "position" then
        local bounds = self:currentBounds(true)
        if bounds and type(value) == "table" and Util.finite(value.x) and Util.finite(value.y) then
            self:move(value.x - bounds.x, value.y - bounds.y)
        end
    elseif mode == "rotation" or mode == "transparency" then
        if not Util.finite(value) then return self:status("Enter a finite number.") end
        if mode == "rotation" and (value < -360 or value > 360) then return self:status("Rotation range: -360 to 360.") end
        if mode == "transparency" and (value < 0 or value > 1) then return self:status("Transparency range: 0 to 1.") end
        if not self:beginGesture(mode) then return end
        local _, skipped = self.transform:setProperty(self.selection, mode, value)
        self.gesture.skipped = skipped
        self:endGesture()
    end
end
function App:align(mode)
    self:_rectAction("Align " .. tostring(mode), function(rects) return Geometry.align(rects, mode) end)
end
function App:distribute(axis)
    self:_rectAction("Distribute " .. tostring(axis), function(rects) return Geometry.distribute(rects, axis) end)
end
function App:reset()
    if #self.selection == 0 then return self:status("Select elements to reset to their original properties.") end
    if not self:beginGesture("Reset to original") then return end
    local _, skipped = self.transform:restore(self.selection)
    self.gesture.skipped = skipped
    self:endGesture()
end
function App:recover()
    self:_rectAction("Recover offscreen selection", function(rects)
        local bounds = Geometry.bounds(rects)
        local w, h = viewport(self.services)
        local safe = Coordinates.coreRect(self.services.GuiService, w, h)
        local left, top = safe.x, safe.y
        local right, bottom = safe.x + safe.w, safe.y + safe.h
        local dx = math.max(left, math.min(bounds.x, right - bounds.w)) - bounds.x
        local dy = math.max(top, math.min(bounds.y, bottom - bounds.h)) - bounds.y
        local changed = {}
        for i, rect in ipairs(rects) do changed[i] = Geometry.translate(rect, dx, dy) end
        return changed
    end)
end
function App:_replay(direction)
    if self.previewState then return self:status("Apply or cancel the preview first.") end
    if self.profiles.suspended then return self:status("Resume the profile before replaying edits.") end
    if self.finishingGesture or self.saving then return self:status("Wait for the current adjustment to finish.") end
    if self.input then self.input:cancel() else self:cancelGesture() end
    local undoing = direction == "undo"
    local stack = undoing and self.history.past or self.history.future
    local entry = stack[#stack]
    if not entry then return end
    local target = undoing and entry.before or entry.after
    local job = {}
    self.finishingGesture = job
    local function complete(ok, reason, skipped)
        if self.finishingGesture ~= job then return end
        self.finishingGesture = nil
        if not self.alive then return end
        if ok then
            local state, label = self.history[direction](self.history)
            self:_setState(state, true)
            local note = (undoing and "Undid " or "Redid ") .. tostring(label)
            if (skipped or 0) > 0 then note = note .. ". " .. skipped .. " missing elements skipped." end
            self:status(note)
        else self:status(reason or "The original state could not be verified. History was preserved.") end
        self:_afterInteraction(ok, reason)
    end
    if not self.transform:applyHistory(self.layout, target.layout, complete) then
        complete(false, "Wait for the current adjustment to finish.")
    end
end
function App:undo() self:_replay("undo") end
function App:redo() self:_replay("redo") end
function App:_clearCurrentDraft(context)
    if not self.draftBlocked and (not self.draft or self.recoveredDraft) then
        local function clear()
            local cleared, reason, busy = self.storage:clearDraft(context)
            if cleared or self.capabilities.storage.status == "Unsupported" then
                if sameContext(self:_currentEditContext(), context) then self.draft, self.recoveredDraft = nil, nil end
            elseif reason then self:log(reason) end
            return busy
        end
        if clear() then
            local generation = self.draftGeneration
            task.delay(0.25, function()
                if self.alive and generation == self.draftGeneration and not self.dirty then
                    clear()
                    if self.ui then self.ui:refresh() end
                end
            end)
        end
    end
end
function App:save(onComplete)
    if self.previewState then return self:status("Apply or cancel the preview before saving.") end
    if self.profiles.suspended then return self:status("Resume the profile before saving. Safe Mode preserves saved configurations.") end
    if self.saving or self.saveWaiting then return false, "A save is already in progress." end
    self:endGesture()
    if self.input then self.input:cancel() end
    if self.finishingGesture then
        if onComplete or not self.gestureSave then self.gestureSave = onComplete or function() end end
        return false, "Waiting for the current adjustment."
    end
    if self.transform.pendingStabilization then
        local requested = self:getState()
        local revision = self.runtimeRevision
        self.saveWaiting = true
        self:status("Waiting for the layout stability check before saving…")
        task.delay(0.35, function()
            self.saveWaiting = nil
            if not self.alive then return end
            if self.transform.pendingStabilization or self.gesture or self.finishingGesture
                or self.previewState or self.profiles.suspended or revision ~= self.runtimeRevision
                or not Util.equal(requested, self:getState()) then
                local reason = "Layout changed during the stability check. Review it and save again."
                self:status(reason)
                if self.dirty then self:_draftLater() end
                if onComplete then onComplete(false, reason) end
            else self:save(onComplete) end
        end)
        return false, "Save is waiting for layout stabilization."
    end
    local state = self:getState()
    local context = Util.copy(self:_currentEditContext())
    self.saving = true
    local ok, message, accepted = self.profiles:save(state.layout, state.groups, state.preferences, self.editBaseline, context)
    if self.alive and (ok or accepted) then
        self.history:checkpoint(state)
        self.profileChanged = false
        self.savedProfilesData = Util.copy(self.profiles.data)
        self.savedState = Util.copy(state)
        self.savedEditTarget = self.profiles:editTargetId(context)
        self.editBaseline = Util.copy(state)
        self:_invalidateDraftTimer()
        self:_clearCurrentDraft(context)
        if self.alive and self.editContext then self:_adoptContext() end
    end
    self.saving = nil
    if not self.alive then return ok, message, accepted end
    self:status(message or (ok and "Profile persisted." or "Save failed; draft retained."))
    self:changed()
    if onComplete then onComplete(ok, message, accepted) end
    return ok, message, accepted
end
function App:cancel(onComplete)
    if self.previewState then return self:profile("cancel") end
    if self.finishingGesture or self.saving then return self:status("Wait for the current adjustment to finish.") end
    if self.input then self.input:cancel() else self:cancelGesture() end
    if self.profiles.suspended then return self:status("Profile is suspended. Resume it before returning to the Save checkpoint.") end
    local context = self:_currentEditContext()
    local job = {}
    self.finishingGesture = job
    local result
    local function complete(ok, reason, skipped)
        if self.finishingGesture ~= job then return end
        if not self.alive then return end
        result = ok
        if ok then
            local state = self.history:cancel()
            self.profiles.data = Util.copy(self.savedProfilesData)
            self.profiles:setEditTarget(self.savedEditTarget, context)
            self.profileChanged = false
            self:_setState(state)
            self.editBaseline = Util.copy(self.savedState)
            self:_invalidateDraftTimer()
            self:_clearCurrentDraft(context)
            if not self.alive or self.finishingGesture ~= job then return end
            if self.editContext then self:_adoptContext() end
            local note = "Returned to the latest Save checkpoint."
            if (skipped or 0) > 0 then note = note .. " " .. skipped .. " missing elements skipped." end
            self:status(note)
        else self:status(reason or "The checkpoint could not be restored. Use Safe Mode to recover originals.") end
        self.finishingGesture = nil
        self:_afterInteraction(ok, reason)
        if onComplete then onComplete(ok) end
    end
    if not self.transform:applyHistory(self.layout, self.savedState.layout, complete) then
        complete(false, "Wait for the current adjustment to finish.")
    end
    return result
end
function App:Done()
    if self.previewState then
        if self.ui and self.ui.setTab then self.ui:setTab("Profiles") end
        return self:status("Apply or cancel the preview before returning to gameplay.")
    end
    if self.saving or self.saveWaiting then return self:status("The save is still in progress.") end
    if self.input then self.input:cancel() else self:cancelGesture() end
    if self.finishingGesture then self.doneWaiting = true; return end
    if not self.dirty or self.profiles.suspended then return self:Close() end
    if not self.ui or not self.ui.confirmDone then return self:status("Save or discard changes before closing.") end
    self.ui:confirmDone(function()
        self:save(function(ok, _, accepted)
            if ok then self:Close()
            elseif accepted and self.ui and self.ui.showExport then self.ui:showExport() end
        end)
    end, function()
        self:cancel(function(ok) if ok then self:Close() end end)
    end)
end
function App:setPreference(name, value)
    if defaults[name] == nil then return end
    if self.previewState then return self:status("Apply or cancel the preview before changing preferences.") end
    if self.profiles.suspended then return self:status("Resume the profile before changing preferences.") end
    if self.finishingGesture or self.saving then return end
    if type(value) ~= type(defaults[name]) then return self:status("Invalid preference value.") end
    if name == "shortcut" then
        local valid, key = pcall(function() return Enum.KeyCode[value] end)
        if not valid or not key or key == Enum.KeyCode.Unknown then return self:status("Use a Roblox key name such as F8.") end
    end
    if name == "step" and (not Util.finite(value) or value < 1 or value > 64) then return end
    if name == "gridSize" and (not Util.finite(value) or value < 4 or value > 128) then return end
    if name == "snapThreshold" and (not Util.finite(value) or value < 1 or value > 32) then return end
    if (name == "launcherX" or name == "launcherY") and (not Util.finite(value) or value < 0 or value > 1) then return end
    if self.preferences[name] == value then return end
    if name == "multiSelect" or name == "boxSelect" then
        self.toolModes, self.toolDefaults = self.toolModes or {}, self.toolDefaults or {}
        if self.toolModes[name] == nil then self.toolDefaults[name] = self.preferences[name] end
        self.toolModes[name], self.preferences[name] = value, value
        if self.ui then self.ui:refresh() end
        return
    end
    if name == "launcherX" or name == "launcherY" or name == "launcherHidden" then
        self.launcherOverrides = self.launcherOverrides or {}
        self.launcherOverrides[name], self.preferences[name] = value, value
        return self:changed()
    end
    local before = self:getState()
    self.preferences[name] = value
    self.history:push(before, self:getState(), "Editor preference")
    self:changed()
end
function App:setLauncherPosition(x, y)
    if self.previewState or self.profiles.suspended or self.saving or self.finishingGesture then return end
    if not Util.finite(x) or not Util.finite(y) or x < 0 or x > 1 or y < 0 or y > 1 then return end
    if self.preferences.launcherX == x and self.preferences.launcherY == y then return end
    self.launcherOverrides = self.launcherOverrides or {}
    self.launcherOverrides.launcherX, self.launcherOverrides.launcherY = x, y
    self.preferences.launcherX, self.preferences.launcherY = x, y
    self:changed()
end
function App:group(action, name, extra)
    if self.previewState then return self:status("Apply or cancel the preview first.") end
    if action ~= "select" and self.profiles.suspended then return self:status("Resume the profile before editing groups.") end
    if action ~= "select" and (self.finishingGesture or self.saving) then return end
    if action == "select" then
        local keys = {}
        local members = self.groups[name] or {}
        for _, descriptor in ipairs(members) do
            local key = Identity.key(descriptor)
            if self.discovery:get(key) then keys[#keys + 1] = key end
        end
        self:selectMany(keys)
        if #keys < #members then self:status(tostring(#members - #keys) .. " group members are currently missing.") end
        return
    end
    if type(name) ~= "string" or not name:match("%S") or #name > 64 or name:find("[%c]") then return self:status("Group names need 1–64 readable characters.") end
    local before = self:getState()
    if action == "create" then
        if self.groups[name] then return self:status("A group with this name already exists.") end
        self.groups[name] = {}
    elseif action == "delete" then self.groups[name] = nil
    elseif action == "rename" then
        if type(extra) ~= "string" or not extra:match("%S") or #extra > 64 or extra:find("[%c]") or self.groups[extra] then return self:status("Choose an unused group name (1–64 readable characters).") end
        self.groups[extra], self.groups[name] = self.groups[name], nil
    end
    if action == "create" or action == "add" then
        if not self.groups[name] then return self:status("Select a saved group first.") end
        local seen = {}
        for _, descriptor in ipairs(self.groups[name]) do seen[Identity.key(descriptor)] = true end
        for _, key in ipairs(self.selection) do
            local record = self.discovery:get(key)
            if record and not seen[key] then self.groups[name][#self.groups[name] + 1] = Util.copy(record.descriptor); seen[key] = true end
        end
    elseif action == "remove" and self.groups[name] then
        local remove = {}
        for _, key in ipairs(self.selection) do remove[key] = true end
        local keep = {}
        for _, descriptor in ipairs(self.groups[name]) do if not remove[Identity.key(descriptor)] then keep[#keep + 1] = descriptor end end
        self.groups[name] = keep
    end
    local valid, reason = Config.validateGroups(self.groups)
    if not valid then self.groups = before.groups; return self:status(reason) end
    self.history:push(before, self:getState(), "Group " .. action)
    self:changed()
end
function App:profile(action, idOrName, extra)
    if self.input then self.input:cancel() elseif self.gesture then self:cancelGesture() end
    if self.finishingGesture or self.saving then return self:status("Wait for the current adjustment to finish.") end
    if self.editContext and action ~= "cancel" and action ~= "apply" and action ~= "suspend"
        and action ~= "restore" and action ~= "recoverDraft" and action ~= "discardDraft" then
        return self:status("Save or discard the previous orientation's edits before managing profiles.")
    end
    local context = self:_currentEditContext()
    if action == "preview" then
        if self.previewState then self:profile("cancel") end
        local before = self:getState()
        local layout, err, prefs, groups = self.profiles:beginPreview(idOrName, context)
        if not layout then return self:status(err or "Profile preview failed.") end
        self.previewState = before
        self.previewSuspended = self.profiles.suspended
        self.profiles:suspend(false)
        self:loadState({layout = layout, preferences = prefs, groups = groups}, true)
        local note = self.profiles.preview.overlaid and " More-specific overrides still apply." or ""
        self:status("Preview only." .. note .. " Apply selects this profile and replaces the current draft. Cancel restores it.")
    elseif action == "apply" then
        if not self.previewState then return self:status("Preview a profile or imported configuration first.") end
        if self.draftPreview then
            local state = self:getState()
            local previous = self.previewState
            local reference = self.draft and self.draft.reference
            if reference and not self.profiles:matchesDraftReference(reference, context) then
                return self:status("The recovery draft's saved profile changed. Cancel the preview to keep it separate.")
            end
            if reference then self.profiles:setEditTarget(reference.profileId or nil, context) end
            self.previewState, self.draftPreview = nil, nil
            self.previewSuspended = nil
            self.recoveredDraft = true
            self.suspendedState = nil
            self.profiles:suspend(false)
            self.transform.safe = false
            self.history:push(previous, state, "Restore recovered draft")
            self:status("Recovered unsaved draft. Save to persist this layout.")
            self:changed()
            return true
        end
        local ok, err = self.profiles:applyPreview()
        if not ok then return self:status(err or "Could not apply preview.") end
        self.previewState, self.previewSuspended = nil, nil
        self.suspendedState = nil
        self.transform.safe = false
        self.launcherOverrides = nil
        self:loadState(resolvedState(self.profiles:resolve(context)))
        self.editBaseline = self:getState()
        self.profileChanged = true
        self.history = History.new(80)
        self.history:checkpoint(self.savedState)
        self:status("Profile activated in this session. Save to persist the active profile.")
    elseif action == "cancel" then
        if self.previewState then
            local previous, suspended = self.previewState, self.previewSuspended
            self.profiles:cancelPreview()
            self.previewState, self.previewSuspended = nil, nil
            self.draftPreview = nil
            self.profiles:suspend(false)
            self:loadState(previous, true)
            self.profiles:suspend(suspended or false)
            if suspended then self.transform:restore() end
            self:status("Preview cancelled; previous layout restored.")
        end
    elseif action == "create" or action == "duplicate" then
        if self.previewState then return self:status("Apply or cancel the preview before managing profiles.") end
        local profile, err
        if action == "create" then profile, err = self.profiles:create(idOrName, extra or "place")
        else profile, err = self.profiles:duplicate(idOrName, extra) end
        if not profile then return self:status(err or "Could not create profile.") end
        self.profileChanged = true
        self:status("Created " .. profile.name .. ". Select Preview to activate; Save persists profile changes.")
    elseif action == "rename" or action == "delete" then
        if self.previewState then return self:status("Cancel the preview before managing profiles.") end
        local deletingActive = action == "delete" and self.profiles:isActive(idOrName, context)
        if deletingActive and not Util.equal(self.editBaseline, self:getState()) then
            return self:status("Save or discard your pending layout edits before deleting an active profile.")
        end
        local ok, err
        if action == "rename" then ok, err = self.profiles:rename(idOrName, extra)
        else ok, err = self.profiles:delete(idOrName, extra == true) end
        if not ok then return self:status(err or "Profile change failed.") end
        if deletingActive then
            -- Do not save the deleted layer's live properties into its less-specific fallback.
            local state = resolvedState(Config.resolve(self.profiles.data, context))
            self:loadState(state)
            if self.profiles.suspended then self.suspendedState = Util.copy(state) end
            self.editBaseline = self:getState()
            self.history = History.new(80)
            self.history:checkpoint(self.savedState)
        end
        self.profileChanged = true
        self:status("Profile " .. action .. " completed in memory; Save persists this change." .. (deletingActive and " The remaining scope defaults are now active; GUI elements were preserved." or ""))
    elseif action == "suspend" or action == "restore" then
        if self.previewState then self:profile("cancel") end
        local suspend = action == "restore" or idOrName ~= false
        if suspend and not self.profiles.suspended then
            self.suspendedState = self:getState()
            self.profiles:suspend(true)
            self.transform:restore()
            self:status("Profile suspended; original properties restored. Saved configurations are preserved.")
        elseif not suspend and self.profiles.suspended then
            self.profiles:suspend(false)
            self.transform.safe = false
            self:loadState(self.suspendedState or self:getState(), true)
            self.suspendedState = nil
            if self.editContext and not self.dirty and not self.profileChanged then self:_adoptContext() end
            self:status("Profile application resumed.")
        end
    elseif action == "recoverDraft" then
        if self.draftBlocked then return self:status(self.draftBlocked) end
        if not self.draft then return self:status("No draft is available for this place, device and orientation.") end
        if self.previewState then return self:status("Cancel the current preview first.") end
        self.previewState = self:getState()
        self.previewSuspended = self.profiles.suspended
        self.profiles:suspend(false)
        self.draftPreview = true
        self:loadState(self.draft, true)
        self:status("Unsaved draft preview. Apply restores the draft for editing; Cancel returns to the previous layout.")
    elseif action == "discardDraft" then
        local ok, message = self.storage:clearDraft(context)
        if ok then self.draft, self.draftBlocked, self.recoveredDraft = nil, nil, nil end
        self:status(message or (ok and "Recovery draft discarded." or "Could not discard draft."))
    end
    self:changed()
end
function App:export()
    local text, err = self.profiles:export()
    if not text then self:status(err or "Export failed."); return nil, err end
    local ok, message = self.storage:copy(text)
    self:status(message or (ok and "Export copied." or "Copy the JSON from the export panel."))
    return text
end
function App:import(text, overwriteConfirmed)
    if self.gesture then self:cancelGesture() end
    if self.finishingGesture or self.saving then return nil, "Wait for the current adjustment to finish." end
    if self.editContext then return nil, "Save or discard the previous orientation's edits before importing." end
    if self.previewState then return nil, "Apply or cancel the current preview first." end
    local before = self:getState()
    local layout, err = self.profiles:beginImport(text, overwriteConfirmed == true, self.context)
    if not layout then self:status(err or "Import validation failed."); return nil, err end
    self.previewState = before
    self.previewSuspended = self.profiles.suspended
    self.profiles:suspend(false)
    local preview = self.profiles.preview
    self:loadState({layout = layout, preferences = preview.preferences or {}, groups = preview.groups or {}}, true)
    self:status("Imported configuration preview. Apply activates it; Cancel preserves the previous configuration.")
    self:changed()
    return true
end
function App:_commitLayoutEdit(state, before, label, message)
    local job = {}
    self.finishingGesture = job
    local function complete(ok, reason)
        if self.finishingGesture ~= job then return end
        self.finishingGesture = nil
        if not self.alive then return end
        if ok then
            self:_setState(state, true)
            self.history:push(before, self:getState(), label)
            self:status(message)
        else self:status(reason or "The requested change could not be verified.") end
        self:_afterInteraction(ok, reason)
    end
    if not self.transform:applyHistory(before.layout, state.layout, complete) then
        complete(false, "Wait for the current adjustment to finish.")
    end
end
function App:approve(key, enabled)
    if self.previewState then return self:status("Apply or cancel the preview first.") end
    if self.profiles.suspended then return self:status("Resume the profile before changing permissions.") end
    if self.gesture or self.finishingGesture or self.saving then return end
    local record = self.discovery:get(key)
    if not record then return end
    if not record.experimental then return self:status("This target has no experimental editing option.") end
    if self.transform.safe then return self:status("Safe Mode disables experimental editing. Resume the profile to leave Safe Mode.") end
    local before = self:getState()
    local state = Util.copy(before)
    local entry = Util.copy((enabled and before.layout[key]) or record.baseline)
    entry.descriptor = Util.copy(record.descriptor)
    entry.experimental = enabled == true
    state.layout[key] = entry
    self:_commitLayoutEdit(state, before, "Experimental permission", enabled and "Experimental editing approved." or "Experimental permission removed. Original properties restored.")
end
function App:remap(oldKey, newKey)
    if self.previewState then return self:status("Apply or cancel the preview first.") end
    if self.profiles.suspended then return self:status("Resume the profile before remapping elements.") end
    if self.gesture or self.finishingGesture or self.saving then return end
    local old, target = self.layout[oldKey], self.discovery:get(newKey)
    if not old or not target then return self:status("Select an unmatched entry and an accessible replacement first.") end
    if not target.editable then return self:status(target.reason or "The selected replacement is unavailable for editing.") end
    if self.layout[newKey] then return self:status("Replacement already has saved settings. Choose another element.") end
    local before = self:getState()
    local state = Util.copy(before)
    local entry = Util.copy(old)
    entry.descriptor, entry.experimental = Util.copy(target.descriptor), false
    state.layout[oldKey], state.layout[newKey] = nil, entry
    for name, members in pairs(state.groups) do
        local remapped, seen = {}, {}
        for _, descriptor in ipairs(members) do
            local memberKey = Identity.key(descriptor)
            if memberKey == oldKey then descriptor, memberKey = Util.copy(target.descriptor), newKey end
            if not seen[memberKey] then
                remapped[#remapped + 1], seen[memberKey] = descriptor, true
            end
        end
        state.groups[name] = remapped
    end
    self:_commitLayoutEdit(state, before, "Remap missing element", "Remapped to the selected element. Save to persist.")
end
function App:setEditing(enabled)
    enabled = enabled == true
    if self.editing == enabled then return end
    if self.input then self.input:cancel() elseif self.gesture then self:cancelGesture() end
    self.editing = enabled
    if self.ui then self.ui:setVisible(enabled) end
end
function App:Open()
    if not self.alive then return end
    if not self.ui then
        local UI = require("UI")
        local Input = require("Input")
        local ok, result = pcall(function()
            self.ui = UI.new(self, self.playerGui, self.services)
            self.discovery.excluded = self.ui.gui
            self.input = Input.new(self, self.ui, self.services)
        end)
        if not ok then
            if self.input then self.input:destroy(); self.input = nil end
            if self.ui then self.ui:destroy(); self.ui = nil end
            self.discovery.excluded = nil
            self:log("Editor initialization failed: " .. tostring(result):sub(1, 160))
            warn("Heavenly Axis could not open. Use the session's :SafeMode() or :Destroy() method.")
            return false
        end
    end
    self:setEditing(true)
    return true
end
function App:Close() self:setEditing(false) end
function App:safeMode()
    if self.input then self.input:cancel() else self:cancelGesture() end
    if self.finishingGesture then
        self.finishingGesture, self.gestureSave, self.doneWaiting = nil, nil, nil
        self.transform:cancelTransaction()
    end
    if self.previewState then self:profile("cancel") end
    if not self.profiles.suspended then self.suspendedState = self:getState() end
    self.profiles:suspend(true)
    self.transform.safe = true
    self.transform:restore()
    self:Open()
    self:status("Safe Mode: original properties restored, profile suspended, experimental edits stopped. Saved profiles are preserved.")
    self:changed()
end
function App:SafeMode() return self:safeMode() end
function App:VerifyStartup()
    local profile = self.profiles:active(self:_currentEditContext())
    return {
        version = self.version, startedAt = self.startedAt, alive = self.alive,
        mode = self.profiles.suspended and "suspended" or (self.ui and "editor" or "loader"),
        profile = profile and profile.name or "none", storage = self.capabilities.storage.status,
        application = Util.copy(self.application or {}), unmatched = #(self.unmatched or {}),
        note = "This confirms this session only. Restart and invoke again to verify your environment's autoexecute setup.",
    }
end
function App:checkUpdates()
    if self.checkingUpdates then return end
    self.checkingUpdates = true
    self:status("Checking trusted GitHub release metadata in the background…")
    task.spawn(function()
        local ok, metadata = pcall(function()
            local url = "https://api.github.com/repos/zryr/Heavenly-Axis/releases/latest"
            if type(self.capabilities._get) ~= "function" then error("Network capability unavailable") end
            local body = self.capabilities._get(url)
            if type(body) ~= "string" or #body > 262144 then error("Invalid metadata size") end
            return self.services.HttpService:JSONDecode(body)
        end)
        if not self.alive then return end
        self.checkingUpdates = false
        if not ok or type(metadata) ~= "table" or type(metadata.tag_name) ~= "string" then
            self.capabilities.network.status = "Failed"
            self:status("Release metadata unavailable. Current version " .. self.version .. "; check github.com/zryr/Heavenly-Axis/releases manually.")
            return
        end
        self.capabilities.network.status = "Supported and verified"
        self.availableVersion = metadata.tag_name:sub(1, 80)
        self:status("Installed " .. self.version .. "; latest release " .. self.availableVersion .. ". Read releases and replace the local script manually; no code was downloaded or executed.")
        if self.ui then self.ui:refresh() end
    end)
end
function App:Destroy(restore)
    if not self.alive then return end
    self:cancelGesture()
    if self.finishingGesture then
        self.finishingGesture, self.gestureSave, self.doneWaiting = nil, nil, nil
        self.transform:cancelTransaction()
    end
    self:_invalidateDraftTimer()
    if self.dirty and self.capabilities.storage.status ~= "Unsupported" and not self.saving
        and not self.previewState and not self.draftBlocked and (not self.draft or self.recoveredDraft) then
        self:_writeDraft()
    end
    self.alive = false
    self.editing = false
    if self.input then self.input:destroy() end
    if self.ui then self.ui:destroy() end
    for _, connection in ipairs(self.connections) do pcall(function() connection:Disconnect() end) end
    if restore ~= false and self.transform then self.transform:restore() end
    if self.transform then self.transform:destroy() end
    if self.discovery then self.discovery:destroy() end
    if self.env.__HEAVENLY_AXIS_V3 == self then self.env.__HEAVENLY_AXIS_V3 = nil end
end
return App
