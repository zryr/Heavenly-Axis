local Util = require("Util")
local Config = require("Config")
local Identity = require("Identity")
local Capabilities = require("Capabilities")
local Storage = require("Storage")
local Profiles = require("Profiles")
local checks = 0
local function check(condition, message)
    checks = checks + 1
    assert(condition, message or ("check " .. checks .. " failed"))
end
local function entry(name)
    local descriptor = {class = "TextLabel", path = {
        {name = "HUD", class = "ScreenGui", ordinal = 1},
        {name = name, class = "TextLabel", ordinal = 1},
    }}
    return Identity.key(descriptor), {descriptor = descriptor, position = {xs = 0.2, xo = 8, ys = 0.3, yo = 4}, size = {xs = 0, xo = 80, ys = 0, yo = 32}}
end
local key, target = entry("Health")
local missingKey, missingTarget = entry("TemporaryMenu")
local context = {experience = "100", place = "200", device = "touch", orientation = "landscape"}

-- The JSON codec is an explicit mock of Roblox HttpService. Tokens are opaque:
-- this suite tests validation/I/O/transaction behavior, not Roblox's JSON parser.
local codecValues, serial = {}, 0
local http = {}
function http:JSONEncode(data)
    serial = serial + 1
    local token = '{"mockJSON":' .. serial .. '}'
    codecValues[token] = Util.copy(data)
    return token
end
function http:JSONDecode(text)
    assert(codecValues[text], "malformed JSON")
    return Util.copy(codecValues[text])
end
local files, faults, writes = {}, {}, 0
local env = {
    isfile = function(path) if faults.exists then error("denied") end; return files[path] ~= nil end,
    readfile = function(path) if faults.read == path then error("denied") end; assert(files[path], "missing"); return files[path] end,
    writefile = function(path, text)
        writes = writes + 1
        if faults.write == path then error("disk full") end
        files[path] = faults.truncate == path and text:sub(1, 3) or text
    end,
    delfile = function(path) files[path] = nil end,
    setclipboard = function(text) if faults.clipboard then error("clipboard failed") end; envClipboard = text end,
}
local cap = Capabilities.detect(env, {HttpService = http, UserInputService = {TouchEnabled = true, MouseEnabled = false, KeyboardEnabled = false}})
check(writes == 0, "detection must never write probes")
check(cap.storage.status == "Available but unverified" and cap.input.touch, "storage availability and input properties")
check(cap.network.status == "Unsupported", "no optional networking API")
local networkCalls = 0
local networkCap = Capabilities.detect({}, {Game = {HttpGet = function(_, url) networkCalls = networkCalls + 1; return url end}})
check(networkCap.network.status == "Available but unverified" and networkCalls == 0, "game HttpGet capability detection makes no network request")
check(networkCap._get("https://api.github.com/test") == "https://api.github.com/test" and networkCalls == 1, "detected game HttpGet uses correct receiver")
local oldGetfenv, ambientCalls = getfenv, 0
local ambient = {
    isfile = function() return false end, readfile = function() return "" end,
    writefile = function() ambientCalls = ambientCalls + 1 end,
    setclipboard = function() ambientCalls = ambientCalls + 1 end,
    http_request = function() ambientCalls = ambientCalls + 1; return {StatusCode = 200, Body = "metadata"} end,
}
getfenv = function() return ambient end
local ambientCap = Capabilities.detect({}, {})
check(ambientCap.storage.status == "Available but unverified" and ambientCap._functions.writefile == ambient.writefile,
    "executors without getgenv still expose curated script-environment file capabilities")
check(ambientCap.clipboard.status == "Available but unverified" and ambientCap.network.status == "Available but unverified" and ambientCalls == 0,
    "ambient clipboard/network detection performs no capability calls")
local explicitWrite = function() end
check(Capabilities.detect({writefile = explicitWrite}, {})._functions.writefile == explicitWrite,
    "explicit shared-environment capability takes precedence over ambient fallback")
