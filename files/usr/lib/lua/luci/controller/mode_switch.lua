module("luci.controller.mode_switch", package.seeall)

function index()
    if not nixio.fs.access("/etc/config/mode-switch") then
        return
    end

    local root = entry({"admin", "status", "mode_switch"},
                       alias("admin", "status", "mode_switch", "status"),
                       _("Mode Switch"), 90)
    root.dependent = false

    entry({"admin", "status", "mode_switch", "status"},
          template("mode_switch/status"), _("Status"), 10).leaf = true

    entry({"admin", "status", "mode_switch", "pppoe"},
          cbi("mode_switch/pppoe"), _("PPPoE"), 20).leaf = true

    entry({"admin", "status", "mode_switch", "bypass"},
          cbi("mode_switch/bypass"), _("Bypass"), 30).leaf = true

    entry({"admin", "status", "mode_switch", "do_switch"},
          call("action_switch")).leaf = true

    entry({"admin", "status", "mode_switch", "current"},
          call("action_current")).leaf = true

    entry({"admin", "status", "mode_switch", "log"},
          call("action_log")).leaf = true
end

local function exec(cmd)
    local p = io.popen(cmd .. " 2>&1; echo __EXIT__$?")
    local out = p:read("*a") or ""
    p:close()
    local code = tonumber(out:match("__EXIT__(%d+)") or "1") or 1
    out = out:gsub("__EXIT__%d+%s*$", "")
    return code, out
end

function action_switch()
    local http = require "luci.http"
    local mode = http.formvalue("mode") or ""
    if not (mode == "pppoe" or mode == "switch" or mode == "bypass") then
        http.status(400, "Bad Request")
        http.prepare_content("application/json")
        http.write_json({ ok = false, error = "invalid mode: " .. mode })
        return
    end
    local code, out = exec("/usr/bin/mode-switch " .. mode)
    http.prepare_content("application/json")
    http.write_json({ ok = (code == 0), code = code, output = out })
end

function action_current()
    local http = require "luci.http"
    local code, out = exec("/usr/bin/mode-switch status")
    http.prepare_content("application/json")
    http.write_json({ ok = (code == 0), output = out })
end

function action_log()
    local http = require "luci.http"
    local f = io.open("/var/log/mode-switch.log", "r")
    local content = ""
    if f then
        content = f:read("*a") or ""
        f:close()
    end
    local lines = {}
    for line in content:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    local start = math.max(1, #lines - 49)
    local tail = {}
    for i = start, #lines do tail[#tail+1] = lines[i] end
    http.prepare_content("text/plain")
    http.write(table.concat(tail, "\n"))
end
