-- Use local layout and presentation evidence to distinguish a composed control
-- from its visible details. No editability or naming assumptions enter this test.
local Coordinates = require("Coordinates")
local SmartLayers = require("SmartLayers")

local ControlScopes = {}
local EMPTY = {}
local MAX_LEVELS, MAX_PARTS, MAX_PEERS = 6, 12, 12
local generic = {frame = true, imagebutton = true, textbutton = true, canvasgroup = true, slot = true,
    ability = true, skill = true, button = true, hotkey = true, action = true, control = true, item = true, tile = true}
local statusText = {ready = true, locked = true, selected = true, cooldown = true, disabled = true, loading = true}

local function parent(discovery, record)
    return record.parentKey and discovery.records[record.parentKey]
end

local function area(rect)
    return rect.w * rect.h
end

local function canEnclose(bounds, inner, point)
    if not bounds or bounds.w <= 0 or bounds.h <= 0 then return false end
    if point and not Coordinates.contains(bounds, point.x, point.y) then return false end
    if not inner then return true end
    local inset = 3
    return inner.x >= bounds.x - inset and inner.y >= bounds.y - inset
        and inner.x + inner.w <= bounds.x + bounds.w + inset and inner.y + inner.h <= bounds.y + bounds.h + inset
end

local function compact(record, bounds, repeated)
    local screen = Coordinates.rect(record.screen)
    if not screen or screen.w <= 0 or screen.h <= 0 then return false end
    if area(bounds) > area(screen) * 0.22 then return false end
    return not repeated or bounds.w < screen.w * 0.7 and bounds.h < screen.h * 0.7
end

