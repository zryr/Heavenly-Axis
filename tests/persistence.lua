local Util = require("Util")
local Config = require("Config")
local Identity = require("Identity")
local Capabilities = require("Capabilities")
local Storage = require("Storage")
local Profiles = require("Profiles")
local EditorPreferences = require("EditorPreferences")
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
        if faults.erase == path then
            files[path] = nil
            error("file replaced unsuccessfully")
        end
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
do
    local repeatedWrites = writes
    local alreadySaved, message = storage:save(Util.copy(data))
    check(alreadySaved and message:find("already saved") and writes == repeatedWrites
        and files[Storage.FILES.saved] == currentRaw and files[Storage.FILES.backup] == firstRaw,
        "repeated Save verifies the existing profile without rotating its previous backup")
end
data.preferences.snapping = true
faults.write = Storage.FILES.pending
check(not storage:save(data) and files[Storage.FILES.saved] == currentRaw, "staging write failure preserves current save")
faults.write = Storage.FILES.backup
check(not storage:save(data) and files[Storage.FILES.saved] == currentRaw, "backup failure never touches primary")
faults.write = nil
faults.truncateOnce = Storage.FILES.backup
check(not storage:save(data) and files[Storage.FILES.saved] == currentRaw and files[Storage.FILES.backup] == firstRaw,
    "a partial backup write restores the older backup and leaves the current save intact")
faults.truncateOnce = Storage.FILES.saved
local rollbackSaved, rollbackReason = storage:save(data)
check(not rollbackSaved and rollbackReason:find("restored and verified") and files[Storage.FILES.saved] == currentRaw
    and files[Storage.FILES.backup] == firstRaw,
    "a failed final write restores the prior checkpoint and keeps the older backup when possible")
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

local function checkCompetingSaves()
    local paths = Storage.FILES
    local original, backup = files[paths.saved], files[paths.backup]
    local legacy = {version = Config.VERSION, profiles = {}, active = {}}
    local legacyRaw = http:JSONEncode(legacy)
    files[paths.saved] = legacyRaw
    local firstStorage, secondStorage = Storage.new(cap, http), Storage.new(cap, http)
    local secondContext = Util.copy(context)
    secondContext.place = "777"
    local first, second = Profiles.new(firstStorage:load(), firstStorage, context), Profiles.new(secondStorage:load(), secondStorage, secondContext)
    local writesBefore = writes
    check(first:save({}, {}, {}) and files[paths.saved] == legacyRaw and writes == writesBefore,
        "an unchanged checkpoint with omitted legacy fields remains valid and is not rewritten")
    check(first:save({[key] = target}, {}, {}), "the first editor can persist its game layout")
    local newest = files[paths.saved]
    local staleSaved, reason, accepted = second:save({[missingKey] = missingTarget}, {}, {})
    check(not staleSaved and not accepted and reason:find("another session") and files[paths.saved] == newest,
        "a concurrent or stale editor cannot overwrite unrelated saved layout scopes")
    check(Util.equal(secondStorage:import(second:export()), legacy) and second:active() == nil,
        "a stale Save preserves the local checkpoint and does not activate the rejected profile")

    local external = Config.empty()
    external.preferences.grid = false
    local externalRaw = http:JSONEncode(external)
    local pendingBackup = files[paths.backup]
    local racingEnv = Util.copy(env)
    function racingEnv.writefile(path, content)
        env.writefile(path, content)
        if path == paths.pending then files[paths.saved] = externalRaw end
    end
    local racingStorage = Storage.new(Capabilities.detect(racingEnv, {}), http)
    local racing, racingError = racingStorage:save(Config.empty())
    check(not racing and racingError:find("changed during Save") and files[paths.saved] == externalRaw and files[paths.backup] == pendingBackup,
        "a primary file changed during staging is preserved along with the preceding backup")

    faults.erase = paths.saved
    check(not firstStorage:save(Config.empty()) and files[paths.saved] == nil and files[paths.backup] == externalRaw,
        "a failed final write and rollback can leave the verified backup as the only primary recovery")
    faults.erase = nil
    local beforeRecovery = writes
    local recovered, recoveryMessage = Storage.new(cap, http):load()
    check(Util.equal(recovered, external) and recoveryMessage:find("validated backup") and writes == beforeRecovery
        and files[paths.saved] == nil, "startup uses a verified backup when the primary disappeared without recreating files")
    files[paths.saved], files[paths.backup], files[paths.pending] = original, backup, nil
end
checkCompetingSaves()

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

