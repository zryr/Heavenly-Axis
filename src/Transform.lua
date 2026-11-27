-- Transforms write accessible GuiObject properties and verify the resulting layout.
local Util = require("Util")
local Discovery = require("Discovery")
local Coordinates = require("Coordinates")
local Geometry = require("Geometry")

local Transform = {}
Transform.__index = Transform

local MAX_RECT_ERROR = 1.5
local dimensionKeys = {"xs", "xo", "ys", "yo"}
local propertyNames = {"position", "size", "rotation", "transparency"}
local rectKeys = {"x", "y", "w", "h"}
local propertyOperations = {position = "move", size = "resize", rotation = "rotation", transparency = "transparency"}
local operationProperties = {move = "position", groupMove = "position", resize = "size", groupResize = "size",
    position = "position", size = "size", rotation = "rotation", transparency = "transparency"}
local cached = {cached = true}
local integerOffsets

local function isA(object, class)
    local ok, result = pcall(function() return object:IsA(class) end)
    return ok and result
end

local function udim(value)
    return UDim2.new(value.xs, value.xo, value.ys, value.yo)
end

local function normalizedOffset(offset)
    if integerOffsets == nil then integerOffsets = UDim2.new(0, 0.5, 0, 0).X.Offset ~= 0.5 end
    if not integerOffsets then return offset end
    return math.floor(offset + 0.5)
end

local function validDimension(value)
    if type(value) ~= "table" then return false end
    for _, key in ipairs(dimensionKeys) do
        if not Util.finite(value[key]) or math.abs(value[key]) > Geometry.MAX_SIZE then return false end
    end
    return true
end

local function validEntry(entry)
    if type(entry) ~= "table" or not validDimension(entry.position) or not validDimension(entry.size) then return false end
    if entry.rotation ~= nil and (not Util.finite(entry.rotation) or math.abs(entry.rotation) > 36000) then return false end
    if entry.transparency ~= nil and (not Util.finite(entry.transparency) or entry.transparency < 0 or entry.transparency > 1) then return false end
    return true
end

local function normalizeEntry(entry)
    local result = Util.copy(entry)
    result.position.xo, result.position.yo = normalizedOffset(result.position.xo), normalizedOffset(result.position.yo)
    result.size.xo, result.size.yo = normalizedOffset(result.size.xo), normalizedOffset(result.size.yo)
    return result
end

local function matchesProperty(actual, expected, property)
    local a, b = actual[property], expected[property]
    if b == nil or a == b then return true end
    if a == nil then return false end
    if property == "size" or property == "position" then
        for _, key in ipairs(dimensionKeys) do
            local tolerance = (key == "xs" or key == "ys") and 0.000001 or 0.0001
            if math.abs(a[key] - b[key]) > tolerance then return false end
        end
        return true
    end
    return math.abs(a - b) <= 0.0001
end

local function matchesProperties(actual, expected)
    if not actual then return false end
    for _, property in ipairs(propertyNames) do
        if not matchesProperty(actual, expected, property) then return false end
    end
    return true
end

local function assign(object, property, value)
    if property == "position" then object.Position = udim(value)
    elseif property == "size" then object.Size = udim(value)
    elseif property == "rotation" then object.Rotation = value
    else object.BackgroundTransparency = value end
end

local function write(object, entry, before)
    for _, property in ipairs(propertyNames) do
        if entry[property] ~= nil and (not before or not matchesProperty(before, entry, property)) then
            assign(object, property, entry[property])
        end
    end
    if not matchesProperties(Discovery.serialize(object), entry) then error("Requested properties were rejected") end
end

local function restoreProperties(object, entry)
    if not object.Parent then return true end
    local actual = Discovery.serialize(object)
    if not actual then return false end
    -- A rejected property must not prevent the other properties from being restored.
    for _, property in ipairs(propertyNames) do
        if entry[property] ~= nil and not matchesProperty(actual, entry, property) then
            pcall(assign, object, property, entry[property])
        end
    end
    return matchesProperties(Discovery.serialize(object), entry)
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

local function effectiveDimensions(object, size, root, projected)
    local parent = object.Parent
    local parentSize = parent and ((projected and projected[parent]) or parent.AbsoluteSize)
    if not parentSize then return nil, nil end
    local positionScale, sizeScale = scales(object, root)
    local basisX, basisY = parentSize.X, parentSize.Y
    local constraint = tostring(object.SizeConstraint)
    if constraint == "Enum.SizeConstraint.RelativeXX" or constraint == "RelativeXX" then basisY = basisX end
    if constraint == "Enum.SizeConstraint.RelativeYY" or constraint == "RelativeYY" then basisX = basisY end
    local own = sizeScale / positionScale
    return basisX * size.xs * own + size.xo * sizeScale, basisY * size.ys * own + size.yo * sizeScale
end

local function rectClose(actual, expected)
    if not actual then return false end
    for _, key in ipairs(rectKeys) do
        if math.abs(actual[key] - expected[key]) > MAX_RECT_ERROR then return false end
    end
    return true
