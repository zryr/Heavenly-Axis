-- InputObject.Position, GuiBase2d.AbsolutePosition and GetGuiObjectsAtPosition
-- use the CoreUISafeInsets origin, including for objects inside other inset modes.
local Util = require("Util")

local Coordinates = {}

function Coordinates.point(input)
    local position = input.Position
    return {x = position.X, y = position.Y}
end

function Coordinates.rect(object)
    if not object then return nil end
    local ok, position, size = pcall(function() return object.AbsolutePosition, object.AbsoluteSize end)
    if ok and position and size
        and Util.finite(position.X) and Util.finite(position.Y) and Util.finite(size.X) and Util.finite(size.Y) then
        return {x = position.X, y = position.Y, w = size.X, h = size.Y}
    end
    return nil
end

function Coordinates.screenToLocal(x, y, container)
    local origin = container and container.AbsolutePosition
    return x - (origin and origin.X or 0), y - (origin and origin.Y or 0)
end

function Coordinates.hitPoint(x, y)
    return math.floor(x), math.floor(y)
end

local function guiInset(guiService)
    if not guiService then return nil, nil end
    local ok, topLeft, bottomRight = pcall(function() return guiService:GetGuiInset() end)
    if ok then return topLeft, bottomRight end
    return nil, nil
end

function Coordinates.insetRect(guiService, inset)
    if not guiService or not inset then return nil end
    local ok, area = pcall(function() return guiService:GetInsetArea(inset) end)
    if not ok or not area or not area.Min or not area.Max then return nil end
    local x, y, right, bottom = area.Min.X, area.Min.Y, area.Max.X, area.Max.Y
    if not Util.finite(x) or not Util.finite(y) or not Util.finite(right) or not Util.finite(bottom)
        or right <= x or bottom <= y then return nil end
    return {x = x, y = y, w = right - x, h = bottom - y}
end

function Coordinates.safeRect(guiService, width, height)
    local area = Coordinates.insetRect(guiService, Enum and Enum.ScreenInsets and Enum.ScreenInsets.DeviceSafeInsets)
    if area then return area end
    local topLeft = guiInset(guiService)
    -- Camera.ViewportSize already excludes hardware cutouts.
    return {x = 0, y = -(topLeft and topLeft.Y or 0), w = width, h = height}
end

function Coordinates.coreRect(guiService, width, height)
    local area = Coordinates.insetRect(guiService, Enum and Enum.ScreenInsets and Enum.ScreenInsets.CoreUISafeInsets)
    if area then return area end
    local topLeft, bottomRight = guiInset(guiService)
    local top, bottom = topLeft and topLeft.Y or 0, bottomRight and bottomRight.Y or 0
    return {x = 0, y = 0, w = width, h = math.max(1, height - top - bottom)}
end

function Coordinates.contains(rect, x, y)
    return rect ~= nil and rect.w > 0 and rect.h > 0 and x >= rect.x and x <= rect.x + rect.w
        and y >= rect.y and y <= rect.y + rect.h
end

function Coordinates.intersection(a, b)
    if not a or not b then return nil end
    local x, y = math.max(a.x, b.x), math.max(a.y, b.y)
    local w, h = math.min(a.x + a.w, b.x + b.w) - x, math.min(a.y + a.h, b.y + b.h) - y
    if w <= 0 or h <= 0 then return nil end
    return {x = x, y = y, w = w, h = h}
end

return Coordinates
