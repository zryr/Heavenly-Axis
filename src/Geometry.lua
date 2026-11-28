-- Pixel-space math, independent of Roblox services or instances.
local Util = require("Util")
local Geometry = { MIN_SIZE = 16, MAX_SIZE = 1000000 }
local function copy(rect) return { x = rect.x, y = rect.y, w = rect.w, h = rect.h } end
local function same(a, b) return math.abs(a - b) < 0.000001 end

function Geometry.minimumSize(original)
    return math.min(Geometry.MIN_SIZE, original)
end

function Geometry.valid(rect)
    return type(rect) == "table" and Util.finite(rect.x) and Util.finite(rect.y)
        and Util.finite(rect.w) and Util.finite(rect.h) and rect.w > 0 and rect.h > 0
end

function Geometry.translate(rect, dx, dy)
    return { x = rect.x + dx, y = rect.y + dy, w = rect.w, h = rect.h }
end

function Geometry.center(rect)
    return {x = rect.x + rect.w / 2, y = rect.y + rect.h / 2}
end

function Geometry.angle(pivot, point)
    return math.deg((math.atan2 or math.atan)(point.y - pivot.y, point.x - pivot.x))
end

function Geometry.angleDelta(from, to)
    return (to - from + 180) % 360 - 180
end

function Geometry.rotatePoint(point, pivot, degrees)
    local radians = math.rad(degrees)
    local sine, cosine = math.sin(radians), math.cos(radians)
    local x, y = point.x - pivot.x, point.y - pivot.y
    return {x = pivot.x + cosine * x - sine * y, y = pivot.y + sine * x + cosine * y}
end

function Geometry.rotatedBounds(rect, degrees)
    local radians = math.rad(degrees)
    local sine, cosine = math.abs(math.sin(radians)), math.abs(math.cos(radians))
    local center = Geometry.center(rect)
    local width, height = rect.w * cosine + rect.h * sine, rect.w * sine + rect.h * cosine
    return {x = center.x - width / 2, y = center.y - height / 2, w = width, h = height}
end

function Geometry.bounds(rects)
    if #rects == 0 then return nil end
    local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
    for _, rect in ipairs(rects) do
        left, top = math.min(left, rect.x), math.min(top, rect.y)
        right, bottom = math.max(right, rect.x + rect.w), math.max(bottom, rect.y + rect.h)
    end
    return { x = left, y = top, w = right - left, h = bottom - top }
end

function Geometry.resize(rect, handle, dx, dy, lockAspect, center)
    local west, east = handle:find("w", 1, true), handle:find("e", 1, true)
    local north, south = handle:find("n", 1, true), handle:find("s", 1, true)
    local multiplier = center and 2 or 1
    local width = rect.w + ((east and dx or 0) - (west and dx or 0)) * multiplier
    local height = rect.h + ((south and dy or 0) - (north and dy or 0)) * multiplier
    if lockAspect then
        local fx, fy = width / rect.w, height / rect.h
        local factor
        if not (west or east) then factor = fy
        elseif not (north or south) then factor = fx
        else factor = math.abs(fx - 1) >= math.abs(fy - 1) and fx or fy end
        factor = math.max(factor, Geometry.minimumSize(rect.w) / rect.w, Geometry.minimumSize(rect.h) / rect.h)
        width, height = rect.w * factor, rect.h * factor
    else
        width, height = math.max(Geometry.minimumSize(rect.w), width), math.max(Geometry.minimumSize(rect.h), height)
    end
    local x = center and rect.x + (rect.w - width) / 2 or (west and rect.x + rect.w - width or rect.x)
    local y = center and rect.y + (rect.h - height) / 2 or (north and rect.y + rect.h - height or rect.y)
    -- Aspect locking on an edge keeps the perpendicular center stationary.
    if lockAspect and not center then
        if not (west or east) then x = rect.x + (rect.w - width) / 2 end
        if not (north or south) then y = rect.y + (rect.h - height) / 2 end
    end
    return { x = x, y = y, w = width, h = height }
end

local function inferredAnchor(deltaStart, deltaSize)
    if same(deltaStart, 0) then return 0 end
    if same(deltaStart, -deltaSize) then return 1 end
    if same(deltaStart, -deltaSize / 2) then return 0.5 end
    return 0
end

local function leadingEdge(oldStart, oldSize, newStart, newSize, appliedSize, center)
    if center then return oldStart + (oldSize - appliedSize) / 2 end
    local anchor = inferredAnchor(newStart - oldStart, newSize - oldSize)
    return newStart + (newSize - appliedSize) * anchor
end

function Geometry.scale(rects, newBounds, center)
    local old = Geometry.bounds(rects)
    if not old or old.w <= 0 or old.h <= 0 then return {} end
    local sx, sy = newBounds.w / old.w, newBounds.h / old.h
    local uniform = same(sx, sy)
    -- Raise the factors, rather than clamping individual rectangles: relative layout stays intact.
    for _, rect in ipairs(rects) do
        sx = math.max(sx, Geometry.minimumSize(rect.w) / rect.w)
        sy = math.max(sy, Geometry.minimumSize(rect.h) / rect.h)
    end
    if uniform then sx, sy = math.max(sx, sy), math.max(sx, sy) end
    local x = leadingEdge(old.x, old.w, newBounds.x, newBounds.w, old.w * sx, center)
    local y = leadingEdge(old.y, old.h, newBounds.y, newBounds.h, old.h * sy, center)
    local result = {}
    for i, rect in ipairs(rects) do
        result[i] = { x = x + (rect.x - old.x) * sx, y = y + (rect.y - old.y) * sy,
            w = rect.w * sx, h = rect.h * sy }
    end
    return result
