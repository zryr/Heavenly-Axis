-- The practice pad uses production Input with a model that owns only synthetic controls.
local mock = require("support/Roblox").new(640, 360)
local Coordinates = require("Coordinates")
local Onboarding = require("Onboarding")
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, message)
end

task = mock.task
local editor = Instance.new("ScreenGui")
editor.Parent = mock.playerGui
local root = Instance.new("Frame")
root.Size, root.Parent = UDim2.fromScale(1, 1), editor
local gameScreen = Instance.new("ScreenGui")
gameScreen.Parent = mock.playerGui
local realJump = Instance.new("TextButton")
realJump.Position, realJump.Size, realJump.Parent = UDim2.fromOffset(460, 200), UDim2.fromOffset(82, 65), gameScreen
local gamePosition, gameSize = realJump.Position, realJump.Size
local savedLayout, userHistory, modes = {Jump = "saved layout"}, {}, {}
local outcomes, stateChanges = {}, 0
local session = Onboarding.new(root, mock.services, {
    changed = function() stateChanges = stateChanges + 1 end,
    finished = function(outcome) outcomes[#outcomes + 1] = outcome end,
})
local landscape = {x = 28, y = 7, w = 572, h = 312}
local portrait = {x = 18, y = 5, w = 344, h = 730}
local input = mock.services.UserInputService
local function press(object, x, y)
    local bounds = Coordinates.rect(object)
    local p = {UserInputType = Enum.UserInputType.Touch, Position = mock.vec(x or bounds.x + bounds.w / 2, y or bounds.y + bounds.h / 2)}
    object.InputBegan:Fire(p)
    return p
end
local function touchTarget(key, fraction)
    local rect = session.rects[key]
    fraction = fraction or .5
    return press(session.canvas, rect.x + rect.w * fraction, rect.y + rect.h * fraction)
end
local function move(pointer, dx, dy)
    pointer.Position = mock.vec(pointer.Position.X + dx, pointer.Position.Y + dy)
    input.InputChanged:Fire(pointer)
end
local function release(pointer)
    input.InputEnded:Fire(pointer)
    mock:flush()
end
local function advance() session.next.Activated:Fire() end
local function inside(area, rect)
    return rect and rect.x >= area.x and rect.y >= area.y and rect.x + rect.w <= area.x + area.w and rect.y + rect.h <= area.y + area.h
end

session:layout(landscape)
check(session:start() and session:isActive() and #session:protectedRects() == 1 and session.next.Text == "Start", "first open shows the welcome and Start or Skip")
check(not session:start(), "a second start cannot duplicate the active tutorial")
session.skip.Activated:Fire()
check(not session:isActive() and outcomes[1] == "skipped" and mock.activeConnections == 0, "Skip dismisses and records only the tutorial choice")
check(session:start(), "Help can start the same isolated tutorial again")
advance()
check(session.lesson.id == "select" and #session:protectedRects() == 2, "Start mounts coach and practice pad")
check(inside(landscape, session.coachRect) and inside(landscape, session.padRect)
    and not Coordinates.intersection(session.coachRect, session.padRect), "landscape coaching never covers practice targets")
release(touchTarget("Jump"))
check(session.app.selection[1] == "Jump" and session.lessonComplete, "practice tap selects and teaches the native selection outline")
advance()
local origin = session.rects.Jump
local finger = touchTarget("Jump")
move(finger, 22, 13)
release(finger)
check(session.lesson.id == "move" and session.lessonComplete and session.rects.Jump.x == origin.x + 22
    and session.rects.Jump.w == origin.w, "real touch drag moves only the practice target")

finger = touchTarget("Jump")
move(finger, 28, 14)
session:layout(portrait)
release(finger)
check(session.lesson.id == "move" and session.lessonComplete and not session.input:isBusy(), "rotation cancels the active practice drag and preserves the lesson")
check(inside(portrait, session.coachRect) and inside(portrait, session.padRect)
    and not Coordinates.intersection(session.coachRect, session.padRect), "portrait stacks the coach and pad inside the safe area")

advance()
check(session.lesson.id == "resize" and session.slider.Visible and session.handle.Visible, "resize offers an external handle, pinch and slider")
local width = session.rects.Jump.w
finger = press(session.handle)
move(finger, 17, 17)
release(finger)
check(session.rects.Jump.w > width and session.lessonComplete, "handle resize runs through the shared gesture owner")
width = session.rects.Jump.w
local track = Coordinates.rect(session.track)
finger = press(session.slider, track.x + track.w * .83, track.y + track.h / 2)
release(finger)
check(session.rects.Jump.w > width, "practice slider writes actual practice geometry")
width = session.rects.Jump.w
finger = touchTarget("Jump", .25)
local second = touchTarget("Jump", .7)
move(second, -15, -15)
release(second)
release(finger)
check(session.rects.Jump.w < width, "pinch also adjusts the isolated practice target")

advance()
check(session.lesson.id == "layers" and session.overlay.Visible and session.layers.Visible, "Layers step adds a visible translucent practice overlay")
local covered = session.rects.Jump
finger = touchTarget("Jump")
mock:flush()
check(session.layerPicker and session.chooseJump.Visible and session.chooseOverlay.Visible and not session.input:isBusy(),
    "holding opens Select Through through the production Input controller")
release(finger)
session.chooseJump.Activated:Fire()
check(session.lessonComplete and session.app.selection[1] == "Jump" and session.rects.Jump == covered,
    "selecting through the overlay neither moves nor resizes the control")

advance()
check(session.lesson.id == "group" and session.multi.Visible and session.group.Visible and session.rects.Move,
    "optional group practice exposes Multi and two controls")
session.multi.Activated:Fire()
release(touchTarget("Jump"))
release(touchTarget("Move"))
session.group.Activated:Fire()
local groupJump, groupMove = session.rects.Jump, session.rects.Move
check(session.lessonComplete and #session.app.selection == 2, "touch Multi selects both practice controls for grouping")
finger = touchTarget("Jump")
move(finger, 12, 9)
release(finger)
check(session.rects.Jump.x == groupJump.x + 12 and session.rects.Move.x == groupMove.x + 12, "group practice drags both targets")
advance()
check(session.lesson.id == "finish" and session.next.Text == "Finish" and session.description.Text:find("Automatic startup", 1, true),
    "final step explains saving, returning and separate startup")
advance()
check(outcomes[2] == "completed" and stateChanges >= 7 and not session:isActive(), "Finish records completion and dismisses")
check(realJump.Position == gamePosition and realJump.Size == gameSize and savedLayout.Jump == "saved layout"
    and #userHistory == 0 and #modes == 0, "practice never accesses actual HUD properties, profiles or user history")
check(mock.activeConnections == 0, "completion releases every practice connection")

session:start()
advance()
local reopenedCanvas = session.canvas
session:close()
check(reopenedCanvas.Destroyed and #outcomes == 2 and not session:isActive(), "closing the editor does not silently mark the tutorial seen")
session:start()
session:destroy()
session:destroy()
check(not session:start() and mock.activeConnections == 0 and #outcomes == 2, "destroy invalidates replay and releases scoped subscriptions")
return checks
