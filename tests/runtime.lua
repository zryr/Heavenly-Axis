-- Public-API Roblox mocks: verifies adapter logic, not Roblox rendering or executor compatibility.
local assertions = 0
local function check(value, message)
    assertions = assertions + 1
    assert(value, message or "Assertion failed")
end
local function near(a, b, message) check(math.abs(a - b) < 0.001, (message or "Unexpected value") .. ": " .. tostring(a) .. " vs " .. tostring(b)) end
local pending = {}
task = {delay = function(_, callback) pending[#pending + 1] = callback end}
local function flush()
    local queue = pending
    pending = {}
    for _, callback in ipairs(queue) do callback() end
end
UDim2 = {new = function(xs, xo, ys, yo) return {X = {Scale = xs, Offset = xo}, Y = {Scale = ys, Offset = yo}} end}
local function signal()
    local result = {callbacks = {}}
    function result:Connect(callback)
        local connection = {connected = true}
        self.callbacks[#self.callbacks + 1] = {callback = callback, connection = connection}
        function connection:Disconnect() self.connected = false end
        return connection
    end
    function result:Fire(...)
        for _, item in ipairs(self.callbacks) do if item.connection.connected then item.callback(...) end end
    end
    return result
end
local Object = {}
local guiClasses = {Frame = true, ImageButton = true, TextButton = true, TextLabel = true, ImageLabel = true, ScrollingFrame = true}
function Object:IsA(class)
    return self.ClassName == class or (class == "GuiObject" and guiClasses[self.ClassName])
        or (class == "GuiButton" and (self.ClassName == "ImageButton" or self.ClassName == "TextButton"))
        or (class == "UIGridStyleLayout" and (self.ClassName == "UIListLayout" or self.ClassName == "UIGridLayout"))
end
function Object:GetChildren()
    local result = {}
    for _, child in ipairs(self._children) do result[#result + 1] = child end
    return result
end
function Object:GetDescendants()
    local result = {}
    local function visit(object)
        for _, child in ipairs(object._children) do result[#result + 1] = child; visit(child) end
    end
    visit(self)
    return result
end
function Object:GetPropertyChangedSignal(name)
    if not self._signals[name] then self._signals[name] = signal() end
    return self._signals[name]
end
function Object:Destroy() self.Parent = nil end
local function ownScale(object)
    local result = 1
    for _, child in ipairs(object._children) do if child.ClassName == "UIScale" then result = result * child.Scale end end
    return result
end
local function parentScale(object)
    local result, current = 1, object.Parent
    while current and current.ClassName ~= "PlayerGui" do result = result * ownScale(current); current = current.Parent end
    return result
end
local function computedSize(object)
    if object.ClassName == "PlayerGui" or object.ClassName == "ScreenGui" then return {X = 1000, Y = 600} end
    local parent = object.Parent
    local parentSize = parent and parent.AbsoluteSize or {X = 1000, Y = 600}
    local s, q, scale = object.Size, parentScale(object), ownScale(object)
    local x, y = (s.X.Scale * parentSize.X + s.X.Offset * q) * scale, (s.Y.Scale * parentSize.Y + s.Y.Offset * q) * scale
    for _, child in ipairs(object._children) do if child.ClassName == "UIAspectRatioConstraint" then y = x / child.AspectRatio end end
    return {X = x, Y = y}
end
local function computedPosition(object)
    if object.ClassName == "PlayerGui" or object.ClassName == "ScreenGui" then return {X = 0, Y = 0} end
    local parent = object.Parent
    local p = parent and parent.AbsolutePosition or {X = 0, Y = 0}
    local s = parent and parent.AbsoluteSize or {X = 1000, Y = 600}
    local position, anchor, q, size = object.Position, object.AnchorPoint, parentScale(object), object.AbsoluteSize
    return {X = p.X + position.X.Scale * s.X + position.X.Offset * q - anchor.X * size.X,
        Y = p.Y + position.Y.Scale * s.Y + position.Y.Offset * q - anchor.Y * size.Y}
end
local Meta = {
    __index = function(object, key)
        if Object[key] then return Object[key] end
        if key == "AbsoluteSize" then return computedSize(object) end
        if key == "AbsolutePosition" then return computedPosition(object) end
        return object._props[key]
    end,
    __newindex = function(object, key, value)
        if key == "Size" and object._props.rejectSize then error("Mock rejected Size") end
        if key == "Parent" then
            local old = object._props.Parent
            if old then
                local ancestor = old
                while ancestor do ancestor.DescendantRemoving:Fire(object); ancestor = ancestor.Parent end
                for i, child in ipairs(old._children) do if child == object then table.remove(old._children, i); break end end
            end
            object._props.Parent = value
            if value then
                value._children[#value._children + 1] = object
                local ancestor = value
                while ancestor do ancestor.DescendantAdded:Fire(object); ancestor = ancestor.Parent end
            end
        else object._props[key] = value end
        if object._signals[key] then object._signals[key]:Fire() end
    end,
}
local function create(class, name, parent)
    local object = setmetatable({_props = {ClassName = class, Name = name, Visible = true, Enabled = true,
        Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(0, 100, 0, 100), AnchorPoint = {X = 0, Y = 0},
        AutomaticSize = "None", Rotation = 0, BackgroundTransparency = 0, ZIndex = 1, DisplayOrder = 0, Scale = 1,
        AspectRatio = 1, ClipsDescendants = false}, _children = {}, _signals = {},
        DescendantAdded = signal(), DescendantRemoving = signal()}, Meta)
    if parent then object.Parent = parent end
    return object
end
local Discovery = require("Discovery")
local Transform = require("Transform")
local Util = require("Util")
local messages = {}
local function log(message) messages[#messages + 1] = message end
local root = create("PlayerGui", "PlayerGui")
local screen = create("ScreenGui", "GameHUD", root)
local parent = create("Frame", "Parent", screen)
parent.Position, parent.Size = UDim2.new(0, 40, 0, 30), UDim2.new(0.5, 0, 0.5, 0)
local child = create("ImageButton", "Child", parent)
child.Position, child.Size = UDim2.new(0.5, 10, 0.4, 5), UDim2.new(0.1, 40, 0.2, 30)
child.AnchorPoint = {X = 0.5, Y = 0.5}
local ancestorScale = create("UIScale", "Scale", parent)
ancestorScale.Scale = 1.5
local selfScale = create("UIScale", "Scale", child)
selfScale.Scale = 0.8
local own = create("ScreenGui", "HeavenlyAxis_V3", root)
create("TextButton", "EditorButton", own)
local changes = 0
local discovery = Discovery.new(root, nil, log)
discovery:start(function() changes = changes + 1 end)
local function key(object) return discovery.byObject[object].key end
local transform = Transform.new(discovery, log)
check(#discovery:list() == 2, "Own UI excluded")
check(discovery.byObject[child].editable, "Basic GUI should be editable")
local rects, keys = transform:selectionRects({key(parent), key(child), key(child)})
check(#rects == 1 and keys[1] == key(parent), "Nested selections prune descendants and duplicates")
local before = Discovery.serialize(child)
local oldRect = transform:selectionRects({key(child)})
oldRect = oldRect[1]
local target = {x = oldRect.x + 23, y = oldRect.y - 12, w = oldRect.w + 45, h = oldRect.h + 30}
local ok, reason = transform:setRects({key(child)}, {target})
check(ok, reason)
near(child.AbsolutePosition.X, target.x, "UIScale/anchor move X")
near(child.AbsolutePosition.Y, target.y, "UIScale/anchor move Y")
near(child.AbsoluteSize.X, target.w, "UIScale size X")
near(child.AbsoluteSize.Y, target.h, "UIScale size Y")
near(child.Position.X.Scale, before.position.xs, "Position scale preserved")
near(child.Size.X.Scale, before.size.xs, "Size scale preserved")
local saved = transform:capture()
check(saved[key(child)] ~= nil and saved[key(parent)] == nil, "Only edited GUI is serialized")
local applied, skipped = transform:apply(saved)
check(applied == 1 and skipped == 0, "Saved layout applies")
transform:apply(saved)
near(child.AbsolutePosition.X, target.x, "Repeated application does not compound")
near(child.AbsoluteSize.X, target.w, "Repeated size does not compound")
transform:restore()
check(Util.equal(Discovery.serialize(child), before), "Restore original properties")
transform:apply(saved)
transform:apply({}, {replace = true})
check(Util.equal(Discovery.serialize(child), before), "Replacement restores omitted targets")
check(next(transform:capture()) == nil, "Replacement clears tracking")
local originalChildKey = key(child)
child:Destroy()
flush()
check(discovery:get(originalChildKey) == nil, "Destroyed target removed")
check(#transform:matches(saved) == 1, "Missing configurations remain unresolved")
local recreated = create("ImageButton", "Child", parent)
recreated.Position, recreated.Size, recreated.AnchorPoint = UDim2.new(0.5, 10, 0.4, 5), UDim2.new(0.1, 40, 0.2, 30), {X = 0.5, Y = 0.5}
local recreatedScale = create("UIScale", "Scale", recreated)
recreatedScale.Scale = 0.8
flush()
check(key(recreated) == originalChildKey, "Exact recreated hierarchy matches")
applied, skipped = transform:apply(saved)
check(applied == 1 and skipped == 0, "Recreated target restored")
near(recreated.AbsolutePosition.X, target.x, "Recreated target coordinates")
local duplicate = create("ImageButton", "Child", parent)
flush()
check(not discovery.byObject[recreated].editable, "Ambiguous same-name hierarchy disabled")
check(#transform:matches(saved) == 1, "Saved descriptor cannot match ambiguous candidate")
check(not transform:setRects({key(recreated)}, {target}), "Ambiguous target cannot transform")
duplicate:Destroy()
flush()
local hidden = create("Frame", "Hidden", screen)
hidden.Visible = false
local hiddenChild = create("Frame", "HiddenChild", hidden)
flush()
check(discovery.byObject[hiddenChild] ~= nil, "Hidden objects retain identity for restoration")
for _, item in ipairs(discovery:list()) do check(item.object ~= hiddenChild and item.object ~= hidden, "Hidden hierarchy filtered") end
local managed = create("Frame", "Managed", screen)
local item = create("Frame", "Item", managed)
create("UIListLayout", "Layout", managed)
flush()
check(discovery.byObject[item].experimental and not discovery.byObject[item].editable, "Layout opt-in required")
local managedRect = transform:selectionRects({key(item)})
check(not transform:setRects({key(item)}, managedRect), "Unapproved experimental target rejected")
check(discovery:approve(key(item), true), "Per-element experimental approval")
check(transform:setRects({key(item)}, {{x = 20, y = 30, w = 100, h = 100}}), "Approved reversible write allowed")
flush()
transform.safe = true
check(not transform:setRects({key(item)}, {{x = 30, y = 30, w = 100, h = 100}}), "Safe Mode blocks experimental")
transform.safe = false
local constrained = create("Frame", "Constrained", screen)
create("UIAspectRatioConstraint", "Aspect", constrained)
flush()
discovery:approve(key(constrained), true)
for _ = 1, 3 do
    check(transform:setRects({key(constrained)}, {{x = 0, y = 0, w = 120, h = 80}}), "Experimental attempt starts")
    flush()
end
check(discovery.byObject[constrained].experimentalSuspended, "Three failed stabilization checks suspend override")
check(not transform:setRects({key(constrained)}, {{x = 0, y = 0, w = 120, h = 80}}), "Suspended override refuses more attempts")
local a = create("Frame", "A", screen)
local b = create("Frame", "B", screen)
flush()
local baselineA, baselineB = Discovery.serialize(a), Discovery.serialize(b)
b.rejectSize = true
ok = transform:setRects({key(a), key(b)}, {{x = 20, y = 20, w = 120, h = 120}, {x = 60, y = 60, w = 120, h = 120}})
check(not ok, "Rejected group transaction fails")
check(Util.equal(Discovery.serialize(a), baselineA), "Previously applied group member rolls back")
check(Util.equal(Discovery.serialize(b), baselineB), "Rejected group member stays original")
b.rejectSize = false
local rotatedParent = create("Frame", "RotatedParent", screen)
rotatedParent.Rotation = 15
local rotatedChild = create("Frame", "RotatedChild", rotatedParent)
flush()
check(not discovery.byObject[rotatedChild].editable, "Rotated ancestor rejects screen-space geometry")
check(not transform:setRects({key(a)}, {{x = 0/0, y = 1, w = 100, h = 100}}), "Non-finite geometry rejected")
check(not transform:setRects({key(a)}, {{x = 0, y = 1, w = 1, h = 100}}), "Impractically small size rejected")
local hit = discovery:hit(a.AbsolutePosition.X + 5, a.AbsolutePosition.Y + 5)
check(#hit > 0, "Hit fallback finds visible targets")
-- Completed gesture boundaries retain the initial snapshot across pointer frames.
local normal = create("Frame", "NormalOverwrite", screen)
flush()
local normalKey, normalBaseline = key(normal), Discovery.serialize(normal)
transform:beginTransaction()
check(transform:setRects({normalKey}, {{x = 20, y = 20, w = 120, h = 120}}), "First drag update")
check(transform:setRects({normalKey}, {{x = 40, y = 40, w = 140, h = 140}}), "Second drag update")
check(#pending == 0, "No stabilization timer is added per drag frame")
normal.Position = UDim2.new(0, 777, 0, 777) -- A game script replaces the edit.
transform:endTransaction()
check(#pending == 1, "One stabilization check per completed drag")
flush()
check(Util.equal(Discovery.serialize(normal), normalBaseline), "Unstable drag rolls back the entire action")
check(discovery.byObject[normal].experimental and not discovery.byObject[normal].editable, "Detected script-managed target requires explicit approval")
local rollback = transform:capture()[normalKey]
check(rollback and Util.equal(rollback.position, normalBaseline.position), "Rollback snapshot remains available to App capture")
check(discovery:approve(normalKey, true), "Detected script-managed target can be explicitly approved")
transform:apply({}, {replace = true})
check(not discovery.approved[normalKey], "Replacing layout revokes absent experimental permission")
check(not discovery.byObject[normal].editable, "Revoked experimental target stays noneditable")

-- Imports cannot make a new invalid tiny target, but exact original dimensions can be restored.
local tiny = create("Frame", "TinyOriginal", screen)
tiny.Size = UDim2.new(0, 8, 0, 8)
flush()
local tinyEntry = Discovery.serialize(tiny)
tinyEntry.descriptor = Util.copy(discovery.byObject[tiny].descriptor)
applied, skipped = transform:apply({[key(tiny)] = tinyEntry})
check(applied == 1 and skipped == 0, "Original small dimensions may be restored")
local invalidTiny = Util.copy(tinyEntry)
invalidTiny.size = {xs = 0, xo = 0, ys = 0, yo = -100}
applied, skipped = transform:apply({[key(tiny)] = invalidTiny})
check(applied == 0 and skipped == 1, "New effective invalid imported dimensions are rejected")
near(tiny.AbsoluteSize.X, 8, "Rejected import leaves original small target intact")
flush()

-- Even direct adapter use without explicit transaction boundaries maintains one pending timer.
local quick = create("Frame", "QuickUpdates", screen)
flush()
for i = 1, 40 do check(transform:setRects({key(quick)}, {{x = i, y = i, w = 100, h = 100}}), "Pointer update accepted") end
check(#pending == 1, "Pointer updates are debounced to one timer")
flush()
check(#pending == 1, "Newer update reschedules one quiet-period check")
flush()
check(#pending == 0, "Stabilization stops after the quiet-period check")
check(not discovery.byObject[quick].experimental, "Stable normal target does not require experimental editing")

-- Lifecycle receipts permit restoration of new instances without fighting existing scripts.
local lifecycle = create("Frame", "LifecycleReceipt", screen)
flush()
local lifecycleKey = key(lifecycle)
local lifecycleEntry = Discovery.serialize(lifecycle)
lifecycleEntry.descriptor = Util.copy(discovery.byObject[lifecycle].descriptor)
lifecycleEntry.position.xo = 35
check(transform:apply({[lifecycleKey] = lifecycleEntry}) == 1, "Initial lifecycle request applies")
flush()
lifecycle.Position = UDim2.new(0, 777, 0, 0)
applied, skipped = transform:apply({[lifecycleKey] = lifecycleEntry}, {onlyNew = true})
check(applied == 0 and skipped == 0 and lifecycle.Position.X.Offset == 777,
    "unrelated lifecycle events never re-enforce the same request against an existing object")
lifecycle:Destroy(); flush()
lifecycle = create("Frame", "LifecycleReceipt", screen); flush()
check(key(lifecycle) == lifecycleKey and transform:apply({[lifecycleKey] = lifecycleEntry}, {onlyNew = true}) == 1,
    "a recreated exact identity receives saved properties despite the old instance receipt")
flush()
near(lifecycle.Position.X.Offset, 35, "Recreated lifecycle position restored once")

local revoked = create("Frame", "RevokedReceipt", managed)
flush()
local revokedKey = key(revoked)
local revokedEntry = Discovery.serialize(revoked)
revokedEntry.descriptor = Util.copy(discovery.byObject[revoked].descriptor)
revokedEntry.position.xo, revokedEntry.experimental = 12, true
check(transform:apply({[revokedKey] = revokedEntry}, {experimental = true}) == 1,
    "explicitly approved managed target may be adjusted")
flush()
revokedEntry.experimental = false
transform:apply({[revokedKey] = revokedEntry}, {onlyNew = true})
near(revoked.Position.X.Offset, 0, "Revocation restores original position once")
revoked.Position = UDim2.new(0, 444, 0, 0) -- Its owning layout resumes control.
local writesAfterRevoke = 0
local revokeConnection = revoked:GetPropertyChangedSignal("Position"):Connect(function() writesAfterRevoke = writesAfterRevoke + 1 end)
transform:apply({[revokedKey] = revokedEntry}, {onlyNew = true})
transform:apply({[revokedKey] = revokedEntry}, {onlyNew = true})
check(writesAfterRevoke == 0 and revoked.Position.X.Offset == 444 and not discovery.byObject[revoked].editable,
    "revoked approval never restores the baseline repeatedly during unrelated HUD events")
revokeConnection:Disconnect()

local connections = {}
for _, connection in ipairs(discovery.connections) do connections[#connections + 1] = connection end
for _, list in pairs(discovery.objectConnections) do for _, connection in ipairs(list) do connections[#connections + 1] = connection end end
discovery:destroy()
for _, connection in ipairs(connections) do check(not connection.connected, "Destroy disconnects every subscription") end
transform:destroy()
flush()
check(next(discovery.records) == nil and next(transform.tracked) == nil, "Destroy releases GUI references")
return assertions
