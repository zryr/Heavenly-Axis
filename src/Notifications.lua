local Coordinates = require("Coordinates")
local Design = require("Design")
local Lucide = require("Lucide")
local Util = require("Util")

local Notifications = {}
Notifications.__index = Notifications

local LAYER = 55
local TEXT_LEFT, TEXT_RIGHT = Design.touch.comfortable, Design.space.medium
local TITLE_TOP, BODY_TOP, BOTTOM = Design.space.small, 28, 10
local BODY_SIZE, BODY_LINE, BODY_MAX = Design.text.control, 17, 68
local GUTTER = 6
local C, F = Design.colors, Design.font

local function make(class, properties, parent)
    local object = Instance.new(class)
    for name, value in pairs(properties) do object[name] = value end
    if object:IsA("GuiObject") then
        object.Active = false
        object.Selectable = false
        pcall(function() object.Interactable = false end)
    end
    object.Parent = parent
    return object
end

local function label(parent, name, size, font, layer)
    return make("TextLabel", {
        Name = name, BackgroundTransparency = 1, BorderSizePixel = 0, Text = "",
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
        TextSize = size, Font = font, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = layer,
    }, parent)
end

local function valid(rect)
    return type(rect) == "table" and Util.finite(rect.x) and Util.finite(rect.y)
        and Util.finite(rect.w) and Util.finite(rect.h) and rect.w > 0 and rect.h > 0
end

local function encloses(area, rect)
    return rect.x >= area.x and rect.y >= area.y and rect.x + rect.w <= area.x + area.w
        and rect.y + rect.h <= area.y + area.h
end

local function overlaps(rect, obstacles)
    for _, obstacle in ipairs(obstacles) do
        if valid(obstacle) then
            local width = math.min(rect.x + rect.w, obstacle.x + obstacle.w + GUTTER) - math.max(rect.x, obstacle.x - GUTTER)
            local height = math.min(rect.y + rect.h, obstacle.y + obstacle.h + GUTTER) - math.max(rect.y, obstacle.y - GUTTER)
            if width > 0 and height > 0 then return true end
        end
    end
    return false
end

