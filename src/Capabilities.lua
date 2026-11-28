-- Heavenly Axis V3. Original project by Syshi; V2 inspired by Danechka.
-- Detect capabilities, never executor brands. Detection performs no file/network writes.
local Capabilities = {}

local function callable(value)
    return type(value) == "function"
end

local function result(available, detail)
    return {status = available and "Available but unverified" or "Unsupported", detail = detail}
end

function Capabilities.detect(env, services)
    env, services = env or {}, services or {}
    -- Session state stays shared, while executor APIs may live only in the
    -- script environment. Query curated capability names without enumerating it.
    local ambient = _G
    if type(getfenv) == "function" then
        local ok, current = pcall(getfenv, 0)
        if ok and type(current) == "table" then ambient = current end
    end
    local function pick(name)
        if callable(env[name]) then return env[name] end
        if callable(ambient[name]) then return ambient[name] end
    end
    local functions = {}
    for _, name in ipairs({"readfile", "writefile", "isfile", "delfile"}) do
        functions[name] = pick(name)
    end
    local fileAvailable = functions.readfile and functions.writefile and functions.isfile
    local capabilities = {
        storage = result(fileAvailable, fileAvailable and "Local file API found; Save verifies write/readback." or "Reliable local storage needs readfile, writefile and isfile; use JSON export."),
        clipboard = result(false, "Clipboard API unavailable; copy JSON from the export field."),
        network = result(false, "Optional update metadata retrieval unavailable."),
        input = result(false, "UserInputService unavailable."),
        _functions = functions,
    }
    local clipboard = pick("setclipboard") or pick("toclipboard")
    if callable(clipboard) then
        capabilities._clipboard = clipboard
        capabilities.clipboard = result(true, "Clipboard API found; success checked when copying.")
    end
    local request = pick("request") or pick("http_request")
    if not request then
        local http = type(env.http) == "table" and env.http or ambient.http
        if type(http) == "table" and callable(http.request) then request = http.request end
    end
    if callable(request) then
        capabilities._get = function(url)
            local response = request({Url = url, Method = "GET"})
            if type(response) ~= "table" or type(response.Body) ~= "string" then error("Invalid metadata response") end
            local code = tonumber(response.StatusCode)
            if not code or code < 200 or code >= 300 then error("Metadata request failed") end
            return response.Body
        end
    elseif pick("HttpGet") then
        capabilities._get = pick("HttpGet")
    else
        local runtimeGame = services.Game or env.game or game
        if runtimeGame then
            local ok, get = pcall(function() return runtimeGame.HttpGet end)
            if ok and callable(get) then capabilities._get = function(url) return get(runtimeGame, url) end end
        end
        if not capabilities._get and services.HttpService then
            local ok, get = pcall(function() return services.HttpService.GetAsync end)
            if ok and callable(get) then capabilities._get = function(url) return get(services.HttpService, url) end end
        end
    end
    if capabilities._get then
        capabilities.network = result(true, "Optional metadata API found; network access has not been verified.")
    end
    if services.UserInputService then
        local ok, touch, mouse, keyboard = pcall(function()
            local input = services.UserInputService
            return input.TouchEnabled == true, input.MouseEnabled == true, input.KeyboardEnabled == true
        end)
        if ok then
            capabilities.input = result(true, "Input API found; physical touch/mouse behavior requires device testing.")
            capabilities.input.touch, capabilities.input.mouse, capabilities.input.keyboard = touch, mouse, keyboard
        else
            capabilities.input = {status = "Failed", detail = "Input capability query failed."}
        end
    end
    return capabilities
end

return Capabilities
