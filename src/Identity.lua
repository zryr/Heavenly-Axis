-- Conservative hierarchy identity: no fuzzy name, size, or appearance matching.
local Identity = {}
local BUILTINS = { JumpButton = true, ThumbstickFrame = true, DynamicThumbstickFrame = true }
local function escaped(value) return tostring(value):gsub("%%", "%%25"):gsub("/", "%%2F"):gsub(":", "%%3A") end

local function siblingOrder(parent, childCache, siblingCache)
    if siblingCache and siblingCache[parent] then return siblingCache[parent] end
    local children = childCache and childCache[parent] or parent:GetChildren()
    if childCache then childCache[parent] = children end
    local orders, countsByName = {}, {}
    for index, sibling in ipairs(children) do
        local name, class = sibling.Name, sibling.ClassName
        local counts = countsByName[name]
        if not counts then counts = {}; countsByName[name] = counts end
        counts[class] = (counts[class] or 0) + 1
        orders[sibling] = {ordinal = counts[class], index = index}
    end
    for _, sibling in ipairs(children) do
        orders[sibling].ambiguous = countsByName[sibling.Name][sibling.ClassName] > 1
    end
    if siblingCache then siblingCache[parent] = orders end
    return orders
end

function Identity.descriptor(instance, root, childCache, siblingCache)
    local path, ambiguous, current = {}, false, instance
    while current and current ~= root do
        local parent = current.Parent
        if not parent then return nil, "Object is outside the discovery root" end
        local order = siblingOrder(parent, childCache, siblingCache)[current]
        if not order then return nil, "Object is outside the discovery root" end
        ambiguous = ambiguous or order.ambiguous
        table.insert(path, 1, { name = current.Name, class = current.ClassName, ordinal = order.ordinal })
        current = parent
    end
    if current ~= root or #path == 0 then return nil, "Object is outside the discovery root" end
    local descriptor = { path = path, class = instance.ClassName }
    if ambiguous then descriptor.ambiguous = true end
    if #path == 3 and path[1].name == "TouchGui" and path[1].class == "ScreenGui"
        and path[2].name == "TouchControlFrame" and path[2].class == "Frame"
        and BUILTINS[path[3].name]
        and ((path[3].name == "JumpButton" and (instance.ClassName == "ImageButton" or instance.ClassName == "TextButton"))
            or (path[3].name ~= "JumpButton" and instance.ClassName == "Frame")) then
        descriptor.builtin = path[3].name
    end
    return descriptor
end

function Identity.key(descriptor)
    local parts = {}
    for i, segment in ipairs(descriptor.path or {}) do
        parts[i] = escaped(segment.name) .. ":" .. escaped(segment.class) .. ":" .. tostring(segment.ordinal or 1)
    end
    return table.concat(parts, "/")
end

local function samePath(a, b)
    if type(b) ~= "table" or type(b.path) ~= "table" or a.class ~= b.class or #a.path ~= #b.path then return false end
    for i, segment in ipairs(a.path) do
        local candidate = b.path[i]
        if type(segment) ~= "table" or type(candidate) ~= "table" or segment.name ~= candidate.name or segment.class ~= candidate.class
            or (segment.ordinal or 1) ~= (candidate.ordinal or 1) then return false end
    end
    return true
end

function Identity.same(descriptor, candidate)
    return type(descriptor) == "table" and type(candidate) == "table" and not descriptor.ambiguous
        and not candidate.ambiguous and type(descriptor.path) == "table" and samePath(descriptor, candidate)
end

function Identity.match(descriptor, candidates)
    if type(descriptor) ~= "table" or type(descriptor.path) ~= "table" then return nil, "Invalid identity" end
    if descriptor.ambiguous then return nil, "Ambiguous saved hierarchy; remap manually" end
    local found
    for i, candidate in ipairs(candidates) do
        if samePath(descriptor, candidate) then
            if found or candidate.ambiguous then return nil, "Ambiguous matching hierarchy; remap manually" end
            found = i
        end
    end
    if found then return found end
    return nil, "No exact hierarchy match"
end

return Identity
