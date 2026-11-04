-- Heavenly Axis V3. Original project by Syshi; V2 inspired by Danechka.
-- Discovery deliberately stays inside the local PlayerGui. Protected CoreGui is never probed.
local Identity = require("Identity")
local Util = require("Util")

local Discovery = {}
Discovery.__index = Discovery

local function isA(object, class)
    local ok, result = pcall(function() return object:IsA(class) end)
    return ok and result
end

local function children(object)
    local ok, result = pcall(function() return object:GetChildren() end)
    return ok and result or {}
end

local function safeName(object)
    local ok, value = pcall(function() return object.Name end)
    return ok and value or "?"
end

local function disconnectAll(connections)
    for _, connection in ipairs(connections or {}) do
        pcall(function() connection:Disconnect() end)
    end
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

function Discovery.new(playerGui, excludedGui, log)
    return setmetatable({
        root = playerGui, excluded = excludedGui, records = {}, byObject = {},
        connections = {}, objectConnections = {}, approved = {}, log = log or function() end,
        destroyed = false, queued = false, revision = 0,
    }, Discovery)
end

function Discovery:_excluded(object)
    local current = object
    while current and current ~= self.root do
        if current == self.excluded then return true end
        -- Exclude our lazily constructed UI before App has received its ScreenGui reference.
        local name = safeName(current)
        if isA(current, "ScreenGui") and name:match("^HeavenlyAxis") then return true end
        local ok, parent = pcall(function() return current.Parent end)
        current = ok and parent or nil
    end
    return false
end

function Discovery:_visible(object)
    local current, foundRoot = object, false
    while current do
        if current == self.root then foundRoot = true break end
        local ok, visible = pcall(function()
            if isA(current, "GuiObject") then return current.Visible end
            if isA(current, "ScreenGui") then return current.Enabled end
            return true
        end)
        if not ok or not visible then return false end
        current = current.Parent
    end
    if not foundRoot then return false end
    local ok, size = pcall(function() return object.AbsoluteSize end)
    return ok and size.X > 0 and size.Y > 0
end

function Discovery:_classify(record)
    local object = record.object
    record.visible = self:_visible(object)
    record.editable, record.reason, record.experimental = true, nil, false
    record.experimentalApproved = self.approved[record.key] == true
    record.functionalStatus = record.builtin and "Available but unverified: visual properties only; functional touch region is not verified" or nil
    if record.descriptor.ambiguous then
        record.editable = false
        record.reason = "Ambiguous same-name hierarchy; rename the HUD object or remap to a unique object"
        return
    end
    local current = object
    while current and current ~= self.root do
        if isA(current, "GuiObject") then
            local ok, rotation = pcall(function() return current.Rotation end)
            if not ok then
                record.editable, record.reason = false, "Inaccessible GUI properties"
                return
            end
            if current ~= object and math.abs(rotation % 360) > 0.001 then
                record.editable, record.reason = false, "Rotated ancestor: screen-space transformation is unsupported"
                return
            end
            local scaleCount = 0
            for _, child in ipairs(children(current)) do
                if isA(child, "UIScale") then
                    scaleCount = scaleCount + 1
                    local scaleOK, scale = pcall(function() return child.Scale end)
                    if not scaleOK or not Util.finite(scale) or scale <= 0 then
                        record.editable, record.reason = false, "Invalid or zero UIScale"
                        return
                    end
                end
            end
            if scaleCount > 1 then
                record.editable, record.reason = false, "Multiple UIScale objects on one ancestor are unsupported"
                return
            end
        end
        current = current.Parent
    end
    local ok, auto = pcall(function() return object.AutomaticSize end)
    if ok and tostring(auto) ~= "Enum.AutomaticSize.None" and tostring(auto) ~= "None" then
        record.experimental, record.reason = true, "AutomaticSize may overwrite dimensions; explicit experimental approval required"
    end
    for _, child in ipairs(children(object)) do
        if isA(child, "UIAspectRatioConstraint") or isA(child, "UISizeConstraint") then
            record.experimental, record.reason = true, "Size constraint may override resizing; explicit experimental approval required"
        end
    end
    local parent = object.Parent
    for _, child in ipairs(children(parent)) do
        if isA(child, "UIGridStyleLayout") or isA(child, "UIListLayout") or isA(child, "UIGridLayout") or isA(child, "UITableLayout") or isA(child, "UIPageLayout") then
            record.experimental, record.reason = true, "Parent layout controls position/size; explicit experimental approval required"
        end
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

function Discovery:_notify()
    if self.destroyed then return end
    self.revision = self.revision + 1
    if self.onChanged then
        local ok, err = pcall(self.onChanged)
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

