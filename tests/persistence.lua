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
        local truncate = faults.truncate == path or faults.truncateOnce == path
        if faults.truncateOnce == path then faults.truncateOnce = nil end
        files[path] = truncate and text:sub(1, 3) or text
    end,
    delfile = function(path) files[path] = nil end,
    setclipboard = function(text)
        if faults.clipboard == "declined" then return false end
        if faults.clipboard then error("clipboard failed") end
        envClipboard = text
    end,
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
faults.truncateOnce = Storage.FILES.saved
local rollbackSaved, rollbackReason = storage:save(data)
check(not rollbackSaved and rollbackReason:find("restored and verified") and files[Storage.FILES.saved] == currentRaw,
    "a failed final write verifies restoration of the prior checkpoint when possible")
faults.truncate = Storage.FILES.saved
check(not storage:save(data), "readback failure is reported, never false success")
faults.truncate = nil
files[Storage.FILES.saved] = "broken original"
local damaged = Storage.new(cap, http)
local recovered = damaged:load()
check(recovered ~= nil and damaged.blocked, "valid backup can be offered without erasing damaged original")
check(not damaged:save(data) and files[Storage.FILES.saved] == "broken original", "corrupt data is never silently overwritten")
files[Storage.FILES.saved] = nil
check(damaged:save(data) and not damaged.blocked, "manually moving the damaged file allows a retry in the same editor session")
files[Storage.FILES.saved] = nil
local interruptedFirstSave = Storage.new(cap, http)
faults.truncateOnce = Storage.FILES.saved
check(not interruptedFirstSave:save(data) and files[Storage.FILES.saved] and files[Storage.FILES.pending],
    "an incomplete first write reports failure and preserves the staged configuration")
check(interruptedFirstSave:save(data) and Util.equal(interruptedFirstSave:load(), data),
    "a retry replaces the exact incomplete first write created in this session")
files[Storage.FILES.saved] = nil
faults.truncateOnce = Storage.FILES.saved
check(not interruptedFirstSave:save(data), "a later first write records an incomplete file for retry")
files[Storage.FILES.saved] = "different damaged contents"
check(not interruptedFirstSave:save(data) and files[Storage.FILES.saved] == "different damaged contents",
    "a retry preserves a damaged file that differs from its own incomplete write")
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
faults.clipboard = "declined"
check(not fresh:copy("payload") and cap.clipboard.status == "Failed", "an explicit clipboard refusal is reported as failure")
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
local pinnedState = Util.copy(state)
pinnedState.preferences.grid = false
check(contextual:draft(pinnedState, context) and Util.equal(contextual:loadDraft(context), pinnedState),
    "an explicitly pinned edit can update its original landscape draft from portrait")
check(contextual:clearDraft() and files[landscapePath], "clearing current orientation retains other recovery")
scopedContext.orientation = "landscape"
check(Util.equal(contextual:loadDraft(), pinnedState), "live context selects original recovery again")
local rawLandscapeDraft = files[landscapePath]
faults.read = landscapePath
local unreadableDraft, _, unreadableBlocked = contextual:loadDraft()
check(not unreadableDraft and unreadableBlocked, "a known present but unreadable draft is flagged for explicit recovery")
faults.read = nil
files[landscapePath] = "corrupt contextual draft"
local damagedDraft, _, damagedBlocked = contextual:loadDraft()
local _, _, unrelatedBlocked = contextual:loadDraft(portraitState.context)
check(not damagedDraft and damagedBlocked and not unrelatedBlocked, "only the damaged draft's own orientation reports a recovery blocker")
local savedBeforeDiscard = files[Storage.FILES.saved]
check(contextual:clearDraft() and files[landscapePath] == nil and files[Storage.FILES.saved] == savedBeforeDiscard,
    "explicitly discarding a damaged contextual draft preserves the saved profile")
