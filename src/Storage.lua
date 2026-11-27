-- Versioned JSON only: imported content is never executed.
local Config = require("Config")
local Util = require("Util")
local Storage = {}
Storage.__index = Storage
Storage.FILES = {
    saved = "HeavenlyAxis-v3.json",
    backup = "HeavenlyAxis-v3.backup.json",
    pending = "HeavenlyAxis-v3.pending.json",
    draft = "HeavenlyAxis-v3.draft.json",
}
Storage.MAX_BYTES = 2 * 1024 * 1024

local function validateState(state)
    if type(state) ~= "table" then return false, "Draft must contain a state" end
    for key in pairs(state) do
        if key ~= "layout" and key ~= "groups" and key ~= "preferences" and key ~= "context" and key ~= "reference" then
            return false, "Unknown draft field"
        end
    end
    if state.context ~= nil then
        if type(state.context) ~= "table" then return false, "Invalid draft context" end
        for key, value in pairs(state.context) do
            if key ~= "experience" and key ~= "place" and key ~= "device" and key ~= "orientation" then return false, "Unknown draft context field" end
            if type(value) ~= "string" or #value > 80 then return false, "Invalid draft context value" end
        end
    end
    local reference = state.reference
    if reference ~= nil then
        if type(reference) ~= "table" then return false, "Invalid draft checkpoint reference" end
        for key in pairs(reference) do
            if key ~= "profileId" and key ~= "revision" then return false, "Unknown draft checkpoint field" end
        end
        local profileId, revision = reference.profileId, reference.revision
        if profileId ~= false and (type(profileId) ~= "string" or #profileId == 0 or #profileId > 128 or profileId:find("%c")) then
            return false, "Invalid draft profile ID"
        end
        if type(revision) ~= "string" or #revision > 21 or not revision:match("^%d+:%d+$") then
            return false, "Invalid draft revision"
        end
    end
    return Config.validateState({layout = state.layout or {}, groups = state.groups or {}, preferences = state.preferences or {}})
end

function Storage.new(capabilities, httpService, log, context)
    return setmetatable({capabilities = capabilities, http = httpService, log = log or function() end, blocked = false, context = context}, Storage)
end

function Storage:_draftPath(context)
    context = context or self.context
    if type(context) == "table" and type(context.experience) == "string" and type(context.place) == "string"
        and #context.experience <= 32 and #context.place <= 32
        and context.experience:match("^%d+$") and context.place:match("^%d+$")
        and (context.device == "touch" or context.device == "desktop")
        and (context.orientation == "portrait" or context.orientation == "landscape") then
        return "HeavenlyAxis-v3.draft." .. context.experience .. "." .. context.place .. "." .. context.device .. "." .. context.orientation .. ".json"
    end
    return self.FILES.draft
end

function Storage:_foreignDraft(value, context)
    local state = value and value.state
    local stored = type(state) == "table" and state.context
    return context and type(stored) == "table" and self:_draftPath(stored) ~= self.FILES.draft
        and not Util.equal(stored, context)
end

function Storage:_available()
    local f = self.capabilities._functions or {}
    return type(f.readfile) == "function" and type(f.writefile) == "function" and type(f.isfile) == "function"
end

function Storage:_fail(message)
    self.capabilities.storage.status = "Failed"
    self.capabilities.storage.detail = message
    self.log(message)
    return false, message
end

function Storage:_exists(path)
    local ok, exists = pcall(self.capabilities._functions.isfile, path)
    if not ok or type(exists) ~= "boolean" then return nil, "File availability check failed; existing files preserved." end
    return exists
end

function Storage:_decode(text)
    if type(text) ~= "string" or #text == 0 or #text > self.MAX_BYTES then return nil, "JSON is empty or exceeds the size limit." end
    if not self.http then return nil, "JSON service unavailable." end
    local ok, value = pcall(function() return self.http:JSONDecode(text) end)
    if not ok or type(value) ~= "table" then return nil, "Malformed JSON." end
    return value
end

function Storage:_encode(value)
    if not self.http then return nil, "JSON service unavailable." end
    local ok, text = pcall(function() return self.http:JSONEncode(value) end)
    if not ok or type(text) ~= "string" or #text > self.MAX_BYTES then return nil, "JSON encoding failed or exceeds the size limit." end
    return text
end

function Storage:import(text)
    local data, err = self:_decode(text)
    if not data then return nil, err end
    local ok, reason = Config.validate(data)
    if not ok then return nil, "Invalid configuration: " .. tostring(reason) end
    return Util.copy(data)
end

function Storage:export(data)
    local ok, err = Config.validate(data)
    if not ok then return nil, "Invalid configuration: " .. tostring(err) end
    return self:_encode(data)
end

function Storage:_read(path)
    local exists, err = self:_exists(path)
    if exists == nil then return nil, err end
    if not exists then return nil, "missing" end
    local ok, raw = pcall(self.capabilities._functions.readfile, path)
    if not ok or type(raw) ~= "string" then return nil, "Local file read failed; existing files preserved.", true end
    return raw
end

function Storage:load()
    if not self:_available() then return nil, "Persistent storage unavailable; profiles stay in memory until exported." end
    local raw, err = self:_read(self.FILES.saved)
    if not raw and err == "missing" then return nil, "No saved V3 configuration." end
    local data, reason
    if raw then data, reason = self:import(raw) else reason = err end
    if data then
        self.capabilities.storage.status = "Available but unverified"
        self.capabilities.storage.detail = "Saved JSON read and validated; next Save verifies writes."
        return data
    end
    self.blocked = true
    local backup = self:_read(self.FILES.backup)
    local recovered = backup and self:import(backup)
    local message = recovered and "Loaded valid backup in memory. Damaged saved file preserved; export before repairing storage manually." or "Saved configuration could not be validated. Original file preserved; Save is blocked until it is repaired or moved manually."
    self:_fail(message)
    return recovered, reason or message
end

function Storage:_verifiedWrite(path, raw)
    local ok = pcall(self.capabilities._functions.writefile, path, raw)
    if not ok then return false end
    local readOk, actual = pcall(self.capabilities._functions.readfile, path)
    return readOk and actual == raw
end

function Storage:save(data)
    local raw, err = self:export(data)
    if not raw then return false, err end
    if not self:_available() then return false, "Checkpoint is in memory only. Export JSON for a durable copy.", true end
    if self.blocked then return self:_fail("Save blocked. Existing configuration needs manual repair. Your edits are still open.") end
    -- Validate every existing primary before any overwrite, including saves before load.
    local previous, readError = self:_read(self.FILES.saved)
    if not previous and readError ~= "missing" then return self:_fail(readError) end
    if previous then
        local valid = self:import(previous)
        if not valid then
            self.blocked = true
            return self:_fail("Save blocked. Existing configuration is invalid and has been preserved.")
        end
    end
    if not self:_verifiedWrite(self.FILES.pending, raw) then return self:_fail("Save failed while staging configuration; previous save preserved.") end
    if previous and not self:_verifiedWrite(self.FILES.backup, previous) then return self:_fail("Save failed while preserving backup; previous save preserved.") end
    if not self:_verifiedWrite(self.FILES.saved, raw) then
        if previous then pcall(self.capabilities._functions.writefile, self.FILES.saved, previous) end
        return self:_fail("Save failed during final write. Previous backup and staged data remain available.")
    end
    local remove = self.capabilities._functions.delfile
    if type(remove) == "function" then pcall(remove, self.FILES.pending) end
    self.capabilities.storage.status = "Supported and verified"
    self.capabilities.storage.detail = "Last Save wrote and read back validated JSON."
    return true, "Profile persisted locally and verified by readback. Automatic execution must be configured separately."
end

function Storage:draft(state, context)
    context = Util.copy(context or self.context)
    local path = self:_draftPath(context)
    if context and path == self.FILES.draft then return false, "Invalid draft context." end
    state = Util.copy(state)
    if type(state) == "table" and context then
        if state.context and not Util.equal(state.context, context) then return false, "Draft context changed before recording; previous recovery preserved." end
        state.context = context
    end
    local valid, reason = validateState(state)
    if not valid then return false, "Invalid draft: " .. tostring(reason) end
    if not self:_available() then return false, "Draft recovery unavailable without local storage." end
    local raw, err = self:_encode({version = Config.VERSION, draft = true, state = state})
    if not raw then return false, err end
    -- A corrupt draft is also user data; keep it until explicitly cleared.
    local previous, readError = self:_read(path)
    if not previous and readError ~= "missing" then return false, readError end
    if previous then
        local old = self:_decode(previous)
        if not old or old.version ~= Config.VERSION or (old.draft ~= false and (old.draft ~= true or not validateState(old.state))) then return false, "Damaged draft preserved; clear it explicitly before recording another draft." end
        if old.draft == true and not Util.equal(old.state.context, state.context) then return false, "Recovery draft from another context preserved; discard it explicitly before recording another draft." end
    end
    if not self:_verifiedWrite(path, raw) then
        if previous then pcall(self.capabilities._functions.writefile, path, previous) end
        return false, "Draft write failed. Saved profiles are preserved."
    end
    return true, "Unsaved draft recorded separately from profiles."
end

function Storage:loadDraft(context)
    if not self:_available() then return nil, "Draft recovery unavailable without local storage." end
    context = Util.copy(context or self.context)
    local path = self:_draftPath(context)
    if context and path == self.FILES.draft then return nil, "Invalid draft context." end
    local raw, err, unreadable = self:_read(path)
    if not raw then return nil, err, unreadable end
    local value, reason = self:_decode(raw)
    if not value then return nil, reason, true end
    if self:_foreignDraft(value, context) then return nil, "Draft belongs to another context." end
    if value.version == Config.VERSION and value.draft == false then return nil, "No recoverable draft." end
    if value.version ~= Config.VERSION or value.draft ~= true then return nil, "Incompatible draft.", true end
    local valid, why = validateState(value.state)
    if not valid then return nil, "Invalid draft: " .. tostring(why), true end
    if context and not Util.equal(value.state.context, context) then return nil, "Draft context is missing or invalid.", true end
    return Util.copy(value.state)
end

function Storage:clearDraft(context)
    if not self:_available() then return false, "Draft storage unavailable." end
    context = Util.copy(context or self.context)
    local path = self:_draftPath(context)
    if context and path == self.FILES.draft then return false, "Invalid draft context." end
    local exists, err = self:_exists(path)
    if exists == nil then return false, err end
    if not exists then return true, "No draft to clear." end
    if context then
        local raw = self:_read(path)
        local value = raw and self:_decode(raw)
        if self:_foreignDraft(value, context) then
            return false, "Draft belongs to another context and was preserved."
        end
    end
    local remove = self.capabilities._functions.delfile
    if type(remove) ~= "function" then
        local raw, encodeError = self:_encode({version = Config.VERSION, draft = false})
        if not raw then return false, encodeError end
        if self:_verifiedWrite(path, raw) then return true, "Draft discarded; saved profiles preserved." end
        return false, "Draft could not be discarded."
    end
    local ok = pcall(remove, path)
    local remaining = self:_exists(path)
    if not ok or remaining ~= false then return false, "Draft could not be deleted." end
    return true, "Draft discarded; saved profiles preserved."
end

function Storage:copy(text)
    if type(text) ~= "string" or #text > self.MAX_BYTES then return false, "Invalid clipboard content." end
    if type(self.capabilities._clipboard) ~= "function" then return false, "Clipboard unavailable; manually copy the JSON field." end
    local ok = pcall(self.capabilities._clipboard, text)
    self.capabilities.clipboard.status = ok and "Supported and verified" or "Failed"
    self.capabilities.clipboard.detail = ok and "Clipboard API accepted the export; paste to verify destination." or "Clipboard call failed; manually copy the JSON field."
    return ok, self.capabilities.clipboard.detail
end

return Storage
