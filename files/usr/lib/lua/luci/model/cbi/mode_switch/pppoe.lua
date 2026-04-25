local m = Map("mode-switch", translate("PPPoE 配置"),
    translate("拨号账号；保存后切到 PPPoE 模式生效。"))

local s = m:section(NamedSection, "pppoe", "pppoe", "")
s.anonymous = true
s.addremove = false

local user = s:option(Value, "username", translate("用户名"))
user.rmempty = true

local pass = s:option(Value, "password", translate("密码"))
pass.password = true
pass.rmempty = true

local mtu = s:option(Value, "mtu", translate("MTU"))
mtu.datatype = "uinteger"
mtu.default = "1492"

local svc = s:option(Value, "service", translate("服务名（可空）"))
svc.rmempty = true

return m