getfenv = oldGetfenv
local storage = Storage.new(cap, http)
local initial, initialMessage = storage:load()
check(initial == nil and initialMessage:find("No saved"), "first launch has no data")
local data = Config.empty()
check(storage:save(data), "first save writes successfully")
check(cap.storage.status == "Supported and verified", "only completed save verifies storage")
local loaded = storage:load()
check(Util.equal(data, loaded), "validated file roundtrip")
local firstRaw = files[Storage.FILES.saved]
data.preferences.grid = true
check(storage:save(data), "subsequent save succeeds")
check(files[Storage.FILES.backup] == firstRaw, "prior known-good configuration retained")
check(files[Storage.FILES.pending] == nil, "staging file cleaned after successful save")
local currentRaw = files[Storage.FILES.saved]
faults.write = Storage.FILES.pending
check(not storage:save(data) and files[Storage.FILES.saved] == currentRaw, "staging write failure preserves current save")
faults.write = Storage.FILES.backup
check(not storage:save(data) and files[Storage.FILES.saved] == currentRaw, "backup failure never touches primary")
faults.write = nil
faults.truncate = Storage.FILES.saved
check(not storage:save(data), "readback failure is reported, never false success")
faults.truncate = nil
files[Storage.FILES.saved] = "broken original"
local damaged = Storage.new(cap, http)
local recovered = damaged:load()
check(recovered ~= nil and damaged.blocked, "valid backup can be offered without erasing damaged original")
check(not damaged:save(data) and files[Storage.FILES.saved] == "broken original", "corrupt data is never silently overwritten")
files[Storage.FILES.saved] = nil
local fresh = Storage.new(cap, http)
check(fresh:save(data), "fresh store can be saved")
faults.exists = true
check(not fresh:save(data), "unknown file existence is treated as failure")
faults.exists = nil
check(fresh:import("not JSON") == nil, "malformed import rejected")
check(fresh:import(string.rep("x", Storage.MAX_BYTES + 1)) == nil, "oversized import rejected before parser")
local unsafe = Config.empty(); unsafe.version = 2
check(fresh:import(http:JSONEncode(unsafe)) == nil, "incompatible version rejected")
unsafe = Config.empty(); unsafe.run = "os.execute('unsafe')"
check(fresh:import(http:JSONEncode(unsafe)) == nil, "code-shaped extra fields rejected")
check(fresh:copy("portable JSON") and envClipboard == "portable JSON", "clipboard API receives exact payload")
faults.clipboard = true
check(not fresh:copy("payload") and cap.clipboard.status == "Failed", "clipboard failures remain visible")
faults.clipboard = nil

local state = {layout = {[key] = target}, groups = {}, preferences = {grid = true}, context = context}
check(fresh:draft(state), "valid contextual draft saved separately")
check(Util.equal(fresh:loadDraft(), state), "draft roundtrip retains context")
check(files[Storage.FILES.saved] ~= files[Storage.FILES.draft], "draft is not saved profile content")
local invalid = Util.copy(state); invalid.script = "return true"
check(not fresh:draft(invalid), "unsafe draft fields rejected")
check(fresh:clearDraft() and fresh:loadDraft() == nil, "explicit discard preserves profiles")
local noDeleteEnv = Util.copy(env); noDeleteEnv.delfile = nil
local noDelete = Storage.new(Capabilities.detect(noDeleteEnv, {}), http)
check(noDelete:draft(state) and noDelete:clearDraft() and noDelete:loadDraft() == nil, "draft discard supports write-only tombstone when deletion absent")
check(noDelete:draft(state), "new draft can replace explicit discard tombstone")
files[Storage.FILES.draft] = "corrupt draft"
check(not fresh:draft(state) and files[Storage.FILES.draft] == "corrupt draft", "damaged draft preserved until explicit discard")
check(fresh:clearDraft(), "explicit discard can clear damaged draft")
local scopedContext = Util.copy(context)
local contextual = Storage.new(cap, http, nil, scopedContext)
check(contextual:draft(state), "contextual draft recorded independently")
local landscapePath = contextual:_draftPath()
check(landscapePath ~= Storage.FILES.draft and files[landscapePath], "contextual filenames use safe bounded scope fields")
scopedContext.orientation = "portrait"
check(contextual:loadDraft() == nil, "another orientation does not inherit unsaved recovery")
local portraitState = Util.copy(state); portraitState.context = Util.copy(scopedContext)
check(contextual:draft(portraitState), "portrait recovery can coexist with landscape")
local portraitPath = contextual:_draftPath()
check(files[portraitPath] and files[landscapePath], "orientation drafts never overwrite one another")
check(not contextual:draft(state), "stale scheduled draft cannot overwrite a changed context")
check(contextual:clearDraft() and files[landscapePath], "clearing current orientation retains other recovery")
scopedContext.orientation = "landscape"
check(Util.equal(contextual:loadDraft(), state), "live context selects original recovery again")
scopedContext.place = "201"
check(contextual:loadDraft() == nil, "place recovery is isolated")
check(fresh:draft(state), "legacy generic draft slot remains supported")
local foreignState = Util.copy(state); foreignState.context.place = "999"
check(not fresh:draft(foreignState), "generic slot never silently overwrites foreign context")
check(fresh:clearDraft(), "generic slot can be explicitly discarded")

