-- App orchestration with real Config/Profiles/History and deterministic adapters.
-- These tests do not simulate Roblox rendering or executor touch regions.
local Util = require("Util")
local Config = require("Config")
local Identity = require("Identity")
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local function signal()
    local callbacks = {}
    return { Connect = function(_, callback)
        local connection = { active = true }
        callbacks[#callbacks + 1] = { connection = connection, callback = callback }
        function connection:Disconnect() self.active = false end
        return connection
    end, Fire = function(_, ...)
        for _, slot in ipairs(callbacks) do if slot.connection.active then slot.callback(...) end end
    end }
end
local descriptor = { class = "Frame", path = {
    { name = "HUD", class = "ScreenGui", ordinal = 1 }, { name = "Health", class = "Frame", ordinal = 1 } } }
local key = Identity.key(descriptor)
local function entry(x)
    return { descriptor = Util.copy(descriptor), position = { xs = 0, xo = x, ys = 0, yo = 20 },
        size = { xs = 0, xo = 100, ys = 0, yo = 50 }, rotation = 0, transparency = 0 }
end
local function profile(id, x, scope, orientation)
    return { id = id, name = id, scope = scope or "place", scopeId = "2", orientation = orientation,
        layout = { [key] = entry(x) }, groups = {}, preferences = {} }
end
local function data()
    local first, second, portrait = profile("first", 10), profile("second", 100), profile("portrait", 200, "orientation", "portrait")
    local config = Config.empty()
    config.profiles = { first, second, portrait }
    config.active[Config.scopeKey(first)] = first.id
    config.active[Config.scopeKey(portrait)] = portrait.id
    return config
end
local scenario
package.loaded.Capabilities = { detect = function()
    return { storage = { status = scenario.storageStatus or "Supported and verified" },
        clipboard = { status = "Unsupported" }, network = { status = "Unsupported" }, input = { status = "Available but unverified" } }
end }
package.loaded.Storage = { new = function(capabilities)
    local state = scenario
    local storage = { cleared = 0, saves = 0, drafts = 0 }
    function storage:load() return Util.copy(state.data or data()) end
    function storage:loadDraft() return Util.copy(state.draft) end
    function storage:save(value)
        self.saves = self.saves + 1
        if capabilities.storage.status == "Unsupported" then return false, "In-memory only; export required.", true end
        if state.saveFails then capabilities.storage.status = "Failed"; return false, "Write failed; draft retained." end
        state.persisted = Util.copy(value)
        return true, "Persisted and verified."
    end
    function storage:draft(value) self.drafts = self.drafts + 1; self.lastDraft = Util.copy(value); return true, "Draft stored." end
    function storage:clearDraft(context) self.cleared = self.cleared + 1; self.clearedContext = Util.copy(context); return true end
    function storage:import() return Util.copy(state.incoming) end
    function storage:export() return "{}" end
    function storage:copy() return false, "Manual copy required." end
    return storage
end }
package.loaded.Discovery = { new = function()
    local original = entry(0)
    local record = {key = key, descriptor = Util.copy(descriptor), baseline = Util.copy(original),
        baselineRect = {x = 0, y = 20, w = 100, h = 50}, editable = true, object = {Parent = {}}}
    local discovery = { records = { [key] = record } }
    function discovery:start(callback) self.callback = callback end
    function discovery:get(id) return self.records[id] end
    function discovery:list() return { record } end
    function discovery:refresh() end
    function discovery:destroy() self.destroyed = true end
    function discovery:approve() return true end
    return discovery
end }
package.loaded.Transform = { new = function(discovery)
    local transform = { live = { [key] = entry(0) }, tracked = {}, safe = false, applyCount = 0 }
    function transform:capture()
        local state = {}
        for id in pairs(self.tracked) do if self.live[id] then state[id] = Util.copy(self.live[id]) end end
        return state
    end
    function transform:apply(layout, options)
        self.applyCount = self.applyCount + 1
        if options and options.replace then self:restore(); self.tracked = {} end
        local count, skipped = 0, 0
        for id, value in pairs(layout) do
            if discovery:get(id) then self.live[id] = Util.copy(value); self.tracked[id] = true; count = count + 1 else skipped = skipped + 1 end
        end
        return count, skipped
    end
    function transform:beginTransaction()
        self.before = {live = Util.copy(self.live), tracked = Util.copy(self.tracked)}
        return true
    end
    function transform:endTransaction(callback)
        if scenario.deferGesture then
            self.complete = function(ok)
                if not ok then self:cancelTransaction() end
                self.before, self.complete = nil, nil
                callback(ok, ok and nil or "Mock geometry mismatch.")
            end
        else self.before = nil; callback(true) end
        return true
    end
    function transform:applyHistory(_, target, callback)
        self:beginTransaction()
        self:apply(target, {replace = true})
        return self:endTransaction(callback)
    end
    function transform:cancelTransaction()
        if not self.before then return false end
        self.live, self.tracked = self.before.live, self.before.tracked
        self.before = nil
        return true
    end
    function transform:selectionRects(keys)
        local rects, roots = {}, {}
        for _, id in ipairs(keys) do
            local value = self.live[id]
            if value then rects[#rects + 1] = { x = value.position.xo, y = value.position.yo, w = value.size.xo, h = value.size.yo }; roots[#roots + 1] = id end
        end
        return rects, roots
    end
    function transform:setRects(keys, rects)
        for i, id in ipairs(keys) do
            local value, rect = self.live[id], rects[i]
            if not value or not rect then return false, "Missing element" end
            value.position.xo, value.position.yo, value.size.xo, value.size.yo = rect.x, rect.y, rect.w, rect.h
            self.tracked[id] = true
        end
        return true
    end
    function transform:restore(keys)
        if not keys then self.live = { [key] = entry(0) }; return end
        for _, id in ipairs(keys) do if discovery:get(id) then self.live[id] = entry(0); self.tracked[id] = true end end
    end
    function transform:matches(layout)
        local missing = {}
        for id in pairs(layout) do if not discovery:get(id) then missing[#missing + 1] = id end end
        return missing
    end
    function transform:destroy() self.destroyed = true end
    return transform
end }
package.loaded.UI = { new = function()
    local ui = { gui = {}, visible = false }
    function ui:status(value, options) self.message, self.notification = value, options end
    function ui:refresh() self.refreshed = true end
    function ui:updateSelection() end
    function ui:setVisible(value) self.visible = value end
    function ui:confirmDone(save, discard) self.done = {save = save, discard = discard} end
    function ui:showExport() self.exportShown = true end
    function ui:destroy() self.destroyed = true end
    return ui
end }
package.loaded.Input = { new = function(app)
    return { destroy = function(self) self.destroyed = true end, cancel = function(self)
        self.cancels = (self.cancels or 0) + 1
        if app.gesture then app:cancelGesture() end
    end }
end }
local App = require("App")
local function setup(options)
    scenario = options or {}
    local pending = {}
    task = { delay = function(_, callback) pending[#pending + 1] = callback end, spawn = function(callback) callback() end, wait = function() end }
    Enum = { KeyCode = { F8 = "F8", F9 = "F9" } }
    Vector2 = { new = function(x, y) return { X = x, Y = y } end }
    warn = function() end
    game = { GameId = 1, PlaceId = 2 }
    local cameraSignal, cameraChanged = signal(), signal()
    local camera = { ViewportSize = { X = 1280, Y = 720 }, GetPropertyChangedSignal = function() return cameraSignal end }
    local services = {
        UserInputService = { TouchEnabled = false, MouseEnabled = true, KeyboardEnabled = true },
        HttpService = {}, GuiService = { GetGuiInset = function() return { X = 0, Y = 36 }, { X = 0, Y = 0 } end },
        Workspace = { CurrentCamera = camera, GetPropertyChangedSignal = function() return cameraChanged end },
    }
    local env = {}
    local app = App.new(env, services, {}, scenario.appOptions or { LoaderOnly = true })
    app:select(key)
    return app, services, cameraSignal, pending, env
end
local function x(app) return app.transform.live[key].position.xo end

local app = setup()
check(x(app) == 10 and not app.dirty, "startup applies saved absolute layout and establishes checkpoint")
app:move(10, 0)
check(x(app) == 20 and app.dirty, "completed transform becomes unsaved")
local saved = app:save()
check(saved and not app.dirty and x(app) == 20, "verified Save establishes checkpoint")
app:undo()
check(x(app) == 10 and app.dirty, "undo after Save changes live state without replacing stored checkpoint")
check(scenario.persisted.profiles[1].layout[key].position.xo == 20, "undo does not silently overwrite storage")
app:redo()
check(x(app) == 20 and not app.dirty, "redo to saved state clears unsaved marker")
app:move(15, 0); app:cancel()
check(x(app) == 20 and not app.dirty and #app.history.past == 0, "Cancel restores latest Save and clears history")

app = setup()
app:move(7, 0)
app:profile("preview", "second")
check(x(app) == 100 and app.profiles:active().id == "first", "profile preview does not change active profile")
app:profile("cancel")
check(x(app) == 17 and app.profiles:active().id == "first" and app.dirty, "preview Cancel restores exact previous unsaved layout")
app:profile("preview", "second"); app:profile("apply")
check(x(app) == 100 and app.profiles:active().id == "second" and app.dirty, "Apply switches profile in memory and marks activation unsaved")
app:cancel()
check(x(app) == 10 and app.profiles:active().id == "first" and not app.dirty, "Cancel after Apply restores latest saved layout and active profile")

app = setup()
app:profile("preview", "second")
app:setPreference("grid", false)
app:profile("cancel"); app:undo()
check(x(app) == 10 and app.preferences.grid == true, "editing preferences during preview cannot leak temporary layout into history")
app:setPreference("snapping", "yes")
check(app.preferences.snapping == false and Config.validateState(app:getState()), "invalid preference types cannot create an unsaveable session")

local globalData = data()
globalData.profiles[#globalData.profiles + 1] = { id = "global", name = "Global", scope = "global", layout = {}, groups = {}, preferences = {} }
app = setup({ data = globalData })
app:profile("preview", "global"); app:profile("apply")
app:setPreference("grid", false); app:save()
check(app.profiles:active().id == "global" and scenario.persisted.profiles[4].preferences.grid == false,
    "Save after selecting global writes the chosen global layer rather than hidden place profile")
check(scenario.persisted.profiles[1].layout[key].position.xo == 10 and #scenario.persisted.profiles == 4,
    "editing global defaults preserves saved place overrides and all profile definitions")

local fallbackData = data()
fallbackData.profiles[#fallbackData.profiles + 1] = {id = "global", name = "Global", scope = "global", layout = {}, groups = {}, preferences = {grid = false}}
fallbackData.active[Config.scopeKey(fallbackData.profiles[4])] = "global"
app = setup({data = fallbackData})
app:profile("delete", "first", true)
check(app.profiles:active().id == "global" and x(app) == 0 and next(app:getState().layout) == nil,
    "deleting active place profile restores lower-layer layout without capturing unrelated GUI baselines")
app:save()
check(scenario.persisted and app.profiles:active().id == "global" and next(scenario.persisted.profiles[3].layout) == nil,
    "saving a deletion never copies deleted place-specific GUI data into global defaults")

app = setup({data = fallbackData})
app:profile("delete", "first", true); app:cancel()
check(app.profiles:active().id == "first" and x(app) == 10 and #app.profiles.data.profiles == 4,
    "Cancel after active deletion restores latest saved profile definitions, activation and exact layout")

app = setup({ storageStatus = "Unsupported" })
app:move(10, 0)
local persisted = app:save()
check(not persisted and not app.dirty and app.profiles:active().layout[key].position.xo == 20, "valid memory Save is a checkpoint and remains exportable while reporting no persistence")
app:move(3, 0); app.groups[string.rep("x", 65)] = {}
app:save()
check(app.dirty and app.history.saved.layout[key].position.xo == 20, "rejected memory Save cannot establish checkpoint")

app = setup({ saveFails = true })
app:move(10, 0); app:save()
check(app.dirty and app.storage.cleared == 0 and app.history.saved.layout[key].position.xo == 10, "failed file Save retains dirty state and previous checkpoint")

local pending
app, _, _, pending = setup()
app:move(10, 0)
app.transform.pendingStabilization = {}
local waiting = app:save()
check(waiting == false and app.saveWaiting and app.storage.saves == 0, "Save defers persistence until its bounded stability observation completes")
app.transform.pendingStabilization = nil
pending[#pending]()
check(app.storage.saves == 1 and not app.dirty and x(app) == 20, "stable unchanged requested layout is saved after bounded wait")

app, _, _, pending = setup()
app:move(10, 0); app.transform.pendingStabilization = {}; app:save()
app.transform.pendingStabilization = nil
app.transform.live[key].position.xo = 10
pending[#pending]()
check(app.storage.saves == 0 and app.history.saved.layout[key].position.xo == 10 and not app.saveWaiting,
    "stabilization rollback cannot be persisted or presented as Save success")

app, _, _, pending = setup()
app:move(10, 0); app.transform.pendingStabilization = {}; app:save()
local saveCallback = pending[#pending]
app:move(7, 0); app.transform.pendingStabilization = nil
saveCallback()
check(app.storage.saves == 0 and x(app) == 27 and app.dirty,
    "a further user edit during the Save wait is retained for review rather than silently persisted")

app, _, _, pending = setup()
app:move(10, 0); app.transform.pendingStabilization = {}; app:save()
pending[#pending]()
check(app.storage.saves == 0 and not app.saveWaiting, "unresolved stability observation aborts Save after one bounded wait")

local draft = { layout = { [key] = entry(55) }, groups = {}, preferences = {}, context = { experience = "1", place = "2", device = "desktop", orientation = "landscape" } }
app = setup({ draft = draft })
check(app.draft and x(app) == 10, "recoverable unsaved draft is offered without automatic gameplay application")
app:profile("recoverDraft")
check(x(app) == 55 and app.previewState and app.profiles:active().id == "first", "draft restoration starts as temporary preview")
app:profile("cancel")
check(x(app) == 10 and not app.previewState, "draft preview Cancel restores previous layout")
app:profile("recoverDraft"); app:profile("apply")
check(x(app) == 55 and app.dirty and not app.previewState and app.profiles:active().id == "first", "draft Apply restores unsaved editing state without needing a profile preview")
app:undo()
check(x(app) == 10, "applied recovery draft is one undo transaction")

app = setup({ draft = { layout = { [key] = entry(55) }, groups = {}, preferences = {}, context = { experience = "1", place = "999", device = "desktop", orientation = "landscape" } } })
check(not app.draft and x(app) == 10, "draft for another place is never offered or applied")

local services, cameraSignal
app, services, cameraSignal = setup()
app:move(13, 0)
services.Workspace.CurrentCamera.ViewportSize = { X = 720, Y = 1280 }; cameraSignal:Fire()
check(app.context.orientation == "portrait" and x(app) == 23 and app.dirty, "orientation changes retain unsaved geometry")
check(app.editContext.orientation == "landscape" and app.profiles:active(app:_currentEditContext()).id == "first",
    "unsaved edits retain their original orientation and write target")
check(app:save() and x(app) == 200 and not app.dirty and not app.editContext,
    "saving the pinned orientation then adopts the current orientation")
check(scenario.persisted.profiles[1].layout[key].position.xo == 23
    and scenario.persisted.profiles[3].layout[key].position.xo == 200 and app.storage.clearedContext.orientation == "landscape",
    "save after rotation updates only the originating profile and draft file")
app, services, cameraSignal = setup()
services.Workspace.CurrentCamera.ViewportSize = { X = 720, Y = 1280 }; cameraSignal:Fire()
check(x(app) == 200 and not app.dirty, "clean orientation change resolves compatible orientation override")
app, services, cameraSignal = setup()
app:profile("create", "Draft profile", "place")
services.Workspace.CurrentCamera.ViewportSize = { X = 720, Y = 1280 }; cameraSignal:Fire()
check(x(app) == 10 and app.dirty, "unsaved profile metadata prevents orientation from replacing current draft")

app, services, cameraSignal, pending = setup()
app:move(13, 0)
services.Workspace.CurrentCamera.ViewportSize = {X = 720, Y = 1280}; cameraSignal:Fire()
pending[#pending]()
check(app.storage.lastDraft.context.orientation == "landscape" and app.storage.lastDraft.reference.profileId == "first",
    "a debounced recovery write follows the pinned editing context")
app:cancel()
check(x(app) == 200 and not app.dirty, "discarding a rotated draft restores the current orientation after the checkpoint")

app = setup()
app:setPreference("multiSelect", true)
check(app.preferences.multiSelect and not app.dirty and #app.history.past == 0, "touch-only multi-select mode is not a layout edit")
check(app:sizeInfo().scale == 100 and app:sizeInfo().original, "relative size is based on captured original dimensions")
app:setSizePercent(150)
check(app.transform.live[key].size.xo == 150 and app.transform.live[key].size.yo == 75 and app:sizeInfo().scale == 150,
    "percent entry updates reported dimensions and preserves aspect ratio")
app:resize(180, 75)
check(app.transform.live[key].size.xo == 180 and app.transform.live[key].size.yo == 90, "precise size input respects aspect lock")
app:setLauncherPosition(1, 0.25)
check(#app.history.past == 2 and app:getEditorPlacement("launcher").x == 1, "moving the launcher is independent of HUD undo history")
app:undo()
check(app.transform.live[key].size.xo == 150 and app:getEditorPlacement("launcher").x == 1, "undo retains launcher placement")

local tinyData = data()
tinyData.profiles[1].layout[key].size.xo, tinyData.profiles[1].layout[key].size.yo = 24, 18
app = setup({data = tinyData})
local reference = app:sizeInfo().baseline
app:select(key)
check(app:sizeInfo().baseline == reference, "tapping the same selection keeps its resize reference")
app:stepSize(1)
check(math.abs(app.transform.live[key].size.xo - 25) < 0.001, "a fine step visibly changes a tiny selection")
app:stepSize(-1)
check(math.abs(app.transform.live[key].size.xo - 24) < 0.001, "opposite tiny fine steps return to the starting width")

app = setup()
app:move(9, 0)
function app.storage:clearDraft()
    coroutine.yield("cleaning draft")
    return true
end
local savingThread = coroutine.create(function() return app:save() end)
local startedSave, pausedSave = coroutine.resume(savingThread)
check(startedSave and pausedSave == "cleaning draft" and app.saving, "Save stays locked while persistent cleanup yields")
app:move(7, 0)
check(x(app) == 19 and coroutine.resume(savingThread) and not app.saving and not app.dirty,
    "a second action cannot change the checkpoint during Save cleanup")

local missing = Util.copy(descriptor)
missing.path[#missing.path].name = "OlderHealth"
local missingKey = Identity.key(missing)
local remapData = data()
local missingEntry = entry(36)
missingEntry.descriptor = missing
remapData.profiles[1].layout = {[missingKey] = missingEntry}
remapData.profiles[1].groups = {Hud = {missing, descriptor}}
app = setup({data = remapData})
app:remap(missingKey, key)
check(x(app) == 36 and app.layout[missingKey] == nil and #app.groups.Hud == 1
    and Identity.key(app.groups.Hud[1]) == key and Config.validateState(app:getState()),
    "remapping onto an existing group member preserves a valid group and portable layout")

app = setup()
local originalUI = package.loaded.UI
package.loaded.UI = {new = function() error("simulated UI construction failure") end}
check(app:Open() == false and not app.editing and not app.ui,
    "a UI startup failure returns safely without disturbing other PlayerGui children")
package.loaded.UI = originalUI

app = setup({deferGesture = true})
app:move(10, 0)
check(x(app) == 20 and app.finishingGesture and #app.history.past == 0 and not app.dirty,
    "a released adjustment waits for geometry verification before history")
app:move(20, 0)
check(x(app) == 20, "a newer adjustment cannot replace a pending transaction")
app:save()
check(app.storage.saves == 0, "Save waits for the released adjustment to verify")
app.transform.complete(false)
check(x(app) == 10 and #app.history.past == 0 and not app.dirty and app.storage.saves == 0,
    "a failed transaction rolls back without history or an implicit Save")
app:move(10, 0); app:save(); app.transform.complete(true)
check(x(app) == 20 and #app.history.past == 1 and not app.dirty and app.storage.saves == 1,
    "a verified transaction creates one action and satisfies a requested Save")
app:undo()
check(#app.history.past == 1 and app.finishingGesture, "Undo keeps its history cursor until geometry verifies")
app.transform.complete(false)
check(x(app) == 20 and #app.history.past == 1 and #app.history.future == 0 and not app.dirty,
    "failed Undo preserves geometry, history cursor and checkpoint")
app:undo(); app.transform.complete(true)
check(x(app) == 10 and app.dirty and #app.history.future == 1, "verified Undo advances its history cursor")
app:cancel(); app.transform.complete(true)
check(x(app) == 20 and not app.dirty and #app.history.future == 0, "verified Discard restores the last checkpoint")

app, _, _, pending = setup()
app:move(7, 0)
local draftWrite = pending[#pending]
app:profile("preview", "second")
draftWrite()
check(app.previewState and x(app) == 100 and app.storage.drafts == 0, "a previously scheduled draft cannot capture a profile preview")
app:profile("cancel")
pending[#pending]()
check(app.storage.lastDraft.layout[key].position.xo == 17, "the draft resumes from the prior edits when preview closes")

app = setup({appOptions = {}})
app:move(7, 0); app:Done()
check(app.ui.done and app.editing and app.dirty, "Done prompts instead of losing unsaved edits")
app.ui.done.discard()
check(not app.editing and x(app) == 10 and not app.dirty, "Done discard restores checkpoint before closing")
app:Open(); app:move(7, 0); app:Done(); app.ui.done.save()
check(not app.editing and x(app) == 17 and not app.dirty, "Done Save closes after a durable checkpoint")
check(app.ui.notification.kind == "success" and app.ui.notification.keepOnClose,
    "durable Save uses a confirmation that remains visible after Done")
app = setup({appOptions = {}, storageStatus = "Unsupported"})
app:move(7, 0); app:Done(); app.ui.done.save()
check(app.editing and app.ui.exportShown and not app.dirty, "Done offers export after a memory-only checkpoint")
check(app.ui.notification.kind == "warning" and not app.ui.notification.keepOnClose,
    "a memory checkpoint is distinct from a durable Save confirmation")
app = setup({appOptions = {}, saveFails = true})
app:move(7, 0); app:Done(); app.ui.done.save()
check(app.editing and app.dirty and app.ui.notification.kind == "error",
    "failed Save keeps the layout open and provides an error notification")

app = setup()
app:move(9, 0)
local beforeSafe, profilesBefore = app:getState(), Util.copy(app.profiles.data)
app:safeMode()
check(app.profiles.suspended and app.transform.safe and x(app) == 0 and app.editing, "Safe Mode restores originals, suspends overrides and reopens editor")
check(Util.equal(profilesBefore, app.profiles.data) and Util.equal(beforeSafe, app:getState()), "Safe Mode preserves saved configuration and recoverable unsaved state")
app:profile("suspend", false)
check(not app.profiles.suspended and not app.transform.safe and x(app) == 19, "resuming Safe Mode restores suspended draft once")
app:Destroy()
check(not app.alive and app.discovery.destroyed and app.transform.destroyed and app.ui.destroyed, "teardown disconnects adapters and destroys UI")

app = setup({appOptions = {SafeMode = true}})
check(app.profiles.suspended and app.transform.safe and app.transform.applyCount == 0 and x(app) == 0,
    "SafeMode startup never applies saved properties before restoring originals")
check(app.editing and app.ui.visible and app.profiles:active().id == "first",
    "SafeMode startup opens recovery while retaining saved profile definitions")
app:Destroy()

do
    local editor, editorServices, viewportChanged = setup()
    check(editor:setEditorPlacement("toolbar", {x = .24, y = .3}) and not editor.dirty and #editor.history.past == 0,
        "moving a panel stays outside HUD history and saved layouts")
    editorServices.Workspace.CurrentCamera.ViewportSize = {X = 720, Y = 1280}
    viewportChanged:Fire()
    check(editor:getEditorPlacement("toolbar") == nil, "portrait uses its own panel placement")
    editor:setEditorPlacement("toolbar", {x = .6, y = .7})
    editorServices.Workspace.CurrentCamera.ViewportSize = {X = 1280, Y = 720}
    viewportChanged:Fire()
    check(editor:getEditorPlacement("toolbar").x == .24 and not editor.dirty, "landscape placement is restored on rotation")
    check(editor:resetEditorLayout() and editor:getEditorPlacement("toolbar") == nil and not editor.dirty,
        "resetting editor placement leaves the HUD checkpoint intact")

    editor:move(9, 0)
    editor:resetAll()
    check(x(editor) == 0 and editor.resetAllPending and #editor.history.past == 2, "Reset All restores original geometry in one history entry")
    editor:undo()
    check(x(editor) == 19 and not editor.resetAllPending, "undo restores the layout and clears the pending reset destination")
    editor:redo()
    check(x(editor) == 0 and editor.resetAllPending, "redo restores originals and the pending reset destination")
    editor:cancel()
    check(x(editor) == 10 and not editor.resetAllPending and not editor.dirty, "discard after Reset All returns to the saved checkpoint")
    editor:resetAll()
    check(editor:save() and x(editor) == 0 and not editor.dirty and not editor.resetAllPending, "saving Reset All creates a clean checkpoint")
    local profileData = scenario.persisted
    check(profileData.profiles[1].layout[key].position.xo == 10 and not Config.resolve(profileData, editor.context)[key],
        "scoped reset masks inherited edits while retaining the original stored profile")
    editor:undo()
    check(x(editor) == 10 and editor.dirty, "undo remains available after the reset is saved")
    editor:redo()
    check(x(editor) == 0 and not editor.dirty, "redo after a saved reset returns to its clean checkpoint")
    editor = setup({data = profileData})
    check(x(editor) == 0 and not editor.dirty, "a fresh session honors the saved original-layout mask")

    editor = setup()
    editor:setLayerState(key, "locked", true)
    editor:resetAll()
    check(x(editor) == 10 and not editor.dirty and editor:resetAllSummary().protected == 1,
        "Reset All skips the editor's locked controls")
end

do
    local editor = setup()
    local first = editor.discovery:get(key)
    local function extra(name, x)
        local identity = Util.copy(descriptor)
        identity.path[#identity.path].name = name
        local id = Identity.key(identity)
        local value = entry(x)
        value.descriptor = identity
        local record = {key = id, descriptor = identity, editable = true, object = {Parent = first.object.Parent}}
        editor.discovery.records[id], editor.transform.live[id] = record, value
        return record
    end
    local parent, neighbor = extra("Control bar", 32), extra("Sibling", 63)
    local controller = {ClassName = "UIListLayout"}
    first.parentKey, first.layoutController, neighbor.layoutController = parent.key, controller, controller
    parent.childKeys = {key, neighbor.key}
    neighbor.parentKey = parent.key
    check(editor:setLayerState(key, "ignored", true) and editor:layerState(key).ignored and not editor.dirty,
        "ignore affects the selection policy without changing a layout checkpoint")
    editor:move(2, 0)
    check(x(editor) == 12, "explicitly selected ignored controls can still be edited")
    check(editor:setLayerState(key, "locked", true) and not editor:capability(key, "move").supported,
        "a locked control remains inspectable and direct movement is refused")
    editor:move(11, 0)
    check(x(editor) == 12, "an attempted direct edit leaves a locked control unchanged")
    check(not editor:capability(parent.key, "move").supported and not editor:capability(parent.key, "rotation").supported
        and editor:capability(parent.key, "transparency").supported,
        "parent movement and rotation protect a locked descendant while background appearance remains available")
    check(not editor:capability(neighbor.key, "resize").supported,
        "reflow cannot resize a sibling when the row contains a locked member")
    check(editor:clearLayerStates("locked") and editor:capability(parent.key, "move").supported
        and editor:capability(neighbor.key, "resize").supported and editor:layerState(key).ignored,
        "clearing locks restores available actions while preserving ignore rules")
    editor:selectMany({key, neighbor.key})
    local beforeGroup = #editor.history.past
    check(editor:quickGroup() and #editor.groupFocus.keys == 2 and #editor.history.past == beforeGroup,
        "temporary grouping preserves layout history")
    check(editor:enterGroupMember(neighbor.key) and #editor.selection == 1 and editor.groupFocus.member == neighbor.key,
        "a group member can be edited without losing group context")
    editor:group("create", "HUD controls")
    check(editor.groupFocus.name == "HUD controls" and #editor.groups["HUD controls"] == 2,
        "naming a quick group while editing a member retains both members")
    check(editor:returnToGroup() and #editor.selection == 2 and editor:ungroup(true)
        and not editor.groups["HUD controls"] and x(editor) == 12,
        "ungrouping a named group changes membership without repositioning controls")
    check(editor:markTutorialSeen() and editor:hasSeenTutorial() and not editor:getState().preferences.onboardingCompleted,
        "onboarding progress is separate from HUD checkpoint data")
end

-- Exercise the release entry separately with a yielding constructor and delayed player.
local actualApp = package.loaded.App
local bootstrap = assert(loadfile("src/Bootstrap.lua"))
local env, created, opened, safed, cleanup = {}, 0, 0, 0, 0
local function newSingleton()
    local singleton = { alive = true }
    function singleton:Open() opened = opened + 1 end
    function singleton:SafeMode() safed = safed + 1 end
    function singleton:Destroy() cleanup = cleanup + 1; self.alive = false end
    return singleton
end
local playerGui = {}
local player = { FindFirstChildOfClass = function() return playerGui end }
local players = { LocalPlayer = player }
game = { GetService = function(_, name) return name == "Players" and players or {} end }
getgenv = function() return env end
warn = function() end
package.loaded.App = { new = function()
    created = created + 1
    return newSingleton()
end }
local first = bootstrap()
check(first and env.__HEAVENLY_AXIS_V3 == first and created == 1, "bootstrap installs one live singleton")
check(bootstrap() == first and created == 1 and opened == 1, "repeated release execution reopens existing singleton")
env.HeavenlyAxisOptions = { LoaderOnly = true }
check(bootstrap() == first and opened == 1 and created == 1, "repeated loader run does not construct or open editor")
env.HeavenlyAxisOptions = { SafeMode = true }
check(bootstrap() == first and safed == 1 and created == 1, "repeated SafeMode run delegates to existing singleton")

env, created = {}, 0
package.loaded.App = { new = function()
    created = created + 1
    coroutine.yield("constructing")
    return newSingleton()
end }
local thread = coroutine.create(bootstrap)
local ok, reason = coroutine.resume(thread)
check(ok and reason == "constructing", "constructor can yield after initialization reservation")
local reserved = bootstrap()
check(reserved and reserved.initializing and created == 1, "concurrent release execution cannot construct duplicate during yielding initialization")
local complete, singleton = coroutine.resume(thread)
check(complete and singleton == env.__HEAVENLY_AXIS_V3 and singleton.alive and created == 1, "reserved constructor publishes live singleton once")

env, created, players.LocalPlayer = {}, 0, nil
package.loaded.App = { new = function() created = created + 1; return newSingleton() end }
task.wait = function() coroutine.yield("waiting for player") end
local delayedA, delayedB = coroutine.create(bootstrap), coroutine.create(bootstrap)
check(coroutine.resume(delayedA) and coroutine.resume(delayedB), "simultaneous startup can wait for missing LocalPlayer")
players.LocalPlayer = player
local readyA, singletonA = coroutine.resume(delayedA)
local readyB, singletonB = coroutine.resume(delayedB)
check(readyA and readyB and singletonA == singletonB and created == 1, "startup rechecks live singleton after delayed PlayerGui/LocalPlayer acquisition")

env = {}
package.loaded.App = { new = function()
    env.__HEAVENLY_AXIS_V3.partial = newSingleton()
    error("simulated initialization failure")
end }
check(bootstrap() == nil and env.__HEAVENLY_AXIS_V3 == nil and cleanup == 1, "failed initialization cleans partially built app and clears reservation")
-- Studio scripts share _G for options/singleton, even when getfenv exists.
getgenv = nil
local oldOptions, oldSingleton = _G.HeavenlyAxisOptions, _G.__HEAVENLY_AXIS_V3
local unrelatedEnvironment = {}
getfenv = function() return unrelatedEnvironment end
_G.HeavenlyAxisOptions, _G.__HEAVENLY_AXIS_V3 = { LoaderOnly = true }, nil
package.loaded.App = { new = function(_, _, _, options)
    check(options.LoaderOnly == true, "Studio bootstrap reads options from shared _G rather than script getfenv")
    return newSingleton()
end }
local studioSingleton = bootstrap()
check(studioSingleton == _G.__HEAVENLY_AXIS_V3 and unrelatedEnvironment.__HEAVENLY_AXIS_V3 == nil,
    "Studio bootstrap exposes singleton through shared _G recovery path")
_G.HeavenlyAxisOptions, _G.__HEAVENLY_AXIS_V3 = oldOptions, oldSingleton
getfenv = nil
package.loaded.App = actualApp
return checks
