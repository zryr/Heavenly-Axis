local Roblox = require("support/Roblox")
local glyphs = require("LucideGlyphs")
local Lucide = require("Lucide")

local mock = Roblox.new(640, 360)
local button = Instance.new("TextButton")
button.Size = UDim2.fromOffset(44, 44)
button.Parent = mock.playerGui
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, message)
end

check(Lucide.version == "0.511.0" and #Lucide.revision == 40, "glyph source is versioned and pinned")
check(Lucide.has("help-circle") and Lucide.has("check-circle-2") and Lucide.has("check-circle") and Lucide.has("text"),
    "upstream aliases resolve to the official glyphs")
check(Lucide.mount(button, "not-a-real-glyph") == nil and #button:GetChildren() == 0,
    "unknown optional glyph leaves the caller's existing label available")

local color = Color3.fromRGB(118, 229, 233)
local icon = Lucide.mount(button, "move", {size = 18, color = color})
check(icon.Parent == button and icon.AbsoluteSize.X == 18 and icon.AbsoluteSize.Y == 18,
    "the icon footprint stays independent from the 44-unit action target")
check(icon.AnchorPoint.X == .5 and icon.AnchorPoint.Y == .5 and icon.BackgroundTransparency == 1,
    "centered icon keeps its transparent content box")
check(not icon.Active and not icon.Selectable and #icon:GetChildren() == 10,
    "the official Move glyph has ten noninteractive native strokes")
local before = icon:GetChildren()[1]
local recolored = Color3.fromRGB(245, 246, 247)
Lucide.setColor(icon, recolored)
check(icon.BackgroundColor3 == recolored and before.BackgroundColor3 == recolored and icon:GetChildren()[1] == before,
    "state tint reuses existing stroke instances")
local listen = before:GetPropertyChangedSignal("BackgroundColor3")
local calls = 0
local connection = listen:Connect(function() calls = calls + 1 end)
Lucide.setColor(icon, recolored)
check(calls == 0, "unchanged tint does not rewrite strokes")
local queried = false
Lucide.setColor({BackgroundColor3 = recolored, GetChildren = function()
    queried = true
    return {}
end}, recolored)
check(not queried, "unchanged tint returns before reading any children")
connection:Disconnect()
icon:Destroy()

local total, maximum, glyphCount = 0, 0, 0
for name in pairs(glyphs) do
    local mounted = Lucide.mount(button, name, {size = 16})
    local descendants = mounted:GetDescendants()
    glyphCount, total, maximum = glyphCount + 1, total + #descendants, math.max(maximum, #descendants)
    local native = true
    for _, part in ipairs(descendants) do
        if part.ClassName ~= "Frame" and part.ClassName ~= "UICorner" and part.ClassName ~= "UIStroke" then native = false end
        if part.ClassName == "Frame" and (part.Active or part.Selectable or part.Interactable ~= false) then native = false end
    end
    check(native and #descendants > 0, name .. " renders native passive strokes without external asset lookups")
    mounted:Destroy()
end
check(glyphCount == 75 and maximum <= 90 and total / glyphCount <= 24, "bounded vector subset and native instance counts")
check(mock.activeConnections == 0 and #button:GetChildren() == 0, "mounting and destroying glyphs leaves no connections or instances")

return checks