end

local function sizeClose(actual, expected)
    return actual and math.abs(actual.w - expected.w) <= MAX_RECT_ERROR and math.abs(actual.h - expected.h) <= MAX_RECT_ERROR
end

local function changedProperties(actual, expected)
    local fields = {}
    for _, field in ipairs(propertyNames) do
        if not matchesProperty(actual, expected, field) then fields[field] = true end
    end
    return fields
end

local function frameReference(object, before, root)
    local positionScale, sizeScale = scales(object, root)
    local parent, anchor, rect = object.Parent, object.AnchorPoint, Coordinates.rect(object)
    if not Geometry.valid(rect) then error("Element geometry is unavailable") end
    if not Util.finite(positionScale) or positionScale <= 0 or not Util.finite(sizeScale) or sizeScale <= 0 then error("Invalid UIScale") end
    return {before = before, rect = rect, parent = parent, parentRect = Coordinates.rect(parent),
        anchorX = anchor.X, anchorY = anchor.Y, positionScale = positionScale, sizeScale = sizeScale}
end

local function fitRect(reference, target, after)
    local start, rect = reference.before, reference.rect
    local positionScale, sizeScale = reference.positionScale, reference.sizeScale
    after.size.xo = normalizedOffset(start.size.xo + (target.w - rect.w) / sizeScale)
    after.size.yo = normalizedOffset(start.size.yo + (target.h - rect.h) / sizeScale)
    if integerOffsets then
        if target.w >= Geometry.MIN_SIZE then
            local minOffset = start.size.xo + (Geometry.MIN_SIZE - rect.w) / sizeScale
            after.size.xo = math.max(after.size.xo, math.ceil(minOffset - 0.000001))
        end
        if target.h >= Geometry.MIN_SIZE then
            local minOffset = start.size.yo + (Geometry.MIN_SIZE - rect.h) / sizeScale
            after.size.yo = math.max(after.size.yo, math.ceil(minOffset - 0.000001))
        end
    end
    local dw, dh = (after.size.xo - start.size.xo) * sizeScale, (after.size.yo - start.size.yo) * sizeScale
    after.position.xo = normalizedOffset(start.position.xo + (target.x - rect.x + reference.anchorX * dw) / positionScale)
    after.position.yo = normalizedOffset(start.position.yo + (target.y - rect.y + reference.anchorY * dh) / positionScale)
    return {x = rect.x + (after.position.xo - start.position.xo) * positionScale - reference.anchorX * dw,
        y = rect.y + (after.position.yo - start.position.yo) * positionScale - reference.anchorY * dh,
        w = rect.w + dw, h = rect.h + dh}
end

function Transform.new(discovery, log)
    return setmetatable({discovery = discovery, log = log or function() end, tracked = {}, pendingByObject = {},
        receipts = setmetatable({}, {__mode = "k"}), safe = false, destroyed = false}, Transform)
end

function Transform:_record(key, entry)
    local record = self.discovery:get(key)
    if record and not record.descriptor.ambiguous then return record end
    if not entry or not entry.descriptor then return nil end
    return self.discovery:match(entry.descriptor)
end

function Transform:_allowed(record, operation, entry, options)
    if not record or not record.object.Parent then return false, "Element is missing" end
    if not options or not options.cached then self.discovery:_classify(record) end
    if record.descriptor.ambiguous then return false, record.reason end
    local field = operationProperties[operation]
    local hardReason = field and record.managedProperties and record.managedProperties[field]
    if hardReason then return false, hardReason end
    local capability = record.capabilities and record.capabilities[operation]
    local experimental = capability and capability.experimental or (not capability and record.experimental)
    if experimental then
        if self.safe or (options and options.safe) then return false, "Safe Mode blocks experimental overrides" end
        local suspended = record.suspendedOperations and record.suspendedOperations[field]
        if suspended or (not capability and record.experimentalSuspended) then return false, capability and capability.reason or record.reason end
        local savedApproval = options and options.experimental and entry and entry.experimental == true
        if savedApproval and options.deferApproval then return true end
        if savedApproval then
            self.discovery.approved[record.key] = true
            record.experimentalApproved = true
            self.discovery:_classify(record)
            capability = record.capabilities and record.capabilities[operation]
        end
    end
    if capability then return capability.supported == true, capability.reason end
    if not record.editable then return false, record.reason or "Unsupported transformation" end
    return true
end

