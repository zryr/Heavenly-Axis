-- Runtime ownership of supported appearance surfaces. Portable entries retain the chosen scope.
local Util = require("Util")
local Geometry = require("Geometry")
local Appearance = require("Appearance")

local TransformOpacity = {}
TransformOpacity.__index = TransformOpacity

local function addSurface(index, target, create)
    local fields = index[target.object]
    if not fields then fields = {}; index[target.object] = fields end
    local surface = fields[target.property]
    if not surface then surface = create(target); fields[target.property] = surface end
    return surface
end

local function identity(target)
    return {target = target, incoming = {}}
end

local function prefer(candidate, current)
    return not current or candidate.depth > current.depth or (candidate.depth == current.depth and candidate.key < current.key)
end

local function readable(target)
    local parent = target.object.Parent
    return parent ~= nil and (target.parent == nil or target.parent == parent) and Util.finite(target.object[target.property])
end

local function close(a, b)
    return Util.finite(a) and math.abs(a - b) <= 0.0001
end

local function matchesValue(actual, write)
    if write.exact then return actual == write.after end
    return close(actual, write.after)
end

local function getField(index, target)
    return index[target.object] and index[target.object][target.property]
end

local function setField(index, target, value)
    local fields = index[target.object]
    if not fields then fields = {}; index[target.object] = fields end
    fields[target.property] = value
end

function TransformOpacity.new(discovery, legacy)
    return setmetatable({discovery = discovery, scopes = {}, claims = setmetatable({}, {__mode = "k"}),
        receipts = setmetatable({}, {__mode = "k"}), blocked = setmetatable({}, {__mode = "k"}), legacy = legacy}, TransformOpacity)
end

