-- Portable data only. Imports are JSON; no profile is ever evaluated as source code.
local Util = require("Util")
local Identity = require("Identity")
local Config = { VERSION = 3, EDITOR_VERSION = 1 }
local MAX_PROFILES, MAX_LAYOUT, MAX_GROUPS, MAX_MEMBERS = 64, 512, 64, 128
local MAX_EDITOR_SCOPES, MAX_LAYER_RULES = 128, 256
Config.MAX_OPACITY_TARGETS = 96
local scopes = { global = true, experience = true, place = true, device = true, orientation = true }
local priorities = { global = 1, experience = 2, place = 3, device = 4, orientation = 5 }
local optionalProperties = { rotation = true, transparency = true, opacity = true, experimental = true, viewport = true }
Config.LAYOUT_PROPERTIES = { "position", "size", "rotation", "transparency", "opacity", "experimental", "viewport" }
Config.EDITOR_PANELS = {inspector = true, toolbar = true, workspace = true, launcher = true}
Config.EDITOR_TUTORIAL_MODES = {quick = true, tour = true}
local panelModes = { ["touch-landscape"] = true, ["touch-portrait"] = true,
    ["desktop-landscape"] = true, ["desktop-portrait"] = true }
local panelEdges = {left = true, right = true, top = true, bottom = true}
local builtins = { JumpButton = true, ThumbstickFrame = true, DynamicThumbstickFrame = true }
local booleanPrefs = { grid = true, snapping = true, multiSelect = true, boxSelect = true,
    aspectLock = true, centerScale = true, equalSize = true, launcherHidden = true,
    panelCollapsed = true, advanced = true, diagnostics = true }
local numericPrefs = { gridSize = { 4, 128 }, snapThreshold = { 1, 32 }, step = { 1, 64 },
    launcherX = { 0, 1 }, launcherY = { 0, 1 } }
local function plain(value) return type(value) == "table" and getmetatable(value) == nil end
local function text(value, max)
    return type(value) == "string" and #value > 0 and #value <= (max or 128) and not value:find("%c")
end
local function number(value, min, max) return Util.finite(value) and value >= min and value <= max end
local function fields(value, allowed)
    if not plain(value) then return false end
    for key in pairs(value) do if not allowed[key] then return false end end
    return true
end
local function array(value, limit)
    if not plain(value) then return false end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > limit then return false end
        count = count + 1
    end
    return count == #value and count <= limit
end
local function mapCount(value, limit)
    if not plain(value) then return false end
    local count = 0
    for key in pairs(value) do
        if not text(key, 8192) then return false end
        count = count + 1
        if count > limit then return false end
    end
    return true
end
local function validBuiltin(descriptor)
    local path = descriptor.path
    return builtins[descriptor.builtin] and #path == 3
        and path[1].name == "TouchGui" and path[1].class == "ScreenGui"
        and path[2].name == "TouchControlFrame" and path[2].class == "Frame"
        and path[3].name == descriptor.builtin
        and ((descriptor.builtin == "JumpButton" and (descriptor.class == "ImageButton" or descriptor.class == "TextButton"))
            or (descriptor.builtin ~= "JumpButton" and descriptor.class == "Frame"))
end