local function checkEditorPreferences()
    local editorFiles = Storage.EDITOR_FILES
    local hudRaw, hudBackup = files[Storage.FILES.saved], files[Storage.FILES.backup]
    local fileWrites = writes
    local editor = EditorPreferences.new(oldStorage, context)
    check(editor.data.smartSelection and editor.data.skipTransparent and not editor.data.onboardingCompleted and writes == fileWrites,
        "legacy V3 installations use Smart Layers and first-run defaults without rewriting storage")
    local changedEditor, editorReason, durableEditor = editor:setPreference("smartSelection", false)
    check(changedEditor and durableEditor and editorReason == nil and not editor.data.smartSelection,
        "a Smart Selection preference is saved and verified independently")
    check(editor:setPreference("skipTransparent", false) and editor:setPreference("onboardingCompleted", true),
        "filtering and finishing onboarding use the editor document")
    local completionWrites = writes
    check(editor:setPreference("onboardingCompleted", true) and writes == completionWrites,
        "replaying completed onboarding is a no-op for persistence")
    check(files[Storage.FILES.saved] == hudRaw and files[Storage.FILES.backup] == hudBackup,
        "editor preferences and onboarding never replace saved HUDs or backups")
    check(not oldStorage:import(files[editorFiles.saved]) and not Config.validateEditorPreferences(migrated),
        "editor metadata is not accepted as a portable layout or vice versa")

    check(editor:setElementFlag("ignored", target.descriptor, true) and editor:setElementFlag("locked", target.descriptor, true),
        "a layer can be independently ignored and locked")
    local recreated = Util.copy(target.descriptor)
    local ignored, locked = editor:elementFlags(recreated, key)
    check(ignored and locked and #editor:listElementFlags("ignored") == 1 and #editor:listElementFlags("locked") == 1,
        "stable preferences match an exact recreated descriptor and remain available for explicit inspection")
    local detached = editor:listElementFlags("ignored")
    detached[1].path[2].name = "Renamed copy"
    check(editor:elementFlags(recreated, key), "preference lists do not expose mutable stored identities")
    local ambiguousLayer = Util.copy(recreated)
    ambiguousLayer.ambiguous = true
    local changedLayer = Util.copy(recreated)
    changedLayer.path[2].ordinal = 2
    check(not editor:elementFlags(ambiguousLayer, key) and not editor:setElementFlag("locked", ambiguousLayer, true)
        and not editor:elementFlags(changedLayer, key), "ambiguous or different layers cannot inherit a saved preference")
    local reoriented = Util.copy(context)
    reoriented.orientation, reoriented.device = "portrait", "desktop"
    local reopened = EditorPreferences.new(oldStorage, reoriented)
    local reopenedIgnore, reopenedLock = reopened:elementFlags(recreated)
    check(reopenedIgnore and reopenedLock and reopened.data.onboardingCompleted and not reopened.data.skipTransparent,
        "reopening preserves layer rules within the same place and completes onboarding across orientations")
    local differentPlace, differentExperience = Util.copy(context), Util.copy(context)
    differentPlace.place = "201"
    differentExperience.experience = "101"
    local otherEditor = EditorPreferences.new(oldStorage, differentPlace)
    check(not otherEditor:elementFlags(recreated) and not EditorPreferences.new(oldStorage, differentExperience):elementFlags(recreated),
        "matching identities from another place or experience do not inherit rules")
    check(otherEditor:setElementFlag("ignored", recreated, true), "another place can independently persist the same identity")
    local staleAccepted, staleMessage, staleDurable = reopened:clearElementFlags("ignored")
    check(staleAccepted and not staleDurable and staleMessage:find("another session"),
        "a stale editor applies a preference locally without overwriting newer saved rule sets")
    reopened = EditorPreferences.new(oldStorage, context)
    check(reopened:clearElementFlags("ignored"), "the ignored list can be safely cleared after reading current preferences")
    local clearedIgnore, retainedLock = reopened:elementFlags(recreated)
    check(not clearedIgnore and retainedLock and EditorPreferences.new(oldStorage, differentPlace):elementFlags(recreated),
        "clearing ignored layers preserves locks and ignores from other places")
    check(reopened:setElementFlag("locked", recreated, false) and #reopened:listElementFlags("locked") == 0,
        "unlock remains available even when the layer is no longer present")

    local portraitEditor = Util.copy(context)
    portraitEditor.orientation = "portrait"
    local landscapePosition = {x = 0.3, y = 0.6}
    local portraitPosition = {x = 1, y = 0.5, dock = "right"}
    check(reopened:setPanelPlacement("inspector", landscapePosition, context)
        and reopened:setPanelPlacement("inspector", portraitPosition, portraitEditor)
        and reopened:setPanelPlacement("toolbar", {x = 0.7, y = 0}, context)
        and reopened:setPanelPlacement("workspace", {x = 0.4, y = 0.3}, context)
        and reopened:setPanelPlacement("launcher", {x = 0, y = 0.3}, context), "four editor panels store individual positions")
    landscapePosition.x = 0.9
    local withPlacements = EditorPreferences.new(oldStorage, context)
    check(withPlacements:panelPlacement("inspector").x == 0.3
        and Util.equal(withPlacements:panelPlacement("inspector", portraitEditor), portraitPosition)
        and not withPlacements:panelPlacement("inspector", reoriented),
        "editor panel positions persist independently by device and orientation without aliasing input")
    check(not reopened.data.panelDocking and reopened:setPreference("panelDocking", true)
        and not reopened:setPanelPlacement("inspector", {x = 1.1, y = 0})
        and not reopened:setPanelPlacement("workspace", {x = 0, y = 0, dock = "center"}),
        "docking is optional and editor placements are validated before writing")
    check(reopened:setTutorialProgress("quick", 2) and reopened:setTutorialProgress("tour", 5)
        and not reopened:setTutorialProgress("tour", 17) and not reopened:setTutorialProgress("quick", 2.5),
        "quick start and guided tour have separate bounded progress")
    check(reopened:resetPanelLayout() and reopened.data.panelLayoutReset
        and not reopened.data.panelDocking and not reopened:panelPlacement("inspector", portraitEditor)
        and not reopened:panelPlacement("launcher") and reopened:tutorialProgress("tour") == 5,
        "Reset Editor Layout clears panel placements and docking without changing lesson progress")
    check(reopened:setTutorialProgress("quick", nil)
        and EditorPreferences.new(oldStorage, context):tutorialProgress("quick") == nil
        and EditorPreferences.new(oldStorage, context):tutorialProgress("tour") == 5
        and EditorPreferences.new(oldStorage, context).data.onboardingCompleted
        and EditorPreferences.new(oldStorage, differentPlace):elementFlags(recreated),
        "clearing completed Quick Start progress preserves guided progress, completion, and independent layer rules")
    check(files[Storage.FILES.saved] == hudRaw and files[Storage.FILES.backup] == hudBackup,
        "panel movements and learning progress never commit HUD state")

    local storedPreferencesRaw = files[editorFiles.saved]
    faults.write = editorFiles.pending
    local failedEditorAccepted, failedEditorMessage, failedEditorDurable = reopened:setPreference("skipTransparent", true)
    check(failedEditorAccepted and reopened.data.skipTransparent and not failedEditorDurable
        and failedEditorMessage:find("session only") and files[editorFiles.saved] == storedPreferencesRaw,
        "an editor preference write failure is honest and keeps the last verified file")
    faults.write = nil
    local _, _, retriedEditorDurable = reopened:setPreference("skipTransparent", true)
    check(retriedEditorDurable and EditorPreferences.new(oldStorage, context).data.skipTransparent,
        "repeating a preference after a transient write failure retries persistence")
    local validPrimary, writesBeforeRecovery = files[editorFiles.saved], writes
    files[editorFiles.saved] = nil
    local missingPrimary, recoveredFromBackup = oldStorage:loadEditorPreferences()
    check(missingPrimary.onboardingCompleted and recoveredFromBackup:find("validated backup")
        and files[editorFiles.saved] == nil and writes == writesBeforeRecovery,
        "missing editor preference files recover the prior settings without changing disk")
    files[editorFiles.saved] = validPrimary
    local corruptEditorFile = "damaged editor preference document"
    files[editorFiles.saved] = corruptEditorFile
    local recoveryLog
    local recoveredEditor = EditorPreferences.new(oldStorage, context, function(message) recoveryLog = message end)
    check(recoveryLog and recoveryLog:find("backup") and recoveredEditor.data.onboardingCompleted,
        "an invalid editor document can start from its validated previous backup")
    local _, corruptPreferenceMessage, corruptPreferenceDurable = recoveredEditor:setPreference("smartSelection", true)
    check(not corruptPreferenceDurable and corruptPreferenceMessage:find("preserved") and files[editorFiles.saved] == corruptEditorFile
        and files[Storage.FILES.saved] == hudRaw, "a damaged preference file is preserved and isolated from the HUD save")
    local invalidEditorDocument = Config.emptyEditorPreferences()
    invalidEditorDocument.scopes[Config.editorScope(context)] = {wrong = {descriptor = recreated, ignored = true}}
    check(not Config.validateEditorPreferences(invalidEditorDocument) and not oldStorage:saveEditorPreferences(invalidEditorDocument),
        "editor preferences validate descriptor keys before any write")
    local inMemory = EditorPreferences.new(memoryStorage, context)
    local acceptedTutorial, tutorialFallback, durableTutorial = inMemory:setPreference("onboardingCompleted", true)
    check(acceptedTutorial and not durableTutorial and tutorialFallback:find("session only") and inMemory.data.onboardingCompleted
        and not EditorPreferences.new(memoryStorage, context).data.onboardingCompleted, "onboarding remains complete in memory when file APIs are absent")
    local yieldingPreferences = EditorPreferences.new({saveEditorPreferences = function()
        coroutine.yield("waiting for preference write")
        return true
    end}, context)
    local worker = coroutine.create(function() return yieldingPreferences:setPreference("smartSelection", false) end)
    local started, held = coroutine.resume(worker)
    check(started and held == "waiting for preference write" and not yieldingPreferences:setPreference("skipTransparent", false)
        and yieldingPreferences.data.skipTransparent, "a yielding editor write cannot overlap a second preference mutation")
    local complete, acceptedYield, _, durableYield = coroutine.resume(worker)
    check(complete and acceptedYield and durableYield and not yieldingPreferences.data.smartSelection,
        "the in-flight editor preference write finishes with the intended settings")
    local unpublishedEditor = EditorPreferences.new(oldStorage, {experience = "0", place = "0"})
    local acceptedUnpublished, unpublishedMessage, durableUnpublished = unpublishedEditor:setElementFlag("locked", recreated, true)
    local _, lockedUnpublished = unpublishedEditor:elementFlags(recreated)
    check(acceptedUnpublished and not durableUnpublished and unpublishedMessage:find("no stable identifier") and lockedUnpublished,
        "unpublished contexts can use session rules without leaking identity preferences to other games")