function Discovery:_watch(object)
    if self.objectConnections[object] then return end
    local connections = {}
    self.objectConnections[object] = connections
    local function connectProperty(name, callback)
        local ok, signal = pcall(function() return object:GetPropertyChangedSignal(name) end)
        if ok then connections[#connections + 1] = signal:Connect(callback) end
    end
    connectProperty("Name", function() self:_schedule() end)
    connectProperty("Visible", function()
        if self.destroyed then return end
        -- Visibility can reveal an entire subtree; reuse indexed records without a new tree scan.
        for _, record in pairs(self.records) do self:_classify(record) end
        self:_notify()
    end)
    connectProperty("AutomaticSize", function() self:_schedule() end)
    connectProperty("Rotation", function()
        if self.destroyed then return end
        for _, record in pairs(self.records) do self:_classify(record) end
        -- Do not notify application/layout restoration for property writes: that would fight editing.
    end)
end

function Discovery:refresh()
    if self.destroyed then return end
    local ok, descendants = pcall(function() return self.root:GetDescendants() end)
    if not ok then self.log("PlayerGui discovery unavailable") return end
    local old, indexed, byObject = self.byObject, {}, {}
    for _, object in ipairs(descendants) do
        if isA(object, "GuiObject") and not self:_excluded(object) then
            local success, descriptor = pcall(Identity.descriptor, object, self.root)
            if success and descriptor then
                local key = Identity.key(descriptor)
                local record = old[object]
                if not record then
                    local baseline = Discovery.serialize(object)
                    if baseline then
                        record = {object = object, baseline = baseline, failures = 0}
                        self:_watch(object)
                    end
                end
                if record then
                    record.key, record.descriptor, record.builtin = key, descriptor, descriptor.builtin
                    self:_classify(record)
                    if indexed[key] then
                        record.editable, record.reason = false, "Ambiguous GUI identity"
                        indexed[key].editable, indexed[key].reason = false, "Ambiguous GUI identity"
                    else indexed[key] = record end
                    byObject[object] = record
                end
            end
        end
    end
    for object in pairs(old) do
        if not byObject[object] then
            disconnectAll(self.objectConnections[object])
            self.objectConnections[object] = nil
        end
    end
    self.records, self.byObject = indexed, byObject
    self:_notify()
end

function Discovery:start(onChanged)
    if self.started or self.destroyed then return end
    self.started, self.onChanged = true, onChanged
    self.connections[#self.connections + 1] = self.root.DescendantAdded:Connect(function(object)
        if not self:_excluded(object) then self:_schedule() end
    end)
    self.connections[#self.connections + 1] = self.root.DescendantRemoving:Connect(function(object)
        if self:_excluded(object) then return end
        -- Drop destroyed references immediately; scan once after this structural event settles.
        local record = self.byObject[object]
        if record then
            self.records[record.key], self.byObject[object] = nil, nil
            disconnectAll(self.objectConnections[object])
            self.objectConnections[object] = nil
        end
        self:_schedule()
    end)
    self.log("Discovery limited to accessible PlayerGui; protected interfaces are excluded")
    self:refresh()
end

function Discovery:get(key)
    local record = self.records[key]
    if record and record.object.Parent then return record end
    return nil
end

function Discovery:list()
    local result = {}
    for _, record in pairs(self.records) do
        if record.object.Parent then
            record.visible = self:_visible(record.object)
            if record.visible then result[#result + 1] = record end
        end
    end
    table.sort(result, function(a, b) return a.key < b.key end)
    return result
end

local function contains(object, x, y)
    local p, s = object.AbsolutePosition, object.AbsoluteSize
    return x >= p.X and y >= p.Y and x <= p.X + s.X and y <= p.Y + s.Y
end

function Discovery:hit(x, y)
    local result, seen = {}, {}
    local ok, objects = pcall(function() return self.root:GetGuiObjectsAtPosition(x, y) end)
    if ok then
        for _, object in ipairs(objects) do
            local record = self.byObject[object]
            if record and self:_visible(object) then result[#result + 1], seen[object] = record, true end
        end
        return result
    end
    -- Public API fallback for restricted environments; honor clipping and hierarchy.
    for _, record in ipairs(self:list()) do
        local object, clipped = record.object, false
        local hitOK, inside = pcall(contains, object, x, y)
        if hitOK and inside then
            local ancestor = object.Parent
            while ancestor and ancestor ~= self.root do
                if isA(ancestor, "GuiObject") and ancestor.ClipsDescendants and not contains(ancestor, x, y) then clipped = true break end
                ancestor = ancestor.Parent
            end
            if not clipped and not seen[object] then result[#result + 1] = record end
        end
    end
    table.sort(result, function(a, b)
        local function order(object)
            local z, display, depth = object.ZIndex, 0, 0
            while object and object ~= self.root do
                depth = depth + 1
                if isA(object, "ScreenGui") then display = object.DisplayOrder break end
                object = object.Parent
            end
            return display, z, depth
        end
        local ad, az, ap = order(a.object)
        local bd, bz, bp = order(b.object)
        if ad ~= bd then return ad > bd end
        if az ~= bz then return az > bz end
        if ap ~= bp then return ap > bp end
        return a.key < b.key
    end)
    return result
end

function Discovery:approve(key, enabled)
    local record = self:get(key)
    if not record then return false, "Element is missing" end
    self.approved[key] = enabled == true or nil
    record.experimentalSuspended, record.failures = false, 0
    self:_classify(record)
    self:_notify()
    return true, enabled and "Experimental override approved for this element" or "Experimental override disabled"
end

function Discovery:destroy()
    if self.destroyed then return end
    self.destroyed = true
    disconnectAll(self.connections)
    for _, connections in pairs(self.objectConnections) do disconnectAll(connections) end
    self.connections, self.objectConnections, self.records, self.byObject = {}, {}, {}, {}
    self.onChanged = nil
end

return Discovery