function Transform:_failed(record, reason, fields, scriptOverwrite, geometryMismatch, requested, actual)
    if scriptOverwrite then
        record.overwrittenProperties = record.overwrittenProperties or {}
        for field in pairs(fields) do record.overwrittenProperties[field] = true end
    elseif geometryMismatch and record.layoutController then
        if record.observedGeometryController ~= record.layoutController then record.observedGeometryBlocks = nil end
        record.observedGeometryController = record.layoutController
        record.observedGeometryBlocks = record.observedGeometryBlocks or {}
        for field in pairs(fields) do
            record.observedGeometryBlocks[field] = "The layout did not honor this adjustment. Select the parent to edit the bar."
        end
    end
    self.discovery:_classify(record)
    for field in pairs(fields) do
        local cap = record.capabilities and record.capabilities[propertyOperations[field]]
        if scriptOverwrite or (cap and cap.experimental) then
            record.operationFailures = record.operationFailures or {}
            record.operationFailures[field] = (record.operationFailures[field] or 0) + 1
            if record.operationFailures[field] >= 3 then
                record.suspendedOperations = record.suspendedOperations or {}
                record.suspendedOperations[field] = true
            end
        end
    end
    self.discovery:_classify(record)
    record.lastFailure = {reason = tostring(reason), requested = requested, actual = actual}
    local label = record.suspendedOperations and next(record.suspendedOperations) and "Experimental override suspended" or "Transform failed"
    self.log(label .. " (" .. tostring(record.object.Name) .. "): " .. tostring(reason):sub(1, 160))
end

function Transform:_operation(record, before, after)
    return {record = record, before = before, after = after, previousTracked = self.tracked[record.key],
        previousReceipt = self.receipts[record.object], previousApproval = self.discovery.approved[record.key]}
end

local function portableEntry(record, before, previous)
    local entry = previous and Util.copy(previous) or {position = before.position, size = before.size}
    entry.descriptor = record.descriptor
    if record.experimentalApproved then entry.experimental = true end
    return entry
end

function Transform:_rollback(operations)
    local rollbacks, restored = {}, true
    for index = #operations, 1, -1 do
        local operation = operations[index]
        local record, object = operation.record, operation.record.object
        local original = {}
        for _, property in ipairs(propertyNames) do
            if not matchesProperty(operation.before, operation.after, property) then original[property] = operation.before[property] end
        end
        if not restoreProperties(object, original) then
            restored = false
            self.log("Original properties could not be restored for " .. tostring(object.Name))
        end
        self.tracked[record.key] = operation.previousTracked
        self.receipts[object] = operation.previousReceipt
        if operation.setApproval and self.discovery.approved[record.key] ~= operation.previousApproval then
            self.discovery.approved[record.key] = operation.previousApproval
            self.discovery:_classify(record)
        end
        rollbacks[record.key] = operation.previousTracked or false
    end
    return rollbacks, restored
end

function Transform:_store(operation)
    local record = operation.record
    local portable = operation.portable or operation.after
    self.tracked[record.key] = not operation.removeTracked and portable or nil
    self.receipts[record.object] = operation.receipt or portable
    if operation.setApproval then
        self.discovery.approved[record.key] = operation.setApproval == "grant" and true or nil
        self.discovery:_classify(record)
    end
end

function Transform:_writeBatch(operations, deferStore)
    for index, operation in ipairs(operations) do
        local ok, problem = pcall(write, operation.record.object, operation.after, operation.before)
        if not ok then
            local written = {}
            for i = 1, index do written[i] = operations[i] end
            local overwritten = tostring(problem):find("Requested properties were rejected", 1, true) ~= nil
            local observed = Discovery.serialize(operation.record.object)
            local fields = changedProperties(overwritten and observed or operation.before, operation.after)
            local _, restored = self:_rollback(written)
            self:_failed(operation.record, problem, fields, overwritten)
            return false, restored and "Transform rejected. The selection was restored." or "Transform rejected. Some original properties could not be restored."
        end
    end
    if not deferStore then
        for _, operation in ipairs(operations) do self:_store(operation) end
    end
    return true
end

function Transform:_observation(operation)
    local object, reference = operation.record.object, operation.reference
    if not object.Parent then return "An element disappeared during editing.", {}, "environment" end
    local observed = Discovery.serialize(object)
    if not observed then return "The resulting GUI properties could not be read.", {}, "environment" end
    local changed = changedProperties(observed, operation.after)
    if next(changed) then
        return "The game replaced the requested properties.", changed, "overwrite", operation.expectedRect and Coordinates.rect(object)
    end
    if operation.expectedRect and math.abs(object.Rotation % 360) > 0.001 then
        return "The element rotated during editing.", {}, "environment"
    end
    local actual, expected = Coordinates.rect(object), operation.expectedRect
    if expected and operation.verify == "position" and actual then
        expected = {x = expected.x - reference.anchorX * (actual.w - expected.w),
            y = expected.y - reference.anchorY * (actual.h - expected.h), w = actual.w, h = actual.h}
    end
    local matches = not expected or (operation.verify == "size" and sizeClose(actual, expected))
        or (operation.verify ~= "size" and rectClose(actual, expected))
    if not matches then
        local parentRect = Coordinates.rect(object.Parent)
        local ps, ss = scales(object, self.discovery.root)
        local anchor = object.AnchorPoint
        if object.Parent ~= reference.parent or (operation.verify ~= "size" and reference.parentRect and not rectClose(parentRect, reference.parentRect))
            or math.abs(ps - reference.positionScale) > 0.001 or math.abs(ss - reference.sizeScale) > 0.001
            or anchor.X ~= reference.anchorX or anchor.Y ~= reference.anchorY then
            return "The parent layout changed during editing.", {}, "environment", actual
        end
        local fields = operation.verify == "size" and {size = true}
            or operation.verify == "position" and {position = true} or {position = true, size = true}
        return "The resulting geometry differed from the requested adjustment.", fields, "geometry", actual
    end
    if operation.checkSize then
        local width, height = effectiveDimensions(object, operation.after.size, self.discovery.root)
        local rect = Coordinates.rect(object)
        if not rect or not Util.finite(width) or not Util.finite(height)
            or width < Geometry.MIN_SIZE or height < Geometry.MIN_SIZE or width > Geometry.MAX_SIZE or height > Geometry.MAX_SIZE
            or math.abs(rect.w - width) > MAX_RECT_ERROR or math.abs(rect.h - height) > MAX_RECT_ERROR then
            return "The layout did not honor the requested dimensions.", {size = true}, "geometry", rect
        end
    end
