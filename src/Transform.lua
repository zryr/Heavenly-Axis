-- Screen-space transforms adapt only accessible GuiObject properties, never Roblox movement code.
local Util = require("Util")
local Identity = require("Identity")
local Discovery = require("Discovery")

local Transform = {}
Transform.__index = Transform

local function isA(object, class)
    local ok, result = pcall(function() return object:IsA(class) end)
    return ok and result
end

local function udim(value)
    return UDim2.new(value.xs, value.xo, value.ys, value.yo)
end

local function validDimension(value)
    if type(value) ~= "table" then return false end
    for _, key in ipairs({"xs", "xo", "ys", "yo"}) do
        if not Util.finite(value[key]) or math.abs(value[key]) > 1000000 then return false end
    end
    return true
end

local function validEntry(entry)
    if type(entry) ~= "table" or not validDimension(entry.position) or not validDimension(entry.size) then return false end
    if entry.rotation ~= nil and (not Util.finite(entry.rotation) or math.abs(entry.rotation) > 36000) then return false end
    if entry.transparency ~= nil and (not Util.finite(entry.transparency) or entry.transparency < 0 or entry.transparency > 1) then return false end
    return true
end

local function close(a, b)
    return math.abs(a - b) < 0.05
end

local function equivalent(object, entry)
    local actual = Discovery.serialize(object)
    if not actual then return false end
    for _, property in ipairs({"position", "size"}) do
        for _, axis in ipairs({"xs", "xo", "ys", "yo"}) do
            if not close(actual[property][axis], entry[property][axis]) then return false end
        end
    end
    if entry.rotation ~= nil and not close(actual.rotation, entry.rotation) then return false end
    if entry.transparency ~= nil and not close(actual.transparency, entry.transparency) then return false end
    return true
end

local function write(object, entry)
    object.Position, object.Size = udim(entry.position), udim(entry.size)
    if entry.rotation ~= nil then object.Rotation = entry.rotation end
    if entry.transparency ~= nil then object.BackgroundTransparency = entry.transparency end
end

local function directScale(object)
    local factor = 1
    for _, child in ipairs(object:GetChildren()) do
        if isA(child, "UIScale") then factor = factor * child.Scale end
    end
    return factor
end

local function scales(object, root)
    local positionScale, current = 1, object.Parent
    while current and current ~= root do
        if isA(current, "GuiObject") then positionScale = positionScale * directScale(current) end
        current = current.Parent
    end
    return positionScale, positionScale * directScale(object)
end

local function depth(record)
    return #record.descriptor.path
end

local function effectiveDimensions(object, size, root)
    local parent = object.Parent
    local parentSize = parent and parent.AbsoluteSize
    if not parentSize then return nil, nil end
    local positionScale = scales(object, root)
    local own = directScale(object)
    local basisX, basisY = parentSize.X, parentSize.Y
    local constraint = tostring(object.SizeConstraint)
    if constraint == "Enum.SizeConstraint.RelativeXX" or constraint == "RelativeXX" then basisY = basisX end
    if constraint == "Enum.SizeConstraint.RelativeYY" or constraint == "RelativeYY" then basisX = basisY end
    return (basisX * size.xs + size.xo * positionScale) * own,
        (basisY * size.ys + size.yo * positionScale) * own
end

local function rollbackEntry(operation)
    local entry = Util.copy(operation.previousTracked or operation.before)
    entry.descriptor = Util.copy(operation.record.descriptor)
    entry.experimental = operation.record.experimentalApproved == true or nil
    return entry
end

function Transform.new(discovery, log)
    return setmetatable({discovery = discovery, log = log or function() end, tracked = {},
        receipts = setmetatable({}, {__mode = "k"}), safe = false, generation = 0, destroyed = false}, Transform)
end

