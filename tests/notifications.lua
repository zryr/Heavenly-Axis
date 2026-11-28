-- Layout and lifecycle with structural Roblox mocks. Native input/rendering needs Roblox.
local mock = require("support/Roblox").new(640, 360)
local Coordinates = require("Coordinates")
local Design = require("Design")
local Notifications = require("Notifications")
local checks = 0
local function check(value, reason)
    checks = checks + 1
    assert(value, reason)
end

local scheduled = {}
task = {
    delay = function(duration, callback)
        local timer = {duration = duration, callback = callback, pending = true}
        scheduled[#scheduled + 1] = timer
        return timer
    end,
    cancel = function(timer) timer.pending = false end,
}
local function tick(timer)
    timer.pending = false
    timer.callback()
end
local function pendingCount()
    local total = 0
    for _, timer in ipairs(scheduled) do if timer.pending then total = total + 1 end end
    return total
end

local measurements = 0
mock.services.TextService = {
    GetTextSize = function(_, value, fontSize, _, bounds)
        measurements = measurements + 1
        local lines = math.ceil(#value * (fontSize * .52) / bounds.X)
        return mock.vec(bounds.X, math.max(1, lines) * fontSize)
    end,
}
local layer = Instance.new("ScreenGui")
layer.Parent = mock.playerGui
local root = Instance.new("Frame")
root.Position, root.Size, root.Parent = UDim2.fromOffset(7, 3), UDim2.fromScale(1, 1), layer
local toast = Notifications.new(root, mock.services)
local childCount = #toast.frame:GetDescendants()
local safe = {x = 30, y = 10, w = 570, h = 306}
local function bounds() return Coordinates.rect(toast.frame) end
local function within(area, rect)
    return area.x <= rect.x and area.y <= rect.y and rect.x + rect.w <= area.x + area.w and rect.y + rect.h <= area.y + area.h
end

check(toast.frame.Parent == root and not toast.frame.Visible and toast.frame.BackgroundColor3 == Design.colors.surface,
    "constructs a hidden native toast with the shared editor surface color")
toast:layout(safe)
check(not toast:show("   \n "), "blank content is ignored")
check(toast:show("Adjust the selection."), "ordinary editor feedback is accepted")
local firstTimer = scheduled[#scheduled]
local firstBounds = bounds()
check(toast.frame.Visible and toast.body.Text == "Adjust the selection." and not toast.title.Visible, "untitled info uses only the message")
check(firstBounds.w < 240 and firstBounds.h == 48 and within(safe, firstBounds), "short feedback uses a compact safe footprint")
check(firstBounds.y + firstBounds.h == safe.y + safe.h and toast.frame.Position.Y.Offset ~= firstBounds.y,
    "bottom placement converts from canonical space through the overlay origin")
local firstRead = measurements
toast:layout(safe)
check(measurements == firstRead and bounds().x == firstBounds.x and bounds().y == firstBounds.y, "stable layout reuses metrics and placement")
check(not toast:show("Adjust the selection.") and #scheduled == 1, "repeated notices coalesce without restarting expiry")

local selection = {x = firstBounds.x - 42, y = firstBounds.y - 20, w = firstBounds.w + 84, h = firstBounds.h + 20}
toast:layout(safe, {selection})
check(within(safe, bounds()) and not Coordinates.intersection(bounds(), selection), "toast moves clear of the selected target")

local warning = "The selected button changed during editing. Reopen Tools to review which changes were saved before this session."
check(toast:show(warning, {kind = "warning", title = "Layout changed"}), "important feedback supersedes ordinary status")
local warningTimer = scheduled[#scheduled]
check(toast.title.Visible and toast.title.Text == "Layout changed" and toast.icons.warning.Visible
    and toast.icons.warning.Name == "Lucide_triangle-alert" and not toast.icons.info.Visible
    and toast.body.TextWrapped and toast.body.Size.Y.Offset > 17,
    "warning uses a Lucide alert, semantic title, distinct accent and wrapped body")
check(not firstTimer.pending and pendingCount() == 1 and warningTimer.duration > firstTimer.duration, "one active expiry remains and warnings stay readable longer")
tick(firstTimer)
check(toast.frame.Visible and toast.body.Text == warning, "a late canceled callback cannot hide current content")
check(not toast:show("Selection cleared."), "transient status preserves a visible warning")
check(toast:show("Check the file path.", {kind = "error"}) and toast.title.Text == "Action failed"
    and toast.icons.error.Visible and toast.icons.error.Name == "Lucide_circle-alert" and not toast.icons.warning.Visible,
    "newer important messages replace old warnings and expose their category")
check(not toast:show("Export copied.", {kind = "success"}), "secondary success does not eclipse unresolved errors")
check(toast:show("Changes restored.", {kind = "success", replace = true}) and toast.body.Text == "Changes restored.",
    "a verified recovery result replaces an earlier warning or error when requested")
check(not toast:show("Changes restored.", {kind = "success", replace = true}), "replacement still deduplicates identical feedback")
toast:show("Check the file path.", {kind = "error"})

check(toast:show("Layout saved on this device.", {kind = "success", title = "Saved", keepOnClose = true}),
    "an explicit keep-on-close result can replace older important status")
local savedTimer = scheduled[#scheduled]
check(toast.icons.success.Visible and toast.icons.success.Name == "Lucide_check" and not toast.icons.error.Visible
    and toast.title.Text == "Saved", "success uses a Lucide check and the supplied title")
toast:close()
check(toast.frame.Visible and savedTimer.pending, "confirmed Save remains briefly visible after leaving the editor")
tick(savedTimer)
check(not toast.frame.Visible and toast.current == nil and pendingCount() == 0, "the kept message still expires without retaining state")

local portrait = {x = 16, y = 4, w = 360, h = 800}
local toolbar = {x = 16, y = 4, w = 360, h = 50}
local inspector = {x = 16, y = 572, w = 360, h = 232}
toast:layout(portrait, {toolbar, inspector})
toast:show("Returned to the previous checkpoint.", {kind = "success", title = "Restored"})
local compact = bounds()
check(compact.y == toolbar.y + toolbar.h + 6 or compact.y + compact.h == inspector.y - 6,
    "when both edges are occupied, portrait placement keeps the clear edge beside a protected surface")
local transient = scheduled[#scheduled]
toast:close()
check(not toast.frame.Visible and not transient.pending and toast.current == nil, "closing discards ordinary transient notices and cancels expiry")

toast:layout(safe, {safe})
toast:show("Group created.", {kind = "success"})
check(not toast.frame.Visible and pendingCount() == 1, "a crowded layout defers the notice instead of covering protected controls")
toast:layout(safe, {selection})
check(toast.frame.Visible and not Coordinates.intersection(bounds(), selection) and pendingCount() == 1,
    "a deferred notice can appear when there is a free region, without another expiry")
toast:close()

toast:layout({x = 80, y = 40, w = 108, h = 38})
toast:show("Wait until the keyboard closes.")
check(not toast.frame.Visible and pendingCount() == 1, "message holds until there is a readable safe region")
toast:layout({x = 80, y = 40, w = 148, h = 85})
check(toast.frame.Visible and within({x = 80, y = 40, w = 148, h = 85}, bounds()), "message reflows within a narrow safe region")

local passive = toast.frame.Active == false and toast.frame.Interactable == false and not toast.frame.Selectable
for _, object in ipairs(toast.frame:GetDescendants()) do
    if object:IsA("GuiObject") then
        passive = passive and object.Active == false and object.Interactable == false and not object.Selectable
    end
end
check(passive and toast.frame.ZIndex < 70 and #toast.frame:GetDescendants() == childCount,
    "toast stays below dialogs, avoids editor input ownership and reuses its instances")
local pendingDestroy = scheduled[#scheduled]
toast:destroy()
toast:destroy()
tick(pendingDestroy)
check(toast.frame.Destroyed and pendingCount() == 0 and not toast:show("Stale message"), "destroy invalidates expiry and further use")
check(mock.activeConnections == 0, "notification uses no service or GUI signal listeners")

local fallback = Notifications.new(root, {})
fallback:layout(safe)
fallback:show(warning, {kind = "warning"})
check(fallback.frame.Visible and fallback.body.Size.Y.Offset > 17, "missing text service retains robust wrapping and safe bounds")
fallback:destroy()

local fades = {}
TweenInfo = {new = function(duration) return {duration = duration} end}
mock.services.TweenService = {Create = function(_, frame, info, target)
    local animation = {info = info, target = target}
    function animation:Play() frame.BackgroundTransparency = target.BackgroundTransparency end
    function animation:Cancel() self.cancelled = true end
    fades[#fades + 1] = animation
    return animation
end}
local animated = Notifications.new(root, mock.services)
animated:layout(safe)
animated:show("A short entrance.")
check(#fades == 1 and fades[1].info.duration == .16 and animated.frame.BackgroundTransparency == .04,
    "motion-capable runtimes fade the surface without moving the toast")
tick(scheduled[#scheduled])
check(#fades == 2 and fades[1].cancelled and animated.frame.Visible and pendingCount() == 1,
    "exit animation is bounded and leaves only one final expiry")
tick(scheduled[#scheduled])
check(not animated.frame.Visible and pendingCount() == 0, "animated exit finishes and releases expiry")
mock.services.GuiService.ReducedMotionEnabled = true
animated:show("Reduced motion.")
check(#fades == 2 and animated.frame.Visible and animated.frame.BackgroundTransparency == .04,
    "the Roblox reduced-motion preference bypasses both transitions")
tick(scheduled[#scheduled])
check(not animated.frame.Visible and #fades == 2, "reduced-motion expiry hides immediately")
animated:destroy()
return checks
