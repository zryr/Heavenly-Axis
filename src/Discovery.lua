-- Heavenly Axis V3. Original project by Syshi; V2 inspired by Danechka.
-- Discovery stays inside the local PlayerGui.
local Coordinates = require("Coordinates")
local Identity = require("Identity")
local Util = require("Util")

local Discovery = {}
Discovery.__index = Discovery
local EMPTY = {}
local MODIFIER_KIND = {
    UIScale = "scale", UIAspectRatioConstraint = "constraint", UISizeConstraint = "constraint",
    UIGridLayout = "layout", UIListLayout = "layout", UIPageLayout = "layout", UITableLayout = "layout",
}

local function isA(object, class)
    local ok, result = pcall(function() return object:IsA(class) end)
    return ok and result
end

local function children(object)
    local ok, result = pcall(function() return object:GetChildren() end)
    return ok and result or {}
end

local function disconnectAll(connections)
    for _, connection in ipairs(connections or {}) do
        pcall(function() connection:Disconnect() end)
    end
end

local function rotated(rotation)
    return math.abs((rotation + 180) % 360 - 180) > 0.001
end

local function enumIs(value, name)
    return tostring(value):match("[^%.]+$") == name
end

local function siblingName(object)
    return object.ClassName .. ":" .. object.Name
end

function Discovery.serialize(object)
    local ok, result = pcall(function()
        local position, size = object.Position, object.Size
        return {
            position = {xs = position.X.Scale, xo = position.X.Offset, ys = position.Y.Scale, yo = position.Y.Offset},
            size = {xs = size.X.Scale, xo = size.X.Offset, ys = size.Y.Scale, yo = size.Y.Offset},
            rotation = object.Rotation,
            transparency = object.BackgroundTransparency,
        }
    end)
    if ok then return result end
    return nil, "GUI properties are inaccessible"
end

function Discovery.new(playerGui, excludedGui, log, guiService)
    return setmetatable({
        root = playerGui, excluded = excludedGui, guiService = guiService,
        records = {}, ordered = {}, byObject = {}, metadata = {}, siblingOrder = {}, containerNames = {}, containerSiblings = {},
        connections = {}, objectConnections = {}, approved = {}, log = log or function() end,
        destroyed = false, queued = false, revision = 0, classificationRevision = 0,
        stats = {scans = 0, indexed = 0, lastScanMs = 0},
    }, Discovery)
end

function Discovery:_excluded(object)
    local current = object
    while current and current ~= self.root do
        if current == self.excluded or (isA(current, "ScreenGui") and current.Name:match("^HeavenlyAxis")) then
            return true
        end
        local ok, parent = pcall(function() return current.Parent end)
        current = ok and parent or nil
    end
    return false
end

function Discovery:_attached(record)
    local current = record.object
    for index = #record.descriptor.path, 1, -1 do
        local expected = record.descriptor.path[index]
        if not current or current.Name ~= expected.name or current.ClassName ~= expected.class then
            self:_schedule()
            return false
        end
        current = current.Parent
    end
    if current == self.root then return true end
    self:_schedule()
    return false
end

function Discovery:_visible(record, bounds)
    local object = record.object
    local current = object
    while current and current ~= self.root do
        if isA(current, "GuiObject") and not current.Visible then return false end
        if isA(current, "ScreenGui") and not current.Enabled then return false end
        if isA(current, "CanvasGroup") and current.GroupTransparency >= 1 then return false end
        current = current.Parent
    end
    if current ~= self.root then return false end
    if not bounds and record.baselineRect then
        local size = object.AbsoluteSize
        return size ~= nil and size.X > 0 and size.Y > 0
    end
    bounds = bounds or Coordinates.rect(object)
    if not bounds or bounds.w <= 0 or bounds.h <= 0 then return false end
    if not record.baselineRect then record.baselineRect = bounds end
    return true, bounds
end