function Config.validateDescriptor(descriptor)
    if not fields(descriptor, { path = true, class = true, builtin = true, ambiguous = true }) then return false, "Invalid element descriptor" end
    if not text(descriptor.class, 64) or not array(descriptor.path, 32) or #descriptor.path == 0 then return false, "Invalid element hierarchy" end
    for _, segment in ipairs(descriptor.path) do
        if not fields(segment, { name = true, class = true, ordinal = true })
            or not text(segment.name, 256) or not text(segment.class, 64)
            or not number(segment.ordinal, 1, 10000) or segment.ordinal % 1 ~= 0 then return false, "Invalid hierarchy segment" end
    end
    if descriptor.path[#descriptor.path].class ~= descriptor.class then return false, "Descriptor class mismatch" end
    if descriptor.ambiguous ~= nil and type(descriptor.ambiguous) ~= "boolean" then return false, "Invalid ambiguity flag" end
    if descriptor.builtin ~= nil and not validBuiltin(descriptor) then return false, "Invalid built-in control identity" end
    return true
end

local function id(value) return text(value, 32) and value:match("^%d+$") ~= nil end

function Config.editorScope(context)
    if type(context) ~= "table" or not id(context.experience) or not id(context.place)
        or context.experience:match("^0%d") or context.place:match("^0%d")
        or (context.experience == "0" and context.place == "0") then return nil end
    return context.experience .. ":" .. context.place
end

function Config.emptyEditorPreferences()
    return {version = Config.EDITOR_VERSION, smartSelection = true, skipTransparent = true, onboardingCompleted = false, scopes = {}}
end

function Config.editorPanelMode(context)
    if type(context) ~= "table" or type(context.device) ~= "string" or type(context.orientation) ~= "string" then return nil end
    local mode = context.device .. "-" .. context.orientation
    return panelModes[mode] and mode or nil
end

function Config.validatePanelPlacement(placement)
    return fields(placement, {x = true, y = true, dock = true})
        and number(placement.x, 0, 1) and number(placement.y, 0, 1)
        and (placement.dock == nil or panelEdges[placement.dock] == true)
end

function Config.validateTutorialStep(step)
    return step == nil or (number(step, 1, 16) and step % 1 == 0)
end

function Config.validateLayerRules(rules)
    if not mapCount(rules, MAX_LAYER_RULES) then return false, "Too many layer preferences for this place." end
    for key, rule in pairs(rules) do
        if not fields(rule, { descriptor = true, ignored = true, locked = true })
            or (rule.ignored ~= nil and rule.ignored ~= true) or (rule.locked ~= nil and rule.locked ~= true)
            or (rule.ignored == nil and rule.locked == nil) then return false, "Invalid layer preference." end
        local valid = Config.validateDescriptor(rule.descriptor)
        if not valid or rule.descriptor.ambiguous or key ~= Identity.key(rule.descriptor) then
            return false, "Layer preferences require an unambiguous matching hierarchy."
        end
    end
    return true
end

function Config.validateEditorPreferences(data)
    if not fields(data, {version = true, smartSelection = true, skipTransparent = true, onboardingCompleted = true, scopes = true,
        panels = true, panelDocking = true, panelLayoutReset = true, tutorialProgress = true})
        or data.version ~= Config.EDITOR_VERSION or type(data.smartSelection) ~= "boolean"
        or type(data.skipTransparent) ~= "boolean" or type(data.onboardingCompleted) ~= "boolean"
        or not mapCount(data.scopes, MAX_EDITOR_SCOPES) then return false, "Invalid or unsupported editor preferences." end
    if (data.panelDocking ~= nil and type(data.panelDocking) ~= "boolean")
        or (data.panelLayoutReset ~= nil and type(data.panelLayoutReset) ~= "boolean") then
        return false, "Invalid panel preferences."
    end
    if data.panels ~= nil then
        if not fields(data.panels, panelModes) then return false, "Invalid panel screen mode." end
        for _, placements in pairs(data.panels) do
            if not fields(placements, Config.EDITOR_PANELS) then return false, "Invalid editor panel." end
            for _, placement in pairs(placements) do
                if not Config.validatePanelPlacement(placement) then return false, "Invalid editor panel position." end
            end
        end
    end
    if data.tutorialProgress ~= nil then
        if not fields(data.tutorialProgress, Config.EDITOR_TUTORIAL_MODES) then return false, "Invalid lesson type." end
        for _, step in pairs(data.tutorialProgress) do
            if not Config.validateTutorialStep(step) then return false, "Invalid lesson progress." end
        end
    end
    for scope, rules in pairs(data.scopes) do
        local experience, place = scope:match("^(%d+):(%d+)$")
        if not Config.editorScope({experience = experience, place = place}) then return false, "Invalid layer preference scope." end
        local valid, reason = Config.validateLayerRules(rules)
        if not valid then return false, reason end
    end
    return true
end

local function preferences(value)
    if not plain(value) then return false, "Preferences must be a map" end
    for key, item in pairs(value) do
        if booleanPrefs[key] then
            if type(item) ~= "boolean" then return false, "Invalid boolean preference: " .. key end
        elseif numericPrefs[key] then
            local range = numericPrefs[key]
            if not number(item, range[1], range[2]) then return false, "Invalid numeric preference: " .. key end
        elseif key == "shortcut" then
            if not text(item, 24) or not item:match("^[A-Za-z][A-Za-z0-9]*$") then return false, "Invalid shortcut" end
        else return false, "Unknown preference" end
    end
    return true
end
Config.validatePreferences = preferences

local function udim(value, size)
    if not fields(value, { xs = true, xo = true, ys = true, yo = true }) then return false end
    if not number(value.xs, size and 0 or -10, 10) or not number(value.ys, size and 0 or -10, 10)
        or not number(value.xo, -100000, 100000) or not number(value.yo, -100000, 100000) then return false end
    if size and ((value.xs == 0 and value.xo <= 0) or (value.ys == 0 and value.yo <= 0)) then return false end
    return true
end

function Config.validateOpacity(value, ownerKey)
    if not fields(value, {factor = true, scope = true, targets = true}) or not number(value.factor, 0, 1)
        or (value.scope ~= "element" and value.scope ~= "contents") then return false end
    if value.targets == nil then return true end
    if not array(value.targets, Config.MAX_OPACITY_TARGETS) or #value.targets == 0 then return false end
    local prefix = ownerKey and (ownerKey .. "/")
    local previous
    for _, target in ipairs(value.targets) do
        if not text(target, 8192) or (previous and target <= previous)
            or (prefix and target ~= ownerKey and target:sub(1, #prefix) ~= prefix) then return false end
        previous = target
    end
    return true
end

function Config.validateLayout(layout, global, overrides)
    if not mapCount(layout, MAX_LAYOUT) then return false, "Layout exceeds limits or is not a map" end
    for key, entry in pairs(layout) do
        if not fields(entry, { descriptor = true, position = true, size = true, rotation = true,
            transparency = true, opacity = true, experimental = true, viewport = true,
            inherit = overrides, removed = overrides, clear = overrides }) then return false, "Invalid layout entry" end
        local valid, reason = Config.validateDescriptor(entry.descriptor)
        if not valid then return false, reason end
        if key ~= Identity.key(entry.descriptor) then return false, "Layout key differs from its identity" end
        if global and not validBuiltin(entry.descriptor) then return false, "Global profiles may contain only recognized built-in controls" end
        if entry.removed ~= nil then
            if entry.removed ~= true or not fields(entry, { descriptor = true, removed = true }) then return false, "Invalid override removal" end
        elseif entry.inherit ~= nil then
            if entry.inherit ~= true or (entry.position ~= nil and not udim(entry.position, false))
                or (entry.size ~= nil and not udim(entry.size, true)) then return false, "Invalid inherited geometry" end
            if entry.clear ~= nil then
                if not fields(entry.clear, optionalProperties) then return false, "Invalid inherited property removal" end
                for property, remove in pairs(entry.clear) do
                    if remove ~= true or entry[property] ~= nil then return false, "Conflicting inherited property removal" end
                end
            end
        elseif entry.clear ~= nil or not udim(entry.position, false) or not udim(entry.size, true) then
            return false, "Invalid position or size"
        end
        if entry.rotation ~= nil and not number(entry.rotation, -360, 360) then return false, "Invalid rotation" end
        if entry.transparency ~= nil and not number(entry.transparency, 0, 1) then return false, "Invalid transparency" end
        if entry.opacity ~= nil and not Config.validateOpacity(entry.opacity, key) then return false, "Invalid opacity" end
        if entry.experimental ~= nil and type(entry.experimental) ~= "boolean" then return false, "Invalid experimental approval" end
        if entry.viewport ~= nil and (not fields(entry.viewport, { w = true, h = true })
            or not number(entry.viewport.w, 1, 32768) or not number(entry.viewport.h, 1, 32768)) then return false, "Invalid saved viewport" end
    end
    return true
end

function Config.validateGroups(groups, global, overrides)
    if not mapCount(groups, MAX_GROUPS) then return false, "Invalid group map" end
    for name, members in pairs(groups) do
        if not text(name, 64) or not name:match("%S") then return false, "Invalid group name" end
        if members ~= false or not overrides then
            if not array(members, MAX_MEMBERS) then return false, "Invalid group member count" end
            local seen = {}
            for _, descriptor in ipairs(members) do
                local valid, reason = Config.validateDescriptor(descriptor)
                if not valid then return false, reason end
                if global and not validBuiltin(descriptor) then return false, "Global groups may contain only built-in controls" end
                local key = Identity.key(descriptor)
                if seen[key] then return false, "Duplicate group member" end
                seen[key] = true
            end
        end
    end
    return true
end

function Config.scopeKey(profile)
    return profile.scope .. ":" .. (profile.scopeId or "*") .. ":" .. (profile.device or "*") .. ":" .. (profile.orientation or "*")
end

function Config.validateProfile(profile)
    if not fields(profile, { id = true, name = true, scope = true, scopeId = true, device = true,
        orientation = true, layout = true, groups = true, preferences = true, resetLayout = true }) then return false, "Invalid profile fields" end
    if not text(profile.id, 128) or not text(profile.name, 64) or not profile.name:match("%S") or not scopes[profile.scope] then return false, "Invalid profile identity or scope" end
    if profile.scope == "global" then
        if profile.scopeId ~= nil or profile.device ~= nil or profile.orientation ~= nil then return false, "Global profile cannot bind an experience or device" end
    elseif not id(profile.scopeId) then return false, "Profile requires a numeric experience/place scope ID" end
    if profile.device ~= nil and profile.device ~= "touch" and profile.device ~= "desktop" then return false, "Invalid device scope" end
    if profile.orientation ~= nil and profile.orientation ~= "portrait" and profile.orientation ~= "landscape" then return false, "Invalid orientation scope" end
    if (profile.scope == "experience" or profile.scope == "place") and (profile.device ~= nil or profile.orientation ~= nil) then return false, "Use device/orientation scope for device overrides" end
    if profile.scope == "device" and (profile.device == nil or profile.orientation ~= nil) then return false, "Device profile requires a device only" end
    if profile.scope == "orientation" and profile.orientation == nil then return false, "Orientation profile requires orientation" end
    if profile.resetLayout ~= nil and (profile.resetLayout ~= true or profile.scope ~= "orientation" or profile.device == nil) then
        return false, "Original-layout overrides require a device-specific orientation profile"
    end
    local valid, reason = Config.validateLayout(profile.layout, profile.scope == "global", true)
    if not valid then return false, reason end
    valid, reason = Config.validateGroups(profile.groups or {}, profile.scope == "global", true)
    if not valid then return false, reason end
    return preferences(profile.preferences or {})
end

function Config.empty() return { version = Config.VERSION, profiles = {}, active = {}, preferences = {} } end

function Config.validate(data)
    if not fields(data, { version = true, profiles = true, active = true, preferences = true, groups = true }) then return false, "Invalid configuration fields" end
    if data.version ~= Config.VERSION then return false, "Incompatible configuration version" end
    if not array(data.profiles, MAX_PROFILES) or not mapCount(data.active, MAX_PROFILES) then return false, "Invalid profile collection" end
    local valid, reason = preferences(data.preferences or {})
    if not valid then return false, reason end
    valid, reason = Config.validateGroups(data.groups or {}, true)
    if not valid then return false, reason end
    local ids = {}
    for _, profile in ipairs(data.profiles) do
        valid, reason = Config.validateProfile(profile)
        if not valid then return false, reason end
        if ids[profile.id] then return false, "Duplicate profile ID" end
        ids[profile.id] = profile
    end
    for key, profileId in pairs(data.active) do
        if type(profileId) ~= "string" or not ids[profileId] or key ~= Config.scopeKey(ids[profileId]) then return false, "Invalid active profile reference" end
    end
    return true
end

function Config.validateState(state)
    if not fields(state, { layout = true, groups = true, preferences = true, resetAll = true })
        or (state.resetAll ~= nil and type(state.resetAll) ~= "boolean") then return false, "Invalid draft state" end
    local valid, reason = Config.validateLayout(state.layout)
    if not valid then return false, reason end
    valid, reason = Config.validateGroups(state.groups or {})
    if not valid then return false, reason end
    return preferences(state.preferences or {})
end

function Config.applies(profile, context)
    if profile.scope == "global" then return true end
    if profile.scope == "experience" then return profile.scopeId == tostring(context.experience) end
    if profile.scopeId ~= tostring(context.place) then return false end
    if profile.scope == "place" then return true end
    if profile.device ~= nil and profile.device ~= context.device then return false end
    if profile.scope == "device" then return profile.device == context.device end
    return profile.scope == "orientation" and profile.orientation == context.orientation
end

function Config.activeProfiles(data, context)
    local active = {}
    for _, profile in ipairs(data.profiles) do
        if Config.applies(profile, context) and data.active[Config.scopeKey(profile)] == profile.id then
            active[#active + 1] = profile
        end
    end
    table.sort(active, function(a, b)
        if a.scope ~= b.scope then return priorities[a.scope] < priorities[b.scope] end
        -- General orientation profiles merge before device-specific ones.
        return a.device == nil and b.device ~= nil
    end)
    return active
end

function Config.resolve(data, context, beforeProfile)
    local layout, prefs, groups = {}, Util.copy(data.preferences or {}), Util.copy(data.groups or {})
    for _, profile in ipairs(Config.activeProfiles(data, context)) do
        if profile.id == beforeProfile then break end
        if profile.resetLayout then layout = {} end
        for key, entry in pairs(profile.layout) do
            if entry.removed then layout[key] = nil
            elseif not entry.inherit then layout[key] = Util.copy(entry)
            elseif layout[key] then
                for _, property in ipairs(Config.LAYOUT_PROPERTIES) do
                    if entry[property] ~= nil then layout[key][property] = Util.copy(entry[property]) end
                    if entry.clear and entry.clear[property] then layout[key][property] = nil end
                end
            end
        end
        for key, value in pairs(profile.preferences or {}) do prefs[key] = Util.copy(value) end
        for key, members in pairs(profile.groups or {}) do
            if members == false then groups[key] = nil else groups[key] = Util.copy(members) end
        end
    end
    return layout, prefs, groups
end

return Config