function Transform:_record(key, entry)
    local record = self.discovery:get(key)
    if record and not record.descriptor.ambiguous then return record end
    if not entry or not entry.descriptor then return nil end
    local candidates, records = {}, {}
    for _, candidate in pairs(self.discovery.records) do
        candidates[#candidates + 1], records[#records + 1] = candidate.descriptor, candidate
    end
    local index = Identity.match(entry.descriptor, candidates)
    return index and records[index] or nil
end

function Transform:_allowed(record, entry, options)
    if not record or not record.object.Parent then return false, "Element is missing" end
    self.discovery:_classify(record)
    if record.descriptor.ambiguous then return false, record.reason end
    if record.experimental then
        if self.safe or (options and options.safe) then return false, "Safe Mode blocks experimental overrides" end
        if record.experimentalSuspended then return false, record.reason end
        local savedApproval = options and options.experimental and entry and entry.experimental == true
        if savedApproval then
            self.discovery.approved[record.key] = true
            record.experimentalApproved = true
            self.discovery:_classify(record)
        end
        if not record.experimentalApproved then return false, record.reason end
    end
    if not record.editable then return false, record.reason or "Unsupported transformation" end
    return true
end

function Transform:_failed(record, reason)
    record.failures = (record.failures or 0) + 1
    if record.experimental and record.failures >= 3 then record.experimentalSuspended = true end
    self.discovery:_classify(record)
    local label = record.experimentalSuspended and "Experimental override suspended" or "Transform failed"
    self.log(label .. " (" .. tostring(record.object.Name) .. "): " .. tostring(reason):sub(1, 160))
end

function Transform:_stabilize(operations, generation)
    if #operations == 0 or not task or not task.delay then return end
    -- Debounce pointer updates into one quiet-period observation. At most one timer is pending.
    self.pendingStabilization = {operations = operations, generation = generation}
    if self.stabilizationScheduled then return end
    self.stabilizationScheduled = true
    local observe
    observe = function(expectedGeneration)
        if self.destroyed then self.pendingStabilization, self.stabilizationScheduled = nil, false return end
        local pending = self.pendingStabilization
        if not pending then self.stabilizationScheduled = false return end
        if pending.generation ~= expectedGeneration then
            task.delay(0.15, function() observe(pending.generation) end)
            return
        end
        self.pendingStabilization, self.stabilizationScheduled = nil, false
        if self.generation ~= pending.generation then return end
        local failed = false
        for _, operation in ipairs(pending.operations) do
            local object = operation.record.object
            local stable = not object.Parent or equivalent(object, operation.after)
            if object.Parent and stable and operation.expectedRect then
                local p, size = object.AbsolutePosition, object.AbsoluteSize
                local rect = operation.expectedRect
                stable = math.abs(p.X - rect.x) <= 1 and math.abs(p.Y - rect.y) <= 1
                    and math.abs(size.X - rect.w) <= 1 and math.abs(size.Y - rect.h) <= 1
            end
            if object.Parent and not stable then
                failed = true
                operation.record.managedByScript = true
                self.discovery:_classify(operation.record)
                self:_failed(operation.record, "Game or layout replaced the requested properties during stabilization")
            end
        end
        if failed then
            for _, operation in ipairs(pending.operations) do
                if operation.record.object.Parent then pcall(write, operation.record.object, operation.before) end
                self.tracked[operation.record.key] = rollbackEntry(operation)
                self.receipts[operation.record.object] = rollbackEntry(operation)
            end
            self.log("Unstable transaction rolled back; no layout enforcement loop is running")
            if self.onChanged then pcall(self.onChanged) end
        end
    end
    task.delay(0.15, function() observe(generation) end)
end

function Transform:beginTransaction()
    self.transaction = {initial = {}, operations = {}}
end

function Transform:_queueOperations(operations)
    if not self.transaction then self:_stabilize(operations, self.generation) return end
    for _, operation in ipairs(operations) do
        local key = operation.record.key
        local initial = self.transaction.initial[key]
        if not initial then
            initial = {before = Util.copy(operation.before), previousTracked = Util.copy(operation.previousTracked)}
            self.transaction.initial[key] = initial
        end
        self.transaction.operations[key] = {
            record = operation.record, before = initial.before, previousTracked = initial.previousTracked,
            after = operation.after, expectedRect = operation.expectedRect,
        }
    end
end

function Transform:endTransaction()
    if not self.transaction then return end
    local operations = {}
    for _, operation in pairs(self.transaction.operations) do operations[#operations + 1] = operation end
    self.transaction = nil
    self:_stabilize(operations, self.generation)
end

function Transform:cancelTransaction()
    self.transaction = nil
    self.generation = self.generation + 1
end

function Transform:capture()
    local result = {}
    for key, entry in pairs(self.tracked) do
        local record = self:_record(key, entry)
        if record then
            local snapshot = Discovery.serialize(record.object)
            if snapshot then
                snapshot.descriptor = Util.copy(record.descriptor)
                snapshot.experimental = record.experimentalApproved == true or nil
                if entry.viewport then snapshot.viewport = Util.copy(entry.viewport) end
                result[key] = snapshot
            end
        end
    end
    return result
end

function Transform:selectionRects(keys)
    local selected, objects = {}, {}
    for _, key in ipairs(keys or {}) do
        local record = self.discovery:get(key)
        if record and not selected[key] then selected[key] = record; objects[record.object] = true end
    end
    local rects, roots = {}, {}
    for _, key in ipairs(keys or {}) do
        local record = selected[key]
        if record then
            local nested, parent = false, record.object.Parent
            while parent and parent ~= self.discovery.root do
                if objects[parent] then nested = true break end
                parent = parent.Parent
            end
            if not nested then
                local ok, rect = pcall(function()
                    local p, s = record.object.AbsolutePosition, record.object.AbsoluteSize
                    return {x = p.X, y = p.Y, w = s.X, h = s.Y}
                end)
                if ok then rects[#rects + 1], roots[#roots + 1] = rect, key end
            end
            selected[key] = nil
        end
    end
    return rects, roots
end

function Transform:setRects(keys, rects)
    if self.destroyed then return false, "Transform controller is closed" end
    if #keys ~= #rects or #keys == 0 then return false, "No valid selection" end
    local roots, rootKeys = self:selectionRects(keys)
    if #rootKeys ~= #keys then return false, "Select parent roots before transforming nested objects" end
    local operations = {}
    for i, key in ipairs(keys) do
        local record, rect = self.discovery:get(key), rects[i]
        local allowed, reason = self:_allowed(record)
        if not allowed then return false, reason end
        if type(rect) ~= "table" then return false, "Invalid dimensions" end
        for _, axis in ipairs({"x", "y", "w", "h"}) do
            if not Util.finite(rect[axis]) or math.abs(rect[axis]) > 1000000 then return false, "Invalid dimensions" end
        end
        if rect.w < 16 or rect.h < 16 then return false, "Minimum size is 16 screen pixels" end
        local ok, operation = pcall(function()
            local object = record.object
            if math.abs(object.Rotation % 360) > 0.001 then error("Reset rotation to zero before screen-space resizing") end
            local positionScale, sizeScale = scales(object, self.discovery.root)
            if not Util.finite(positionScale) or positionScale <= 0 or not Util.finite(sizeScale) or sizeScale <= 0 then error("Invalid UIScale") end
            local before, after = Discovery.serialize(object), Discovery.serialize(object)
            if not before or not after then error("Properties inaccessible") end
            local p, s, anchor = object.AbsolutePosition, object.AbsoluteSize, object.AnchorPoint
            after.position.xo = before.position.xo + (rect.x - p.X + anchor.X * (rect.w - s.X)) / positionScale
            after.position.yo = before.position.yo + (rect.y - p.Y + anchor.Y * (rect.h - s.Y)) / positionScale
            after.size.xo = before.size.xo + (rect.w - s.X) / sizeScale
            after.size.yo = before.size.yo + (rect.h - s.Y) / sizeScale
            after.descriptor, after.experimental = Util.copy(record.descriptor), record.experimentalApproved == true or nil
            return {record = record, before = before, after = after, previousTracked = self.tracked[key],
                previousReceipt = self.receipts[record.object], expectedRect = Util.copy(rect)}
        end)
        if not ok then return false, tostring(operation):gsub("^.-:%d+: ", "") end
        operations[#operations + 1] = operation
    end
    self.generation = self.generation + 1
    for _, operation in ipairs(operations) do
        local ok, errorMessage = pcall(function()
            write(operation.record.object, operation.after)
            if not equivalent(operation.record.object, operation.after) then error("Requested properties were rejected") end
        end)
        if not ok then
            for _, rollback in ipairs(operations) do
                pcall(write, rollback.record.object, rollback.before)
                self.tracked[rollback.record.key] = rollback.previousTracked
                self.receipts[rollback.record.object] = rollback.previousReceipt
            end
            self:_failed(operation.record, errorMessage)
            return false, "Transform rejected; entire selection restored"
        end
        self.tracked[operation.record.key] = Util.copy(operation.after)
        self.receipts[operation.record.object] = Util.copy(operation.after)
    end
    self:_queueOperations(operations)
    return true
end

function Transform:apply(layout, options)
    options = options or {}
    if self.destroyed or type(layout) ~= "table" then return 0, 0 end
    local applied, skipped, operations, pending = 0, 0, {}, {}
    if options.replace then
        self.generation = self.generation + 1
        -- Permissions are part of the saved layout/checkpoint, so Undo and profile replacement
        -- revoke absent approvals rather than retaining a permission from the previous profile.
        for key in pairs(self.discovery.approved) do
            if not layout[key] or layout[key].experimental ~= true then
                self.discovery.approved[key] = nil
                local record = self.discovery:get(key)
                if record then self.discovery:_classify(record) end
            end
        end
        for key, entry in pairs(self.tracked) do
            if not layout[key] then
                local record = self:_record(key, entry)
                if record then
                    local ok = pcall(write, record.object, record.baseline)
                    if ok then self.receipts[record.object] = Util.copy(record.baseline)
                    else self.log("Original properties could not be restored for " .. tostring(record.object.Name)) end
                end
            end
        end
        self.tracked = {}
    end
    for key, entry in pairs(layout) do
        local record = self:_record(key, entry)
        if options.onlyNew and record and Util.equal(self.receipts[record.object], entry) then
            -- Structural/visibility events restore new instances only. Never re-enforce a
            -- previously applied request against an existing object's game scripts.
        elseif not validEntry(entry) then
            skipped = skipped + 1
            self.log("Skipped invalid layout properties")
        elseif not record then
            skipped = skipped + 1
        else
            if entry.experimental == false then
                self.discovery.approved[record.key] = nil
                self.discovery:_classify(record)
                if record.experimental then
                    -- Revocation restores the baseline once. Remember the handled
                    -- request even though this target is now intentionally skipped,
                    -- so unrelated HUD events cannot repeatedly fight its layout.
                    local restored = pcall(write, record.object, record.baseline)
                    self.receipts[record.object] = Util.copy(entry)
                    if not restored then self.log("Original properties unavailable while revoking experimental approval") end
                end
            end
            local allowed, reason = self:_allowed(record, entry, options)
            if allowed and not Util.equal(entry.size, record.baseline.size) then
                local dimensionOK, width, height = pcall(effectiveDimensions, record.object, entry.size, self.discovery.root)
                if not dimensionOK or not Util.finite(width) or not Util.finite(height)
                    or width < 16 or height < 16 or width > 1000000 or height > 1000000 then
                    allowed, reason = false, "Saved dimensions fall outside the supported 16–1000000 screen-pixel range"
                end
            end
            if not allowed then
                skipped = skipped + 1
                self.log("Skipped " .. tostring(record.object.Name) .. ": " .. tostring(reason))
            else pending[#pending + 1] = {record = record, entry = entry} end
        end
    end
    table.sort(pending, function(a, b) return depth(a.record) < depth(b.record) end)
    if not options.replace and #pending > 0 then self.generation = self.generation + 1 end
    for _, item in ipairs(pending) do
        local record, entry = item.record, item.entry
        local before = Discovery.serialize(record.object)
        local after = Util.copy(entry)
        local previousTracked = self.tracked[record.key]
        local ok, err = pcall(function()
            write(record.object, entry)
            if not equivalent(record.object, entry) then error("Requested properties were rejected") end
        end)
        if ok then
            applied = applied + 1
            self.tracked[record.key] = after
            self.receipts[record.object] = Util.copy(after)
            operations[#operations + 1] = {record = record, before = before, after = after, previousTracked = previousTracked}
        else
            skipped = skipped + 1
            if before then pcall(write, record.object, before) end
            self:_failed(record, err)
        end
    end
    self:_queueOperations(operations)
    return applied, skipped
end

function Transform:restore(keys)
    self.generation = self.generation + 1
    local restored, failed = 0, 0
    local targets = keys
    if not targets then
        targets = {}
        for key in pairs(self.tracked) do targets[#targets + 1] = key end
    end
    for _, key in ipairs(targets) do
        local record = self:_record(key, self.tracked[key])
        if record then
            local ok = pcall(write, record.object, record.baseline)
            if ok then
                restored = restored + 1
                local entry = Util.copy(record.baseline)
                entry.descriptor = Util.copy(record.descriptor)
                self.tracked[key] = entry
                self.receipts[record.object] = Util.copy(entry)
            else failed = failed + 1 end
        else failed = failed + 1 end
    end
    if failed > 0 then self.log(tostring(failed) .. " original elements unavailable during restoration") end
    return restored, failed
end

function Transform:matches(layout)
    local result = {}
    for key, entry in pairs(layout or {}) do
        if not self:_record(key, entry) then result[#result + 1] = {key = key, descriptor = Util.copy(entry.descriptor), reason = "No unique exact hierarchy match; manual remapping required"} end
    end
    table.sort(result, function(a, b) return a.key < b.key end)
    return result
end

function Transform:clearTracked()
    self.tracked = {}
end

function Transform:destroy()
    self.destroyed, self.generation, self.tracked = true, self.generation + 1, {}
    self.pendingStabilization, self.stabilizationScheduled, self.transaction = nil, false, nil
    self.receipts = setmetatable({}, {__mode = "k"})
end

return Transform