end

function Transform:_finish(job, cancellation, early)
    local jobs = self.pendingStabilization
    if not jobs or not jobs[job] then return true end
    local reason, failures, onlyGeometry = cancellation, {}, true
    if not reason then
        for _, operation in ipairs(job.operations) do
            local ok, problem, fields, kind, actual = pcall(self._observation, self, operation)
            if not ok then problem, fields, kind = "The resulting GUI geometry could not be read.", {}, "environment" end
            if problem then
                reason = reason or problem
                onlyGeometry = onlyGeometry and kind == "geometry"
                failures[#failures + 1] = {record = operation.record, problem = problem, fields = fields, kind = kind,
                    requested = operation.expectedRect, actual = actual}
            end
        end
    end
    if early and reason and onlyGeometry then return nil end
    jobs[job] = nil
    for _, operation in ipairs(job.operations) do self.pendingByObject[operation.record.object] = nil end
    if not next(jobs) then self.pendingStabilization = nil end
    if self.interactivePending == job then self.interactivePending = nil end
    for _, failure in ipairs(failures) do
        if failure.record.object.Parent and failure.kind ~= "environment" then
            self:_failed(failure.record, failure.problem, failure.fields, failure.kind == "overwrite", failure.kind == "geometry",
                failure.requested, failure.actual)
        end
    end
    local rollbacks
    if reason then
        local restored
        rollbacks, restored = self:_rollback(job.operations)
        for _, operation in ipairs(job.operations) do
            -- A failed saved request is still handled for this instance. Structural
            -- refreshes can restore recreated instances without retrying an old one.
            if not cancellation and not job.replay and operation.receipt and operation.record.object.Parent then
                self.receipts[operation.record.object] = operation.receipt
            end
        end
        if not restored then reason = reason .. " Some original properties could not be restored." end
        if not cancellation then self.log(reason) end
    elseif job.replay then
        for _, operation in ipairs(job.operations) do self:_store(operation) end
    end
    if job.callback then
        local ok, problem = pcall(job.callback, not reason, reason, rollbacks)
        if not ok then self.log("Adjustment completion could not be reported: " .. tostring(problem):sub(1, 160)) end
    elseif reason and not cancellation and self.onChanged then pcall(self.onChanged, rollbacks) end
    return not reason
end

function Transform:_schedule()
    if self.stabilizationScheduled or not self.pendingStabilization then return end
    local early = self.interactivePending
    if early and early.earlyChecked then early = nil end
    if early then
        for _, operation in ipairs(early.operations) do
            local capabilities = operation.record.capabilities
            for field in pairs(operation.after) do
                local capability = capabilities and capabilities[field]
                if capability and capability.experimental then early = nil; break end
            end
            if not early then break end
        end
    end
    local scheduled = {}
    if early then scheduled[early] = early.revision
    else for job in pairs(self.pendingStabilization) do scheduled[job] = job.revision end end
    local function observe()
        self.stabilizationScheduled = false
        if self.destroyed then return end
        for job, revision in pairs(scheduled) do
            if job.revision == revision then
                if job == early then job.earlyChecked = true end
                self:_finish(job, nil, job == early)
            end
        end
        self:_schedule()
    end
    self.stabilizationScheduled = true
    if task and task.delay then task.delay(early and 0.04 or 0.10, observe) else observe() end
end

function Transform:_queue(job, deferSchedule)
    self.pendingStabilization = self.pendingStabilization or {}
    self.pendingStabilization[job] = true
    job.revision = (job.revision or 0) + 1
    for _, operation in ipairs(job.operations) do self.pendingByObject[operation.record.object] = job end
    if not deferSchedule then self:_schedule() end
end

function Transform:_supersedePending()
    self:cancelTransaction()
    local pending = self.pendingStabilization
    for job in pairs(pending or {}) do self:_finish(job, "Layout superseded.") end
end

