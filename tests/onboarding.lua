-- The practice pad uses production Input with a model that owns only synthetic controls.
local mock = require("support/Roblox").new(640, 360)
local Coordinates = require("Coordinates")
local Design = require("Design")
local Onboarding = require("Onboarding")
local Reference = require("ActionReference")
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
local outcomes, stateChanges, writes, progress = {}, 0, 0, {}
local realToolbar = Instance.new("Frame")
realToolbar.Position, realToolbar.Size, realToolbar.Parent = UDim2.fromOffset(120, 52), UDim2.fromOffset(280, 48), root
local function newTutorial()
    return Onboarding.new(root, mock.services, {
        changed = function() stateChanges = stateChanges + 1 end,
        finished = function(outcome, mode) outcomes[#outcomes + 1] = {outcome = outcome, mode = mode} end,
        highlight = function(id) if id == "toolbar" then return realToolbar end end,
        readProgress = function(mode) return progress[mode] end,
        saveProgress = function(mode, step) progress[mode], writes = step, writes + 1 end,
    })
end
local session = newTutorial()
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
check(session:start() and session:isActive() and session.mode == "quick" and session.next.Text == "Start", "first open shows short Quick Start with Start or Skip")
check(session.coach.BackgroundColor3 == Design.colors.surface and session.next.BackgroundColor3 == Design.colors.cyan
    and session.next.AbsoluteSize.Y >= Design.touch.minimum, "tutorial uses the shared surface, primary action and touch target tokens")
check(session.highlightFrames[1].Visible and session.highlightRects[1].x == realToolbar.AbsolutePosition.X,
    "welcome highlights the actual toolbar bounds without invoking it")
check(not session:start(), "a second start cannot duplicate the active tutorial")
session.skip.Activated:Fire()
check(not session:isActive() and outcomes[1].outcome == "skipped" and outcomes[1].mode == "quick" and mock.activeConnections == 0,
    "Skip dismisses and reports only the tutorial choice")
check(session:start(), "Help can replay Quick Start")
advance()
check(session.lesson.id == "panel" and session.practicePanel.Visible and session.back.Visible, "Quick Start teaches moving the inspector before HUD edits")
check(inside(landscape, session.coachRect) and inside(landscape, session.padRect)
    and not Coordinates.intersection(session.coachRect, session.padRect), "landscape coach stays clear of practice targets")
local panelStart, jumpStart = session.sampleRect, session.rects.Jump
local finger = press(session.practiceGrip)
move(finger, 24, 20)
release(finger)
check(session.sampleRect.x == panelStart.x + 24 and session.rects.Jump == jumpStart and session.lessonComplete,
    "dragging the sample inspector moves only that surface")
advance()
check(session.lesson.id == "select", "Next reaches selection practice")
session.back.Activated:Fire()
check(session.lesson.id == "panel", "Back returns to the prior lesson")
advance()
check(writes == 1, "tutorial neither writes during a gesture nor after each Next or Back")
session:close()
check(progress.quick == 3 and #outcomes == 1 and not session:isActive(), "closing saves only the current lesson and does not mark completion")
session:destroy()
session = newTutorial()
session:layout(landscape)
check(session:hasProgress("quick") and session:start("quick", true) and session.lesson.id == "select", "a new tutorial resumes the saved Quick Start step")
release(touchTarget("Jump"))
check(session.app.selection[1] == "Jump" and session.lessonComplete, "practice tap selects and displays the outline")
advance()
local origin = session.rects.Jump
finger = touchTarget("Jump")
move(finger, 22, 13)
release(finger)
check(session.lesson.id == "move" and session.lessonComplete and session.rects.Jump.x == origin.x + 22
    and session.rects.Jump.w == origin.w, "real touch drag moves only the practice target")

finger = touchTarget("Jump")
move(finger, 28, 14)
session:layout(portrait)
release(finger)
check(session.lesson.id == "move" and session.lessonComplete and not session.input:isBusy(), "rotation cancels the practice drag and preserves the current lesson")
check(inside(portrait, session.coachRect) and inside(portrait, session.padRect)
    and not Coordinates.intersection(session.coachRect, session.padRect), "portrait stacks the coach and pad inside the safe area")

advance()
check(session.lesson.id == "resize" and session.slider.Visible and session.handle.Visible, "size practice exposes the handle, slider and pinch")
check(session.description.Text:find("Spread to grow", 1, true) and session.description.Text:find("Lift either finger", 1, true),
    "practice explains pinch direction and release consistently with the shared gesture owner")
check(session.description.AbsoluteSize.Y > Design.text.body and session.instructions.CanvasSize.Y.Offset >= session.description.AbsoluteSize.Y,
    "wrapped teaching copy has its full measured height and remains scrollable")
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
check(session.lesson.id == "finish" and session.tour.Visible and session.description.Text:find("startup", 1, true),
    "Quick Start explains saving, Done and separate startup, then offers the guided tour")
session.tour.Activated:Fire()
check(outcomes[2].outcome == "completed" and outcomes[2].mode == "quick" and not progress.quick and session.mode == "tour",
    "the optional Guided Tour begins only by choice and clears the completed Quick Start progress")
check(session.step == 1 and session.progress.Text:find("Editor navigation", 1, true), "the full tour starts with a numbered navigation chapter")
for _ = 1, 4 do advance() end
check(session.lesson.id == "layers" and session.overlay.Visible and session.layers.Visible, "selection chapter includes a translucent practice overlay")
local covered = session.rects.Jump
finger = touchTarget("Jump")
mock:flush()
check(session.layerPicker and session.chooseJump.Visible and session.chooseOverlay.Visible and not session.input:isBusy(),
    "holding invokes Select Through through the production Input controller")
release(finger)
session.chooseJump.Activated:Fire()
check(session.lessonComplete and session.app.selection[1] == "Jump" and session.rects.Jump == covered,
    "selecting through the overlay preserves the control's geometry")
advance()
advance()
session.skip.Activated:Fire()
check(not session:isActive() and outcomes[3].mode == "tour" and progress.tour == 7 and mock.activeConnections == 0,
    "Skip leaves a resumable Guided Tour checkpoint and releases its input subscriptions")
check(session:hasProgress("tour") and session:start("tour", true) and session.lesson.id == "move", "Resume restores the exact Guided Tour step")
advance()
advance()
check(session.lesson.id == "rotate" and session.rotationHandle.gui.Visible and session.angleSlider.Visible, "rotation practice offers a real handle and angle slider")
local center = session.app:appearanceInfo("rotation").pivot
finger = press(session.rotationHandle.gui)
local dx, dy = finger.Position.X - center.x, finger.Position.Y - center.y
move(finger, -dy - dx, dx - dy)
release(finger)
check(math.abs(session.angle) > 40 and session.targets.Jump.object.Rotation == session.angle and session.lessonComplete,
    "rotating around the practice center changes only its rendered angle")
advance()
check(session.lesson.id == "opacity" and session.opacitySlider.Visible and session.scopeButton.Visible, "opacity practice offers relative value and contents choice")
track = Coordinates.rect(session.opacityTrack)
release(press(session.opacitySlider, track.x + track.w * .25, track.y + track.h / 2))
check(session.opacity < 40 and session.targets.Jump.object.BackgroundTransparency > .6
    and session.targets.Jump.text.TextTransparency == 0 and session.lessonComplete, "the real opacity slider fades the selected practice visual")
session.scopeButton.Activated:Fire()
check(session.targets.Jump.text.TextTransparency > .6, "contents practice visibly fades the child's text too")

advance()
check(session.lesson.id == "group" and session.multi.Visible and session.group.Visible and session.rects.Move, "group chapter uses two practice controls")
session.multi.Activated:Fire()
release(touchTarget("Jump"))
release(touchTarget("Move"))
session.group.Activated:Fire()
local groupJump, groupMove = session.rects.Jump, session.rects.Move
check(session.lessonComplete and #session.app.selection == 2, "touch-only Multi selects both practice controls")
finger = touchTarget("Jump")
move(finger, 12, 9)
release(finger)
check(session.rects.Jump.x == groupJump.x + 12 and session.rects.Move.x == groupMove.x + 12, "group practice drags both targets")
for _ = 1, 3 do advance() end
check(session.lesson.id == "reset" and session.resetButton.Visible and session.angle == 28 and session.opacity == 55,
    "recovery chapter demonstrates reset on changed practice data")
session.resetButton.Activated:Fire()
check(session.angle == 0 and session.opacity == 100 and session.lessonComplete, "Reset restores the practice geometry and visual defaults")
advance()
check(session.lesson.id == "compatibility" and session.description.Text:find("containing bar", 1, true), "compatibility chapter teaches container fallback and details")
advance()
advance()
check(outcomes[4].outcome == "completed" and outcomes[4].mode == "tour" and progress.tour == nil and stateChanges >= 24 and not session:isActive(),
    "the final chapter completes and clears Guide progress")
check(realJump.Position == gamePosition and realJump.Size == gameSize and savedLayout.Jump == "saved layout"
    and #userHistory == 0 and #modes == 0, "practice never writes actual HUD properties, profiles or user history")
check(mock.activeConnections == 0, "completion releases every practice connection")

local opacity = Reference.get("opacity")
check(opacity.label == "Opacity" and opacity.how:find("100%", 1, true) and opacity.effect and opacity.note,
    "reference states activation, saved-layout effect and limits")
check(Reference.get("size").how:find("on or near the selection", 1, true), "Help explains the broader near-selection pinch area")
check(#Reference.search("Rotate") > 0 and #Reference.search("   ") == #Reference.sections and #Reference.search("[[[no action]]]" ) == 0,
    "reference groups literal case-insensitive search results by category")
session:start()
advance()
local reopenedCanvas = session.canvas
session:close()
check(reopenedCanvas.Destroyed and #outcomes == 4 and not session:isActive(), "editor close preserves progress without reporting completion")
session:start()
session:destroy()
session:destroy()
check(not session:start() and mock.activeConnections == 0 and #outcomes == 4, "destroy invalidates replay and releases scoped subscriptions")
return checks