local memoryCap = Capabilities.detect({}, {})
local memoryStorage = Storage.new(memoryCap, http)
local memorySaved, memoryMessage = memoryStorage:save(Config.empty())
check(not memorySaved and memoryMessage:find("memory"), "no storage reports memory-only fallback")
check(not memoryStorage:copy("x"), "clipboard fallback remains usable through JSON text")
local profiles = Profiles.new(Config.empty(), memoryStorage, context)
local created = profiles:create("Landscape controls", "orientation")
check(created and created.scopeId == context.place and created.device == "touch", "specific profiles bind current place/device")
check(profiles:active() == nil, "create does not activate")
local preview = profiles:beginPreview(created.id)
check(preview and profiles:active() == nil and profiles.preview, "preview never changes active map")
check(profiles:cancelPreview() and profiles:active() == nil, "preview cancellation leaves active unchanged")
check(profiles:beginPreview(created.id) and profiles:applyPreview() and profiles:active().id == created.id, "explicit Apply activates candidate")
local saved, message, accepted = profiles:save({[key] = target, [missingKey] = missingTarget}, {}, {grid = true})
check(not saved and accepted and message:find("memory"), "save result accurately distinguishes valid memory checkpoint from durability")
check(profiles:active().layout[key] ~= nil, "in-memory checkpoint remains exportable")
profiles:save({[key] = target, [missingKey] = missingTarget}, {}, {})
check(profiles:active().layout[missingKey] ~= nil, "full authoritative state retains unresolved entries")
profiles:save({[key] = target}, {}, {})
check(profiles:active().layout[missingKey] == nil, "deliberate removal or remapping is not resurrected from prior profile")
check(profiles:export() ~= nil, "manual JSON export available")
check(profiles:rename(created.id, "Renamed") and profiles:active().name == "Renamed", "profile rename")
check(not profiles:rename(created.id, "\n"), "invalid names rejected")
local duplicate = profiles:duplicate(created.id)
check(duplicate and duplicate.id ~= created.id and Util.equal(duplicate.layout, profiles:active().layout), "duplicate copies layout without aliasing identity")
check(not profiles:delete(duplicate.id, false), "deletion requires confirmation")
check(profiles:delete(duplicate.id, true) and #profiles:list() == 1, "confirmed delete removes group definition only")
local export = profiles:export()
local imported = profiles:import(export)
check(imported and #imported.profiles == 1, "import returns validated portable configuration")
imported.profiles[1].name = "Imported name"
local altered = http:JSONEncode(imported)
check(profiles:beginImport(altered) == nil, "conflicting import requires explicit overwrite confirmation")
local before = Util.copy(profiles.data)
check(profiles:beginImport(altered, true) and Util.equal(before, profiles.data), "confirmed import still previews before mutation")
check(profiles:cancelPreview() and Util.equal(before, profiles.data), "cancel import preserves exact active configuration")
check(profiles:beginImport(altered, true) and profiles:applyPreview() and profiles:active().name == "Imported name", "Apply commits accepted import in memory")
profiles:suspend(true)
check(next((profiles:resolve())) == nil and profiles:active() ~= nil, "suspension preserves profiles while suppressing layout")
profiles:suspend(false)
check(profiles:resolve()[key] ~= nil, "resuming reuses saved layout")
context.orientation = "portrait"
check(profiles:active() == nil and #profiles:list() == 0, "orientation changes use live current context")
local unrelated = profiles:beginPreview(created.id)
check(unrelated == nil, "profiles from unrelated scope cannot be activated")
context.orientation = "landscape"
local global = profiles:create("Builtins only", "global")
profiles:beginPreview(global.id); profiles:applyPreview()
check(profiles:active().id == global.id and #profiles.data.profiles == 2,
    "selecting global explicitly deactivates higher current-context slots without deleting definitions")
local okGlobal, _, acceptedGlobal = profiles:save({[key] = target}, {}, {})
check(not okGlobal and not acceptedGlobal and next(profiles:active().layout) == nil, "global saves cannot leak game-specific elements")
local layers = Profiles.new(Config.empty(), memoryStorage, context)
local globalLayer = layers:create("Shared defaults", "global")
local experienceLayer = layers:create("Experience", "experience")
local placeLayer = layers:create("Place", "place")
local deviceLayer = layers:create("Touch", "device")
local orientationLayer = layers:create("Landscape", "orientation")
for _, layer in ipairs({ globalLayer, experienceLayer, placeLayer, deviceLayer, orientationLayer }) do
    check(layers:beginPreview(layer.id) and layers:applyPreview(), "scope layers activate from general to specific")
end
local layeredBefore = Util.copy(layers.data)
check(layers:active().id == orientationLayer.id, "most-specific active layer initially wins")
check(layers:beginPreview(globalLayer.id) ~= nil and layers:active().id == orientationLayer.id
    and layers.preview.data.active[Config.scopeKey(orientationLayer)] == nil,
    "global preview removes higher references only in candidate")
check(layers:cancelPreview() and Util.equal(layeredBefore, layers.data), "cancel global preview preserves exact higher-scope activation")
check(layers:beginPreview(globalLayer.id) and layers:applyPreview() and layers:active().id == globalLayer.id,
    "Apply makes global editable even with saved place/device/orientation definitions")
check(#layers.data.profiles == 5 and layers.data.active[Config.scopeKey(placeLayer)] == nil,
    "layer selection never deletes profile definitions")
local jumpDescriptor = { class = "ImageButton", builtin = "JumpButton", path = {
    { name = "TouchGui", class = "ScreenGui", ordinal = 1 },
    { name = "TouchControlFrame", class = "Frame", ordinal = 1 },
    { name = "JumpButton", class = "ImageButton", ordinal = 1 } } }
local jumpKey, jumpEntry = Identity.key(jumpDescriptor), Util.copy(target)
jumpEntry.descriptor = jumpDescriptor
local _, _, globalAccepted = layers:save({ [jumpKey] = jumpEntry }, {}, { grid = true })
check(globalAccepted and layers:active().id == globalLayer.id and layers:active().layout[jumpKey],
    "saving selected global defaults writes recognized builtins into global layer")
check(layers:beginPreview(placeLayer.id) and layers:applyPreview() and layers:active().id == placeLayer.id,
    "higher definitions can be explicitly reactivated after editing defaults")
local empty = Profiles.new(Config.empty(), memoryStorage, context)
empty:save({[key] = target}, {}, {})
check(empty:active() and empty:active().scope == "place", "Save creates a place profile only when none is active")
return checks