local wrongContextRaw = http:JSONEncode({version = Config.VERSION, draft = true, state = portraitState})
files[landscapePath] = wrongContextRaw
local wrongDraft, _, wrongBlocked = contextual:loadDraft()
check(not wrongDraft and not wrongBlocked and not contextual:clearDraft() and files[landscapePath] == wrongContextRaw,
    "misfiled drafts from another orientation are neither offered nor deleted")
files[landscapePath] = rawLandscapeDraft
scopedContext.place = "201"
check(contextual:loadDraft() == nil, "place recovery is isolated")
check(fresh:draft(state), "legacy generic draft slot remains supported")
local foreignState = Util.copy(state); foreignState.context.place = "999"
check(not fresh:draft(foreignState), "generic slot never silently overwrites foreign context")
check(fresh:clearDraft(), "generic slot can be explicitly discarded")

local slowContext = Util.copy(context)
slowContext.place = "300"
local slowEnv = Util.copy(env)
function slowEnv.writefile(path, text)
    if path:match("%.landscape%.json$") then coroutine.yield("write in progress") end
    env.writefile(path, text)
end
local slowStorage = Storage.new(Capabilities.detect(slowEnv, {}), http, nil, slowContext)
local slowState = Util.copy(state)
slowState.context = Util.copy(slowContext)
local draftWriter = coroutine.create(function() return slowStorage:draft(slowState) end)
local started, suspension = coroutine.resume(draftWriter)
check(started and suspension == "write in progress", "mock draft writer pauses inside its file operation")
local clearedWhileBusy, _, clearBusy = slowStorage:clearDraft()
local wroteWhileBusy, _, writeBusy = slowStorage:draft(slowState)
local loadedWhileBusy, _, classifiedDamage = slowStorage:loadDraft()
check(not clearedWhileBusy and clearBusy and not wroteWhileBusy and writeBusy and not loadedWhileBusy and not classifiedDamage,
    "same-context writes and clears cannot race, and an active write is not classified as damage")
local otherDraft = Util.copy(slowState)
otherDraft.context.orientation = "portrait"
check(slowStorage:draft(otherDraft, otherDraft.context), "an active landscape write does not lock portrait draft storage")
local finished, recorded = coroutine.resume(draftWriter)
check(finished and recorded and Util.equal(slowStorage:loadDraft(), slowState), "the first write completes with the intended data")
check(slowStorage:clearDraft() and slowStorage:loadDraft() == nil and slowStorage:loadDraft(otherDraft.context),
    "cleanup can retry after the write without clearing the other orientation")

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
local renameExport = profiles:import(profiles:export())
check(renameExport.profiles[1].name == "Landscape controls", "export omits unsaved profile metadata")
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
    "selecting global sets a save target without deleting higher definitions")
local okGlobal, _, acceptedGlobal = profiles:save({[key] = target, [missingKey] = missingTarget}, {}, {})
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
    and layers.preview.overlaid and layers.preview.data.active[Config.scopeKey(orientationLayer)] == orientationLayer.id,
    "global preview keeps higher overrides active in both the current and candidate configurations")
check(layers:cancelPreview() and Util.equal(layeredBefore, layers.data), "cancel global preview preserves exact higher-scope activation")
check(layers:beginPreview(globalLayer.id) and layers:applyPreview() and layers:active().id == globalLayer.id,
    "Apply makes global editable even with saved place/device/orientation definitions")
check(#layers.data.profiles == 5 and layers.data.active[Config.scopeKey(placeLayer)] == placeLayer.id,
    "layer selection retains unrelated active slots and definitions")
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
    "higher active layers can become the explicit save target")
local empty = Profiles.new(Config.empty(), memoryStorage, context)
empty:save({[key] = target}, {}, {})
check(empty:active() and empty:active().scope == "place", "Save creates a place profile only when none is active")

local function activeData(...)
    local value = Config.empty()
    value.profiles = {...}
    for _, profile in ipairs(value.profiles) do value.active[Config.scopeKey(profile)] = profile.id end
    return value