local function place(area, width, height, obstacles)
    local left, top = area.x, area.y
    local right, bottom = left + area.w - width, top + area.h - height
    local xs, ys = {(left + right) / 2, left, right}, {bottom, top}
    for _, obstacle in ipairs(obstacles) do
        if valid(obstacle) then
            xs[#xs + 1], xs[#xs + 2] = obstacle.x - width - GUTTER, obstacle.x + obstacle.w + GUTTER
            ys[#ys + 1], ys[#ys + 2] = obstacle.y - height - GUTTER, obstacle.y + obstacle.h + GUTTER
        end
    end
    ys[#ys + 1] = (top + bottom) / 2
    for _, y in ipairs(ys) do
        for _, x in ipairs(xs) do
            local rect = {x = math.max(left, math.min(x, right)), y = math.max(top, math.min(y, bottom)), w = width, h = height}
            if not overlaps(rect, obstacles) then return rect end
        end
    end
end

local function normalize(message)
    if type(message) ~= "string" then return "" end
    return message:gsub("%s+", " "):match("^%s*(.-)%s*$")
end

local function count(message)
    return (utf8 and utf8.len(message)) or #message
end

function Notifications.new(parent, services)
    local self = setmetatable({parent = parent, services = services or {}, generation = 0, obstacles = {}}, Notifications)
    self.styles = {
        info = {accent = C.cyan, title = "", icon = "info", duration = 3.0},
        success = {accent = C.success, title = "Complete", icon = "check", duration = 3.2},
        warning = {accent = C.warning, title = "Needs attention", icon = "triangle-alert", duration = 4.7, important = true},
        error = {accent = C.danger, title = "Action failed", icon = "circle-alert", duration = 5.2, important = true},
    }
    self.frame = make("Frame", {
        Name = "Toast", Visible = false, ClipsDescendants = true, BorderSizePixel = 0,
        BackgroundColor3 = C.surface, BackgroundTransparency = .04, ZIndex = LAYER,
    }, parent)
    Design.round(self.frame, Design.radius.surface)
    Design.stroke(self.frame, nil, nil, .25)

    local badge = make("Frame", {
        Name = "Severity", Size = UDim2.fromOffset(28, 28), Position = UDim2.fromOffset(10, 10), BorderSizePixel = 0,
        BackgroundColor3 = self.styles.info.accent, BackgroundTransparency = .86, ZIndex = LAYER + 1,
    }, self.frame)
    Design.round(badge, 14)
    self.badge, self.icons = badge, {}
    for kind, style in pairs(self.styles) do
        local icon = Lucide.mount(badge, style.icon, {size = 17, color = style.accent,
            position = UDim2.fromScale(.5, .5), anchor = Vector2.new(.5, .5), zIndex = LAYER + 2})
        if icon then icon.Visible = false; self.icons[kind] = icon end
    end

    self.title = label(self.frame, "Title", Design.text.body, F.strong, LAYER + 1)
    self.title.Position = UDim2.fromOffset(TEXT_LEFT, TITLE_TOP)
    self.title.Size = UDim2.new(1, -TEXT_LEFT - TEXT_RIGHT, 0, 18)
    self.body = label(self.frame, "Body", BODY_SIZE, F.body, LAYER + 1)
    self.body.Position = UDim2.fromOffset(TEXT_LEFT, BODY_TOP)
    self.body.TextColor3 = C.subtleText
    self.body.TextWrapped = true
    return self
end

function Notifications:_dimensions(area)
    local message = self.current
    local preferredWidth = math.max(count(message.title) * 7, count(message.body) * 6.7) + TEXT_LEFT + TEXT_RIGHT
    local width = math.min(math.floor(area.w), math.max(214, math.min(360, math.ceil(preferredWidth))))
    local bodyTop = message.title ~= "" and BODY_TOP or 14
    if width < 144 or area.h < math.max(48, bodyTop + BODY_LINE + BOTTOM) then return nil end
    local bodyWidth = width - TEXT_LEFT - TEXT_RIGHT
    if width ~= self.measuredWidth then
        local measured
        local textService = self.services.TextService
        if textService then
            local ok, bounds = pcall(textService.GetTextSize, textService, message.body, BODY_SIZE, F.body,
                Vector2.new(bodyWidth, 10000))
            if ok and bounds and Util.finite(bounds.Y) then measured = math.ceil(bounds.Y) + 3 end
        end
        local charsPerLine = math.max(1, math.floor(bodyWidth / (BODY_SIZE * .52)))
        local approximate = math.ceil(count(message.body) / charsPerLine) * BODY_LINE
        self.measuredWidth, self.measuredHeight = width, math.min(BODY_MAX, math.max(BODY_LINE, measured or approximate))
    end
    local bodyHeight = math.min(self.measuredHeight, math.floor(area.h) - bodyTop - BOTTOM)
    return width, math.max(48, bodyTop + bodyHeight + BOTTOM), bodyHeight, bodyTop
end

function Notifications:layout(area, avoidRects)
    if self.dead then return end
    self.area, self.obstacles = valid(area) and area or nil, avoidRects or {}
    if not self.current then return end
    local width, height, bodyHeight, bodyTop
    if self.area then width, height, bodyHeight, bodyTop = self:_dimensions(area) end
    if not width then self.frame.Visible = false; return end
    local rect = self.rect
    if not rect or width ~= rect.w or height ~= rect.h or not encloses(area, rect) or overlaps(rect, self.obstacles) then
        rect = place(area, width, height, self.obstacles)
        self.rect = rect
    end
    if not rect then self.frame.Visible = false; return end
    if self.drawnWidth ~= width or self.drawnHeight ~= height or self.drawnBodyTop ~= bodyTop or self.drawnBodyHeight ~= bodyHeight then
        self.frame.Size = UDim2.fromOffset(width, height)
        self.body.Size = UDim2.fromOffset(width - TEXT_LEFT - TEXT_RIGHT, bodyHeight)
        self.body.Position = UDim2.fromOffset(TEXT_LEFT, bodyTop)
        self.drawnWidth, self.drawnHeight, self.drawnBodyTop, self.drawnBodyHeight = width, height, bodyTop, bodyHeight
    end
    local x, y = Coordinates.screenToLocal(rect.x, rect.y, self.parent)
    if x ~= self.drawnX or y ~= self.drawnY then
        self.frame.Position = UDim2.fromOffset(x, y)
        self.drawnX, self.drawnY = x, y
    end
    self.frame.Visible = true
end

function Notifications:_cancelTween()
    if self.tween then pcall(self.tween.Cancel, self.tween); self.tween = nil end
end

function Notifications:_fade(transparency, duration)
    if not self.frame.Visible then return false end
    local service, guiService = self.services.TweenService, self.services.GuiService
    if not service or not TweenInfo then return false end
    local ok, reduced = pcall(function() return guiService and guiService.ReducedMotionEnabled end)
    if ok and reduced then return false end
    self:_cancelTween()
    local started, tween = pcall(function()
        local animation = service:Create(self.frame, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
            {BackgroundTransparency = transparency})
        animation:Play()
        return animation
    end)
    if started then self.tween = tween end
    return started
end

function Notifications:_cancelExpiry()
    self.generation = self.generation + 1
    if self.timer and task and task.cancel then pcall(task.cancel, self.timer) end
    self.timer = nil
end

function Notifications:_hide()
    self:_cancelExpiry()
    self:_cancelTween()
    self.current, self.rect = nil, nil
    self.frame.Visible = false
end

function Notifications:show(message, options)
    if self.dead then return false end
    local body = normalize(message)
    if body == "" then return false end
    options = type(options) == "table" and options or {}
    local kind = self.styles[options.kind] and options.kind or "info"
    local style = self.styles[kind]
    local title = normalize(options.title)
    if title == "" then title = style.title end
    local keep = options.keepOnClose == true
    local current = self.current
    if current then
        if current.style.important and not style.important and not keep and options.replace ~= true then return false end
        if current.kind == kind and current.title == title and current.body == body and current.keepOnClose == keep then return false end
    end
    self:_cancelExpiry()
    self:_cancelTween()
    local generation = self.generation
    self.current = {kind = kind, style = style, title = title, body = body, keepOnClose = keep}
    self.rect, self.measuredWidth = nil, nil
    self.badge.BackgroundColor3 = style.accent
    for iconKind, icon in pairs(self.icons) do icon.Visible = iconKind == kind end
    self.title.Text, self.title.TextColor3, self.title.Visible = title, style.accent, title ~= ""
    self.body.Text = body
    self:layout(self.area, self.obstacles)
    self.frame.BackgroundTransparency = .24
    if not self:_fade(.04, Design.motion.enter) then self.frame.BackgroundTransparency = .04 end
    if task and task.delay then
        local function expire()
            if self.dead or generation ~= self.generation then return end
            self.timer = nil
            self:_hide()
        end
        self.timer = task.delay(style.duration, function()
            if self.dead or generation ~= self.generation then return end
            if self:_fade(.24, Design.motion.exit) then self.timer = task.delay(Design.motion.exit, expire) else expire() end
        end)
    end
    return true
end

function Notifications:close()
    if not self.dead and self.current and not self.current.keepOnClose then self:_hide() end
end

function Notifications:destroy()
    if self.dead then return end
    self:_hide()
    self.dead = true
    self.area, self.obstacles = nil, nil
    self.frame:Destroy()
end

return Notifications
