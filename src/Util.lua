-- Heavenly Axis V3. Original project by Syshi; V2 inspired by Danechka.
local Util = {}

function Util.finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Util.copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[Util.copy(key, seen)] = Util.copy(item, seen) end
    return result
end

function Util.equal(a, b, seen)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    seen = seen or {}
    if seen[a] == b then return true end
    seen[a] = b
    for key, value in pairs(a) do
        if not Util.equal(value, b[key], seen) then return false end
    end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

return Util