function Discovery:_metadata(object, childCache)
    local result = self.metadata[object]
    if result then return result end
    result = {scales = {}}
    local list = childCache and childCache[object] or children(object)
    if childCache then childCache[object] = list end
    for _, child in ipairs(list) do
        if isA(child, "GuiObject") then
            result.hasGuiChild = true
        else
            local kind = MODIFIER_KIND[child.ClassName]
            if kind then
                result.modifiers = result.modifiers or {}
                result.modifiers[child] = kind
                if kind == "scale" then result.scales[#result.scales + 1] = child
                else result[kind] = true end
            end
        end
    end
    self.metadata[object] = result
    return result
end

function Discovery:_classify(record, childCache)
    local object = record.object
    record.editable, record.reason, record.experimental = true, nil, false
    record.classificationRevision = self.classificationRevision
    record.experimentalApproved = self.approved[record.key] == true
    if record.descriptor.ambiguous then
        record.editable = false
        record.reason = "Ambiguous same-name hierarchy; rename the HUD object or remap to a unique object"
        return
    end
    local current = object
    while current and current ~= self.root do
        if isA(current, "GuiObject") then
            local ok, rotation = pcall(function() return current.Rotation end)
            if not ok or not Util.finite(rotation) then
                record.editable, record.reason = false, "Inaccessible GUI properties"
                return
            end
            if current ~= object and rotated(rotation) then
                record.editable, record.reason = false, "Rotated ancestor: screen-space transformation is unsupported"
                return
            end
            local scales = self:_metadata(current, childCache).scales
            if #scales > 1 then
                record.editable, record.reason = false, "Multiple UIScale objects on one ancestor are unsupported"
                return
            end
            if scales[1] then
                local value = scales[1].Scale
                if not Util.finite(value) or value <= 0 then
                    record.editable, record.reason = false, "Invalid or zero UIScale"
                    return
                end
            end
        end
        current = current.Parent
    end
    if current ~= self.root then
        record.editable, record.reason = false, "Element is no longer in PlayerGui"
        return
    end
    local auto = tostring(object.AutomaticSize)
    if auto ~= "Enum.AutomaticSize.None" and auto ~= "None" and auto ~= "nil" then
        record.experimental, record.reason = true, "AutomaticSize may overwrite dimensions; explicit experimental approval required"
    end
    if self:_metadata(object, childCache).constraint then
        record.experimental, record.reason = true, "Size constraint may override resizing; explicit experimental approval required"
    end
    if object.Parent and self:_metadata(object.Parent, childCache).layout then
        record.experimental, record.reason = true, "Parent layout controls position/size; explicit experimental approval required"
    end
    if record.managedByScript then
        record.experimental, record.reason = true, "Game script replaced an edit; explicit experimental approval required"
    end
    if record.experimental then
        record.editable = record.experimentalApproved and not record.experimentalSuspended
        if record.experimentalSuspended then
            record.reason = "Experimental override suspended after three failed attempts; disable/reapprove to retry"
        end
    end
end

function Discovery:_notify(reason)
    if self.destroyed then return end
    self.revision = self.revision + 1
    if self.onChanged then
        local ok, err = pcall(self.onChanged, reason)
        if not ok then self.log("Discovery callback failed: " .. tostring(err):sub(1, 180)) end
    end
end

function Discovery:_schedule()
    if self.destroyed or self.queued then return end
    self.queued = true
    local function run()
        if self.destroyed then return end
        self.queued = false
        self:refresh()
    end
    if task and task.delay then task.delay(0.08, run) else run() end
end

function Discovery:_presentation(reclassify)
    if self.destroyed or self.queued then return end
    self.classificationPending = self.classificationPending or reclassify
    if self.presentationQueued then return end
    self.presentationQueued = true
    local function run()
        self.presentationQueued = false
        local reclassifyPending = self.classificationPending
        self.classificationPending = nil
        if not self.destroyed and not self.queued then
            if reclassifyPending then self.classificationRevision = self.classificationRevision + 1 end
            self:_notify("presentation")
        end
    end
    if task and task.delay then task.delay(0.04, run) else run() end
end

function Discovery:_watch(object, childCache, modifier)
    local connections = self.objectConnections[object]
    local new = not connections
    if new then
        connections = {}
        self.objectConnections[object] = connections
    end
    local function watch(name, callback)
        local ok, signal = pcall(function() return object:GetPropertyChangedSignal(name) end)
        if ok and signal then connections[#connections + 1] = signal:Connect(callback) end
    end
    if modifier then
        if not new then return end
        connections.modifierParent = object.Parent
        watch("Parent", function()
            -- Reparenting inside PlayerGui can change the modifier without a root descendant event.
            local previous, parent = connections.modifierParent, object.Parent
            if previous then self.metadata[previous] = nil end
            if parent then self.metadata[parent] = nil end
            connections.modifierParent = parent
            self:_presentation(true)
        end)
        if modifier == "scale" then
            local valid = Util.finite(object.Scale) and object.Scale > 0
            watch("Scale", function()
                local changed = Util.finite(object.Scale) and object.Scale > 0
                if changed ~= valid then self:_presentation(true) end
                valid = changed
            end)
        end
        return
    end
    local gui = isA(object, "GuiObject")
    if new then
        watch("Name", function() self:_schedule() end)
        if isA(object, "ScreenGui") then
            watch("Enabled", function() self:_presentation() end)
        elseif gui then
            watch("Visible", function() self:_presentation() end)
            watch("AutomaticSize", function() self:_presentation(true) end)
            if isA(object, "CanvasGroup") then watch("GroupTransparency", function() self:_presentation() end) end
        end
    end
    if gui and not connections.rotates and self:_metadata(object, childCache).hasGuiChild then
        connections.rotates = true
        local wasRotated = rotated(object.Rotation)
        watch("Rotation", function()
            local isRotated = rotated(object.Rotation)
            if isRotated ~= wasRotated then self:_presentation(true) end
            wasRotated = isRotated
        end)
    end
    return gui or object.ClassName == "ScreenGui"
end

local function enclosingScreen(object, root)
    local current = object.Parent
    while current and current ~= root do
        if isA(current, "ScreenGui") then return current end
        if isA(current, "LayerCollector") then return nil end
        current = current.Parent
    end
    return nil
end

function Discovery:refresh()
    if self.destroyed then return end
    local startedAt = os.clock()
    local ok, descendants = pcall(function() return self.root:GetDescendants() end)
    if not ok then self.log("PlayerGui discovery unavailable") return end
    local old, indexed, byObject, ordered, watched = self.byObject, {}, {}, {}, {}
    local childCache, siblingCache, containerNames, containerSiblings = {}, {}, {}, {}
    self.metadata = {}
    self.classificationRevision = self.classificationRevision + 1
    for _, object in ipairs(descendants) do
        if isA(object, "GuiObject") and not self:_excluded(object) then
            local screen = enclosingScreen(object, self.root)
            local success, descriptor
            if screen then success, descriptor = pcall(Identity.descriptor, object, self.root, childCache, siblingCache) end
            if success and descriptor then
                local key = Identity.key(descriptor)
                local record = old[object]
                if not record then
                    local baseline = Discovery.serialize(object)
                    if baseline then record = {object = object, baseline = baseline, failures = 0} end
                end
                if record then
                    record.key, record.descriptor, record.builtin, record.screen = key, descriptor, descriptor.builtin, screen
                    record.interactive = isA(object, "GuiButton") or isA(object, "TextBox")
                    record.functionalStatus = record.builtin and "Visual geometry only. Functional touch region unverified." or nil
                    record.visible = self:_visible(record)
                    self:_classify(record, childCache)
                    if not indexed[key] then
                        indexed[key] = record
                        ordered[#ordered + 1] = record
                    else
                        record.editable, record.reason = false, "Ambiguous GUI identity"
                        indexed[key].editable, indexed[key].reason = false, "Ambiguous GUI identity"
                    end
                    byObject[object] = record
                    local current = object
                    while current and current ~= self.root and not watched[current] do
                        watched[current] = true
                        if not self:_watch(current, childCache) then
                            local names = containerNames[current.Parent] or {}
                            names[siblingName(current)] = true
                            containerNames[current.Parent] = names
                        end
                        for modifier, kind in pairs(self:_metadata(current, childCache).modifiers or EMPTY) do
                            watched[modifier] = true
                            self:_watch(modifier, nil, kind)
                        end
                        current = current.Parent
                    end
                end
            end
        end
    end
    for object, connections in pairs(self.objectConnections) do
        if not watched[object] then
            disconnectAll(connections)
            self.objectConnections[object] = nil
        end
    end
    for parent, names in pairs(containerNames) do
        for sibling in pairs(siblingCache[parent] or EMPTY) do
            if names[siblingName(sibling)] then containerSiblings[sibling] = true end
        end
    end
    table.sort(ordered, function(a, b) return a.key < b.key end)
    self.records, self.byObject, self.ordered, self.siblingOrder = indexed, byObject, ordered, siblingCache
    self.containerNames, self.containerSiblings = containerNames, containerSiblings
    self.stats.scans = self.stats.scans + 1
    self.stats.indexed, self.stats.lastScanMs = #ordered, (os.clock() - startedAt) * 1000
    self:_notify("structure")
end

function Discovery:start(onChanged)
    if self.started or self.destroyed then return end
    self.started, self.onChanged = true, onChanged
    self.connections[#self.connections + 1] = self.root.DescendantAdded:Connect(function(object)
        local modifier = MODIFIER_KIND[object.ClassName]
        local parent = object.Parent
        local container = self.containerNames[parent]
        local identityMayChange = object.ClassName == "ScreenGui" or container and container[siblingName(object)]
        if not identityMayChange and (not modifier and not isA(object, "GuiObject") or not enclosingScreen(object, self.root)) then return end
        if self:_excluded(object) then return end
        if parent then self.metadata[parent] = nil end
        if modifier then
            self:_watch(object, nil, modifier)
            self:_presentation(true)
        else self:_schedule() end
    end)
    self.connections[#self.connections + 1] = self.root.DescendantRemoving:Connect(function(object)
        local modifier = MODIFIER_KIND[object.ClassName]
        local connections = self.objectConnections[object]
        local record = self.byObject[object]
        if not connections and not record and not self.containerSiblings[object] and object.ClassName ~= "ScreenGui" then return end
        if not connections and self:_excluded(object) then return end
        local parent = object.Parent
        if parent then self.metadata[parent] = nil end
        if modifier and connections and connections.modifierParent then self.metadata[connections.modifierParent] = nil end
        if record then
            if self.records[record.key] == record then self.records[record.key] = nil end
            self.byObject[object] = nil
        end
        disconnectAll(connections)
        self.objectConnections[object] = nil
        if modifier then self:_presentation(true) else self:_schedule() end
    end)
    self.log("Discovery limited to accessible on-screen PlayerGui objects")
    self:refresh()
end

function Discovery:get(key)
    local record = self.records[key]
    if not record or not self:_attached(record) then return nil end
    if not record.baselineRect then record.visible = self:_visible(record) end
    if record.classificationRevision ~= self.classificationRevision then self:_classify(record) end
    return record
end

function Discovery:match(descriptor)
    if type(descriptor) ~= "table" or descriptor.ambiguous or type(descriptor.path) ~= "table" then return nil end
    local ok, key = pcall(Identity.key, descriptor)
    local record = ok and self:get(key) or nil
    if record and Identity.same(descriptor, record.descriptor) then return record end
    return nil
end

function Discovery:list()
    local result = {}
    for _, record in ipairs(self.ordered) do
        if self.byObject[record.object] then
            record.visible = self:_attached(record) and self:_visible(record)
            if record.visible then
                if record.classificationRevision ~= self.classificationRevision then self:_classify(record) end
                result[#result + 1] = record
            end
        end
    end
    return result
end

local function rotation(object)
    return object.AbsoluteRotation or object.Rotation or 0
end

local function visualBounds(bounds, angle)
    if not rotated(angle) then return bounds end
    local radians = math.rad(angle)
    local sin, cos = math.abs(math.sin(radians)), math.abs(math.cos(radians))
    local w, h = bounds.w * cos + bounds.h * sin, bounds.w * sin + bounds.h * cos
    return {x = bounds.x + (bounds.w - w) / 2, y = bounds.y + (bounds.h - h) / 2, w = w, h = h}
end

local function containsRotated(bounds, angle, x, y)
    if not rotated(angle) then return Coordinates.contains(bounds, x, y) end
    local radians = math.rad(-angle)
    local sin, cos = math.sin(radians), math.cos(radians)
    local dx, dy = x - bounds.x - bounds.w / 2, y - bounds.y - bounds.h / 2
    return math.abs(dx * cos - dy * sin) <= bounds.w / 2 and math.abs(dx * sin + dy * cos) <= bounds.h / 2
end

local function scrollWindow(ancestor, bounds)
    local window = ancestor.AbsoluteWindowSize
    if not window then return bounds end
    local left = enumIs(ancestor.VerticalScrollBarPosition, "Left")
    return {
        x = bounds.x + (left and math.max(0, bounds.w - window.X) or 0), y = bounds.y,
        w = math.min(bounds.w, window.X), h = math.min(bounds.h, window.Y),
    }
end

local function clippingAncestor(ancestor)
    if isA(ancestor, "GuiObject") and ancestor.ClipsDescendants and not rotated(rotation(ancestor)) then
        local bounds = Coordinates.rect(ancestor)
        if bounds and isA(ancestor, "ScrollingFrame") then return scrollWindow(ancestor, bounds) end
        return bounds
    end
    return nil
end

function Discovery:_clip(record, bounds, deviceArea)
    if record.screen.ClipToDeviceSafeArea and not enumIs(record.screen.ScreenInsets, "None") then
        if not deviceArea and enumIs(record.screen.ScreenInsets, "DeviceSafeInsets") then
            deviceArea = Coordinates.rect(record.screen)
        end
        if deviceArea then bounds = Coordinates.intersection(bounds, deviceArea) end
    end
    local ancestor = record.object.Parent
    while bounds and ancestor and ancestor ~= record.screen do
        local clip = clippingAncestor(ancestor)
        if clip then bounds = Coordinates.intersection(bounds, clip) end
        ancestor = ancestor.Parent
    end
    return bounds
end

function Discovery:_deviceArea()
    return Coordinates.insetRect(self.guiService, Enum and Enum.ScreenInsets and Enum.ScreenInsets.DeviceSafeInsets)
end

function Discovery:visibleRect(record)
    if not record or not record.screen or not self:_attached(record) then return nil end
    local bounds = Coordinates.rect(record.object)
    if not bounds or not self:_visible(record, bounds) then return nil end
    return self:_clip(record, visualBounds(bounds, rotation(record.object)), self:_deviceArea())
end

local function structural(record, bounds, screenBounds, metadata)
    if record.object.Name == "TouchControlFrame" and record.screen.Name == "TouchGui" then return true end
    local container = isA(record.object, "Frame") or isA(record.object, "ScrollingFrame") or isA(record.object, "CanvasGroup")
    if not container then return false end
    local broad = screenBounds and bounds.w * bounds.h >= screenBounds.w * screenBounds.h * 0.4
    local transparent = record.object.BackgroundTransparency >= 0.95
    return (broad and (metadata.hasGuiChild or transparent)) or (metadata.hasGuiChild and transparent)
end

function Discovery:_drawPath(record)
    local path, current = {}, record.object
    while current and current ~= self.root do
        local parent = current.Parent
        local order = self.siblingOrder[parent]
        local sibling = order and order[current]
        local z = isA(current, "GuiObject") and current.ZIndex or 0
        table.insert(path, 1, {z = z, order = sibling and sibling.index or 0})
        current = parent
    end
    return path
end

local function frontmost(a, b)
    local ad, bd = a.record.screen.DisplayOrder, b.record.screen.DisplayOrder
    if ad ~= bd then return ad > bd end
    if a.record.screen == b.record.screen and enumIs(a.record.screen.ZIndexBehavior, "Global") then
        if a.record.object.ZIndex ~= b.record.object.ZIndex then return a.record.object.ZIndex > b.record.object.ZIndex end
    end
    for index = 1, math.min(#a.drawPath, #b.drawPath) do
        local left, right = a.drawPath[index], b.drawPath[index]
        if left.z ~= right.z then return left.z > right.z end
        if left.order ~= right.order then return left.order > right.order end
    end
    if #a.drawPath ~= #b.drawPath then return #a.drawPath > #b.drawPath end
    return a.record.key < b.record.key
end

function Discovery:hit(x, y)
    if not Util.finite(x) or not Util.finite(y) then return {}, false end
    local hitX, hitY = Coordinates.hitPoint(x, y)
    local ok, objects = pcall(function() return self.root:GetGuiObjectsAtPosition(hitX, hitY) end)
    local native = ok and type(objects) == "table"
    local candidates, seen, screenBounds = {}, {}, {}
    local deviceArea = self:_deviceArea()
    local function consider(record, index)
        if not record or seen[record] or not self.byObject[record.object] then return end
        seen[record] = true
        local bounds = Coordinates.rect(record.object)
        if not bounds or bounds.w <= 0 or bounds.h <= 0 then return end
        local angle = rotation(record.object)
        if not native and not containsRotated(bounds, angle, x, y) then return end
        if not self:_attached(record) or not self:_visible(record, bounds) then return end
        local clipped = self:_clip(record, visualBounds(bounds, angle), deviceArea)
        if not Coordinates.contains(clipped, native and hitX or x, native and hitY or y) then return end
        self:_classify(record)
        local area = screenBounds[record.screen]
        if not area then
            area = Coordinates.rect(record.screen)
            screenBounds[record.screen] = area
        end
        local metadata = self:_metadata(record.object)
        local broad = structural(record, clipped, area, metadata)
        local passive = record.builtin == "DynamicThumbstickFrame"
            or broad and record.object.BackgroundTransparency >= 0.95
        local priority
        if record.builtin == "DynamicThumbstickFrame" then priority = 5
        elseif record.builtin then priority = 1
        elseif record.interactive and not metadata.hasGuiChild then priority = 2
        elseif record.interactive then priority = 3
        elseif not broad then priority = 4
        else priority = 6 end
        if not record.editable then priority = priority + 6 end
        candidates[#candidates + 1] = {record = record, priority = priority, nativeIndex = index, passive = passive,
            drawPath = not native and self:_drawPath(record) or nil}
    end
    if native then
        for index, object in ipairs(objects) do consider(self.byObject[object], index) end
    else
        for _, record in ipairs(self.ordered) do consider(record) end
    end
    table.sort(candidates, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        if native then return a.nativeIndex < b.nativeIndex end
        return frontmost(a, b)
    end)
    local result, primary = {}, false
    for index, candidate in ipairs(candidates) do
        result[index] = candidate.record
        if not primary and not candidate.passive then primary = candidate.record end
    end
    -- Transparent gameplay containers remain available through explicit overlap selection.
    return result, primary
end

function Discovery:alignmentRects(keys, focusBounds, limit)
    local omitted, candidates, screenBounds = {}, {}, {}
    for _, key in ipairs(keys or {}) do omitted[key] = true end
    local deviceArea = self:_deviceArea()
    for _, record in ipairs(self.ordered) do
        if not omitted[record.key] and self.byObject[record.object] then
            local bounds = Coordinates.rect(record.object)
            if screenBounds[record.screen] == nil then screenBounds[record.screen] = Coordinates.rect(record.screen) or false end
            if bounds and self:_attached(record) and self:_visible(record, bounds)
                and not structural(record, bounds, screenBounds[record.screen], self:_metadata(record.object)) then
                local ancestor, relative = record.object, false
                while ancestor and ancestor ~= record.screen do
                    local indexed = self.byObject[ancestor]
                    if indexed and omitted[indexed.key] then relative = true break end
                    ancestor = ancestor.Parent
                end
                bounds = not relative and self:_clip(record, visualBounds(bounds, rotation(record.object)), deviceArea) or nil
                if bounds then
                    local dx, dy = 0, 0
                    if focusBounds then
                        dx = bounds.x + bounds.w / 2 - focusBounds.x - focusBounds.w / 2
                        dy = bounds.y + bounds.h / 2 - focusBounds.y - focusBounds.h / 2
                    end
                    candidates[#candidates + 1] = {bounds = bounds, distance = dx * dx + dy * dy, key = record.key}
                end
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.distance ~= b.distance then return a.distance < b.distance end
        return a.key < b.key
    end)
    local result = {}
    for index = 1, math.min(limit or 64, #candidates) do result[index] = candidates[index].bounds end
    return result
end

function Discovery:approve(key, enabled)
    local record = self:get(key)
    if not record then return false, "Element is missing" end
    self.approved[key] = enabled == true or nil
    record.experimentalSuspended, record.failures = false, 0
    self:_classify(record)
    self:_notify("presentation")
    return true, enabled and "Experimental override approved for this element" or "Experimental override disabled"
end

function Discovery:destroy()
    if self.destroyed then return end
    self.destroyed = true
    disconnectAll(self.connections)
    for _, connections in pairs(self.objectConnections) do disconnectAll(connections) end
    self.connections, self.objectConnections, self.records, self.byObject = {}, {}, {}, {}
    self.ordered, self.metadata, self.siblingOrder, self.containerNames, self.containerSiblings = {}, {}, {}, {}, {}
    self.onChanged = nil
end

return Discovery
