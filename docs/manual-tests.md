# 实机测试清单

## 前置

- 烧录最新 `out/<date>-<commit>/sysupgrade.img.gz` 到 microSD
- 准备：
  - 上级路由（用于 bypass 模式测试）
  - 一台测试 PC（直连 R2S）
  - PPPoE 测试账号（用于 pppoe 模式）
  - 串口 / SSH 客户端

## 1. 启动与默认模式

- [ ] R2S 上电，金属壳风扇短暂全速 → 数秒内 PID 接管平滑下降
- [ ] PC 网线接 R2S 任一网口（默认 switch-equal，两口等效）
- [ ] PC 自动取得 192.168.2.x IP
- [ ] 浏览器访问 `http://192.168.2.1`，提示设置 root 密码
- [ ] 设密码后能进 LuCI 主页

## 2. switch-equal（默认）

- [ ] 同时连两台 PC 各到一个网口，分别取得 192.168.2.x
- [ ] PC1 ping PC2 通
- [ ] `cat /etc/config/mode-switch` 显示 `current.name='switch-equal'`

## 3. pppoe-main

- [ ] LuCI `Mode Switch → PPPoE` tab，填测试账号 + 保存
- [ ] LuCI `Mode Switch → Status`，点 "PPPoE 主路由"
- [ ] 等待 ~30 秒，`ifstatus wan | jq .ipv4-address` 取得运营商 IP
- [ ] LAN 客户端能上网，DNS 解析正常
- [ ] `iptables -t nat -nvL | grep MASQUERADE` 看到规则

## 4. bypass-gateway

- [ ] LuCI `Mode Switch → Bypass` tab，填上级网关 IP / 掩码 / DNS / 本机 IP
- [ ] 切换到 bypass
- [ ] 上级路由内手动改一台 PC 网关到 R2S 旁路 IP
- [ ] PC 仍能上网；`traceroute 8.8.8.8` 第一跳显示 R2S
- [ ] Passwall2 启用一个简单代理；测试国外访问走代理

## 5. 模式切换无残留

- [ ] 从 pppoe → switch → bypass → switch 来回各一次
- [ ] 每次切换后 `ip a` 和 `cat /etc/config/network` 内容与 profile 一致
- [ ] 没有遗留的 `pppoe-wan` 接口或 br-lan 残留
- [ ] `find /etc -maxdepth 1 -name 'config.bak.*' -type d` 累计备份按时间排序

## 6. PID 风扇

- [ ] 启动 `stress-ng --cpu 4 --timeout 5m`
- [ ] 5 分钟内温度收敛在 setpoint (55°C) ±5°C
- [ ] `tail -f /var/run/fan-pid.state` 看到 pwm 平滑变化（不抖动）
- [ ] LuCI `系统 → Fan PID` 改 setpoint=60，保存后 5 秒内 pwm 下降

## 7. 异常恢复

- [ ] 故意填一个不存在的 PPPoE 账号 + 切换 → 5 秒回滚到原模式
- [ ] `tail /var/log/mode-switch.log` 看到 rollback 记录
- [ ] 删除 `/sys/class/thermal/thermal_zone0/temp`（用 mount --bind 一个空文件） → 风扇切到全速；放开后恢复