end

function Geometry.adjustMembers(rects, oldBounds, newBounds, center, lockAspect, aspectAxis)
    local dw, dh = newBounds.w - oldBounds.w, newBounds.h - oldBounds.h
    local lockX = lockAspect and (aspectAxis == "x"
        or (aspectAxis ~= "y" and math.abs(dw / oldBounds.w) >= math.abs(dh / oldBounds.h)))
    local lockY = lockAspect and not lockX
    local dx, dy = newBounds.x - oldBounds.x, newBounds.y - oldBounds.y
    local anchorX = center and 0.5 or inferredAnchor(dx, dw)
    local anchorY = center and 0.5 or inferredAnchor(dy, dh)
    if center then dx, dy = 0, 0 else dx, dy = dx + dw * anchorX, dy + dh * anchorY end
    for _, rect in ipairs(rects) do
        if lockX then
            local minimum = math.max(Geometry.minimumSize(rect.w), Geometry.minimumSize(rect.h) * rect.w / rect.h)
            dw = math.max(dw, minimum - rect.w)
        elseif lockY then
            local minimum = math.max(Geometry.minimumSize(rect.h), Geometry.minimumSize(rect.w) * rect.h / rect.w)
            dh = math.max(dh, minimum - rect.h)
        else
            if not same(dw, 0) then dw = math.max(dw, Geometry.minimumSize(rect.w) - rect.w) end
            if not same(dh, 0) then dh = math.max(dh, Geometry.minimumSize(rect.h) - rect.h) end
        end
    end
    local result = {}
    for i, rect in ipairs(rects) do
        local memberWidth = lockY and dh * rect.w / rect.h or dw
        local memberHeight = lockX and dw * rect.h / rect.w or dh
        result[i] = {x = rect.x + dx - memberWidth * anchorX, y = rect.y + dy - memberHeight * anchorY,
            w = rect.w + memberWidth, h = rect.h + memberHeight}
    end
    return result
end

function Geometry.align(rects, mode)
    local bounds, result = Geometry.bounds(rects), {}
    if not bounds then return result end
    for i, rect in ipairs(rects) do
        local nextRect = copy(rect)
        if mode == "left" then nextRect.x = bounds.x
        elseif mode == "right" then nextRect.x = bounds.x + bounds.w - rect.w
        elseif mode == "top" then nextRect.y = bounds.y
        elseif mode == "bottom" then nextRect.y = bounds.y + bounds.h - rect.h
        elseif mode == "centerX" or mode == "horizontal" or mode == "center" then nextRect.x = bounds.x + (bounds.w - rect.w) / 2
        elseif mode == "centerY" or mode == "vertical" then nextRect.y = bounds.y + (bounds.h - rect.h) / 2 end
        result[i] = nextRect
    end
    return result
end

function Geometry.distribute(rects, axis)
    local result, order = {}, {}
    for i, rect in ipairs(rects) do result[i], order[i] = copy(rect), i end
    if #rects < 3 then return result end
    local horizontal = axis == "x" or axis == "horizontal"
    local coordinate, dimension = horizontal and "x" or "y", horizontal and "w" or "h"
    table.sort(order, function(a, b)
        if rects[a][coordinate] == rects[b][coordinate] then return a < b end
        return rects[a][coordinate] < rects[b][coordinate]
    end)
    local first, last = rects[order[1]], rects[order[#order]]
    local total = 0
    for _, rect in ipairs(rects) do total = total + rect[dimension] end
    local gap = (last[coordinate] + last[dimension] - first[coordinate] - total) / (#rects - 1)
    local cursor = first[coordinate]
    for _, index in ipairs(order) do
        result[index][coordinate] = cursor
        cursor = cursor + rects[index][dimension] + gap
    end
    return result
end

function Geometry.roots(items, parentFn)
    local selected, result = {}, {}
    for _, item in ipairs(items) do selected[item] = true end
    for _, item in ipairs(items) do
        local parent, visited, nested = parentFn(item), {}, false
        while parent ~= nil and not visited[parent] do
            if selected[parent] then nested = true; break end
            visited[parent] = true
            parent = parentFn(parent)
        end
        if not nested then result[#result + 1] = item end
    end
    return result
end

function Geometry.snap(rect, others, grid, threshold, enabled)
    local result, guides = copy(rect), {}
    threshold, grid = threshold or 6, grid or 16
    local bestX, bestY, lineX, lineY = threshold + 1, threshold + 1, nil, nil
    local xs, ys = { rect.x, rect.x + rect.w / 2, rect.x + rect.w }, { rect.y, rect.y + rect.h / 2, rect.y + rect.h }
    for _, other in ipairs(others or {}) do
        for _, x in ipairs({ other.x, other.x + other.w / 2, other.x + other.w }) do
            for _, own in ipairs(xs) do if math.abs(x - own) < math.abs(bestX) then bestX, lineX = x - own, x end end
        end
        for _, y in ipairs({ other.y, other.y + other.h / 2, other.y + other.h }) do
            for _, own in ipairs(ys) do if math.abs(y - own) < math.abs(bestY) then bestY, lineY = y - own, y end end
        end
    end
    if math.abs(bestX) <= threshold then
        guides[#guides + 1] = { axis = "x", value = lineX }
        if enabled then result.x = result.x + bestX end
    elseif enabled and grid > 0 then result.x = math.floor(result.x / grid + 0.5) * grid end
    if math.abs(bestY) <= threshold then
        guides[#guides + 1] = { axis = "y", value = lineY }
        if enabled then result.y = result.y + bestY end
    elseif enabled and grid > 0 then result.y = math.floor(result.y / grid + 0.5) * grid end
    return result, guides
end

return Geometry
