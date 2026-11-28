-- Fade supported appearance components relative to the first values seen on each instance.
local Identity = require("Identity")
local SmartLayers = require("SmartLayers")
local Util = require("Util")

local Appearance = {}
Appearance.__index = Appearance
Appearance.MAX_LAYERS = 64
Appearance.MAX_COMPONENTS = 256

local EMPTY = {}
local images = {ImageButton = true, ImageLabel = true, ViewportFrame = true}
local text = {TextButton = true, TextLabel = true, TextBox = true}

local function transparency(value)
    return Util.finite(value) and value >= 0 and value <= 1
end

local function nonempty(value)
    return type(value) == "string" and value:find("%S") ~= nil
end

local function hasText(object, class)
    return text[class] and (nonempty(object.Text) or class == "TextBox" and nonempty(object.PlaceholderText))
end

local function siblingCompositor(record)
    return record.object.ClassName == "CanvasGroup" and record.screen ~= nil
        and tostring(record.screen.ZIndexBehavior):match("Sibling$") ~= nil
end

function Appearance.new(discovery)
    return setmetatable({discovery = discovery, originals = setmetatable({}, {__mode = "k"})}, Appearance)
end

function Appearance:_remember(object, property, fallback)
    local originals = self.originals[object]
    if not originals then originals = {}; self.originals[object] = originals end
    if originals[property] == nil then
        local ok, value = pcall(function() return object[property] end)
        if transparency(fallback) then originals[property] = fallback
        elseif ok and transparency(value) then originals[property] = value end
    end
    return originals[property]
end

function Appearance:remember(record, strokes)
    local object, class = record.object, record.object.ClassName
    self:_remember(object, "BackgroundTransparency", record.baseline and record.baseline.transparency)
    local originals = self.originals[object]
    if images[class] then
        self:_remember(object, "ImageTransparency")
        originals.imageSeen = originals.imageSeen or SmartLayers.hasImage(object)
    end
    if text[class] then
        self:_remember(object, "TextTransparency")
        self:_remember(object, "TextStrokeTransparency")
        originals.textSeen = originals.textSeen or hasText(object, class)
    end
    if class == "CanvasGroup" then self:_remember(object, "GroupTransparency") end
    for _, stroke in ipairs(strokes or EMPTY) do self:_remember(stroke, "Transparency") end
end

function Appearance.value(original, factor)
    if not transparency(original) or not transparency(factor) then return nil end
    if factor == 1 then return original end
    if factor == 0 then return 1 end
    return 1 - (1 - original) * factor
end

local function component(record, object, property, original, relativeKey, contents)
    return {
        object = object, property = property, original = original, record = record, key = record.key,
        id = relativeKey or property, contents = contents == true, parent = object.Parent,
    }
end

