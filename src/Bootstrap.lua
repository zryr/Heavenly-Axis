-- Heavenly Axis V3: self-contained release entry. Original project by Syshi.
local App = require("App")
local env = _G
pcall(function()
    if type(getgenv) == "function" then
        local shared = getgenv()
        if type(shared) == "table" then env = shared end
    end
end)
local options = env.HeavenlyAxisOptions or {}
if type(options) ~= "table" then options = {} end
local function reuse(app)
    if type(app) ~= "table" or not app.alive or type(app.Open) ~= "function" then return false end
    local notice
    if app.version ~= App.VERSION then
        notice = "Heavenly Axis " .. tostring(app.version or "V3") .. " is already running. Save or export your edits, then rejoin to start " .. App.VERSION .. "."
        warn(notice)
    end
    if options.SafeMode then app:SafeMode()
    elseif not options.LoaderOnly then
        app:Open()
        if notice and type(app.status) == "function" then app:status(notice) end
    end
    return true
end
local previous = env.__HEAVENLY_AXIS_V3
if reuse(previous) then return previous end
-- A bounded startup wait supports delayed LocalPlayer/PlayerGui without hanging forever.
local services = {}
for _, name in ipairs({"Players", "UserInputService", "GuiService", "RunService", "HttpService", "TextService", "TweenService", "ContextActionService", "Workspace"}) do
    services[name] = game:GetService(name)
end
local player = services.Players.LocalPlayer
local deadline = os.clock() + 15
while not player and os.clock() < deadline do
    task.wait(0.1)
    player = services.Players.LocalPlayer
end
if not player then warn("Heavenly Axis: LocalPlayer unavailable after 15 seconds. Run as a client after joining."); return nil end
local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 15)
if not playerGui then warn("Heavenly Axis: PlayerGui unavailable. Retry after the client finishes loading."); return nil end
-- Reserve the slot before yielding module initialization; concurrent invocations cannot create duplicate handlers.
local token = { initializing = true }
local pending = env.__HEAVENLY_AXIS_V3
if reuse(pending) then return pending end
if type(pending) == "table" and pending.initializing then
    warn("Heavenly Axis: initialization already in progress.")
    return pending
end
env.__HEAVENLY_AXIS_V3 = token
local ok, app = pcall(App.new, env, services, playerGui, options)
if not ok then
    if token.partial then pcall(function() token.partial:Destroy() end) end
    if env.__HEAVENLY_AXIS_V3 == token then env.__HEAVENLY_AXIS_V3 = nil end
    warn("Heavenly Axis: initialization failed: " .. tostring(app))
    return nil
end
env.__HEAVENLY_AXIS_V3 = app
return app
