-- Public-API Roblox mocks: verifies adapter logic, not Roblox rendering or executor compatibility.
local assertions = 0
local function check(value, message)
    assertions = assertions + 1
    assert(value, message or "Assertion failed")
end
local function near(a, b, message) check(math.abs(a - b) < 0.001, (message or "Unexpected value") .. ": " .. tostring(a) .. " vs " .. tostring(b)) end
local pending, scheduledDelay = {}, nil
task = {delay = function(delay, callback)
    scheduledDelay = delay
    pending[#pending + 1] = callback
end}
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
local function controller(parent)
    if not parent then return nil end
    for _, child in ipairs(parent._children) do
        if child.ClassName == "UIListLayout" or child.ClassName == "UIGridLayout" then return child end
    end
    return nil
end
local function guiSiblings(parent)
    local result = {}
    for _, sibling in ipairs(parent._children) do
        if sibling:IsA("GuiObject") and sibling.Visible then result[#result + 1] = sibling end
    end
    return result
end
local function computedSize(object)
    if object.ClassName == "PlayerGui" or object.ClassName == "ScreenGui" then return {X = 1000, Y = 600} end
    local parent = object.Parent
    local parentSize = parent and parent.AbsoluteSize or {X = 1000, Y = 600}
    local layout = controller(parent)
    if layout and layout.ClassName == "UIGridLayout" then return {X = layout.CellWidth or 64, Y = layout.CellHeight or 56} end
    if layout and layout.HorizontalFlex == "Fill" then return {X = parentSize.X / #guiSiblings(parent), Y = 56} end
    if layout and layout.forceWidth then return {X = layout.forceWidth, Y = 56} end
    local s, q, scale = object.Size, parentScale(object), ownScale(object)
    local basisX, basisY = parentSize.X, parentSize.Y
    if object.SizeConstraint == "RelativeXX" then basisY = basisX end
    if object.SizeConstraint == "RelativeYY" then basisX = basisY end
    local x, y = (s.X.Scale * basisX + s.X.Offset * q) * scale, (s.Y.Scale * basisY + s.Y.Offset * q) * scale
    for _, child in ipairs(object._children) do if child.ClassName == "UIAspectRatioConstraint" then y = x / child.AspectRatio end end
    return {X = x, Y = y}
end
local function computedPosition(object)
    if object.ClassName == "PlayerGui" or object.ClassName == "ScreenGui" then return {X = 0, Y = 0} end
    local parent = object.Parent
    local p = parent and parent.AbsolutePosition or {X = 0, Y = 0}
    local s = parent and parent.AbsoluteSize or {X = 1000, Y = 600}
    local position, anchor, q, size = object.Position, object.AnchorPoint, parentScale(object), object.AbsoluteSize
    local layout = controller(parent)
    if layout then
        local siblings, gap, width = guiSiblings(parent), layout.Gap or 0, 0
        for _, sibling in ipairs(siblings) do width = width + sibling.AbsoluteSize.X end
        width = width + math.max(0, #siblings - 1) * gap
        local x = p.X + (layout.HorizontalAlignment == "Center" and (s.X - width) / 2 or 0)
        for _, sibling in ipairs(siblings) do
            if sibling == object then break end
            x = x + sibling.AbsoluteSize.X + gap
        end
        return {X = x, Y = p.Y}
    end
    return {X = p.X + position.X.Scale * s.X + position.X.Offset * q - anchor.X * size.X,
        Y = p.Y + position.Y.Scale * s.Y + position.Y.Offset * q - anchor.Y * size.Y}
end
local Meta = {
    __index = function(object, key)
        if Object[key] then return Object[key] end
        if key == "AbsoluteSize" then return object._props.frozenSize or computedSize(object) end
        if key == "AbsolutePosition" then return object._props.frozenPosition or computedPosition(object) end
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
managed.Size = UDim2.new(0, 400, 0, 100)
local item = create("TextButton", "Ability1", managed)
local adjacentAbility = create("TextButton", "Ability2", managed)
local listLayout = create("UIListLayout", "Layout", managed)
listLayout.HorizontalAlignment, listLayout.Gap = "Center", 8
flush()
local itemKey, itemRecord = key(item), discovery.byObject[item]
local originalPosition, alternateX = item.Position, adjacentAbility.AbsolutePosition.X
check(not itemRecord.capabilities.move.supported and itemRecord.capabilities.resize.supported and not itemRecord.experimental,
    "Plain listed ability can resize without an experimental approval, while its layout owns movement")
check(not transform:setRects({itemKey}, {{x = 25, y = 30, w = 100, h = 100}}, "move"), "Known layout-managed movement is blocked immediately")
discovery:approve(itemKey, true)
check(not transform:setRects({itemKey}, {{x = 25, y = 30, w = 100, h = 100}}, "move"), "Approval cannot bypass a known list layout")
discovery:approve(itemKey, false)
local listPositionWrites = 0
local listPositionConnection = item:GetPropertyChangedSignal("Position"):Connect(function() listPositionWrites = listPositionWrites + 1 end)
check(transform:beginTransaction(), "List size transaction starts")
check(transform:setRects({itemKey}, {{x = 300, y = 211, w = 140, h = 110}}, "resize"), "List size uses only supported Size")
local listOutcome
transform:endTransaction(function(success) listOutcome = success end)
flush()
check(listOutcome == true and listPositionWrites == 0 and item.Position == originalPosition, "Real layout reflow does not invalidate independent size verification")
near(item.AbsoluteSize.X, 140, "Managed ability visibly changes width")
check(adjacentAbility.AbsolutePosition.X ~= alternateX, "Plain-list fixture models sibling reflow")
local listSaved = transform:capture()[itemKey]
check(listSaved.position.xo == 0 and listSaved.size.xo == 140, "Checkpoint retains original raw position and chosen size")
check(transform:restore({itemKey}) == 1 and transform:apply({[itemKey] = listSaved}) == 1, "Reset and restore a managed ability size")
flush()
near(item.AbsoluteSize.X, 140, "Saved size is restored without writing Position")
local legacyList = Util.copy(listSaved)
legacyList.position.xo, legacyList.size.xo = 47, 145
applied, skipped = transform:apply({[itemKey] = legacyList})
check(applied == 1 and skipped == 1 and listPositionWrites == 0, "Legacy unsupported Position is reported independently of a supported saved Size")
flush()
local parentRect = transform:selectionRects({key(managed)})[1]
local abilityX = item.AbsolutePosition.X
check(transform:setRects({key(managed)}, {{x = parentRect.x + 22, y = parentRect.y, w = parentRect.w, h = parentRect.h}}, "move"),
    "Move the compatible entire ability bar")
flush()
near(item.AbsolutePosition.X, abilityX + 22, "Parent move relocates its controls without changing their raw positions")
check(listPositionWrites == 0, "No supported list operation writes the managed Position")
listPositionConnection:Disconnect()

local flex = create("Frame", "FlexBar", screen)
local flexAbility = create("TextButton", "Ability1", flex)
local flexLayout = create("UIListLayout", "Layout", flex)
flexLayout.HorizontalFlex = "Fill"
local grid = create("Frame", "GridBar", screen)
local gridAbility = create("TextButton", "Ability1", grid)
create("UIGridLayout", "Layout", grid)
flush()
for _, control in ipairs({flexAbility, gridAbility}) do
    local record = discovery.byObject[control]
    check(not record.capabilities.move.supported and not record.capabilities.resize.supported
        and record.capabilities.transparency.supported and not record.experimental, "Managed flex/grid control supports visual properties only")
    local rect = transform:selectionRects({record.key})[1]
    check(not transform:setRects({record.key}, {{x = rect.x, y = rect.y, w = 101, h = 82}}, "resize"), "Known controller size is rejected without a trial write")
    check(transform:setProperty({record.key}, "transparency", 0.45) == 1, "Layout child still supports independent transparency")
    near(control.BackgroundTransparency, 0.45, "Visual property writes without attempting geometry")
end

local constrained = create("Frame", "Constrained", screen)
create("UIAspectRatioConstraint", "Aspect", constrained)
local automatic = create("Frame", "Automatic", screen)
automatic.AutomaticSize = "X"
flush()
for _, control in ipairs({constrained, automatic}) do
    local record = discovery.byObject[control]
    check(record.capabilities.move.supported and not record.capabilities.resize.supported and not record.experimental,
        "Known size control blocks only resizing, without encouraging repeat experiments")
    check(not transform:setRects({record.key}, {{x = 0, y = 0, w = 120, h = 80}}, "resize"), "Constrained size is blocked before a write")
    check(transform:setRects({record.key}, {{x = 12, y = 8, w = 100, h = 100}}, "move"), "Own size constraints do not prevent moving the layer")
    flush()
    near(control.AbsolutePosition.X, 12, "Requested supported movement is applied")
end
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
check(not discovery.byObject[rotatedChild].capabilities.move.supported and discovery.byObject[rotatedChild].capabilities.transparency.supported,
    "Rotated ancestor rejects screen-space geometry and preserves visual operations")
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
local normalRecord = discovery.byObject[normal]
check(normalRecord.experimental and not normalRecord.capabilities.move.supported and normalRecord.capabilities.resize.supported,
    "Detected script overwrite requires approval only for the replaced property")
check(transform:capture()[normalKey] == nil, "Rollback restores absence of a previous override")
check(discovery:approve(normalKey, true), "Detected script-managed target can be explicitly approved")
for _ = 1, 3 do
    check(transform:setRects({normalKey}, {{x = 40, y = 40, w = 100, h = 100}}, "move"), "Approved position can be tested once per completed action")
    normal.Position = UDim2.new(0, 777, 0, 777)
    flush()
end
check(normalRecord.suspendedOperations.position and not normalRecord.capabilities.move.supported,
    "Repeated observed position overwrites suspend only independent movement")
check(normalRecord.capabilities.resize.supported and normalRecord.capabilities.transparency.supported,
    "Suspended position cannot disable safe resize and visual operations")
transform.safe = true
check(transform:setRects({normalKey}, {{x = 0, y = 0, w = 110, h = 110}}, "resize"), "Safe Mode permits supported independent resizing")
flush()
check(not transform:setRects({normalKey}, {{x = 40, y = 40, w = 110, h = 110}}, "move"), "Safe Mode blocks experimental movement")
transform.safe = false
transform:apply({}, {replace = true})
check(not discovery.approved[normalKey], "Replacing layout revokes absent experimental permission")
check(not normalRecord.capabilities.move.supported and normalRecord.capabilities.resize.supported,
    "Revoked experimental operation stays blocked while safe resize remains available")

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

local revoked = create("Frame", "RevokedReceipt", screen)
flush()
local revokedKey = key(revoked)
discovery.byObject[revoked].overwrittenProperties = {position = true}
discovery:_classify(discovery.byObject[revoked])
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
check(writesAfterRevoke == 0 and revoked.Position.X.Offset == 444 and not discovery.byObject[revoked].capabilities.move.supported,
    "revoked approval never restores the baseline repeatedly during unrelated HUD events")
revokeConnection:Disconnect()

-- Roblox layout reads can lag behind two input updates in the same frame.
local deferred = create("Frame", "DeferredGeometry", screen)
flush()
local deferredKey = key(deferred)
deferred.AnchorPoint = {X = 0.5, Y = 0.5}
local deferredBefore = Discovery.serialize(deferred)
local original = transform:selectionRects({deferredKey})[1]
deferred.frozenPosition, deferred.frozenSize = deferred.AbsolutePosition, deferred.AbsoluteSize
check(transform:beginTransaction(), "Deferred geometry transaction starts")
check(transform:setRects({deferredKey}, {{x = original.x + 7, y = original.y + 9, w = 140, h = 130}}), "First deferred write")
local finalRect = {x = original.x + 18, y = original.y + 24, w = 160, h = 150}
check(transform:setRects({deferredKey}, {finalRect}), "Second write uses a stable geometry reference")
near(deferred.Position.X.Offset, 48, "Accumulated drag never double-counts previous X offset")
near(deferred.Size.Y.Offset, 150, "Accumulated resize never double-counts previous height")
local outcome
check(transform:endTransaction(function(ok) outcome = ok end), "Completion callback is registered")
check(outcome == nil and not transform:beginTransaction(), "History can await verified geometry before another edit")
near(scheduledDelay, 0.04, "An ordinary adjustment uses the earlier geometry check")
flush()
check(outcome == nil and #pending == 1, "A slow layout gets one additional check without confirming stale geometry")
near(scheduledDelay, 0.10, "Retry uses the full observation window")
deferred.frozenPosition, deferred.frozenSize = nil, nil
flush()
check(outcome == true, "Delayed real geometry is confirmed after layout catches up")
near(deferred.AbsolutePosition.X, finalRect.x, "Deferred geometry lands at requested position")
near(deferred.AbsoluteSize.Y, finalRect.h, "Deferred geometry lands at requested height")
local verified = transform:capture()[deferredKey]
check(transform:beginTransaction(), "Cancellation starts from a verified layout")
check(transform:setRects({deferredKey}, {{x = 100, y = 100, w = 180, h = 180}}), "Cancellation has a provisional write")
check(transform:cancelTransaction() and Util.equal(transform:capture()[deferredKey], verified),
    "Cancellation restores prior portable request without reapplying other targets")
near(deferred.AbsolutePosition.X, finalRect.x, "Cancellation restores live geometry")
check(not Util.equal(Discovery.serialize(deferred), deferredBefore), "Cancellation preserves earlier completed action")

local replaced = create("Frame", "RecreatedDuringGesture", screen)
flush()
local replacedKey = key(replaced)
check(transform:beginTransaction(), "Start gesture before target is recreated")
check(transform:setRects({replacedKey}, {{x = 10, y = 10, w = 100, h = 100}}), "Move original target before replacement")
replaced:Destroy()
local replacement = create("Frame", "RecreatedDuringGesture", screen)
flush()
check(key(replacement) == replacedKey, "Replacement has the same portable identity")
check(not transform:setRects({replacedKey}, {{x = 40, y = 40, w = 100, h = 100}}), "Gesture cannot move a recreated instance")
check(transform:cancelTransaction(), "Recreation safely cancels old ownership")
near(replacement.Position.X.Offset, 0, "Replacement remains at its own baseline until explicit restoration")

local first = create("Frame", "IndependentFailure", screen)
local second = create("Frame", "IndependentSuccess", screen)
flush()
check(transform:setRects({key(first)}, {{x = 12, y = 12, w = 100, h = 100}}), "First standalone request")
first.Position = UDim2.new(0, 999, 0, 999)
check(transform:setRects({key(second)}, {{x = 44, y = 44, w = 100, h = 100}}), "Unrelated standalone request")
flush()
flush()
near(first.AbsolutePosition.X, 0, "Later unrelated request cannot replace earlier verification")
near(second.AbsolutePosition.X, 44, "Failed request never reverts unrelated geometry")
check(transform:capture()[key(first)] == nil and transform:capture()[key(second)] ~= nil,
    "Only the verified request remains available to checkpoint")

local selectedRects, selectedKeys, skippedTargets = transform:selectionRects({key(rotatedChild), key(second)}, true)
check(#selectedRects == 1 and selectedKeys[1] == key(second) and skippedTargets == 1,
    "Unsupported members remain selected for inspection and are counted when transforming supported members")
check(#transform:selectionRects({key(rotatedChild), key(second)}) == 2, "Inspection retains incompatible member bounds")

local relative = create("Frame", "RelativeSizeConstraint", screen)
relative.Size = UDim2.new(0.10, 0, 0.03, 0)
relative.SizeConstraint = "RelativeXX"
flush()
local relativeKey = key(relative)
local originalRelative = Discovery.serialize(relative)
check(transform:setRects({relativeKey}, {{x = 32, y = 17, w = 90, h = 25}}), "RelativeXX resize uses rendered dimensions")
flush()
near(relative.AbsoluteSize.Y, 25, "RelativeXX Y uses parent width")
local relativeLayout = {[relativeKey] = transform:capture()[relativeKey]}
check(transform:restore({relativeKey}) == 1 and Util.equal(Discovery.serialize(relative), originalRelative), "Constraint reset restores original raw properties")
check(transform:apply(relativeLayout) == 1, "Saved RelativeXX override passes effective size validation")
flush()
near(relative.AbsoluteSize.Y, 25, "Restored RelativeXX geometry matches the saved edit")

local growParent = create("Frame", "DeferredParent", screen)
local growChild = create("Frame", "ChildOfDeferredParent", growParent)
growParent.Size = UDim2.new(0, 40, 0, 40)
growChild.Size = UDim2.new(0, 25, 0, 25)
flush()
local parentEntry, childEntry = Discovery.serialize(growParent), Discovery.serialize(growChild)
parentEntry.size.xo, parentEntry.size.yo = 200, 200
childEntry.size = {xs = 0.24, xo = 0, ys = 0.24, yo = 0}
growParent.frozenSize = growParent.AbsoluteSize
applied, skipped = transform:apply({[key(growParent)] = parentEntry, [key(growChild)] = childEntry})
check(applied == 2 and skipped == 0, "Restoration projects pending ancestor dimensions before validating child layout")
growParent.frozenSize = nil
flush()
flush()
near(growChild.AbsoluteSize.X, 48, "Restored child uses the settled ancestor dimensions")

local clean = create("Frame", "NoOp", screen)
flush()
local cleanKey = key(clean)
check(transform:beginTransaction(), "No-op gesture can start")
check(transform:setRects({cleanKey}, {{x = 0, y = 0, w = 100, h = 100}}), "Exact already displayed rectangle is accepted")
local noOp
check(transform:endTransaction(function(ok) noOp = ok end) and noOp == true, "No-op resolves immediately")
check(transform:capture()[cleanKey] == nil and #pending == 0, "No-op creates no override or deferred work")

local sparse = create("Frame", "SparseInheritedSettings", screen)
flush()
local sparseKey = key(sparse)
local sparseEntry = Discovery.serialize(sparse)
sparseEntry.rotation, sparseEntry.transparency = nil, nil
sparseEntry.descriptor = Util.copy(discovery.byObject[sparse].descriptor)
check(transform:apply({[sparseKey] = sparseEntry}) == 1, "Apply a resolved entry with optional settings absent")
flush()
check(transform:beginTransaction(), "Move after applying sparse inherited configuration")
check(transform:setRects({sparseKey}, {{x = 22, y = 16, w = 100, h = 100}}), "Move writes only supported geometry")
sparse.BackgroundTransparency = 0.8
outcome = nil
check(transform:endTransaction(function(ok) outcome = ok end), "Move proceeds while a game animates unedited properties")
flush()
local sparseResult = transform:capture()[sparseKey]
check(outcome == true and sparseResult.position.xo == 22 and sparseResult.rotation == nil and sparseResult.transparency == nil,
    "Geometry edits never materialize unrelated optional fields into profile patches")
check(not transform.pendingStabilization and #pending == 0, "Resolved ordinary geometry releases the next action at the first check")
near(sparse.BackgroundTransparency, 0.8, "Geometry verification leaves the game's separate property unchanged")
check(transform:beginTransaction(), "Start second sparse edit")
check(transform:setRects({sparseKey}, {{x = 60, y = 60, w = 100, h = 100}}), "Write another provisional move")
sparse.BackgroundTransparency = 0.5
check(transform:cancelTransaction(), "Cancel only the owned edit")
near(sparse.BackgroundTransparency, 0.5, "Cancellation preserves changes to unowned game properties")
near(sparse.AbsolutePosition.X, 22, "Cancellation restores the edited position")

check(transform:setRects({key(tiny)}, {{x = 2, y = 4, w = 8, h = 8}}), "A small original control is still movable")
flush()
check(not transform:setRects({key(tiny)}, {{x = 2, y = 4, w = 12, h = 12}}), "Resizing to a new subminimum size is rejected")
near(tiny.AbsolutePosition.X, 2, "Small moved control remains at the last valid adjustment")

local historyBefore = {[deferredKey] = verified, [cleanKey] = Discovery.serialize(clean)}
historyBefore[cleanKey].position.xo = 35
check(transform:applyHistory({[deferredKey] = verified}, historyBefore, function(ok) outcome = ok end), "Replay adds a previous override")
check(transform:capture()[cleanKey] == nil, "Replay does not expose unverified overrides to the App state")
flush()
check(outcome == true and transform:capture()[cleanKey].position.xo == 35, "Replay commits the verified request")
outcome = nil
check(transform:applyHistory(historyBefore, {}, function(ok, reason) outcome = ok and true or reason end), "Replay can restore omitted targets")
clean.Position = UDim2.new(0, 123, 0, 0)
flush()
check(type(outcome) == "string" and transform:capture()[cleanKey].position.xo == 35,
    "Unstable restore reports failure and preserves the previous history state")
near(deferred.AbsolutePosition.X, finalRect.x, "One failed replay member rolls back both members")
near(clean.AbsolutePosition.X, 35, "Failed history replay restores the exact previous properties")
local removedKey = key(second)
local removedEntry = transform:capture()[removedKey]
second:Destroy()
flush()
local missing
check(transform:applyHistory({[removedKey] = removedEntry}, {}, function(ok, _, skipped) missing = ok and skipped end)
    and missing == 1, "Missing members allow portable history to proceed without a live write")

-- The real UDim2 stores integral offsets. Model its constructor independently of float test values.
local floatUdim = UDim2.new
UDim2.new = function(xs, xo, ys, yo) return floatUdim(xs, math.floor(xo), ys, math.floor(yo)) end
local scaled = create("Frame", "QuantizedSize", screen)
scaled.AnchorPoint = {X = 0.5, Y = 0.5}
local quantizingScale = create("UIScale", "Scale", scaled)
quantizingScale.Scale = 1.5
flush()
local preciseTransform = dofile("src/Transform.lua").new(discovery, log)
local preciseKey = key(scaled)
local precise = {x = 23, y = 31, w = 100, h = 16}
check(preciseTransform:setRects({preciseKey}, {precise}), "Quantized offset math adjusts anchor compensation after rounding")
flush()
check(preciseTransform:capture()[preciseKey] and scaled.AbsoluteSize.Y >= 16, "An accepted minimum size remains valid after quantization")
check(math.abs(scaled.AbsolutePosition.X - precise.x) <= 1.5 and math.abs(scaled.AbsoluteSize.Y - precise.h) <= 1.5,
    "Quantized rendered geometry stays within the requested screen tolerance")
local preciseLayout = preciseTransform:capture()
preciseTransform:restore()
check(preciseTransform:apply(preciseLayout) == 1, "Quantized minimum edit can be saved and restored")
flush()
preciseTransform:destroy()
UDim2.new = floatUdim

local connections = {}
for _, connection in ipairs(discovery.connections) do connections[#connections + 1] = connection end
for _, list in pairs(discovery.objectConnections) do for _, connection in ipairs(list) do connections[#connections + 1] = connection end end
discovery:destroy()
for _, connection in ipairs(connections) do check(not connection.connected, "Destroy disconnects every subscription") end
transform:destroy()
flush()
check(next(discovery.records) == nil and next(transform.tracked) == nil, "Destroy releases GUI references")
return assertions
