-- Heavenly Axis V3. Original project by Syshi; V2 inspired by Danechka.
local Util = require("Util")
local Geometry = require("Geometry")
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
App.VERSION = "3.0.0"
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
    local layout, prefs, groups = self.profiles:resolve()
    self.layout, self.groups = Util.copy(layout or {}), Util.copy(groups or {})
    for key, value in pairs(prefs or {}) do self.preferences[key] = value end
    self.discovery = Discovery.new(playerGui, nil, log)
    self.transform = Transform.new(self.discovery, log)
    if self.options.SafeMode then
        self.suspendedState = {layout = Util.copy(self.layout), groups = Util.copy(self.groups), preferences = Util.copy(self.preferences)}
        self.profiles:suspend(true)
        self.transform.safe = true
    end
    self.transform.onChanged = function()
        if not self.alive then return end
        for key, entry in pairs(self.transform:capture()) do self.layout[key] = entry end
        self:status("An unstable experimental transaction was rolled back. Repeated failures suspend that element.")
        self:changed()
    end
    self.discovery:start(function() self:_discoveryChanged() end)
    self:_applyLayout(self.layout, true)
    self.history:checkpoint(self:getState())
    self.savedProfilesData = Util.copy(self.profiles.data)
    self.savedState = self:getState()
    local draft, draftError = self.storage:loadDraft()
    if draftError then self:log(draftError) end
    if draft and draft.context and draft.context.place == self.context.place
        and draft.context.experience == self.context.experience
        and draft.context.device == self.context.device
        and draft.context.orientation == self.context.orientation then
        self.draft = draft
        self:log("A recoverable unsaved draft is available in Profiles; it has not been applied.")
    end
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
function App:_discoveryChanged()
    if not self.alive or self.discoveryPending then return end
    self.discoveryPending = true
    task.delay(0.12, function()
        self.discoveryPending = false
        if not self.alive then return end
        if not self.gesture then self:_applyLayout(self.layout, false, true) end
        local selected = {}
        for _, key in ipairs(self.selection) do
            local record = self.discovery:get(key)
            if record and exists(record.object) then selected[#selected + 1] = key end
        end
        self.selection = selected
        self.unmatched = self.transform:matches(self.layout)
        if self.ui then self.ui:refresh() end
    end)
end
function App:_watchViewport()
    local function resize()
        if not self.alive then return end
        if self.gesture then self:cancelGesture() end
        local w, h = viewport(self.services)
        local orientation = w >= h and "landscape" or "portrait"
        if orientation ~= self.context.orientation then
            local wasDirty = self.profileChanged or self.history:dirty(self:getState())
            self.context.orientation = orientation
            self.draft = self.storage:loadDraft()
            if not wasDirty and not self.previewState and not self.profiles.suspended then
                local layout, prefs, groups = self.profiles:resolve()
                local state = { layout = layout, preferences = Util.copy(defaults), groups = groups }
                for k, v in pairs(prefs or {}) do state.preferences[k] = v end
                self:loadState(state)
                self.history:checkpoint(self:getState())
                self.savedState = self:getState()
                self:log("Applied " .. orientation .. " profile precedence.")
            else
                self:log("Orientation changed; current draft retained. Apply a profile to load orientation overrides.")
            end
        end
        if self.ui then self.ui:refresh() end
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
    return { layout = layout, groups = Util.copy(self.groups), preferences = Util.copy(self.preferences) }
end
function App:loadState(state)
    self.layout = Util.copy(state.layout or {})
    self.groups = Util.copy(state.groups or {})
    self.preferences = Util.copy(defaults)
    for key, value in pairs(state.preferences or {}) do self.preferences[key] = value end
    self:_applyLayout(self.layout, true)
    self.unmatched = self.transform:matches(self.layout)
end
function App:_draftLater()
    if self.previewState or self.profiles.suspended or (self.draft and not self.recoveredDraft) then return end
    self.draftGeneration = (self.draftGeneration or 0) + 1
    local generation = self.draftGeneration
    task.delay(1, function()
        if not self.alive or generation ~= self.draftGeneration or self.gesture or not self.dirty then return end
        local state = self:getState()
        state.context = Util.copy(self.context)
        local ok, message = self.storage:draft(state)
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
function App:select(key, toggle)
    if not key then return self:clearSelection() end
    local record = self.discovery:get(key)
    if not record then return self:status("Element no longer available. Use the list to select another.") end
    if toggle or self.preferences.multiSelect then
        local selected = Util.copy(self.selection)
        for index, old in ipairs(selected) do
            if old == key then table.remove(selected, index); self.selection = selected; self:changed(); return end
        end
        selected[#selected + 1] = key
        self.selection = selected
    else self.selection = {key} end
    if not record.editable then self:status(record.reason or "Unsupported element.") end
    self:changed()
end
function App:selectMany(keys)
    self.selection = {}
    local seen = {}
    for _, key in ipairs(keys) do
        if not seen[key] and self.discovery:get(key) then self.selection[#self.selection + 1] = key; seen[key] = true end
    end
    self:changed()
end
function App:clearSelection() self.selection = {}; self:changed() end
function App:getRects() return self.transform:selectionRects(self.selection) end
function App:currentBounds()
    local rects = self:getRects()
    return Geometry.bounds(rects)
end
function App:beginGesture(label)
    if self.previewState then self:status("Apply or cancel the profile preview before editing."); return false end
    if self.profiles.suspended then self:status("Profiles are suspended. Resume application before editing."); return false end
    if self.gesture then return false end
    self.gesture = { before = self:getState(), label = label or "Transform" }
    if self.transform.beginTransaction then self.transform:beginTransaction() end
    return true
end
function App:updateGesture(rects, keys)
    if not self.gesture then return false end
    local ok, reason = self.transform:setRects(keys or self.selection, rects)
    if not ok then self:status(reason or "Transformation is unsupported."); return false end
    if self.ui then self.ui:updateSelection() end
    return true
end
function App:endGesture()
    if not self.gesture then return end
    local gesture = self.gesture
    self.gesture = nil
    if self.transform.endTransaction then self.transform:endTransaction() end
    local after = self:getState()
    self.layout = Util.copy(after.layout)
    self.history:push(gesture.before, after, gesture.label)
    self:changed()
    local bounds = self:currentBounds()
    if bounds then
        local w, h = viewport(self.services)
        if bounds.x < 0 or bounds.y < 0 or bounds.x + bounds.w > w or bounds.y + bounds.h > h then
            self:status("Selection extends offscreen. Recover brings it back into view.")
        end
    end
end
function App:cancelGesture()
    if not self.gesture then return end
    local state = self.gesture.before
    self.gesture = nil
    if self.transform.cancelTransaction then self.transform:cancelTransaction() end
    self:loadState(state)
    self:changed()
end
function App:_rectAction(label, callback)
    local rects, keys = self:getRects()
    if #keys == 0 then return self:status("Select an editable element first.") end
    if not self:beginGesture(label) then return end
    local ok, result = pcall(callback, rects)
    if ok and result then self:updateGesture(result, keys)
    else self:status("Invalid transformation; layout retained.") end
    self:endGesture()
end
function App:move(dx, dy)
    if not Util.finite(dx) or not Util.finite(dy) then return end
    self:_rectAction("Move", function(rects)
        local moved = {}
        for index, rect in ipairs(rects) do moved[index] = Geometry.translate(rect, dx, dy) end
        return moved
    end)
end
function App:resize(width, height)
    if not Util.finite(width) or not Util.finite(height) or width < 16 or height < 16 or width > 100000 or height > 100000 then
        return self:status("Width and height must be finite values between 16 and 100000 pixels.")
    end
    self:_rectAction("Resize", function(rects)
        local bounds = Geometry.bounds(rects)
        if self.preferences.equalSize then
            local changed = {}
            for i, rect in ipairs(rects) do changed[i] = {x = rect.x, y = rect.y, w = width, h = height} end
            return changed
        end
        return Geometry.scale(rects, {x = bounds.x, y = bounds.y, w = width, h = height}, self.preferences.centerScale)
    end)
end
function App:scale(factor)
    if not Util.finite(factor) or factor <= 0 or factor > 100 then return self:status("Invalid scale.") end
    local bounds = self:currentBounds()
    if not bounds then return end
    self:resize(math.max(16, bounds.w * factor), math.max(16, bounds.h * factor))
end
function App:geometry(mode, value)
    if mode == "position" then
        local bounds = self:currentBounds()
        if bounds and type(value) == "table" and Util.finite(value.x) and Util.finite(value.y) then
            self:move(value.x - bounds.x, value.y - bounds.y)
        end
    elseif mode == "rotation" or mode == "transparency" then
        if not Util.finite(value) then return self:status("Enter a finite number.") end
        if mode == "rotation" and (value < -360 or value > 360) then return self:status("Rotation range: -360 to 360.") end
        if mode == "transparency" and (value < 0 or value > 1) then return self:status("Transparency range: 0 to 1.") end
        if not self:beginGesture(mode) then return end
        local layout = self:getState().layout
        for _, key in ipairs(self.selection) do
            local record = self.discovery:get(key)
            if record and record.editable then
                local entry = layout[key] or Util.copy(record.baseline)
                entry.descriptor = Util.copy(record.descriptor)
                entry[mode] = value
                layout[key] = entry
            end
        end
        self.layout = layout
        self:_applyLayout(layout, false)
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
    self.transform:restore(self.selection)
    for _, key in ipairs(self.selection) do
        local record = self.discovery:get(key)
        if record then
            local entry = Util.copy(record.baseline)
            entry.descriptor = Util.copy(record.descriptor)
            self.layout[key] = entry
        end
    end
    self:endGesture()
end
function App:recover()
    self:_rectAction("Recover offscreen selection", function(rects)
        local bounds = Geometry.bounds(rects)
        local w, h = viewport(self.services)
        local insetA, insetB = self.services.GuiService:GetGuiInset()
        local left, top = insetA.X, insetA.Y
        local right, bottom = w - insetB.X, h - insetB.Y
        local dx = math.max(left, math.min(bounds.x, right - bounds.w)) - bounds.x
        local dy = math.max(top, math.min(bounds.y, bottom - bounds.h)) - bounds.y
        local changed = {}
        for i, rect in ipairs(rects) do changed[i] = Geometry.translate(rect, dx, dy) end
        return changed
    end)
end
function App:undo()
    if self.previewState then return self:status("Apply or cancel the preview first.") end
    if self.profiles.suspended then return self:status("Resume the profile before undoing edits.") end
    if self.input then self.input:cancel() else self:cancelGesture() end
    local state, label = self.history:undo()
    if state then self:loadState(state); self:status("Undid " .. tostring(label)); self:changed() end
end
function App:redo()
    if self.previewState then return self:status("Apply or cancel the preview first.") end
    if self.profiles.suspended then return self:status("Resume the profile before redoing edits.") end
    if self.input then self.input:cancel() else self:cancelGesture() end
    local state, label = self.history:redo()
    if state then self:loadState(state); self:status("Redid " .. tostring(label)); self:changed() end
end
function App:save()
    if self.previewState then return self:status("Apply or cancel the preview before saving.") end
    if self.profiles.suspended then return self:status("Resume the profile before saving. Safe Mode preserves saved configurations.") end
    self:endGesture()
    if self.input then self.input:cancel() end
    -- Do not persist a property write before its bounded stabilization observation.
    -- A later rollback must remain unsaved rather than being presented as a durable success.
    if self.transform.pendingStabilization then
        if self.saveWaiting then return false, "Save is waiting for layout stabilization." end
        local requested = self:getState()
        self.saveWaiting = true
        self:status("Waiting for the layout stability check before saving…")
        task.delay(0.35, function()
            self.saveWaiting = nil
            if not self.alive then return end
            if self.transform.pendingStabilization or not Util.equal(requested, self:getState()) then
                self:status("Layout changed during the stability check. Review it, then Save again; stored data was preserved.")
            elseif not self.previewState and not self.profiles.suspended then self:save() end
        end)
        return false, "Save is waiting for layout stabilization."
    end
    local state = self:getState()
    local ok, message, accepted = self.profiles:save(state.layout, state.groups, state.preferences)
    if ok or (accepted and self.capabilities.storage.status == "Unsupported") then
        self.history:checkpoint(state)
        self.profileChanged = false
        self.savedProfilesData = Util.copy(self.profiles.data)
        self.savedState = Util.copy(state)
        self.draftGeneration = (self.draftGeneration or 0) + 1
        if not self.draft or self.recoveredDraft then
            self.storage:clearDraft()
            self.draft, self.recoveredDraft = nil, nil
        end
    end
    self:status(message or (ok and "Profile persisted." or "Save failed; draft retained."))
    self:changed()
    return ok, message
end
function App:cancel()
    if self.previewState then return self:profile("cancel") end
    if self.input then self.input:cancel() else self:cancelGesture() end
    if self.profiles.suspended then return self:status("Profile is suspended. Resume it before returning to the Save checkpoint.") end
    local state = self.history:cancel()
    self.profiles.data = Util.copy(self.savedProfilesData)
    self.profileChanged = false
    if state then self:loadState(state) end
    self.draftGeneration = (self.draftGeneration or 0) + 1
    if not self.draft or self.recoveredDraft then
        self.storage:clearDraft()
        self.draft, self.recoveredDraft = nil, nil
    end
    self:status("Returned to the latest Save checkpoint. Session history was cleared.")
    self:changed()
end
function App:setPreference(name, value)
    if defaults[name] == nil then return end
    if self.previewState then return self:status("Apply or cancel the preview before changing preferences.") end
    if self.profiles.suspended then return self:status("Resume the profile before changing preferences.") end
    if type(value) ~= type(defaults[name]) then return self:status("Invalid preference value.") end
    if name == "shortcut" then
        local valid, key = pcall(function() return Enum.KeyCode[value] end)
        if not valid or not key or key == Enum.KeyCode.Unknown then return self:status("Use a Roblox key name such as F8.") end
    end
    if name == "step" and (not Util.finite(value) or value < 1 or value > 64) then return end
    if name == "gridSize" and (not Util.finite(value) or value < 4 or value > 128) then return end
    if name == "snapThreshold" and (not Util.finite(value) or value < 1 or value > 32) then return end
    if (name == "launcherX" or name == "launcherY") and (not Util.finite(value) or value < 0 or value > 1) then return end
    local before = self:getState()
    self.preferences[name] = value
    self.history:push(before, self:getState(), "Editor preference")
    self:changed()
end
function App:group(action, name, extra)
    if self.previewState then return self:status("Apply or cancel the preview first.") end
    if action ~= "select" and self.profiles.suspended then return self:status("Resume the profile before editing groups.") end
    if action == "select" then
        local keys = {}
        for _, descriptor in ipairs(self.groups[name] or {}) do
            local key = Identity.key(descriptor)
            if self.discovery:get(key) then keys[#keys + 1] = key end
        end
        self:selectMany(keys)
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
    if action == "preview" then
        if self.previewState then self:profile("cancel") end
        local before = self:getState()
        local layout, err, prefs, groups = self.profiles:beginPreview(idOrName)
        if not layout then return self:status(err or "Profile preview failed.") end
        self.previewState = before
        self.previewSuspended = self.profiles.suspended
        self.profiles:suspend(false)
        self:loadState({ layout = layout, preferences = prefs or self.profiles.preview.preferences or {}, groups = groups or self.profiles.preview.groups or {} })
        self:status("Preview only: more-specific profiles for this context are inactive; their definitions are preserved. Apply switches profile and replaces the draft; Cancel restores it.")
    elseif action == "apply" then
        if not self.previewState then return self:status("Preview a profile or imported configuration first.") end
        if self.draftPreview then
            local state = self:getState()
            local previous = self.previewState
            self.previewState, self.draftPreview = nil, nil
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
        self.previewState = nil
        self.suspendedState = nil
        self.transform.safe = false
        self:_applyLayout(self.layout, true)
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
            self:loadState(previous)
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
        local current = self.profiles:active()
        local deletingActive = action == "delete" and current and current.id == idOrName
        local ok, err
        if action == "rename" then ok, err = self.profiles:rename(idOrName, extra)
        else ok, err = self.profiles:delete(idOrName, extra == true) end
        if not ok then return self:status(err or "Profile change failed.") end
        if deletingActive then
            -- Do not save the deleted layer's live properties into its less-specific fallback.
            local layout, prefs, groups = Config.resolve(self.profiles.data, self.context)
            local state = {layout = layout, preferences = Util.copy(defaults), groups = groups}
            for key, value in pairs(prefs or {}) do state.preferences[key] = value end
            self:loadState(state)
            if self.profiles.suspended then self.suspendedState = Util.copy(state) end
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
            self:loadState(self.suspendedState or self:getState())
            self.suspendedState = nil
            self:status("Profile application resumed.")
        end
    elseif action == "recoverDraft" then
        if not self.draft then return self:status("No draft is available for this place, device and orientation.") end
        if self.previewState then return self:status("Cancel the current preview first.") end
        self.previewState = self:getState()
        self.previewSuspended = self.profiles.suspended
        self.profiles:suspend(false)
        self.draftPreview = true
        self:loadState(self.draft)
        self:status("Unsaved draft preview. Apply restores the draft for editing; Cancel returns to the previous layout.")
    elseif action == "discardDraft" then
        local ok, message = self.storage:clearDraft()
        if ok then self.draft = nil end
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
    if self.previewState then return nil, "Apply or cancel the current preview first." end
    local before = self:getState()
    local layout, err = self.profiles:beginImport(text, overwriteConfirmed == true)
    if not layout then self:status(err or "Import validation failed."); return nil, err end
    self.previewState = before
    self.previewSuspended = self.profiles.suspended
    self.profiles:suspend(false)
    local preview = self.profiles.preview
    self:loadState({layout = layout, preferences = preview.preferences or {}, groups = preview.groups or {}})
    self:status("Imported configuration preview. Apply activates it; Cancel preserves the previous configuration.")
    self:changed()
    return true
end
function App:approve(key, enabled)
    if self.previewState then return self:status("Apply or cancel the preview first.") end
    local record = self.discovery:get(key)
    if not record then return end
    if not self.discovery.approve then return self:status("Experimental edits are unsupported for this target.") end
    if self.transform.safe then return self:status("Safe Mode disables experimental editing. Resume the profile to leave Safe Mode.") end
    local before = self:getState()
    local ok, reason = self.discovery:approve(key, enabled)
    if ok == false then return self:status(reason or "This target cannot be safely overridden.") end
    local entry = Util.copy(before.layout[key] or record.baseline)
    entry.descriptor = Util.copy(record.descriptor)
    entry.experimental = enabled == true
    self.layout[key] = entry
    self:_applyLayout(self.layout, false)
    self.history:push(before, self:getState(), "Experimental permission")
    self:status(enabled and "Experimental editing approved for this element. Attempts are bounded; unstable changes are suspended." or "Experimental permission removed; original properties restored for this element.")
    if not enabled then self.transform:restore({key}) end
    self:changed()
end
function App:remap(oldKey, newKey)
    if self.previewState then return self:status("Apply or cancel the preview first.") end
    if self.profiles.suspended then return self:status("Resume the profile before remapping elements.") end
    local old, target = self.layout[oldKey], self.discovery:get(newKey)
    if not old or not target then return self:status("Select an unmatched entry and an accessible replacement first.") end
    if self.layout[newKey] and oldKey ~= newKey then return self:status("Replacement already has saved settings. Reset or choose another element.") end
    local before = self:getState()
    local entry = Util.copy(old)
    entry.descriptor, entry.experimental = Util.copy(target.descriptor), false
    self.layout[oldKey], self.layout[newKey] = nil, entry
    for _, members in pairs(self.groups) do
        for index, descriptor in ipairs(members) do
            if Identity.key(descriptor) == oldKey then members[index] = Util.copy(target.descriptor) end
        end
    end
    self:_applyLayout(self.layout, true)
    self.history:push(before, self:getState(), "Remap missing element")
    self:status("Saved identity explicitly remapped. Save to persist.")
    self:changed()
end
function App:setEditing(enabled)
    if self.input then self.input:cancel() elseif self.gesture then self:cancelGesture() end
    self.editing = enabled == true
    if self.ui then self.ui:setVisible(self.editing); self.ui:refresh() end
    if self.editing then
        self:status("Editing intercepts canvas gestures. Game scripts may still observe input; test controls after closing.")
    end
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
            for _, child in ipairs(self.playerGui:GetChildren()) do
                if child.Name == "HeavenlyAxis" and child:IsA("ScreenGui") then child:Destroy() end
            end
            self:log("Editor initialization failed: " .. tostring(result):sub(1, 160))
            warn("Heavenly Axis: editor could not open. Use __HEAVENLY_AXIS_V3.SafeMode() or Destroy().")
            return false
        end
    end
    self.preferences.launcherHidden = false
    self:setEditing(true)
    return true
end
function App:Close() self:setEditing(false) end
function App:safeMode()
    if self.input then self.input:cancel() else self:cancelGesture() end
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
    local profile = self.profiles:active()
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
    if self.dirty and not self.previewState and (not self.draft or self.recoveredDraft) then
        local state = self:getState()
        state.context = Util.copy(self.context)
        self.storage:draft(state)
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
