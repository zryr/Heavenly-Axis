-- The shipped script must reuse its singleton without global module loading or game access.
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local externalRequire, initialGame, initialGetgenv = require, game, getgenv
local opened, safed = 0, 0
local singleton = { alive = true }
function singleton:Open() opened = opened + 1 end
function singleton:SafeMode() safed = safed + 1 end
local env = { __HEAVENLY_AXIS_V3 = singleton }
getgenv = function() return env end
require = function() error("release must not call global require") end
game = setmetatable({}, { __index = function() error("duplicate release must not call Roblox APIs") end })
local release = assert(loadfile("dist/HeavenlyAxis.lua"))
check(release() == singleton and opened == 1, "self-contained release loads private modules and reopens existing singleton")
env.HeavenlyAxisOptions = { LoaderOnly = true }
check(release() == singleton and opened == 1, "self-contained loader run reuses singleton without UI creation")
env.HeavenlyAxisOptions = { SafeMode = true }
check(release() == singleton and safed == 1, "self-contained Safe Mode run delegates to singleton")
local source = assert(loadfile("Source"))
env.HeavenlyAxisOptions = nil
check(source() == singleton and opened == 2, "legacy Source entry is also self-contained and duplicate-safe")
require, game, getgenv = externalRequire, initialGame, initialGetgenv
return checks
