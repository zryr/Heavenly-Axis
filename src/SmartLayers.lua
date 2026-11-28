local SmartLayers = {}

local builtins = {
    JumpButton = {"Jump button", "JMP"},
    ThumbstickFrame = {"Classic joystick", "JOY"},
    DynamicThumbstickFrame = {"Dynamic joystick zone", "JOY"},
}
local icons = {
    Frame = "FR", CanvasGroup = "GR", ScrollingFrame = "SC",
    TextButton = "BTN", ImageButton = "BTN", TextBox = "IN",
    TextLabel = "TXT", ImageLabel = "IMG", ViewportFrame = "3D", VideoFrame = "VID",
}
local textClasses = {TextButton = true, TextLabel = true, TextBox = true}
local imageClasses = {ImageButton = true, ImageLabel = true}

local function nonempty(value)
    return type(value) == "string" and value:find("%S") ~= nil
end

local function paintedAlpha(value)
    return type(value) == "number" and value < 0.99
end

function SmartLayers.hasImage(object)
    local class = object.ClassName
    if class == "ViewportFrame" then return object.CurrentCamera ~= nil end
    if not imageClasses[class] then return false end
    if nonempty(object.Image) then return true end
    local ok, hasContent = pcall(function()
        local content = object.ImageContent
        return content ~= nil and (content.Object ~= nil or nonempty(content.Uri))
    end)
    return ok and hasContent
end

function SmartLayers.name(record)
    local builtin = builtins[record.builtin]
    local object = record.object
    if builtin then return builtin[1], builtin[2] end
    local name = object.Name:gsub("[_%-]+", " "):gsub("(%l)(%u)", "%1 %2"):gsub("(%u)(%u%l)", "%1 %2")
    name = name:match("^%s*(.-)%s*$")
    if not nonempty(name) then name = object.ClassName end
    return name, icons[object.ClassName] or "UI"
end

function SmartLayers.painted(object, strokes)
    if paintedAlpha(object.BackgroundTransparency) then return true end
    local class = object.ClassName
    local text
    if textClasses[class] then
        text = object.MaxVisibleGraphemes ~= 0 and (nonempty(object.Text) or class == "TextBox" and nonempty(object.PlaceholderText))
        if text and (paintedAlpha(object.TextTransparency) or paintedAlpha(object.TextStrokeTransparency)) then return true end
    elseif (imageClasses[class] or class == "ViewportFrame") and paintedAlpha(object.ImageTransparency) and SmartLayers.hasImage(object) then return true
    elseif class == "VideoFrame" and nonempty(object.Video) then return true end
    local borderWidth = 0
    for _, stroke in ipairs(strokes or {}) do
        local border = tostring(stroke.ApplyStrokeMode):match("Border$") ~= nil
        if stroke.Enabled ~= false and type(stroke.Thickness) == "number" and stroke.Thickness > 0
            and paintedAlpha(stroke.Transparency) then
            if border or not textClasses[class] then borderWidth = math.max(borderWidth, stroke.Thickness)
            elseif text then return true end
        end
    end
    if borderWidth > 0 then return true, borderWidth end
    return false, nil
end

function SmartLayers.actionable(record)
    local object = record.object
    return (record.interactive or object.ClassName == "Frame" and object.Active == true)
        and object.Interactable ~= false and object.Active ~= false
end

function SmartLayers.decorative(record)
    local class = record.object.ClassName
    return class == "ImageLabel" or class == "TextLabel"
end

return SmartLayers