end
local experienceProfile = {id = "experience", name = "Experience", scope = "experience", scopeId = context.experience,
    layout = {[key] = Util.copy(target), [missingKey] = Util.copy(missingTarget)}, groups = {HUD = {target.descriptor}}, preferences = {grid = true}}
experienceProfile.layout[key].rotation = 13
local placeProfile = {id = "place", name = "Place", scope = "place", scopeId = context.place, layout = {}, groups = {}, preferences = {}}
local inherited = Profiles.new(activeData(experienceProfile, placeProfile), memoryStorage, context)
local resolvedLayout, resolvedPreferences, resolvedGroups = inherited:resolve()
resolvedLayout[key].position.xo = 28
local _, _, deltaAccepted = inherited:save(resolvedLayout, resolvedGroups, resolvedPreferences)
local positionPatch = inherited:active().layout[key]
check(deltaAccepted and positionPatch.inherit and positionPatch.position.xo == 28 and positionPatch.size == nil and positionPatch.rotation == nil,
    "editing position persists only position while inherited size and rotation remain live")
check(inherited:active().layout[missingKey] == nil and not next(inherited:active().groups) and not next(inherited:active().preferences),
    "untouched inherited elements, groups, and preferences remain in their source scope")
local decodedPatches = memoryStorage:import(inherited:export())
check(decodedPatches and Util.equal(decodedPatches, inherited.data), "new inherited overrides survive validated JSON export/import")

check(inherited:beginPreview(experienceProfile.id) and inherited:applyPreview()
    and inherited:resolve()[key].position.xo == 28 and inherited:active().id == experienceProfile.id,
    "selecting a broader save target keeps place geometry in effect")
local oldDraftReference = inherited:draftReference()
local mergedLayout, mergedPreferences, mergedGroups = inherited:resolve()
mergedLayout[key].size.xo = 125
local _, _, parentUpdated = inherited:save(mergedLayout, mergedGroups, mergedPreferences)
check(parentUpdated and inherited:resolve()[key].size.xo == 125 and inherited:resolve()[key].position.xo == 28,
    "a broader size edit remains inherited through a narrower position patch")
check(not inherited:matchesDraftReference(oldDraftReference), "changed profile contents invalidate a previously recorded draft reference")
local currentReference = inherited:draftReference()
local restart = Profiles.new(inherited.data, memoryStorage, context)
check(restart:active().id == placeProfile.id and restart:matchesDraftReference(currentReference)
    and restart:setEditTarget(currentReference.profileId), "broader draft targets can be validated and restored after restarting")
check(restart:active().id == experienceProfile.id, "recoverable draft keeps its explicit scope")
local withReference = Util.copy(state)
withReference.reference = currentReference
check(fresh:draft(withReference) and Util.equal(fresh:loadDraft(), withReference), "draft references are validated and round trip separately from profiles")
check(fresh:clearDraft(), "draft reference can be cleared independently")

local beforeConflict = Util.copy(inherited.data)
local conflictingLayout, conflictingPreferences, conflictingGroups = inherited:resolve()
conflictingLayout[key].position.xo = 100
local conflictSaved, conflictMessage, conflictAccepted = inherited:save(conflictingLayout, conflictingGroups, conflictingPreferences)
check(not conflictSaved and not conflictAccepted and conflictMessage:find("more specific") and Util.equal(beforeConflict, inherited.data),
    "a broader scope cannot silently save an edit masked by a more specific profile")

check(inherited:setEditTarget(placeProfile.id), "switch write target to the applicable place profile")
local clippedLayout, clippedPreferences, clippedGroups = inherited:resolve()
clippedLayout[key].position.xo = target.position.xo
clippedLayout[missingKey], clippedGroups.HUD = nil, nil
local _, _, removalsAccepted = inherited:save(clippedLayout, clippedGroups, clippedPreferences)
check(removalsAccepted and inherited:active().layout[key] == nil and inherited:active().layout[missingKey].removed
    and inherited:active().groups.HUD == false, "matching inherited values clear overrides and intentional removals mask them")
