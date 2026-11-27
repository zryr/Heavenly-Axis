local Config = require("Config")
local Identity = require("Identity")
local Util = require("Util")

local EditorPreferences = {}
EditorPreferences.__index = EditorPreferences

local booleanPreferences = {smartSelection = true, skipTransparent = true, onboardingCompleted = true}
local layerFlags = {ignored = true, locked = true}

function EditorPreferences.new(storage, context, log)
    local data, reason
    if storage and type(storage.loadEditorPreferences) == "function" then
        data, reason = storage:loadEditorPreferences()
    end
    if reason and log then log(reason) end
    if not Config.validateEditorPreferences(data) then data = Config.emptyEditorPreferences() end
    return setmetatable({storage = storage, data = data, persistedData = data,
        scope = Config.editorScope(context), localRules = {}}, EditorPreferences)
end

function EditorPreferences:_commit(candidate)
    if self.writing then return false, "Wait for the current editor preference to save.", false end
    local valid, reason = Config.validateEditorPreferences(candidate)
    if not valid then return false, reason, false end
    self.data = candidate
    self.writing = true
    local stored, message
    if self.storage and type(self.storage.saveEditorPreferences) == "function" then
        local ran, saved, problem = pcall(self.storage.saveEditorPreferences, self.storage, candidate, self.persistedData)
        if ran then stored, message = saved, problem end
    end
    self.writing = nil
    self.needsWrite = stored ~= true
    if stored == true then
        self.persistedData = candidate
        return true, nil, true
    end
    local sessionMessage = "Editor preference applied for this session only."
    return true, message and (sessionMessage .. " " .. message) or sessionMessage, false
end

function EditorPreferences:_unchanged()
    if self.writing then return false, "Wait for the current editor preference to save.", false end
    if self.needsWrite then return self:_commit(self.data) end
    return true, nil, true
end

function EditorPreferences:setPreference(name, value)
    if not booleanPreferences[name] or type(value) ~= "boolean" then return false, "Invalid editor preference.", false end
    if self.data[name] == value then return self:_unchanged() end
    local candidate = Util.copy(self.data)
    candidate[name] = value
    return self:_commit(candidate)
end

function EditorPreferences:_rules()
    return (self.scope and self.data.scopes[self.scope]) or self.localRules
end

function EditorPreferences:elementFlags(descriptor, key)
    if type(descriptor) ~= "table" or descriptor.ambiguous then return false, false end
    if not key then
        if not Config.validateDescriptor(descriptor) then return false, false end
        key = Identity.key(descriptor)
    end
    local rule = self:_rules()[key]
    if not rule or not Identity.same(rule.descriptor, descriptor) then return false, false end
    return rule.ignored == true, rule.locked == true
end

function EditorPreferences:listElementFlags(kind)
    local keys, descriptors = {}, {}
    if not layerFlags[kind] then return descriptors end
    local rules = self:_rules()
    for key, rule in pairs(rules) do
        if rule[kind] then keys[#keys + 1] = key end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do descriptors[#descriptors + 1] = Util.copy(rules[key].descriptor) end
    return descriptors
end

function EditorPreferences:_replaceRules(rules)
    if not self.scope then
        local valid, reason = Config.validateLayerRules(rules)
        if not valid then return false, reason, false end
        self.localRules = rules
        return true, "Layer preference applies for this session because this place has no stable identifier.", false
    end
    local candidate = Util.copy(self.data)
    candidate.scopes[self.scope] = next(rules) and rules or nil
    return self:_commit(candidate)
end

function EditorPreferences:setElementFlag(kind, descriptor, value)
    if not layerFlags[kind] or type(value) ~= "boolean" then return false, "Invalid layer preference.", false end
    if not Config.validateDescriptor(descriptor) or descriptor.ambiguous then
        return false, "This layer needs an unambiguous hierarchy to set a preference.", false
    end
    local key = Identity.key(descriptor)
    local current = self:_rules()[key]
    if (current ~= nil and current[kind] == true) == value then return self:_unchanged() end
    local rules = Util.copy(self:_rules())
    local rule = rules[key] or {descriptor = Util.copy(descriptor)}
    rule[kind] = value or nil
    rules[key] = (rule.ignored or rule.locked) and rule or nil
    return self:_replaceRules(rules)
end

function EditorPreferences:clearElementFlags(kind)
    if not layerFlags[kind] then return false, "Invalid layer preference.", false end
    local rules, changed = Util.copy(self:_rules()), false
    for key, rule in pairs(rules) do
        if rule[kind] then
            rule[kind], changed = nil, true
            if not rule.ignored and not rule.locked then rules[key] = nil end
        end
    end
    if not changed then return self:_unchanged() end
    return self:_replaceRules(rules)
end

return EditorPreferences
