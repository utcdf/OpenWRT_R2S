module("luci.controller.fan_pid", package.seeall)

function index()
    if not nixio.fs.access("/etc/config/fan") then
        return
    end
    entry({"admin", "system", "fan_pid"},
          cbi("fan_pid/main"), _("Fan PID"), 80).leaf = true
    entry({"admin", "system", "fan_pid", "state"},
          call("action_state")).leaf = true
end

function action_state()
    local http = require "luci.http"
    local f = io.open("/var/run/fan-pid.state", "r")
    local kv = {}
    if f then
        for line in f:lines() do
            local k, v = line:match("^(%w+)=(.*)$")
            if k then kv[k] = v end
        end
        f:close()
    end
    http.prepare_content("application/json")
    http.write_json(kv)
end