local clippedResolved, _, clippedResolvedGroups = inherited:resolve()
check(clippedResolved[missingKey] == nil and clippedResolvedGroups.HUD == nil, "masked entries remain absent after resolving active layers")
local otherContext = Util.copy(context); otherContext.place = "201"
local otherLayout, _, otherGroups = inherited:resolve(otherContext)
check(otherLayout[missingKey] and otherGroups.HUD, "place-specific removal does not erase another place's inherited defaults")

local oldPlace = Util.copy(placeProfile)
oldPlace.layout[key] = Util.copy(target)
local oldV3 = activeData(experienceProfile, oldPlace)
local oldStorage = Storage.new(cap, http)
check(oldStorage:save(oldV3), "legacy V3 full-override configuration accepted on disk")
local oldRaw = files[Storage.FILES.saved]
local oldLoaded = oldStorage:load()
local migrating = Profiles.new(oldLoaded, oldStorage, context)
check(Util.equal(oldLoaded, oldV3) and migrating:resolve()[key].rotation == nil,
    "loading an existing V3 checkpoint preserves legacy full-entry replacement semantics")
local changedLayout, changedPreferences, changedGroups = migrating:resolve()
changedLayout[missingKey].position.xo = 95
faults.write = Storage.FILES.pending
local failed, _, acceptedFailure = migrating:save(changedLayout, changedGroups, changedPreferences)
check(not failed and not acceptedFailure and Util.equal(migrating.data, oldV3)
    and Util.equal(oldStorage:import(migrating:export()), oldV3), "failed Save retains both the previous configuration and its export")
faults.write = nil
check(migrating:save(changedLayout, changedGroups, changedPreferences) and files[Storage.FILES.backup] == oldRaw,
    "first incremental update preserves the previous raw V3 file as backup")
local migrated = oldStorage:load()
check(migrated.profiles[2].layout[missingKey].inherit and Util.equal(migrated.profiles[2].layout[key], oldPlace.layout[key]),
    "incremental save adds only the edited override and preserves untouched legacy entries")

local movedScope = Util.copy(experienceProfile)
movedScope.scope, movedScope.scopeId, movedScope.device, movedScope.orientation = "orientation", context.place, context.device, context.orientation
local movedJson = http:JSONEncode(activeData(movedScope))
check(not migrating:beginImport(movedJson), "moving an imported profile ID to a new scope requires confirmation")
check(migrating:beginImport(movedJson, true) and migrating:applyPreview()
    and migrating.data.active[Config.scopeKey(experienceProfile)] == nil
    and migrating.data.active[Config.scopeKey(movedScope)] == movedScope.id
    and migrating.data.active[Config.scopeKey(oldPlace)] == oldPlace.id,
    "confirmed import moves its stale activation without dropping unrelated scopes")

local previousApp, previousWarn, previousGetgenv = package.loaded.App, warn, getgenv
local opened, warnings, notice = 0, {}, nil
local existingEditor = {alive = true, version = "3.1.0", pendingEdits = true}
function existingEditor:Open() opened = opened + 1 end
function existingEditor:status(message) notice = message end
local sharedEditorEnvironment = {__HEAVENLY_AXIS_V3 = existingEditor}
package.loaded.App = {VERSION = "3.1.1", new = function() error("should reuse the existing editor") end}
warn = function(message) warnings[#warnings + 1] = message end
getgenv = function() return sharedEditorEnvironment end
local startup = assert(loadfile("src/Bootstrap.lua"))
check(startup() == existingEditor and existingEditor.pendingEdits and opened == 1
    and #warnings == 1 and notice == warnings[1] and notice:find("rejoin to start 3.1.1", 1, true),
    "re-running a different version preserves live edits and tells the user how to activate the new release")
existingEditor.version = "3.1.1"
check(startup() == existingEditor and opened == 2 and #warnings == 1, "re-running the same version opens it without a version warning")
package.loaded.App, warn, getgenv = previousApp, previousWarn, previousGetgenv
return checks