end
checkEditorPreferences()

local function checkResetAndOpacity()
    local globalEntry = Util.copy(jumpEntry)
    globalEntry.transparency = 0.42
    local globalDefaults = {id = "retained-global", name = "Built-in defaults", scope = "global",
        layout = {[jumpKey] = globalEntry}, groups = {}, preferences = {snapping = true}}
    local localPlace = Util.copy(placeProfile)
    localPlace.layout[key] = Util.copy(target)
    localPlace.groups.HUD = {target.descriptor}
    local original = activeData(globalDefaults, localPlace)

    local changedOpacity = Profiles.new(original, memoryStorage, context)
    local layout, prefs, groups = changedOpacity:resolve()
    local childKey = jumpKey .. "/Outline:UIStroke:1"
    layout[jumpKey].opacity = {factor = 0.5, scope = "contents", targets = {jumpKey, childKey}}
    local _, _, acceptedOpacity = changedOpacity:save(layout, groups, prefs)
    local sparse = changedOpacity:active().layout[jumpKey]
    check(acceptedOpacity and sparse.inherit and sparse.opacity.factor == 0.5 and sparse.transparency == nil,
        "new opacity can be saved as a sparse local edit without flattening a legacy background value")
    local opacityReopen = Profiles.new(memoryStorage:import(changedOpacity:export()), memoryStorage, context)
    local reopenedOpacity = opacityReopen:resolve()[jumpKey]
    check(reopenedOpacity.transparency == 0.42 and reopenedOpacity.opacity.scope == "contents"
        and reopenedOpacity.opacity.targets[2] == childKey, "legacy background transparency and new contents opacity round trip independently")
    check(Config.validateOpacity({factor = 0, scope = "element"}, jumpKey)
        and not Config.validateOpacity({factor = .5, scope = "element", targets = {childKey}}, jumpKey)
        and not Config.validateOpacity({factor = .5, scope = "element", targets = {jumpKey, childKey}}, jumpKey)
        and not Config.validateOpacity({factor = 1.1, scope = "element"}, jumpKey)
        and not Config.validateOpacity({factor = 0.5, scope = "all"}, jumpKey)
        and not Config.validateOpacity({factor = 0.5, scope = "contents", targets = {missingKey}}, jumpKey)
        and not Config.validateOpacity({factor = 0.5, scope = "contents", targets = {jumpKey, jumpKey}}, jumpKey),
        "portable opacity validates bounded factors, known scopes, and exact non-duplicate descendant keys")

    local orientation = {id = "existing-mobile-landscape", name = "My landscape", scope = "orientation", scopeId = context.place,
        orientation = context.orientation, device = context.device, layout = {[missingKey] = Util.copy(missingTarget)}, groups = {}, preferences = {grid = true}}
    local originalWithOrientation = activeData(globalDefaults, localPlace, orientation)
    local resetSession = Profiles.new(originalWithOrientation, memoryStorage, context)
    check(resetSession:setEditTarget(globalDefaults.id) and resetSession:resetTarget().id == orientation.id,
        "Reset All always chooses the exact device and orientation slot even while editing a broader profile")
    local _, resetPrefs, resetGroups = resetSession:resolve()
    local _, _, acceptedReset = resetSession:save({}, resetGroups, resetPrefs, nil, context, {resetAll = true})
    local resetLayout, restoredPrefs, restoredGroups = resetSession:resolve()
    check(acceptedReset and not next(resetLayout) and resetSession:active().id == orientation.id
        and resetSession:active().name == orientation.name and resetSession:active().resetLayout and #resetSession.data.profiles == 3,
        "saving Reset All keeps the named exact profile and masks inherited and missing scoped layouts")
    check(restoredPrefs.grid and restoredPrefs.snapping and restoredGroups.HUD and Util.equal(resetSession.data.profiles[1], globalDefaults),
        "Reset All preserves inherited non-layout preferences, groups, and the original global profile")
    local portraitContext, desktopContext, unrelatedContext = Util.copy(context), Util.copy(context), Util.copy(context)
    portraitContext.orientation = "portrait"
    desktopContext.device = "desktop"
    unrelatedContext.place = "999"
    check(resetSession:resolve(portraitContext)[jumpKey] and resetSession:resolve(desktopContext)[jumpKey]
        and resetSession:resolve(unrelatedContext)[jumpKey] and not resetSession:resolve(unrelatedContext)[key],
        "the original-layout override does not affect other devices, orientations, or places")
    local reopenedReset = Profiles.new(memoryStorage:import(resetSession:export()), memoryStorage, context)
    check(not next((reopenedReset:resolve())), "reopening a saved reset does not reapply inherited layout values")
    local laterEdit = Util.copy(jumpEntry)
    laterEdit.position.xo = 15
    laterEdit.opacity = {factor = 0, scope = "element", targets = {jumpKey}}
    local _, _, laterSaved = reopenedReset:save({[jumpKey] = laterEdit}, restoredGroups, restoredPrefs)
    check(laterSaved and reopenedReset:active().resetLayout and not reopenedReset:active().layout[jumpKey].inherit
        and reopenedReset:resolve()[jumpKey].opacity.factor == 0 and not reopenedReset:resolve()[key],
        "new edits after Reset All persist against originals without resurrecting other inherited entries")
    local freshScope = Profiles.new(original, memoryStorage, context)
    local _, freshPrefs, freshGroups = freshScope:resolve()
    local beforeReset = freshScope:draftReference()
    local _, _, createdScope = freshScope:save({[jumpKey] = laterEdit}, freshGroups, freshPrefs, nil, context, {resetAll = true})
    check(createdScope and freshScope:active().scope == "orientation" and freshScope:active().resetLayout
        and freshScope:resolve()[jumpKey].position.xo == 15 and not freshScope:resolve()[key]
        and not freshScope:matchesDraftReference(beforeReset),
        "a reset with new edits creates a narrow destination only on Save and invalidates older draft baselines")
    local failure = Profiles.new(original, {save = function() return false, "Test write failure" end}, context)
    local _, failedPrefs, failedGroups = failure:resolve()
    local savedFailure, _, acceptedResetFailure = failure:save({}, failedGroups, failedPrefs, nil, context, {resetAll = true})
    check(not savedFailure and not acceptedResetFailure and Util.equal(failure.data, original) and not failure:resetTarget(),
        "failed Reset All Save neither selects a new destination nor changes existing checkpoints")
    local invalidReset = Util.copy(localPlace)
    invalidReset.resetLayout = true
    check(not Config.validateProfile(invalidReset), "a broad place profile cannot be imported with an original-layout override")

    local draftContext = Util.copy(context)
    draftContext.place = "411"
    local storage = Storage.new(cap, http, nil, draftContext)
    local resetDraft = {layout = {}, groups = {}, preferences = {}, context = draftContext, resetAll = true}
    check(storage:draft(resetDraft) and Util.equal(storage:loadDraft(), resetDraft), "reset intent survives a draft round trip")
    resetDraft.resetAll = "true"
    check(not storage:draft(resetDraft), "malformed reset intent cannot be saved into a draft")
end
checkResetAndOpacity()

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
