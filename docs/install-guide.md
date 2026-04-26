# NanoPi R2S 定制 OpenWRT — 安装与使用手册

适用于本仓库 `utcdf/OpenWRT_R2S` 编译产出的 ImmortalWrt 定制固件。涵盖从下载、烧卡、首次配置到三种工作模式切换、风扇调优、常用插件、升级与排错。

---

## 1. 准备工作

### 1.1 硬件清单

| 件 | 说明 |
| --- | --- |
| NanoPi R2S | RK3328 / 1GB DDR4 / 板载千兆 + USB3 千兆 |
| microSD 卡 | ≥ 16 GB，建议 Class 10 / A1 三星或闪迪 |
| USB-C 电源 | 5V / ≥ 2A |
| 网线 | 至少 1 根超五类，PPPoE 模式需 2 根 |
| 烧卡机器 | macOS / Linux / Windows 任一 |

### 1.2 烧卡软件（任选其一）

| 操作系统 | 推荐工具 |
| --- | --- |
| macOS | 本仓库 `scripts/flash-sd.sh`（最安全） 或 [balenaEtcher](https://etcher.balena.io/) |
| Linux | `dd` 命令 或 balenaEtcher |
| Windows | [balenaEtcher](https://etcher.balena.io/)（最简单） / Rufus / Win32DiskImager |

---

## 2. 下载固件

### 2.1 从 GitHub Actions Artifact 下载（最新构建）

1. 浏览器打开 [https://github.com/utcdf/OpenWRT_R2S/actions](https://github.com/utcdf/OpenWRT_R2S/actions)
2. 点最近一个绿勾 ✓ 的 build 任务
3. 滚到页面底部 **Artifacts**
4. 下载 `nanopi-r2s-<commit-short>` 压缩包，解压

解压后得到：
- `immortalwrt-rockchip-armv8-friendlyarm_nanopi-r2s-squashfs-sysupgrade.img.gz`（**推荐**，约 61 MB，可 sysupgrade）
- `immortalwrt-rockchip-armv8-friendlyarm_nanopi-r2s-ext4-sysupgrade.img.gz`（约 78 MB，首刷更宽容、可调整分区大小）
- `*.sha256` — 单文件校验
- `sha256sums` — 多文件校验
- `*.manifest` — 完整内置软件包清单

### 2.2 从 GitHub Release 下载（带 tag 时）

如发布过版本：[https://github.com/utcdf/OpenWRT_R2S/releases](https://github.com/utcdf/OpenWRT_R2S/releases)。

### 2.3 校验镜像

下载后**强烈建议**校验 sha256，避免传输损坏：

| 系统 | 命令 |
| --- | --- |
| macOS / Linux | `shasum -a 256 immortalwrt-*.img.gz` |
| Windows PowerShell | `Get-FileHash -Algorithm SHA256 immortalwrt-*.img.gz` |

将输出对比文件旁的 `.sha256` 文件。不一致则重新下载。

---

## 3. 烧录 SD 卡

### 3.1 macOS：本仓库脚本（最安全）

```bash
cd /path/to/OpenWRT_R2S    # 仓库根目录
./scripts/flash-sd.sh --list                   # 1) 列出外置磁盘
./scripts/flash-sd.sh \                        # 2) 烧录
    --image ~/Downloads/immortalwrt-rockchip-armv8-friendlyarm_nanopi-r2s-squashfs-sysupgrade.img.gz \
    --target /dev/disk2
```

脚本安全机制：
- 拒绝内置磁盘（`Internal: Yes` 直接退出）
- 要求输入磁盘大小数字二次确认
- 要求输入 `yes` 最终确认
- 自动 sha256 校验（如有 `.sha256` 同名文件）
- 用 `/dev/rdisk*` 加速并 `eject` 收尾

### 3.2 balenaEtcher（图形化，全平台）

1. 安装并打开 [balenaEtcher](https://etcher.balena.io/)
2. **Flash from file** → 选 `.img.gz`（无需解压）
3. **Select target** → SD 卡（Etcher 默认隐藏内置硬盘）
4. **Flash!** → 等 3–5 分钟

### 3.3 Linux：dd 命令

```bash
gunzip -k immortalwrt-*.img.gz
lsblk                                          # 确认 SD 卡设备名（如 /dev/sdX、/dev/mmcblk0）
sudo dd if=immortalwrt-*.img of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

> ⚠️ **设备名写错可丢失硬盘数据**。用 `lsblk` 反复核对。

### 3.4 Windows：Rufus / Win32DiskImager

1. 先用 7-Zip 解压 `.img.gz` 得到 `.img`
2. 打开 Rufus → Device 选 SD 卡 → SELECT → 选 `.img` → START
3. 提示 ISOHybrid 选 **Write in DD Image mode**

---

## 4. 首次开机

### 4.1 接线

```
[电脑] ──网线── (USB 网口 eth1)  R2S  (板载网口 eth0) ──暂不接──
                                  │
                                  USB-C 电源
```

> 默认是「双口对等交换」模式，两个网口都是 LAN，**任一口插电脑即可**。但通常先用 USB 网口（eth1）连电脑。

### 4.2 上电与等待

1. SD 卡插入 R2S 底部卡槽
2. 通电（USB-C 5V）
3. 第一次开机 `uci-defaults` 脚本会跑一次（设主机名 / 时区 / NTP / 默认模式）
4. 风扇先全速吹 5–10 秒，PID 接管后稳定下来
5. 30–60 秒后服务全起

### 4.3 访问 LuCI

电脑会自动获取 `192.168.2.x` 的 IP。浏览器打开 `http://192.168.2.1`：

- 用户名：`root`
- 密码：**留空**（首次空密码）→ 登录

进入后立刻：**系统 → 管理权 → 路由器密码** 设置一个强密码。

### 4.4 默认参数速查

| 项 | 值 |
| --- | --- |
| 主机名 | `NanoPi-R2S` |
| LAN IP | 192.168.2.1 / 24 |
| LAN DHCP | 启用，100–249 |
| 时区 | Asia/Shanghai (CST-8) |
| NTP | ntp.aliyun.com / ntp1.aliyun.com / time.cloudflare.com |
| 默认模式 | `switch-equal`（双口对等） |
| LuCI 主题 | Argon |
| 默认语言 | 简体中文 |

---

## 5. 三种工作模式与切换

### 5.1 模式概览

| 模式 | eth0（板载） | eth1（USB） | 用途 |
| --- | --- | --- | --- |
| `switch-equal`（默认） | LAN（br-lan） | LAN（br-lan） | 局域网千兆交换机 + DHCP 服务 |
| `pppoe-main` | **WAN PPPoE 拨号** | LAN | 家庭主路由（光猫接 eth0） |
| `bypass-gateway` | LAN（静态 IP，挂上级） | 不启用 | 旁路由科学上网 / 广告过滤 |

切换在 LuCI 或 SSH 都可，**已切换后再换网线接法**。

### 5.2 通过 LuCI 切换

LuCI → **状态 → Mode Switch** 三个标签：

#### `Status` 标签
- 顶部徽章显示当前模式
- 三个按钮：双口对等交换 / PPPoE 主路由 / 旁路由网关
- 下方滚动日志（最近 50 行）

#### `PPPoE` 标签（切到 PPPoE 前先填）
| 字段 | 说明 |
| --- | --- |
| 用户名 | 运营商 PPPoE 账号 |
| 密码 | 运营商 PPPoE 密码 |
| MTU | 默认 1492，特殊运营商可能 1480 |
| 服务名 | 一般留空，少数运营商需填 |

**点保存**后再回 Status 切换才生效。

#### `Bypass` 标签（切到旁路由前先填）
| 字段 | 默认 | 说明 |
| --- | --- | --- |
| 本机 IP | 192.168.1.2 | 与上级路由 LAN 段同段，避开 DHCP 池 |
| 子网掩码 | 255.255.255.0 | |
| 上级网关 | 192.168.1.1 | 上级路由的 LAN IP |
| 上游 DNS | 192.168.1.1 | 一般同上级网关 |

### 5.3 切换流程内部做了什么

1. 备份当前 `/etc/config/{network,firewall,dhcp}` 到 `/etc/config.bak.<timestamp>/`
2. 复制目标 profile 的三个 UCI 文件到 `/etc/config/`
3. 注入动态参数（PPPoE 账号、旁路由 IP 等，从 `/etc/config/mode-switch` 读）
4. 重启 `network` / `firewall` / `dnsmasq`
5. **5 秒载波检查**：目标接口起不来即自动回滚到上一模式
6. 写日志到 `/var/log/mode-switch.log`

> 切换期间网络可能短暂中断 5–15 秒。

### 5.4 SSH 命令行切换

```bash
ssh root@192.168.2.1
mode-switch status              # 看当前模式 + 最近日志
mode-switch switch              # 切到双口对等
mode-switch pppoe               # 切到 PPPoE 主路由（需先在 LuCI 填账号）
mode-switch bypass              # 切到旁路由
tail -f /var/log/mode-switch.log    # 实时观察日志
```

### 5.5 各模式接线建议

#### 双口对等
```
[设备 A] ── eth0 (板载)
[设备 B] ── eth1 (USB)
```
任一口连电脑都行，两口互通。

#### PPPoE 主路由
```
[光猫] ────── eth0 (板载, WAN PPPoE)
[交换机/PC] ── eth1 (USB, LAN)
```
切换前先填账号；切换后会自动开始拨号；如果光猫已是路由模式，请先把光猫改桥接。

#### 旁路由
```
[上级路由 LAN] ── eth0 (板载, 静态 IP 192.168.1.2)
                                  ↑
                                  R2S 单臂
```
eth1 不接。上级路由内的客户端把网关手动改为 R2S 的 IP（192.168.1.2）即可走透明代理。

---

## 6. PID 风扇控制

LuCI → **系统 → Fan PID**。

| 字段 | 默认 | 含义 |
| --- | --- | --- |
| 启用 | ✓ | 关闭后风扇停（不推荐） |
| 目标温度 | 55°C | PID setpoint，越低风扇越响 |
| Kp | 4.0 | 比例项，越大反应越激进 |
| Ki | 0.2 | 积分项，消除稳态偏差 |
| Kd | 1.0 | 微分项，抑制超调 |
| 采样间隔 | 5 s | 5–10 s 平衡响应与噪音 |
| PWM min / max | 0 / 255 | 安静办公可设 30 / 220 |
| PWM 设备路径 | `/sys/class/pwm/pwmchip0/pwm0` | 不要改 |
| 温度文件路径 | `/sys/class/thermal/thermal_zone0/temp` | 不要改 |

保存后自动 `reload`，无需重启。

实时状态：

```bash
ssh root@192.168.2.1
cat /var/run/fan-pid.state
# temp_c=52
# pwm=78
# err=-3.000000
# integ=12.500000
# ts=2026-04-26 14:23:11
```

降级保护：温度文件读不到 → 强制 PWM 拉满；PWM 写不到 → 日志限流但继续重试，**绝不**自动停风扇。

---

## 7. 常用插件配置

### 7.1 Passwall2（透明代理 / 科学上网）

LuCI → **服务 → Passwall2**

1. **节点列表** → 添加节点
   - 手动添加：选协议（VLESS / VMess / Trojan / Shadowsocks / Hysteria 等）→ 填地址端口密码
   - 订阅：节点订阅 → 添加订阅链接 → 手动更新订阅
2. **基本设置**
   - 主节点：选刚加的节点
   - 模式：`分流模式`（推荐，自动判断 GFW List）/ `黑名单模式` / `白名单模式` / `全局模式`
   - 内核：`xray-core`（默认）/ `sing-box` / `hysteria`，按节点协议匹配
3. 顶部 **启用主开关** → 保存应用
4. **节点订阅** 标签可以批量订阅

> 主路由模式 + Passwall2 = 全家自动科学上网；旁路由模式 + Passwall2 = 单设备改网关切换。

### 7.2 SmartDNS（DNS 优化）

LuCI → **服务 → SmartDNS**

默认监听 `6053`。要让 dnsmasq 把 LAN 客户端的 DNS 请求转给 SmartDNS：

- **常规设置** → 启用 → 作为 dnsmasq 的上游服务器 ✓
- **上游服务器** → 添加几组国内 DoH（阿里、DNSPod）+ 几组国外 DoH（Cloudflare、Google）→ 用 `分组` 区分
- **第二 DNS 服务器** 可启用专用 IPv6 优化

### 7.3 Tailscale（远程访问）

LuCI → **服务 → Tailscale**

```bash
ssh root@192.168.2.1
tailscale up --advertise-routes=192.168.2.0/24 --accept-routes
# 浏览器打开输出的 URL，登录 Tailscale 账号绑定
```

到 Tailscale Admin Console → Machines → R2S → 启用 **Subnet routes** → 勾 192.168.2.0/24。

之后在外网用任意 Tailscale 客户端即可访问 192.168.2.x 内网设备（NAS、相机等）。

### 7.4 SQM（QoS 限速整流）

LuCI → **网络 → SQM QoS**

适合上传带宽吃紧（ADSL / 上传上限）场景。填上下行带宽（kbps），开启 cake 算法即可。

---

## 8. 升级固件

### 8.1 在线 sysupgrade（保留配置，推荐）

```bash
ssh root@192.168.2.1
cd /tmp
wget https://github.com/utcdf/OpenWRT_R2S/releases/download/v0.x.x/immortalwrt-rockchip-armv8-friendlyarm_nanopi-r2s-squashfs-sysupgrade.img.gz
sysupgrade -v /tmp/immortalwrt-*.img.gz   # 默认保留 /etc/config 等
```

或 LuCI：**系统 → 备份/升级 → 上传镜像 → 安装** → 等约 2 分钟自动重启。

### 8.2 不保留配置升级

```bash
sysupgrade -n /tmp/immortalwrt-*.img.gz
```

### 8.3 重新烧卡（最干净，所有数据丢失）

按第 3 节重新写卡。**烧卡前**先做配置备份（见 §9）。

---

## 9. 备份与恢复配置

### 9.1 备份

```bash
ssh root@192.168.2.1 'sysupgrade -b -' > r2s-config-$(date +%Y%m%d).tar.gz
```

或 LuCI：**系统 → 备份/升级 → 生成备份**。

### 9.2 恢复

```bash
scp r2s-config-20260426.tar.gz root@192.168.2.1:/tmp/
ssh root@192.168.2.1 'sysupgrade -r /tmp/r2s-config-20260426.tar.gz && reboot'
```

或 LuCI：**系统 → 备份/升级 → 上传备份**。

### 9.3 备份内容范围

默认 sysupgrade 备份的是 `/etc/sysupgrade.conf` 列出的路径。可在 LuCI 备份/升级页面看「保留文件列表」并自定义追加（如证书、定制脚本）。

---

## 10. 常见问题排查

| 现象 | 排查步骤 |
| --- | --- |
| 上电后电脑取不到 IP | ① 网线接的是不是 USB RJ45（eth1）；② R2S 三个 LED 是否亮；③ 等待 60 秒看是否还没起 |
| 浏览器打不开 192.168.2.1 | ① 电脑 IP 是不是 192.168.2.x；② `ping 192.168.2.1`；③ 关闭 VPN / 代理 |
| 切 PPPoE 后掉线 5 秒回滚 | ① 检查账号密码；② `logread \| grep -i pppoe` 看错误；③ 是否需要把光猫改桥接 |
| 切到 PPPoE 后能拨号但无法上网 | ① `ping 8.8.8.8` 看 IP 层；② 检查 DNS：`cat /tmp/resolv.conf.auto`；③ MTU 试 1480 |
| 风扇全速不停 | `cat /var/run/fan-pid.state` 看 temp_c；如为空说明温度读取失败，检查 `/sys/class/thermal/thermal_zone0/temp` 是否存在 |
| Passwall2 节点不通 | ① ping 节点 IP；② tcpdump 看是否到达节点；③ 切换内核（xray ↔ sing-box ↔ hysteria）；④ 看节点是否过期 |
| Tailscale 无法连接 | `tailscale status`；防火墙 LAN→LAN 必须 ACCEPT；上级路由可能 NAT 类型严格，启用 DERP relay |
| LuCI 速度慢/打不开 | ① 重启 uhttpd：`/etc/init.d/uhttpd restart`；② 看 dmesg 是否 OOM |
| 忘记 root 密码 | 唯一办法：重新烧卡；下次记得做配置备份 |
| 模式切换后 LuCI 显示模式不对 | 系统 → 管理权 → 重启路由器；或 `/etc/init.d/rpcd restart` |

---

## 11. 实用命令速查（SSH 后）

| 目标 | 命令 |
| --- | --- |
| 当前模式 | `mode-switch status` |
| 模式切换日志 | `tail -f /var/log/mode-switch.log` |
| 系统日志 | `logread -f` |
| WAN 状态 | `ifstatus wan \| jq .` |
| 重启网络 | `/etc/init.d/network restart && /etc/init.d/firewall restart && /etc/init.d/dnsmasq restart` |
| 风扇状态 | `cat /var/run/fan-pid.state` |
| CPU 温度 | `awk '{printf "%.1f°C\n", $1/1000}' /sys/class/thermal/thermal_zone0/temp` |
| 内存使用 | `free -m` |
| 磁盘使用 | `df -h` |
| Passwall2 状态 | LuCI 服务 → Passwall2 主页 |
| 软件包列表 | `cat /usr/lib/opkg/info/*.control 2>/dev/null \| grep '^Package:'` 或 LuCI → 系统 → 软件包 |
| 重启 | `reboot` |
| 关机 | `poweroff`（仍需手动断电） |

---

## 12. 项目相关链接

- 仓库主页：[https://github.com/utcdf/OpenWRT_R2S](https://github.com/utcdf/OpenWRT_R2S)
- CI 构建历史：[https://github.com/utcdf/OpenWRT_R2S/actions](https://github.com/utcdf/OpenWRT_R2S/actions)
- 设计 spec：[`docs/superpowers/specs/2026-04-25-nanopi-r2s-openwrt-design.md`](superpowers/specs/2026-04-25-nanopi-r2s-openwrt-design.md)
- 实施 plan：[`docs/superpowers/plans/2026-04-25-nanopi-r2s-openwrt-implementation.md`](superpowers/plans/2026-04-25-nanopi-r2s-openwrt-implementation.md)
- 实机测试清单：[`docs/manual-tests.md`](manual-tests.md)
- ImmortalWrt 上游：[https://github.com/immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt)
- Passwall2 上游：[https://github.com/Openwrt-Passwall/openwrt-passwall2](https://github.com/Openwrt-Passwall/openwrt-passwall2)
- NanoPi R2S 硬件：[https://www.friendlyelec.com/index.php?route=product/product&product_id=282](https://www.friendlyelec.com/index.php?route=product/product&product_id=282)
