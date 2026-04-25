local m = Map("mode-switch", translate("旁路由配置"),
    translate("作为旁路由时本机的 IP 与上级网关；保存后切到 bypass 模式生效。"))

local s = m:section(NamedSection, "bypass", "bypass", "")
s.anonymous = true
s.addremove = false

local ip = s:option(Value, "ipaddr", translate("本机 IP"))
ip.datatype = "ip4addr"
ip.default = "192.168.1.2"

local mask = s:option(Value, "netmask", translate("子网掩码"))
mask.datatype = "ip4addr"
mask.default = "255.255.255.0"

local gw = s:option(Value, "gateway", translate("上级网关"))
gw.datatype = "ip4addr"
gw.default = "192.168.1.1"

local dns = s:option(Value, "dns", translate("上游 DNS"))
dns.datatype = "ip4addr"
dns.default = "192.168.1.1"

return m