local function template(discovery, record)
    local output = {image = 0, text = 0, actions = 0, parts = 0}
    local current = {{record, 0}}
    local index, inspected = 1, 0
    while current[index] do
        local item, depth = current[index][1], current[index][2]
        index = index + 1
        output.parts = output.parts + 1
        if output.parts > MAX_PARTS or output.actions > 1 then return nil end
        local class = item.object.ClassName
        if item ~= record and SmartLayers.actionable(item) then
            output.actions = output.actions + 1
            output.action = item
        end
        if (class == "ImageLabel" or class == "ImageButton") and SmartLayers.hasImage(item.object) then output.image = output.image + 1 end
        if (class == "TextLabel" or class == "TextButton") and SmartLayers.hasText(item.object) then output.text = output.text + 1 end
        if depth < 3 then
            for _, key in ipairs(item.childKeys or EMPTY) do
                inspected = inspected + 1
                if inspected > MAX_PARTS * 2 then return nil end
                local child = discovery.records[key]
                if child and child.object.Visible ~= false then current[#current + 1] = {child, depth + 1} end
                if #current > MAX_PARTS then return nil end
            end
        elseif #(item.childKeys or EMPTY) > 0 then return nil end
    end
    if output.actions > 1 or output.text == 0
        or output.image == 0 and (output.actions == 0 or #(record.childKeys or EMPTY) < 2) then return nil end
    return output
end

local function similar(a, b)
    return math.abs(a - b) <= math.max(4, math.max(a, b) * 0.25)
end

local function separateBand(a, b)
    local overlap = Coordinates.intersection(a, b)
    if overlap and area(overlap) > math.min(area(a), area(b)) * 0.08 then return false end
    local ax, ay = a.x + a.w / 2, a.y + a.h / 2
    local bx, by = b.x + b.w / 2, b.y + b.h / 2
    local dx, dy = math.abs(ax - bx), math.abs(ay - by)
    return dx <= math.max(8, a.w * 0.25) and dy <= math.max(a.h, b.h) * 6
        or dy <= math.max(8, a.h * 0.25) and dx <= math.max(a.w, b.w) * 6
end

local function repeatedControl(discovery, record, bounds)
    local class = record.object.ClassName
    if class ~= "Frame" and class ~= "CanvasGroup" and class ~= "ImageLabel" then return false end
    if not compact(record, bounds, true) then return false end
    local owner = parent(discovery, record)
    if not owner or #(owner.childKeys or EMPTY) < 2 then return false end
    local layout = record.layoutController
    local needed = layout and 1 or 2
    local shape = template(discovery, record)
    if not shape then return false end
    for index, key in ipairs(owner.childKeys) do
        if index > MAX_PEERS then break end
        local peer = discovery.records[key]
        if peer and peer ~= record and peer.object.ClassName == class
            and peer.object.Parent == record.object.Parent and peer.object.Visible ~= false and peer.layoutController == layout then
            local other = Coordinates.rect(peer.object)
            if other and similar(bounds.w, other.w) and similar(bounds.h, other.h) and separateBand(bounds, other) then
                local comparison = template(discovery, peer)
                if comparison and shape.image == comparison.image and shape.text == comparison.text and shape.actions == comparison.actions then
                    needed = needed - 1
                    if needed == 0 then return shape end
                end
            end
        end
    end
    return false
end

local function inferName(discovery, whole)
    if whole.builtin or whole.controlNameRevision == discovery.revision then return end
    whole.controlNameRevision = discovery.revision
    whole.displayName = SmartLayers.name(whole)
    local raw = whole.object.Name:lower():gsub("[%s_%-]", "")
    local prefix, slot = raw:match("^(%a*)(%d+)$")
    if not (generic[raw] or prefix and (prefix == "" or generic[prefix])) then return end

    local title, queue, index, inspected = nil, {{whole, 0}}, 1, 0
    while queue[index] do
        local record, depth = queue[index][1], queue[index][2]
        index = index + 1
        local object = record.object
        local class = object.ClassName
        if (class == "TextLabel" or class == "TextButton") and SmartLayers.hasText(object)
            and type(object.TextTransparency) == "number" and object.TextTransparency < 0.99 then
            local caption = object.Text:match("^%s*(.-)%s*$")
            if #caption >= 3 and #caption <= 40 and caption:find("%a") and not caption:find("[<>\r\n]")
                and not statusText[caption:lower()] then
                if title and title ~= caption then return end
                title = caption
            end
        end
        if depth < 2 then
            for _, key in ipairs(record.childKeys or EMPTY) do
                inspected = inspected + 1
                if inspected > MAX_PARTS * 2 then return end
                local child = discovery.records[key]
                if child and child.object.Visible ~= false then queue[#queue + 1] = {child, depth + 1} end
                if #queue > MAX_PARTS then return end
            end
        end
    end
    if title then whole.displayName = slot and title .. " (" .. slot .. ")" or title end
end

local function relatedContainer(discovery, record)
    local layout = record.layoutController
    if layout and layout.Parent then
        local owner = discovery.byObject[layout.Parent]
        if owner and owner ~= record then return owner end
    end
    return parent(discovery, record)
end

function ControlScopes.resolve(discovery, layer, point, repeated)
    if not layer then return {current = "layer"} end
    local inner = Coordinates.rect(layer.object)
    local record, whole, action, actionBounds = layer, nil, nil, nil
    for depth = 1, MAX_LEVELS do
        if not record then break end
        local bounds = depth == 1 and inner or Coordinates.rect(record.object)
        if canEnclose(bounds, inner, point) then
            local actionable = compact(record, bounds, false) and SmartLayers.actionable(record)
            if record.builtin and (not action or action == record) then whole = record; break end
            if actionable and not action then action, actionBounds = record, bounds end
            local matching = repeated and repeated[record.key]
            if matching == nil then
                matching = repeatedControl(discovery, record, bounds)
                if repeated then repeated[record.key] = matching end
            end
            if matching and (not action or action == record or matching.action == action and area(actionBounds) >= area(bounds) * 0.35) then
                whole = record
                break
            end
        end
        record = parent(discovery, record)
    end
    whole = whole or action
    if whole then
        inferName(discovery, whole)
        return {current = whole == layer and "whole" or "layer", whole = whole, layer = whole ~= layer and layer or nil,
            container = relatedContainer(discovery, whole)}
    end
    if discovery:_metadata(layer.object).layout then
        return {current = "container", container = layer}
    end
    return {current = "layer", layer = layer, container = relatedContainer(discovery, layer)}
end

function ControlScopes.layers(discovery, root)
    if not root then return {} end
    local result, queue = {}, {root}
    local index, inspected = 1, 0
    while queue[index] do
        local record = queue[index]
        index = index + 1
        for _, key in ipairs(record.childKeys or EMPTY) do
            local child = discovery:get(key)
            inspected = inspected + 1
            if child then
                if discovery:_painted(child) or child.originalOpacityPaint then result[#result + 1] = child end
                queue[#queue + 1] = child
            end
            if inspected >= 24 then return result end
        end
    end
    return result
end

return ControlScopes
