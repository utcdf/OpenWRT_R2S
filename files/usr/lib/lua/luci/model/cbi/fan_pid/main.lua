local m = Map("fan", translate("Fan PID"),
    translate("基于 thermal_zone0 的 PID 风扇控制；保存后自动 reload。"))

local s = m:section(NamedSection, "pid", "fan", "")
s.anonymous = true
s.addremove = false

s:option(Flag, "enabled", translate("启用"))

local sp = s:option(Value, "setpoint", translate("目标温度 (°C)"))
sp.datatype = "uinteger"
sp.default = "55"

local kp = s:option(Value, "kp", translate("Kp"))
kp.default = "4.0"
local ki = s:option(Value, "ki", translate("Ki"))
ki.default = "0.2"
local kd = s:option(Value, "kd", translate("Kd"))
kd.default = "1.0"

local interval = s:option(Value, "interval", translate("采样间隔 (s)"))
interval.datatype = "uinteger"
interval.default = "5"

local pmin = s:option(Value, "pwm_min", translate("PWM min"))
pmin.datatype = "uinteger"
pmin.default = "0"

local pmax = s:option(Value, "pwm_max", translate("PWM max"))
pmax.datatype = "uinteger"
pmax.default = "255"

s:option(Value, "pwm_path", translate("PWM 设备路径")).default = "/sys/class/pwm/pwmchip0/pwm0"
s:option(Value, "thermal_path", translate("温度文件路径")).default = "/sys/class/thermal/thermal_zone0/temp"

function m.on_after_commit(self)
    luci.sys.exec("/etc/init.d/fan-pid reload >/dev/null 2>&1 &")
end

return m