function TransformOpacity:snapshot(keys, scope, canEdit)
    if scope ~= "element" and scope ~= "contents" then return nil, "Choose an opacity scope." end
    local planner = self.discovery.appearance
    if not planner then return nil, "No supported appearance properties are available." end
    local objects, records, seen = {}, {}, {}
    for _, key in ipairs(keys) do
        local record = self.discovery:get(key)
        if record and not seen[record.object] and (not canEdit or canEdit(record, false)) then
            objects[#objects + 1], records[record.object], seen[record.object] = record.object, record, true
        end
    end
    if scope == "contents" then objects = Geometry.roots(objects, function(object) return object.Parent end) end
    local groups, roots, factor, mixed, reason = {}, {}, nil, false, nil
    for _, object in ipairs(objects) do
        local record = records[object]
        local targets, message, details = planner:plan({record.key}, scope, {canEdit = canEdit})
        local eligible, targetKeys = {}, {}
        for _, target in ipairs(targets or {}) do
            if not getField(self.blocked, target) then
                eligible[#eligible + 1] = target
                targetKeys[target.key] = true
            end
        end
        targets = eligible
        local persisted = {}
        for key in pairs(targetKeys) do persisted[#persisted + 1] = key end
        table.sort(persisted)
        if targets and #targets > 0 then
            groups[#groups + 1] = {record = record, targets = targets, keys = persisted, skipped = details and details.skipped or 0}
            roots[#roots + 1] = record.key
            local current = self.scopes[record.key]
            local value = current and current.spec.scope == scope and current.spec.factor or 1
            if factor and factor ~= value then mixed = true else factor = value end
        else reason = reason or message end
    end
    if #groups == 0 then return nil, reason or "No supported visible surfaces in this scope." end
    return {keys = roots, groups = groups, factor = factor or 1, scope = scope, mixed = mixed,
        revision = self.discovery.revision, canEdit = canEdit}
end

function TransformOpacity:_setScope(key, scope)
    local previous = self.scopes[key]
    if previous then
        for _, target in ipairs(previous.targets) do
            local owners = getField(self.claims, target)
            if owners then owners[key] = nil end
        end
    end
    self.scopes[key] = scope
    if scope then
        for _, target in ipairs(scope.targets) do
            local owners = addSurface(self.claims, target, function() return {} end)
            owners[key] = scope
        end
    end
end

local function within(key, root)
    return key == root or key:sub(1, #root + 1) == root .. "/"
end

local function conflictsWithComposite(scopes, owner, composite)
    for key, candidate in pairs(scopes) do
        if key ~= owner and within(key, composite.key) then
            for _, target in ipairs(candidate.nativeTargets) do
                if target.object ~= composite.object or target.property ~= composite.property then return true end
            end
        end
    end
    return false
end

local function sameSurfaces(a, b)
    if a == b then return true end
    if #a ~= #b then return false end
    for index, target in ipairs(a) do
        if target.object ~= b[index].object or target.property ~= b[index].property then return false end
    end
    return true
end

function TransformOpacity:_composeScopes(before, after, planner, canEdit)
    local prospective, expanded, decomposed = {}, {}, {}
    for key, scope in pairs(self.scopes) do if after[key] == nil then prospective[key] = scope end end
    for key, scope in pairs(after) do if scope then prospective[key] = scope end end
    for key, scope in pairs(prospective) do
        for _, target in ipairs(scope.nativeTargets) do
            if target.contents and conflictsWithComposite(prospective, key, target) then decomposed[target.key] = true end
        end
    end
    for key, scope in pairs(prospective) do
        local effective, composites = {}, {}
        for _, target in ipairs(scope.nativeTargets) do
            local flatten = false
            if target.contents then
                for root in pairs(decomposed) do if within(target.key, root) then flatten = true; break end end
            end
            if flatten then
                local pieces = expanded[target.key]
                if not pieces then
                    local blocked = false
                    local function allowed(record)
                        if not canEdit or canEdit(record, true) then return true end
                        blocked = true
                        return false
                    end
                    local reason
                    pieces, reason = planner:flattenGroup(target.key, allowed)
                    if blocked then return false, "Unlock the CanvasGroup contents before adjusting nested opacity." end
                    if not pieces then return false, reason or "Choose a smaller CanvasGroup opacity scope." end
                    expanded[target.key] = pieces
                end
                composites[target.key] = true
                for _, piece in ipairs(pieces) do effective[#effective + 1] = piece end
            else effective[#effective + 1] = target end
        end
        if not sameSurfaces(scope.targets, effective) then
            if before[key] == nil then before[key] = self.scopes[key] or false end
            after[key] = {key = key, depth = scope.depth, spec = scope.spec,
                nativeTargets = scope.nativeTargets, targets = effective, flattened = composites}
        end
    end
    return true
end

function TransformOpacity:prepare(edits, onlyNew)
    local surfaces, before, after, legacy = {}, {}, {}, {}
    local planner = self.discovery.appearance
    if not planner then return nil end
    local topologyChanged, canEdit = false, nil
    for _, edit in ipairs(edits) do
        local key = edit.record.key
        local old = self.scopes[key]
        local object = edit.record.object
        if edit.legacy ~= nil then
            legacy[key] = edit.legacy
            local entries = self.claims[object]
            if entries and entries.BackgroundTransparency and next(entries.BackgroundTransparency) then
                addSurface(surfaces, {object = object, key = key, property = "BackgroundTransparency",
                    original = edit.record.baseline.transparency}, identity)
            end
        end
        local requested = false
        if not edit.keep and edit.spec then
            local targets = edit.targets
            if not targets then
                targets = planner:plan({key}, edit.spec.scope, {targets = edit.spec.targets})
            end
            targets = targets or {}
            local same = old and old.nativeTargets == targets
            topologyChanged = topologyChanged or not same
            requested = {key = key, depth = #edit.record.descriptor.path, spec = edit.spec,
                nativeTargets = targets, targets = same and old.targets or targets, flattened = same and old.flattened}
        end
        if not edit.keep then
            before[key], after[key] = old or false, requested
            if old and not requested then topologyChanged = true end
        end
        canEdit = canEdit or edit.canEdit
    end
    if topologyChanged then
        local ok, reason = self:_composeScopes(before, after, planner, canEdit)
        if not ok then return nil, reason end
    end
    for key, previous in pairs(before) do
        if previous then for _, target in ipairs(previous.targets) do addSurface(surfaces, target, identity) end end
        local requested = after[key]
        if requested then
            for _, target in ipairs(requested.targets) do
                local surface = addSurface(surfaces, target, identity)
                surface.incoming[#surface.incoming + 1] = requested
            end
        end
    end
    local writes, index = {}, {}
    for _, fields in pairs(surfaces) do
        for _, item in pairs(fields) do
            local target = item.target
            if readable(target) and not getField(self.blocked, target) then
                local winner
                for owner, claim in pairs(getField(self.claims, target) or {}) do
                    if after[owner] == nil and prefer(claim, winner) then winner = claim end
                end
                for _, claim in ipairs(item.incoming) do if prefer(claim, winner) then winner = claim end end
                local original = target.original
                if not winner and target.property == "BackgroundTransparency" then
                    local configured = legacy[target.key]
                    if configured == nil then configured = self.legacy(target.key) end
                    if Util.finite(configured) then original = configured end
                end
                local factor = winner and winner.spec.factor or 1
                local wanted = Appearance.value(original, factor)
                local current, receipt = target.object[target.property], getField(self.receipts, target)
                if wanted and (not onlyNew or receipt == nil or receipt ~= wanted) then
                    local write = {target = target, before = current, after = wanted, receipt = receipt,
                        exact = factor == 0 or factor == 1}
                    writes[#writes + 1] = write
                    setField(index, target, write)
                end
            end
        end
    end
    return {before = before, after = after, writes = writes, index = index}
end

function TransformOpacity:write(change)
    for _, write in ipairs(change.writes) do
        local target = write.target
        if not readable(target) then error("An appearance layer became unavailable") end
        write.attempted = true
        if not matchesValue(target.object[target.property], write) then target.object[target.property] = write.after end
    end
    if not self:matches(change) then error("The game rejected an opacity adjustment") end
end

function TransformOpacity:_superseded(change, write)
    local expected = change.committed and getField(self.receipts, write.target) or nil
    return expected ~= nil and expected ~= write.after
end

function TransformOpacity:matches(change)
    for _, write in ipairs(change.writes) do
        local target = write.target
        if not self:_superseded(change, write)
            and (not readable(target) or not matchesValue(target.object[target.property], write)) then return false end
    end
    return true
end

function TransformOpacity:property(change, object, property)
    local fields = change and change.index[object]
    return fields and fields[property] and fields[property].after
end

function TransformOpacity:markFailed(change)
    for _, write in ipairs(change.writes) do
        local target = write.target
        if write.attempted and not self:_superseded(change, write) and readable(target)
            and not matchesValue(target.object[target.property], write) then
            setField(self.blocked, target, true)
        end
    end
end

function TransformOpacity:commit(change)
    for key, scope in pairs(change.after) do self:_setScope(key, scope or nil) end
    for _, write in ipairs(change.writes) do setField(self.receipts, write.target, write.after) end
    change.committed = true
end

function TransformOpacity:rollback(change)
    local restored = true
    for _, write in ipairs(change.writes) do
        local target = write.target
        local superseded = self:_superseded(change, write)
        if write.attempted and not superseded and target.object.Parent and write.before ~= write.after then
            local ok = pcall(function() target.object[target.property] = write.before end)
            restored = ok and target.object[target.property] == write.before and restored
        end
        if change.committed and not superseded then setField(self.receipts, target, write.receipt) end
    end
    if change.committed then
        for key, scope in pairs(change.before) do
            if self.scopes[key] == (change.after[key] or nil) then self:_setScope(key, scope or nil) end
        end
    end
    return restored
end

function TransformOpacity:merge(prior, latest)
    if not prior then return latest end
    if not latest then return prior end
    for _, write in ipairs(latest.writes) do
        local initial = getField(prior.index, write.target)
        if initial then initial.after, initial.exact, initial.attempted = write.after, write.exact, write.attempted
        else
            prior.writes[#prior.writes + 1] = write
            setField(prior.index, write.target, write)
        end
    end
    for key, scope in pairs(latest.before) do if prior.before[key] == nil then prior.before[key] = scope end end
    for key, scope in pairs(latest.after) do prior.after[key] = scope end
    prior.committed = prior.committed or latest.committed
    return prior
end

function TransformOpacity:changed(change)
    if not change then return false end
    if self:surfaceChanged(change) then return true end
    for key, after in pairs(change.after) do
        local before = change.before[key]
        if not Util.equal(before and before.spec, after and after.spec) then return true end
    end
    return false
end

function TransformOpacity:surfaceChanged(change)
    for _, write in ipairs(change.writes) do if not matchesValue(write.before, write) then return true end end
    return false
end

function TransformOpacity:targets(key)
    local scope = self.scopes[key]
    return scope and scope.targets or {}
end

function TransformOpacity:hasScope(key)
    return self.scopes[key] ~= nil
end

function TransformOpacity:owns(object, property)
    local fields = self.claims[object]
    return fields and fields[property] and next(fields[property]) ~= nil
end

function TransformOpacity:forget(key)
    local scope = self.scopes[key]
    if not scope then return end
    self:_setScope(key, nil)
    for _, target in ipairs(scope.targets) do
        local current = target.object
        while current and current ~= self.discovery.root do current = current.Parent end
        local receipt = getField(self.receipts, target)
        if current and receipt ~= nil and close(target.object[target.property], receipt) then
            local winner
            for _, claim in pairs(getField(self.claims, target) or {}) do
                if prefer(claim, winner) then winner = claim end
            end
            local original = target.original
            if not winner and target.property == "BackgroundTransparency" then
                local legacy = self.legacy(target.key)
                if Util.finite(legacy) then original = legacy end
            end
            local value = Appearance.value(original, winner and winner.spec.factor or 1)
            local ok = value ~= nil and pcall(function() target.object[target.property] = value end)
            if ok then setField(self.receipts, target, winner and value or nil) end
        elseif not current then setField(self.receipts, target, nil) end
    end
end

function TransformOpacity:destroy()
    self.scopes, self.claims, self.receipts, self.blocked = {}, {}, {}, {}
end

return TransformOpacity