function Transform:beginTransaction()
    if self.destroyed or self.transaction or self.interactivePending then return false end
    self.transaction = {initial = {}, operations = {}, objectsByKey = {}}
    return true
end

function Transform:_recordUpdates(operations)
    for _, operation in ipairs(operations) do
        local transaction, object = self.transaction, operation.record.object
        local initial = transaction.initial[object]
        if not initial then
            initial = operation
            transaction.initial[object] = initial
            transaction.operations[#transaction.operations + 1] = initial
        else
            initial.after, initial.expectedRect, initial.verify = operation.after, operation.expectedRect, operation.verify
            initial.portable, initial.checkSize = operation.portable, operation.checkSize
        end
    end
end

function Transform:endTransaction(callback)
    local transaction = self.transaction
    self.transaction = nil
    if not transaction then return false end
    local operations = {}
    for _, operation in ipairs(transaction.operations) do
        if matchesProperties(operation.before, operation.after)
            and (not operation.previousTracked or Util.equal(operation.previousTracked, operation.portable or operation.after))
            and matchesProperties(Discovery.serialize(operation.record.object), operation.after) then
            local record = operation.record
            self.tracked[record.key], self.receipts[record.object] = operation.previousTracked, operation.previousReceipt
        else
            operations[#operations + 1] = operation
        end
    end
    if #operations == 0 then
        if callback then callback(true) end
    else
        local job = {operations = operations, callback = callback}
        self.interactivePending = job
        self:_queue(job)
    end
    return true
end

function Transform:cancelTransaction()
    local transaction = self.transaction
    self.transaction = nil
    if transaction then
        local _, restored = self:_rollback(transaction.operations)
        return true, restored
    end
    if self.interactivePending then
        self:_finish(self.interactivePending, "The adjustment was canceled.")
        return true
    end
    return false
end

function Transform:capture()
    local result = {}
    for key, entry in pairs(self.tracked) do
        if self:_record(key, entry) then result[key] = Util.copy(entry) end
    end
    return result
end

function Transform:selectionRects(keys, editableOnly, operation)
    if type(editableOnly) == "string" then operation, editableOnly = editableOnly, true end
    local seen, records, recordKeys, skipped = {}, {}, {}, 0
    for _, key in ipairs(keys or {}) do
        if not seen[key] then
            seen[key] = true
            local record = self.discovery:get(key)
            local supportsEdit = not editableOnly or (operation and self:_allowed(record, operation, nil, cached))
                or (not operation and (self:_allowed(record, "move", nil, cached) or self:_allowed(record, "resize", nil, cached)))
            if record and supportsEdit then
                records[#records + 1], recordKeys[record.object] = record.object, key
            else skipped = skipped + 1 end
        end
    end
    local rects, roots = {}, {}
    local members = #records > 1 and Geometry.roots(records, function(item) return item.Parent end) or records
    for _, object in ipairs(members) do
        local rect = Coordinates.rect(object)
        if Geometry.valid(rect) then rects[#rects + 1], roots[#roots + 1] = rect, recordKeys[object]
        else skipped = skipped + 1 end
    end
    return rects, roots, skipped
end

local function sameDirectJob(job, records)
    if not job or not job.direct or #job.operations ~= #records then return false end
    for index, record in ipairs(records) do
        if job.operations[index].record ~= record then return false end
    end
    return true
end

function Transform:setRects(keys, rects, operation)
    if self.destroyed then return false, "Transform controller is closed." end
    if #keys ~= #rects or #keys == 0 then return false, "No valid selection." end
    local transaction, records, selected = self.transaction, {}, {}
    for _, key in ipairs(keys) do
        local record = self.discovery:get(key)
        if not record or not record.object.Parent then return false, "An element is missing." end
        if record.descriptor.ambiguous then return false, record.reason or "This layer does not have a unique identity." end
        if transaction then
            local original = transaction.objectsByKey[key]
            if original and original ~= record.object then return false, "An element was recreated during editing." end
            transaction.objectsByKey[key] = record.object
        end
        if selected[record.object] then return false, "Repeated selection." end
        records[#records + 1], selected[record.object] = record, true
    end
    local direct = not transaction and self.pendingByObject[records[1].object] or nil
    if not sameDirectJob(direct, records) then direct = nil end
    local operations = {}
    for i, record in ipairs(records) do
        local object, target = record.object, rects[i]
        local pending = self.pendingByObject[object]
        if pending and pending ~= direct then self:_finish(pending) end
        local previous = transaction and transaction.initial[object] or (direct and direct.operations[i])
        if not previous then
            local parent = object.Parent
            while parent and parent ~= self.discovery.root do
                if selected[parent] then return false, "A selected parent already transforms its children." end
                parent = parent.Parent
            end
            self.discovery:_classify(record)
        end
        if not Geometry.valid(target) then return false, "Invalid dimensions." end
        for _, axis in ipairs(rectKeys) do
            if math.abs(target[axis]) > Geometry.MAX_SIZE then return false, "Invalid dimensions." end
        end
        local ok, mutation = pcall(function()
            local before = Discovery.serialize(object)
            if not before then error("Properties inaccessible") end
            if previous and not matchesProperties(before, previous.after) then
                local message = "The game replaced the adjustment during editing"
                self:_failed(record, message, changedProperties(before, previous.after), true)
                error(message)
            end
            -- Intermediate Roblox AbsolutePosition/AbsoluteSize can be one layout frame behind writes.
            local reference = previous and previous.reference or frameReference(object, before, self.discovery.root)
            if object.Parent ~= reference.parent then error("The element was moved to a different parent during editing") end
            local resizeMode = operation == "resize" or operation == "groupResize"
            local resizeRequested = math.abs(target.w - reference.rect.w) > 0.001 or math.abs(target.h - reference.rect.h) > 0.001
            local moveRequested = math.abs(target.x - reference.rect.x) > 0.001 or math.abs(target.y - reference.rect.y) > 0.001
            local useSize = resizeRequested or resizeMode or (previous and previous.after.size ~= nil)
            local canMove, moveReason = self:_allowed(record, operation == "groupMove" and "groupMove" or "move", nil, cached)
            if (operation == "move" or operation == "groupMove" or (not resizeMode and moveRequested)) and not canMove then
                error(moveReason or "Independent movement is unavailable")
            end
            if useSize then
                local canResize, resizeReason = self:_allowed(record, operation == "groupResize" and "groupResize" or "resize", nil, cached)
                if not canResize then error(resizeReason or "Independent resizing is unavailable") end
            end
            if not useSize and not canMove then error(moveReason or "Independent movement is unavailable") end
            if useSize and ((target.w < Geometry.MIN_SIZE and math.abs(target.w - reference.rect.w) > 0.001)
                or (target.h < Geometry.MIN_SIZE and math.abs(target.h - reference.rect.h) > 0.001)) then
                error("Minimum resized dimension is 16 screen units")
            end
            local after = {position = Util.copy(before.position), size = Util.copy(before.size)}
            local expected = fitRect(reference, target, after)
            local usePosition = canMove and (moveRequested or not useSize or (previous and previous.after.position ~= nil)
                or not matchesProperty(reference.before, after, "position"))
            if not validEntry(after) or (usePosition and not rectClose(expected, target)) or (useSize and not sizeClose(expected, target)) then
                error("This scale cannot represent the requested geometry accurately")
            end
            if not usePosition then after.position = nil end
            if not useSize then after.size = nil end
            local result = self:_operation(record, before, after)
            local prior = result.previousTracked
            if previous then prior = previous.previousTracked end
            result.portable = portableEntry(record, reference.before, prior)
            if not matchesProperty(reference.before, after, "position") then result.portable.position = after.position end
            if not matchesProperty(reference.before, after, "size") then result.portable.size = after.size end
            result.reference, result.expectedRect = reference, Util.copy(target)
            result.verify = usePosition and (useSize and "bounds" or "position") or "size"
            return result
        end)
        if not ok then return false, tostring(mutation):gsub("^.-:%d+: ", "") end
        if direct or not matchesProperties(mutation.before, mutation.after) then operations[#operations + 1] = mutation end
    end
    if #operations == 0 then return true end
    local ok, reason = self:_writeBatch(operations)
    if not ok then return false, reason end
    if transaction then self:_recordUpdates(operations)
    elseif direct then
        for index, operation in ipairs(operations) do
            direct.operations[index].after, direct.operations[index].expectedRect = operation.after, operation.expectedRect
            direct.operations[index].portable, direct.operations[index].verify = operation.portable, operation.verify
        end
        self:_queue(direct)
    else self:_queue({operations = operations, direct = true}) end
    return true
end

function Transform:_savedFields(record, before, entry, previous, options)
    local portable = normalizeEntry(entry or record.baseline)
    local raw, blocked = {}, nil
    local revoking = entry and entry.experimental == false
    local approval = {cached = true, experimental = options.experimental, deferApproval = true, safe = options.safe}
    for _, field in ipairs(propertyNames) do
        local value = portable[field]
        local prior = previous and previous[field]
        if value == nil and prior ~= nil and options.replace then value = record.baseline[field] end
        local old = record.baseline[field]
        if previous then old = prior end
        local scriptOwned = record.overwrittenProperties and record.overwrittenProperties[field] == true
        local revokeField = revoking and previous and previous.experimental == true and scriptOwned
        if revokeField then
            value = record.baseline[field]
            portable[field] = value
        end
        local requested = value ~= nil and (not options.delta or not Util.equal(old, value) or revokeField)
        if requested and (not revoking or not scriptOwned or revokeField) then
            local allowed, reason = self:_allowed(record, field, entry, approval)
            local owned = prior ~= nil and Util.equal(before[field], prior)
            local safeRestore = (not entry or revokeField) and owned and not (record.managedProperties and record.managedProperties[field])
            if allowed or safeRestore then raw[field] = value
            elseif not Util.equal(before[field], value) then blocked = blocked or reason or "A layout controls this property" end
        end
    end
    return raw, portable, blocked
end

function Transform:apply(layout, options)
    options = options or {}
    if self.destroyed or type(layout) ~= "table" then return 0, 0 end
    local applied, skipped, pending, projected = 0, 0, {}, {}
    if options.replace then
        self:_supersedePending()
        -- Permissions belong to the new checkpoint. Replacing it revokes absent approvals.
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
                    local before = Discovery.serialize(record.object)
                    if before then
                        self.discovery:_classify(record)
                        local original = self:_savedFields(record, before, nil, entry, {replace = true, delta = true})
                        if restoreProperties(record.object, original) then self.receipts[record.object] = record.baseline
                        else self.log("Original properties could not be restored for " .. tostring(record.object.Name)) end
                    end
                end
            end
        end
        for key in pairs(self.tracked) do if not layout[key] then self.tracked[key] = nil end end
    end
    for key, entry in pairs(layout) do
        local record = self:_record(key, entry)
        if options.onlyNew and record and Util.equal(self.receipts[record.object], entry) then
            -- The same request already ran for this instance.
        elseif not validEntry(entry) then
            skipped = skipped + 1
            self.log("Skipped invalid layout properties")
        elseif not record then skipped = skipped + 1
        else pending[#pending + 1] = {record = record, entry = entry} end
    end
    table.sort(pending, function(a, b) return #a.record.descriptor.path < #b.record.descriptor.path end)
    for _, item in ipairs(pending) do
        local record, entry = item.record, item.entry
        local object = record.object
        local previous = self.pendingByObject[object]
        if previous then self:_finish(previous) end
        self.discovery:_classify(record)
        local before = Discovery.serialize(object)
        local after, portable, reason
        if before then after, portable, reason = self:_savedFields(record, before, entry, self.tracked[record.key], options) end
        local width, height
        local checkSize = after and after.size ~= nil and not Util.equal(after.size, record.baseline.size)
        if after then
            local dimensionsOK
            dimensionsOK, width, height = pcall(effectiveDimensions, object, after.size or before.size, self.discovery.root, projected)
            local ancestor, parentResized = object.Parent, false
            while ancestor and ancestor ~= self.discovery.root do
                if projected[ancestor] then parentResized = true break end
                ancestor = ancestor.Parent
            end
            if checkSize and (not dimensionsOK or not Util.finite(width) or not Util.finite(height)
                or width < Geometry.MIN_SIZE or height < Geometry.MIN_SIZE or width > Geometry.MAX_SIZE or height > Geometry.MAX_SIZE)
                and not parentResized then
                after.size, checkSize, width, height = nil, false, nil, nil
                reason = reason or "Saved dimensions fall outside the supported range"
            end
        end
        if reason then skipped = skipped + 1; self.log("Skipped part of " .. tostring(object.Name) .. ": " .. reason) end
        if before and (not reason or not matchesProperties(before, after)) then
            local operation = self:_operation(record, before, after)
            operation.receipt, operation.checkSize, operation.portable = Util.copy(entry), checkSize, portable
            if entry.experimental == false then operation.setApproval = "revoke"
            elseif options.experimental and entry.experimental == true then operation.setApproval = "grant" end
            local ok, message = self:_writeBatch({operation})
            if ok then
                applied = applied + 1
                if Util.finite(width) and Util.finite(height) then projected[object] = {X = width, Y = height} end
                if self.transaction then self:_recordUpdates({operation})
                else self:_queue({operations = {operation}}, true) end
            else
                skipped = skipped + 1
                self.log(message)
            end
        else
            if not before then
                skipped = skipped + 1
                self.log("Skipped " .. tostring(object.Name) .. ": Properties inaccessible")
            else
                self.receipts[object] = Util.copy(entry)
                if entry.experimental == false then
                    self.discovery.approved[record.key] = nil
                    self.discovery:_classify(record)
                end
            end
        end
    end
    self:_schedule()
    return applied, skipped
end

function Transform:applyHistory(previous, desired, callback)
    if self.destroyed or self.transaction or self.interactivePending then return false end
    local changed = {}
    for key, entry in pairs(previous) do
        if not Util.equal(entry, desired[key]) then changed[key] = true end
    end
    for key in pairs(desired) do if not previous[key] then changed[key] = true end end
    local operations, skipped = {}, 0
    for key in pairs(changed) do
        local entry = desired[key]
        local record = self:_record(key, entry or previous[key])
        if not record or not record.object.Parent then
            skipped = skipped + 1
        else
            local pending = self.pendingByObject[record.object]
            if pending then self:_finish(pending) end
            self.discovery:_classify(record)
            local before = Discovery.serialize(record.object)
            if not before or not validEntry(entry or record.baseline) then
                callback(false, "The previous layout properties are unavailable.", skipped)
                return true
            end
            local raw, portable, problem = self:_savedFields(record, before, entry, previous[key],
                {delta = true, replace = true, experimental = true})
            if problem then callback(false, problem, skipped); return true end
            local operation = self:_operation(record, before, raw)
            operation.portable = portable
            operation.removeTracked = entry == nil
            operation.checkSize = raw.size ~= nil and not Util.equal(raw.size, record.baseline.size)
            if (entry and entry.experimental == true) ~= (previous[key] and previous[key].experimental == true) then
                operation.setApproval = entry and entry.experimental == true and "grant" or "revoke"
            end
            operation.receipt = entry and Util.copy(entry) or operation.after
            operations[#operations + 1] = operation
        end
    end
    if #operations == 0 then callback(true, nil, skipped); return true end
    table.sort(operations, function(a, b) return #a.record.descriptor.path < #b.record.descriptor.path end)
    local ok, problem = self:_writeBatch(operations, true)
    if not ok then callback(false, problem, skipped); return true end
    local job = {operations = operations, replay = true,
        callback = function(success, reason) callback(success, reason, skipped) end}
    self.interactivePending = job
    self:_queue(job)
    return true
end

function Transform:_editProperties(keys, createEntry, capability, rootOnly)
    local operations, seen, failed = {}, {}, 0
    for _, key in ipairs(keys) do
        local record = self:_record(key, self.tracked[key])
        if record and seen[record.object] then
            -- Repeated keys or matched aliases refer to the same live target.
        elseif record and (not capability or self:_allowed(record, capability)) then
            local object = record.object
            seen[object] = true
            local previous = self.pendingByObject[object]
            if previous then self:_finish(previous) end
            local before = Discovery.serialize(object)
            if before then
                local after, portable = createEntry(record, before)
                if after and validEntry(portable or after) then
                    local operation = self:_operation(record, before, after)
                    operation.portable = portable
                    operations[#operations + 1] = operation
                else failed = failed + 1 end
            else failed = failed + 1 end
        else failed = failed + 1 end
    end
    if rootOnly and #operations > 1 then
        local objects, byObject = {}, {}
        for _, operation in ipairs(operations) do
            local object = operation.record.object
            objects[#objects + 1], byObject[object] = object, operation
        end
        operations = {}
        for _, object in ipairs(Geometry.roots(objects, function(item) return item.Parent end)) do
            operations[#operations + 1] = byObject[object]
        end
    end
    if #operations == 0 then return 0, failed end
    if self.transaction then
        if not self:_writeBatch(operations) then return 0, failed + #operations end
        self:_recordUpdates(operations)
        return #operations, failed
    end
    local applied = 0
    for _, operation in ipairs(operations) do
        if self:_writeBatch({operation}) then applied = applied + 1 else failed = failed + 1 end
    end
    return applied, failed
end

function Transform:setProperty(keys, property, value)
    if property ~= "rotation" and property ~= "transparency" then return 0, #keys end
    if not Util.finite(value) then return 0, #keys end
    return self:_editProperties(keys, function(record, before)
        local after = {[property] = value}
        local previous = self.tracked[record.key]
        local portable = portableEntry(record, before, previous)
        if not matchesProperty(before, after, property) or (previous and previous[property] ~= nil) then
            portable[property] = value
        end
        return after, portable
    end, property, property == "rotation")
end

function Transform:restore(keys)
    local targets = keys
    if not targets then
        self:_supersedePending()
        targets = {}
        for key in pairs(self.tracked) do targets[#targets + 1] = key end
    end
    local restored, failed = self:_editProperties(targets, function(record, before)
        local previous = self.tracked[record.key]
        self.discovery:_classify(record)
        local after = self:_savedFields(record, before, nil, previous, {delta = keys == nil, replace = true})
        local portable = portableEntry(record, before, previous)
        if after.position then portable.position = after.position end
        if after.size then portable.size = after.size end
        for _, property in ipairs({"rotation", "transparency"}) do
            if after[property] and ((previous and previous[property] ~= nil) or not matchesProperty(before, after, property)) then
                portable[property] = after[property]
            end
        end
        if record.experimental then portable.experimental = record.experimentalApproved == true end
        return after, portable
    end, false)
    if failed > 0 then self.log(tostring(failed) .. " original elements unavailable during restoration") end
    return restored, failed
end

function Transform:matches(layout)
    local result = {}
    for key, entry in pairs(layout or {}) do
        if not self:_record(key, entry) then result[#result + 1] = {key = key, descriptor = Util.copy(entry.descriptor), reason = "No unique exact hierarchy match. Remap manually."} end
    end
    table.sort(result, function(a, b) return a.key < b.key end)
    return result
end

function Transform:clearTracked()
    self.tracked = {}
end

function Transform:destroy()
    self.destroyed, self.tracked, self.pendingByObject = true, {}, {}
    self.pendingStabilization, self.stabilizationScheduled, self.transaction, self.interactivePending = nil, false, nil, nil
    self.receipts = setmetatable({}, {__mode = "k"})
end

return Transform
