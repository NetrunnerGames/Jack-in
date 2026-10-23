-- DataJackUI injector stub.
-- The real backend is the DataJackUI desktop app (HTTP on 127.0.0.1:6767). This lua
-- backend has two jobs:
--   1. Put datajackui.js onto the Steam store webkit context (copy into steamui/webkit +
--      Millennium.add_browser_js) — delivery is backend-only in Millennium.
--   2. Be the RPC bridge between the injected page and the app. datajackui.js calls
--      window.Millennium.callServerMethod("datajackui", "<Name>", args).

local millennium  = require("millennium")
local fs          = require("fs")
local m_utils     = require("utils")
local logger      = require("plugin_logger")
local paths       = require("paths")
local steam_utils = require("steam_utils")
local http        = require("http")
local cjson       = require("json")

-- ── App backend bridge (127.0.0.1:6767) ────────────────────────────────────────

local BACKEND_BASE = "http://127.0.0.1:6767"

local function backend_request(method, path, body)
    local opts = { method = method, timeout = 15 }
    if body then
        opts.data = cjson.encode(body)
        opts.headers = { ["Content-Type"] = "application/json" }
    end
    local response, err = http.request(BACKEND_BASE .. path, opts)
    if not response then
        return cjson.encode({ success = false, error = tostring(err or "request failed") })
    end
    return response.body
end

-- ── Ensure the app is running ──────────────────────────────────────────────────

local function ensure_backend_running()
    local response = http.get(BACKEND_BASE .. "/has/0", { timeout = 2 })
    if response then return end -- already up

    local local_appdata = m_utils.getenv("LOCALAPPDATA")
    if not local_appdata or local_appdata == "" then
        logger.warn("LOCALAPPDATA not available, cannot launch DataJackUI backend")
        return
    end

    local exe_path = local_appdata .. "\\DataJackUIGui\\DataJackUI.exe"
    if not fs.exists(exe_path) then
        exe_path = local_appdata .. "\\DataJackUI\\current\\DataJackUI.exe"
    end

    if not fs.exists(exe_path) then
        logger.warn("DataJackUI.exe not found at " .. exe_path)
        return
    end

    m_utils.exec('start "" "' .. exe_path .. '" --minimized')
    logger.log("Launched DataJackUI backend: " .. exe_path)
end

-- ── RPC handlers (must be GLOBAL functions — Millennium looks these up by name) ─

function HasDataJackUIForApp(appid)
    return backend_request("GET", "/has/" .. tostring(appid))
end

function DeleteDataJackUIForApp(appid)
    return backend_request("POST", "/remove/" .. tostring(appid))
end

function CheckApisForApp(appid)
    return backend_request("POST", "/check-sources/" .. tostring(appid))
end

function StartAddViaDataJackUIFromUrl(appid, source)
    return backend_request("POST", "/download/" .. tostring(appid), { source = source })
end

function GetDataJackUIAddStatus(appid)
    return backend_request("GET", "/download-status/" .. tostring(appid))
end

function CancelAddViaDataJackUI(appid)
    return backend_request("POST", "/cancel/" .. tostring(appid))
end

-- ── IceBreaker IPC Named Pipe Bridge (\\.\pipe\IceBreaker_IPC) ────────────────

local function ipc_send(command)
    local pipe = io.open([[\.\pipe\IceBreaker_IPC]], "r+")
    if not pipe then return nil end
    pipe:write(command .. "\n")
    pipe:flush()
    local res = pipe:read("*l")
    pipe:close()
    return res
end

function HotReload()
    -- 1. Try DataJackUI desktop app first
    local res = backend_request("POST", "/hot-reload")
    if res then
        local ok, decoded = pcall(cjson.decode, res)
        if ok and decoded and decoded.success then
            return res
        end
    end

    -- 2. Direct fallback to IceBreaker IPC Named Pipe in Steam
    local ipc_res = ipc_send("RELOAD")
    if ipc_res and ipc_res:find("^OK") then
        logger.log("Hot-reloaded manifests via direct IceBreaker IPC pipe")
        return cjson.encode({ success = true, hotReloaded = true, source = "icebreaker_ipc" })
    end

    return cjson.encode({ success = false, error = "IPC unavailable" })
end

function RestartSteam()
    -- Try hot-reloading manifests without killing Steam first!
    local hr = HotReload()
    local ok, decoded = pcall(cjson.decode, hr)
    if ok and decoded and decoded.success and decoded.hotReloaded then
        logger.log("RestartSteam intercepted: performed zero-restart hot reload via IPC")
        return hr
    end

    return backend_request("POST", "/restart-steam")
end

function StartDataJackUIAdd(appid)
    return backend_request("POST", "/add/" .. tostring(appid))
end

function PickDataJackUIAddSource(appid, source)
    return backend_request("POST", "/add-source/" .. tostring(appid), { source = source })
end

function OpenSettings()
    return backend_request("POST", "/open/settings")
end

function OpenFix(appid)
    return backend_request("POST", "/open/fix/" .. tostring(appid))
end

function ReadLoadedApps()
    return backend_request("GET", "/loaded-apps")
end

function DismissLoadedApps()
    return backend_request("POST", "/loaded-apps")
end


-- ── Webkit file management ───────────────────────────────────────────────────

local function copy_webkit_files()
    local steam_dir = steam_utils.detect_steam_install_path()
    if not steam_dir or steam_dir == "" then return end

    local target_webkit_dir = fs.join(steam_dir, "steamui", "webkit")
    if not fs.exists(target_webkit_dir) then
        fs.create_directories(target_webkit_dir)
    end

    local public_dir = fs.join(paths.get_plugin_dir(), "public")

    local src_js = fs.join(public_dir, "datajackui.js")
    local dst_js = fs.join(target_webkit_dir, "datajackui.js")
    if fs.exists(src_js) then
        local content = m_utils.read_file(src_js)
        if content then m_utils.write_file(dst_js, content) end
    end

    local src_css = fs.join(public_dir, "steamdb-webkit.css")
    local dst_css = fs.join(target_webkit_dir, "steamdb-webkit.css")
    if fs.exists(src_css) then
        local content = m_utils.read_file(src_css)
        if content then m_utils.write_file(dst_css, content) end
    end
end

local function inject_webkit_files()
    millennium.add_browser_css("webkit/steamdb-webkit.css")
    millennium.add_browser_js("webkit/datajackui.js")
end

-- ── Lifecycle ────────────────────────────────────────────────────────────────

local function on_load()
    logger.log("DataJackUI injector stub loading (millennium " .. tostring(millennium.version()) .. ")")
    ensure_backend_running()
    copy_webkit_files()
    inject_webkit_files()
    millennium.ready()
end

local function on_unload()
    logger.log("DataJackUI injector stub unloading")
end

local function on_frontend_loaded()
    copy_webkit_files()
end

return {
    on_load            = on_load,
    on_unload          = on_unload,
    on_frontend_loaded = on_frontend_loaded,
}
