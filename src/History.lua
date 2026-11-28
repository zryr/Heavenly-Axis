local Util = require("Util")
local History = {}
History.__index = History

function History.new(limit)
    return setmetatable({ limit = math.max(1, math.floor(limit or 80)), past = {}, future = {}, saved = {} }, History)
end

function History:push(before, after, label)
    if Util.equal(before, after) then return false end
    self.past[#self.past + 1] = { before = Util.copy(before), after = Util.copy(after), label = label or "Edit" }
    if #self.past > self.limit then table.remove(self.past, 1) end
    self.future = {}
    return true
end

function History:undo()
    local entry = table.remove(self.past)
    if not entry then return nil, "Nothing to undo" end
    self.future[#self.future + 1] = entry
    return Util.copy(entry.before), entry.label
end

function History:redo()
    local entry = table.remove(self.future)
    if not entry then return nil, "Nothing to redo" end
    self.past[#self.past + 1] = entry
    return Util.copy(entry.after), entry.label
end

function History:checkpoint(state) self.saved = Util.copy(state) end
function History:dirty(state) return not Util.equal(state, self.saved) end
function History:cancel()
    self.past, self.future = {}, {}
    return Util.copy(self.saved)
end

return History