function Appearance:_own(record, strokes, persisted)
    local object, class = record.object, record.object.ClassName
    local originals = self.originals[object] or EMPTY
    local targets, paints = {}, false
    local function add(subject, property, original, relativeKey)
        if not transparency(original) then return end
        targets[#targets + 1] = component(record, subject, property, original, relativeKey)
        if original < 1 then paints = true end
    end
    add(object, "BackgroundTransparency", originals.BackgroundTransparency)
    if images[class] and (originals.imageSeen or persisted) then
        add(object, "ImageTransparency", originals.ImageTransparency)
    end
    local useText = text[class] and (originals.textSeen or persisted)
    if useText then
        add(object, "TextTransparency", originals.TextTransparency)
        add(object, "TextStrokeTransparency", originals.TextStrokeTransparency)
    end
    local strokeNames = {}
    for _, stroke in ipairs(strokes or EMPTY) do strokeNames[stroke.Name] = (strokeNames[stroke.Name] or 0) + 1 end
    for _, stroke in ipairs(strokes or EMPTY) do
        local borders = not text[class] or tostring(stroke.ApplyStrokeMode):match("Border$") ~= nil
        local original = self.originals[stroke] and self.originals[stroke].Transparency
        if stroke.Parent == object and strokeNames[stroke.Name] == 1 and stroke.Enabled ~= false
            and Util.finite(stroke.Thickness) and stroke.Thickness > 0 and (borders or useText) then
            local path = Identity.key({path = {{name = stroke.Name, class = "UIStroke", ordinal = 1}}})
            add(stroke, "Transparency", original, path .. "/Transparency")
        end
    end
    return paints and targets or EMPTY
end

function Appearance:_group(record)
    local object = record.object
    local originals = self.originals[object]
    local original = originals and originals.GroupTransparency
    if siblingCompositor(record) and transparency(original) and original < 1 then
        return component(record, object, "GroupTransparency", original, nil, true)
    end
    return nil
end

function Appearance:available(record, strokes)
    self:remember(record, strokes)
    local originals = self.originals[record.object]
    if siblingCompositor(record) and originals.GroupTransparency == 1 then return false, false, true end
    local background = originals.BackgroundTransparency
    return transparency(background) and background < 1 or #self:_own(record, strokes) > 0, self:_group(record) ~= nil
end

function Appearance:hasNewContent(record)
    local object, class = record.object, record.object.ClassName
    local originals = self.originals[object]
    return originals ~= nil and (images[class] and not originals.imageSeen and SmartLayers.hasImage(object)
        or text[class] and not originals.textSeen and hasText(object, class))
end

local function ownedStrokes(discovery, record)
    return discovery:_metadata(record.object).strokes
end

function Appearance:plan(keys, scope, options)
    if scope ~= "element" and scope ~= "contents" then return nil, "Choose an opacity scope." end
    options = options or EMPTY
    local discovery = self.discovery
    local selected, roots = {}, {}
    for _, key in ipairs(keys or EMPTY) do selected[key] = true end
    for _, key in ipairs(keys or EMPTY) do
        local record = selected[key] and discovery:get(key)
        if record then
            local parentKey, nested = record.parentKey, false
            while scope == "contents" and parentKey do
                if selected[parentKey] then nested = true; break end
                local parent = discovery.records[parentKey]
                parentKey = parent and parent.parentKey
            end
            if not nested and not roots[key] then roots[#roots + 1], roots[key] = record, true end
        end
    end

    local allowedKeys, relevant, hasExactDescendant, missing
    if options.targets then
        allowedKeys, relevant, hasExactDescendant, missing = {}, {}, {}, 0
        for _, key in ipairs(options.targets) do
            if not allowedKeys[key] then missing = missing + 1 end
            allowedKeys[key], relevant[key] = true, true
            for slash in key:gmatch("()/") do
                local ancestor = key:sub(1, slash - 1)
                relevant[ancestor], hasExactDescendant[ancestor] = true, true
            end
        end
    end
    local flattenGroups = options.flattenGroups or EMPTY
    local targets, affected, seen = {}, {}, {}
    local layers, skipped = 0, 0
    local function visit(record, covered, flattened)
        if seen[record.key] then return true end
        seen[record.key] = true
        layers = layers + 1
        if layers > Appearance.MAX_LAYERS then return false, "Choose a smaller set of layers to adjust opacity." end
        local wanted = flattened or not allowedKeys or allowedKeys[record.key]
        if allowedKeys and allowedKeys[record.key] then missing = missing - 1 end
        local editable, reason = not record.descriptor.ambiguous, nil
        if editable and options.canEdit then editable, reason = options.canEdit(record, covered == true) end
        if covered and not editable then return false, reason or "A locked or ambiguous layer is inside this CanvasGroup." end

        if not covered and wanted and editable then
            local strokes = ownedStrokes(discovery, record)
            self:remember(record, strokes)
            if siblingCompositor(record) and self.originals[record.object].GroupTransparency == 1 then
                skipped = skipped + 1
                return true
            end
            flattened = flattened or flattenGroups[record.key] == true
            local group = scope == "contents" and not flattened and not (hasExactDescendant and hasExactDescendant[record.key])
                and self:_group(record)
            if group then
                if options.canEdit then
                    local groupEditable, groupReason = options.canEdit(record, true)
                    if not groupEditable then return false, groupReason or "This CanvasGroup's contents cannot be edited together." end
                end
                targets[#targets + 1] = group
                affected[#affected + 1] = record.key
                covered = true
            elseif not options.groupsOnly then
                local own = self:_own(record, strokes, allowedKeys and allowedKeys[record.key])
                if #own > 0 then affected[#affected + 1] = record.key end
                for _, target in ipairs(own) do targets[#targets + 1] = target end
            end
            if #targets > Appearance.MAX_COMPONENTS then return false, "Choose fewer appearance components to adjust at once." end
        elseif wanted and not covered and not editable then skipped = skipped + 1 end

        if scope == "contents" then
            for _, key in ipairs(record.childKeys or EMPTY) do
                if covered or flattened or not relevant or relevant[key] then
                    local child = discovery:get(key)
                    if child then
                        local ok, message = visit(child, covered, flattened)
                        if not ok then return false, message end
                    end
                end
            end
        end
        return true
    end

    for _, record in ipairs(roots) do
        local ok, reason = visit(record, false, false)
        if not ok then return nil, reason end
    end
    table.sort(affected)
    local details = {targets = affected, layers = layers, skipped = skipped, missing = missing or 0}
    if #targets == 0 then
        return options.targets and targets or nil, "The selected layers have no supported visible opacity in this scope.", details
    end
    return targets, nil, details
end

function Appearance:flattenGroup(key, canEdit)
    return self:plan({key}, "contents", {flattenGroups = {[key] = true}, canEdit = canEdit})
end

return Appearance
