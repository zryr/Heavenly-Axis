local Config = require("Config")
local Util = require("Util")
local Profiles = {}
Profiles.__index = Profiles
local priorities = {global = 1, experience = 2, place = 3, device = 4, orientation = 5}

local function find(data, id)
    for index, profile in ipairs(data.profiles) do
        if profile.id == id then return profile, index end
    end
end

local function cleanName(name)
    if type(name) ~= "string" then return nil end
    name = name:match("^%s*(.-)%s*$")
    if #name == 0 or #name > 64 or name:find("[%c]") then return nil end
    return name
end

function Profiles.new(data, storage, context, log)
    data = data or Config.empty()
    local valid, reason = Config.validate(data)
    assert(valid, "Invalid initial configuration: " .. tostring(reason))
    data = Util.copy(data)
    data.preferences = data.preferences or {}
    return setmetatable({data = data, checkpoint = Util.copy(data), storage = storage, context = context,
        log = log or function() end, serial = 0, suspended = false, editTargets = {}}, Profiles)
end

function Profiles:list(allScopes)
    local profiles = {}
    for _, profile in ipairs(self.data.profiles) do
        if allScopes or Config.applies(profile, self.context) then profiles[#profiles + 1] = profile end
    end
    table.sort(profiles, function(a, b)
        local first, second = a.name:lower(), b.name:lower()
        if first == second then return a.id < b.id end
        return first < second
    end)
    return profiles
end

local function contextKey(context)
    return table.concat({tostring(context.experience), tostring(context.place), tostring(context.device), tostring(context.orientation)}, ":")
end

local function activeById(data, context, id)
    local profile = id and find(data, id)
    if profile and Config.applies(profile, context) and data.active[Config.scopeKey(profile)] == id then return profile end
end

function Profiles:editTargetId(context)
    context = context or self.context
    local id = self.editTargets[contextKey(context)]
    return activeById(self.data, context, id) and id or nil
end

function Profiles:setEditTarget(id, context)
    context = context or self.context
    if id ~= nil and not activeById(self.data, context, id) then return false end
    self.editTargets[contextKey(context)] = id
    return true
end

function Profiles:active(context)
    context = context or self.context
    local selected = self:editTargetId(context)
    if selected then return find(self.data, selected) end
    local active = Config.activeProfiles(self.data, context)
    return active[#active]
end

function Profiles:resetTarget(context)
    context = context or self.context
    local active = Config.activeProfiles(self.data, context)
    local profile = active[#active]
    if profile and profile.scope == "orientation" and profile.device == context.device then return profile end
end

function Profiles:_id()
    repeat
        self.serial = self.serial + 1
        local id = "profile-" .. tostring(os.time()) .. "-" .. tostring(self.serial)
        if not find(self.data, id) then return id end
    until false
end

function Profiles:create(name, scope)
    if self.saving then return nil, "Wait for the current Save to finish." end
    if self.preview then return nil, "Apply or cancel the preview before managing profiles." end
    name = cleanName(name)
    if not name then return nil, "Choose a profile name of 1–64 readable characters." end
    scope = scope or "place"
    if not priorities[scope] then return nil, "Unknown profile scope." end
    local profile = {id = self:_id(), name = name, scope = scope, layout = {}, groups = {}, preferences = {}}
    if scope == "experience" then profile.scopeId = self.context.experience end
    if scope == "place" or scope == "device" or scope == "orientation" then profile.scopeId = self.context.place end
    if scope == "device" or scope == "orientation" then profile.device = self.context.device end
    if scope == "orientation" then profile.orientation = self.context.orientation end
    local valid, err = Config.validateProfile(profile)
    if not valid then return nil, err end
    local candidate = Util.copy(self.data)
    candidate.profiles[#candidate.profiles + 1] = profile
    local accepted, reason = Config.validate(candidate)
    if not accepted then return nil, reason end
    self.data = candidate
    self.log("Created profile " .. name .. "; preview and Apply to activate, Save to persist.")
    return find(self.data, profile.id)
end

function Profiles:rename(id, name)
    if self.saving then return false, "Wait for the current Save to finish." end
    if self.preview then return false, "Apply or cancel the preview before managing profiles." end
    name = cleanName(name)
    if not name then return false, "Choose a profile name of 1–64 readable characters." end
    local profile = find(self.data, id)
    if not profile then return false, "Profile not found." end
    profile.name = name
    return true, "Profile renamed in memory; Save to persist."
end

function Profiles:duplicate(id, name)
    if self.saving then return nil, "Wait for the current Save to finish." end
    if self.preview then return nil, "Apply or cancel the preview before managing profiles." end
    local source = find(self.data, id)
    if not source then return nil, "Profile not found." end
    name = cleanName(name or (source.name:sub(1, 58) .. " copy"))
    if not name then return nil, "Choose a profile name of 1–64 readable characters." end
    local profile = Util.copy(source)
    profile.id, profile.name = self:_id(), name
    local candidate = Util.copy(self.data)
    candidate.profiles[#candidate.profiles + 1] = profile
    local ok, reason = Config.validate(candidate)
    if not ok then return nil, reason end
    self.data = candidate
    return find(self.data, profile.id)
end

function Profiles:delete(id, confirmed)
    if self.saving then return false, "Wait for the current Save to finish." end
    if confirmed ~= true then return false, "Confirm profile deletion. GUI elements and original layouts will be preserved." end
    if self.preview then return false, "Apply or cancel the profile preview first." end
    local profile, index = find(self.data, id)
    if not profile then return false, "Profile not found." end
    table.remove(self.data.profiles, index)
    for key, activeId in pairs(self.data.active) do
        if activeId == id then self.data.active[key] = nil end
    end
    self.revisions = nil
    return true, "Profile deleted in memory; Save to persist. GUI elements were preserved."
end

function Profiles:isActive(id, context)
    return activeById(self.data, context or self.context, id) ~= nil
end

function Profiles:resolve(context)
    if self.suspended then return {}, Util.copy(self.data.preferences or {}), {} end
    return Config.resolve(self.data, context or self.context)
end

function Profiles:beginPreview(id, context)
    if self.saving then return nil, "Wait for the current Save to finish." end
    context = context or self.context
    local profile = find(self.data, id)
    if not profile then return nil, "Profile not found." end
    if not Config.applies(profile, context) then return nil, "This profile belongs to another experience, place, device or orientation." end
    local candidate = Util.copy(self.data)
    candidate.active[Config.scopeKey(profile)] = profile.id
    local valid, err = Config.validate(candidate)
    if not valid then return nil, err end
    local layout, preferences, groups = Config.resolve(candidate, context)
    local active = Config.activeProfiles(candidate, context)
    self.preview = {kind = "profile", id = profile.id, data = candidate, context = Util.copy(context),
        preferences = preferences, groups = groups, overlaid = active[#active].id ~= profile.id}
    return layout, nil, preferences, groups
end

function Profiles:applyPreview()
    if self.saving then return false, "Wait for the current Save to finish." end
    if not self.preview then return false, "No profile preview to apply." end
    local valid, err = Config.validate(self.preview.data)
    if not valid then return false, err end
    local preview = self.preview
    self.data = preview.data
    self:setEditTarget(preview.id, preview.context)
    self.preview = nil
    self.suspended = false
    return true, "Profile preview applied in memory; Save to persist."
end

function Profiles:cancelPreview()
    self.preview = nil
    return true, "Preview canceled; active profile unchanged."
end

local function differences(before, after)
    local changes = {}
    for key, value in pairs(after) do
        if not Util.equal(value, before[key]) then changes[#changes + 1] = {key = key, before = before[key], value = value} end
    end
    for key, value in pairs(before) do
        if after[key] == nil then changes[#changes + 1] = {key = key, before = value} end
    end
    return changes
end

local function patchLayout(layout, changes, inherited)
    for _, change in ipairs(changes) do
        local key, before, value = change.key, change.before, change.value
        local own, base = layout[key], inherited[key]
        if not value then
            layout[key] = base and {descriptor = Util.copy(before.descriptor), removed = true} or nil
        elseif own and not own.inherit and not own.removed then
            -- Preserve untouched fields of legacy full overrides, even when a higher layer is visible.
            for _, property in ipairs(Config.LAYOUT_PROPERTIES) do
                if not before or not Util.equal(before[property], value[property]) then own[property] = Util.copy(value[property]) end
            end
        elseif not base then
            layout[key] = Util.copy(value)
        else
            local patch = own and own.inherit and own or {descriptor = Util.copy(value.descriptor), inherit = true}
            local clear = patch.clear or {}
            local hasOverride = false
            for _, property in ipairs(Config.LAYOUT_PROPERTIES) do
                if not before or not Util.equal(before[property], value[property]) then
                    local inherit = Util.equal(base[property], value[property])
                    if inherit then
                        patch[property], clear[property] = nil, nil
                    else
                        patch[property] = Util.copy(value[property])
                        clear[property] = value[property] == nil or nil
                    end
                end
                if patch[property] ~= nil or clear[property] then hasOverride = true end
            end
            patch.clear = next(clear) and clear or nil
            layout[key] = hasOverride and patch or nil
        end
    end
end

local function patchValues(map, changes, inherited, canRemove)
    for _, change in ipairs(changes) do
        local key, value = change.key, change.value
        if Util.equal(value, inherited[key]) then map[key] = nil
        elseif value == nil and canRemove then map[key] = false
        else map[key] = Util.copy(value) end
    end
end

local function conflicts(changes, resolved, layout)
    for _, change in ipairs(changes) do
        local before, value, actual = change.before, change.value, resolved[change.key]
        if layout and before and value and actual then
            for _, property in ipairs(Config.LAYOUT_PROPERTIES) do
                if not Util.equal(before[property], value[property]) and not Util.equal(value[property], actual[property]) then return true end
            end
        elseif not Util.equal(value, actual) then return true end
    end
    return false
end

function Profiles:save(layout, groups, preferences, baseline, context, options)
    if self.preview then return false, "Apply or cancel the preview before saving." end
    if self.saving then return false, "Save is already in progress." end
    context = context or self.context
    local reset = type(options) == "table" and options.resetAll == true
    if reset and ((context.device ~= "touch" and context.device ~= "desktop")
        or (context.orientation ~= "landscape" and context.orientation ~= "portrait")) then
        return false, "Reset requires a recognized device and screen orientation."
    end
    layout, groups, preferences = layout or {}, groups or {}, preferences or {}
    local stateValid, stateReason = Config.validateState({layout = layout, groups = groups, preferences = preferences})
    if not stateValid then return false, "Checkpoint rejected. " .. tostring(stateReason) end
    if not baseline then
        local previousLayout, previousPrefs, previousGroups = self:resolve(context)
        baseline = {layout = previousLayout, preferences = previousPrefs, groups = previousGroups}
    end
    local layoutChanges = differences(baseline.layout, layout)
    local groupChanges = differences(baseline.groups, groups)
    local prefChanges = differences(baseline.preferences, preferences)
    local candidate = Util.copy(self.data)
    local resetProfileId
    if reset or #layoutChanges + #groupChanges + #prefChanges > 0 then
        local active = self:active(context)
        if reset then active = self:resetTarget(context) end
        local profile = active and find(candidate, active.id)
        if not profile then
            profile = {id = self:_id(), name = "Default place", scope = "place", scopeId = context.place, layout = {}, groups = {}, preferences = {}}
            if reset then
                profile.name, profile.scope = "Original " .. context.orientation .. " layout", "orientation"
                profile.device, profile.orientation = context.device, context.orientation
            end
            candidate.profiles[#candidate.profiles + 1] = profile
            candidate.active[Config.scopeKey(profile)] = profile.id
        end
        local inheritedLayout, inheritedPrefs, inheritedGroups = Config.resolve(candidate, context, profile.id)
        profile.groups, profile.preferences = profile.groups or {}, profile.preferences or {}
        if reset then
            profile.resetLayout, profile.layout = true, Util.copy(layout)
            resetProfileId = profile.id
        else
            patchLayout(profile.layout, layoutChanges, profile.resetLayout and {} or inheritedLayout)
        end
        patchValues(profile.groups, groupChanges, inheritedGroups, true)
        patchValues(profile.preferences, prefChanges, inheritedPrefs, false)
        local valid, reason = Config.validate(candidate)
        if not valid then return false, "Save rejected. " .. tostring(reason) .. ". Use an experience or place profile for game-specific elements." end
        local candidateLayout, candidatePrefs, candidateGroups = Config.resolve(candidate, context)
        if (reset and not Util.equal(layout, candidateLayout)) or (not reset and conflicts(layoutChanges, candidateLayout, true))
            or conflicts(groupChanges, candidateGroups) or conflicts(prefChanges, candidatePrefs) then
            return false, "A more specific profile overrides these edits. Choose that profile to save them here."
        end
    end
    self.saving = true
    local ran, saved, message, memoryOnly = pcall(self.storage.save, self.storage, candidate)
    self.saving = nil
    if not ran then return false, "Save could not complete. Your edits are still open." end
    if saved or memoryOnly then
        self.data = candidate
        self.checkpoint = Util.copy(candidate)
        if resetProfileId then self:setEditTarget(resetProfileId, context) end
    end
    self.log(message)
    return saved, message, saved == true or memoryOnly == true
end

function Profiles:import(text)
    return self.storage:import(text)
end

function Profiles:beginImport(text, overwriteConfirmed, context)
    if self.saving then return nil, "Wait for the current Save to finish." end
    context = context or self.context
    local incoming, err = self:import(text)
    if not incoming then return nil, err end
    local candidate = Util.copy(self.data)
    local conflicts = false
    for _, profile in ipairs(incoming.profiles) do
        local existing = find(candidate, profile.id)
        if existing and not Util.equal(existing, profile) then conflicts = true end
    end
    for key, value in pairs(incoming.preferences or {}) do
        if candidate.preferences[key] ~= nil and not Util.equal(candidate.preferences[key], value) then conflicts = true end
    end
    for key, id in pairs(incoming.active) do
        if candidate.active[key] ~= nil and candidate.active[key] ~= id then conflicts = true end
    end
    for name, members in pairs(incoming.groups or {}) do
        if candidate.groups and candidate.groups[name] and not Util.equal(candidate.groups[name], members) then conflicts = true end
    end
    if conflicts and overwriteConfirmed ~= true then return nil, "Import would overwrite existing profiles, activation, groups, or preferences. Confirm overwrite, then preview again." end
    for _, profile in ipairs(incoming.profiles) do
        local existing, index = find(candidate, profile.id)
        if existing then
            local oldSlot = Config.scopeKey(existing)
            if oldSlot ~= Config.scopeKey(profile) and candidate.active[oldSlot] == profile.id then candidate.active[oldSlot] = nil end
            candidate.profiles[index] = Util.copy(profile)
        else
            candidate.profiles[#candidate.profiles + 1] = Util.copy(profile)
        end
    end
    for key, id in pairs(incoming.active) do candidate.active[key] = id end
    for key, value in pairs(incoming.preferences or {}) do candidate.preferences[key] = Util.copy(value) end
    if incoming.groups then
        candidate.groups = candidate.groups or {}
        for name, members in pairs(incoming.groups) do candidate.groups[name] = Util.copy(members) end
    end
    local valid, reason = Config.validate(candidate)
    if not valid then return nil, "Merged import rejected: " .. tostring(reason) end
    local layout, preferences, groups = Config.resolve(candidate, context)
    self.preview = {kind = "import", data = candidate, context = Util.copy(context), preferences = preferences, groups = groups}
    return layout, nil, preferences, groups
end

function Profiles:export()
    return self.storage:export(self.checkpoint)
end

-- Stable across JSON key ordering. Used to detect a changed draft checkpoint.
local function revision(data, context)
    local hash, second = 5381, 2166136261
    local function update(value)
        for index = 1, #value do
            local byte = value:byte(index)
            hash = (hash * 33 + byte) % 4294967296
            second = (second * 65599 + byte) % 4294967296
        end
    end
    local function visit(value)
        local kind = type(value)
        if kind ~= "table" then
            local stringValue = kind == "number" and string.format("%.17g", value) or tostring(value)
            update(kind .. #stringValue .. ":" .. stringValue)
            return
        end
        local keys = {}
        for key in pairs(value) do keys[#keys + 1] = key end
        table.sort(keys)
        update("{")
        for _, key in ipairs(keys) do visit(key); visit(value[key]) end
        update("}")
    end
    visit(data.preferences or {})
    visit(data.groups or {})
    for _, profile in ipairs(Config.activeProfiles(data, context)) do
        visit(profile.id)
        visit(Config.scopeKey(profile))
        if profile.resetLayout then visit("original layout override") end
        visit(profile.layout)
        visit(profile.groups or {})
        visit(profile.preferences or {})
    end
    return string.format("%.0f:%.0f", hash, second)
end

function Profiles:_draftRevision(context)
    if self.revisionData ~= self.data or not self.revisions then
        self.revisionData, self.revisions = self.data, {}
    end
    local key = contextKey(context)
    if not self.revisions[key] then self.revisions[key] = revision(self.data, context) end
    return self.revisions[key]
end

function Profiles:draftReference(context)
    context = context or self.context
    local active = self:active(context)
    return {profileId = active and active.id or false, revision = self:_draftRevision(context)}
end

function Profiles:matchesDraftReference(reference, context)
    if reference == nil then return true end
    context = context or self.context
    if reference.profileId == false then
        if self:active(context) then return false end
    elseif not activeById(self.data, context, reference.profileId) then
        return false
    end
    return reference.revision == self:_draftRevision(context)
end

function Profiles:suspend(value)
    self.suspended = value == true
    return self.suspended
end

return Profiles
