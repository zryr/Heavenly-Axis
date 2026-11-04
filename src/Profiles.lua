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
    return setmetatable({data = data, storage = storage, context = context, log = log or function() end, serial = 0, suspended = false}, Profiles)
end

function Profiles:list(allScopes)
    local profiles = {}
    for _, profile in ipairs(self.data.profiles) do
        if allScopes or Config.applies(profile, self.context) then profiles[#profiles + 1] = profile end
    end
    table.sort(profiles, function(a, b)
        if a.name == b.name then return a.id < b.id end
        return a.name:lower() < b.name:lower()
    end)
    return profiles
end

function Profiles:active()
    local current
    for _, profile in ipairs(self.data.profiles) do
        if Config.applies(profile, self.context) and self.data.active[Config.scopeKey(profile)] == profile.id then
            if not current or priorities[profile.scope] > priorities[current.scope]
                or (priorities[profile.scope] == priorities[current.scope] and profile.device ~= nil and current.device == nil) then current = profile end
        end
    end
    return current
end

function Profiles:_id()
    repeat
        self.serial = self.serial + 1
        local id = "profile-" .. tostring(os.time()) .. "-" .. tostring(self.serial)
        if not find(self.data, id) then return id end
    until false
end

function Profiles:create(name, scope)
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
    if self.preview then return false, "Apply or cancel the preview before managing profiles." end
    name = cleanName(name)
    if not name then return false, "Choose a profile name of 1–64 readable characters." end
    local profile = find(self.data, id)
    if not profile then return false, "Profile not found." end
    profile.name = name
    return true, "Profile renamed in memory; Save to persist."
end

function Profiles:duplicate(id, name)
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
    if confirmed ~= true then return false, "Confirm profile deletion. GUI elements and original layouts will be preserved." end
    if self.preview then return false, "Apply or cancel the profile preview first." end
    local profile, index = find(self.data, id)
    if not profile then return false, "Profile not found." end
    table.remove(self.data.profiles, index)
    for key, activeId in pairs(self.data.active) do
        if activeId == id then self.data.active[key] = nil end
    end
    return true, "Profile deleted in memory; Save to persist. GUI elements were preserved."
end

function Profiles:resolve()
    if self.suspended then return {}, Util.copy(self.data.preferences or {}), {} end
    return Config.resolve(self.data, self.context)
end

function Profiles:beginPreview(id)
    local profile = find(self.data, id)
    if not profile then return nil, "Profile not found." end
    if not Config.applies(profile, self.context) then return nil, "This profile belongs to another experience, place, device or orientation." end
    local candidate = Util.copy(self.data)
    local chosenKey = Config.scopeKey(profile)
    -- Selecting a layer explicitly makes it the editable layer for this context.
    -- Suspend more-specific active references in the preview candidate only;
    -- their profile definitions remain available for later reactivation.
    for _, other in ipairs(candidate.profiles) do
        local otherKey = Config.scopeKey(other)
        if Config.applies(other, self.context)
            and (priorities[other.scope] > priorities[profile.scope]
                or (other.scope == profile.scope and otherKey ~= chosenKey)) then
            candidate.active[otherKey] = nil
        end
    end
    candidate.active[chosenKey] = profile.id
    local valid, err = Config.validate(candidate)
    if not valid then return nil, err end
    local layout, preferences, groups = Config.resolve(candidate, self.context)
    self.preview = {kind = "profile", id = profile.id, data = candidate, preferences = preferences, groups = groups}
    return layout, nil, preferences, groups
end

function Profiles:applyPreview()
    if not self.preview then return false, "No profile preview to apply." end
    local valid, err = Config.validate(self.preview.data)
    if not valid then return false, err end
    self.data = Util.copy(self.preview.data)
    self.preview = nil
    self.suspended = false
    return true, "Profile preview applied in memory; Save to persist."
end

function Profiles:cancelPreview()
    self.preview = nil
    return true, "Preview canceled; active profile unchanged."
end

function Profiles:save(layout, groups, preferences)
    if self.preview then return false, "Apply or cancel the preview before saving." end
    local stateValid, stateReason = Config.validateProfile({id = "checkpoint", name = "Checkpoint", scope = "place", scopeId = self.context.place, layout = layout or {}, groups = groups or {}, preferences = preferences or {}})
    if not stateValid then return false, "Checkpoint rejected: " .. tostring(stateReason) end
    local candidate = Util.copy(self.data)
    local active = self:active()
    local profile
    if active then
        profile = find(candidate, active.id)
    else
        profile = {id = self:_id(), name = "Default place", scope = "place", scopeId = self.context.place, layout = {}, groups = {}, preferences = {}}
        candidate.profiles[#candidate.profiles + 1] = profile
        candidate.active[Config.scopeKey(profile)] = profile.id
    end
    -- App supplies the full authoritative state, including unresolved identities.
    -- Replacing here also preserves deliberate removals during manual remapping.
    profile.layout = Util.copy(layout or {})
    profile.groups, profile.preferences = Util.copy(groups or {}), Util.copy(preferences or {})
    local valid, reason = Config.validate(candidate)
    if not valid then return false, "Save rejected: " .. tostring(reason) .. ". Use a place profile for game-specific elements." end
    -- A valid in-memory checkpoint remains exportable even when persistence is unavailable.
    self.data = candidate
    local saved, message = self.storage:save(candidate)
    self.log(message)
    return saved, message, true
end

function Profiles:import(text)
    return self.storage:import(text)
end

function Profiles:beginImport(text, overwriteConfirmed)
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
    if conflicts and overwriteConfirmed ~= true then return nil, "Import would overwrite existing profiles or preferences. Confirm overwrite, then preview again." end
    for _, profile in ipairs(incoming.profiles) do
        local _, index = find(candidate, profile.id)
        if index then candidate.profiles[index] = Util.copy(profile) else candidate.profiles[#candidate.profiles + 1] = Util.copy(profile) end
    end
    for key, id in pairs(incoming.active) do candidate.active[key] = id end
    for key, value in pairs(incoming.preferences or {}) do candidate.preferences[key] = Util.copy(value) end
    local valid, reason = Config.validate(candidate)
    if not valid then return nil, "Merged import rejected: " .. tostring(reason) end
    local layout, preferences, groups = Config.resolve(candidate, self.context)
    self.preview = {kind = "import", data = candidate, preferences = preferences, groups = groups}
    return layout, nil, preferences, groups
end

function Profiles:export()
    return self.storage:export(self.data)
end

function Profiles:suspend(value)
    self.suspended = value == true
    return self.suspended
end

return Profiles
