# NanoPi R2S 多模式定制 OpenWRT 设计

- 日期：2026-04-25
- 硬件参考：FriendlyElec NanoPi R2S（RK3328 / 1GB DDR4 / GMAC + USB3 RTL8153B）
- 源码基线：ImmortalWrt master（编译时锁定具体 commit）

## 1. 目标

在 NanoPi R2S 上构建一份**单镜像、可在线切换**的定制 OpenWRT 固件，覆盖三种工作场景：

1. **PPPoE 主路由**：WAN 拨号、LAN 局域网、NAT/防火墙/DHCP 全套
2. **双口对等交换**：`eth0`、`eth1` 桥接为 `br-lan`，同段 DHCP，互通
3. **旁路由透明网关**：单臂模式，挂在上级路由下，提供透明代理与 DNS 服务

切换通过 LuCI Web 界面完成，无需重刷固件。

## 2. 硬件与资源

| 项 | 值 |
| --- | --- |
| SoC | Rockchip RK3328（4×Cortex-A53 @ 1.3 GHz，aarch64） |
| 内存 | 1 GB DDR4 |
| 网口 1（`eth0`） | 板载 RK GMAC，1 Gbps |
| 网口 2（`eth1`） | USB3.0 RTL8153B，1 Gbps |
| 存储 | microSD ≥ 16 GB（建议 A1 / Class 10） |
| 散热 | 配套金属外壳 + 小型 5V 风扇（PWM 通过 GPIO 控制） |

**网口约定**（沿用 ImmortalWrt R2S 默认）：`eth0` = WAN，`eth1` = LAN。

## 3. 软件栈

### 3.1 源码与目标

- 源码：ImmortalWrt master，编译时记录并锁定 commit hash 至 `build/IMMORTALWRT_COMMIT`
- Target：`rockchip/armv8`
- Profile：`friendlyarm_nanopi-r2s`
- 内核：跟随 ImmortalWrt 当前 master（5.15 或 6.6 视当时分支）

### 3.2 内置软件包清单

| 类别 | 包 |
| --- | --- |
| 透明代理 | `luci-app-passwall2`、`xray-core`、`sing-box`、`hysteria` |
| DNS | `smartdns`、`luci-app-smartdns` |
| VPN | `wireguard-tools`、`luci-app-wireguard`、`tailscale`、`luci-app-tailscale` |
| 工具 | `luci-app-ttyd`、`luci-app-sqm`、`htop`、`curl`、`nano`、`bash` |
| 驱动 | `kmod-usb-net-rtl8152`（USB 千兆网卡）、`kmod-pwm-rockchip` |
| UI | `luci-theme-argon`、`luci-i18n-base-zh-cn` 及各应用 zh-cn 语言包 |
| 自研 | mode-switch（LuCI 应用）、fan-pid（init 脚本 + UCI 配置） |

### 3.3 多模式 Profile 架构

```
/etc/profiles/
├── pppoe-main/
│   ├── network
│   ├── firewall
│   └── dhcp
├── switch-equal/
│   ├── network
│   ├── firewall
│   └── dhcp
└── bypass-gateway/
    ├── network
    ├── firewall
    └── dhcp
```

每个 profile 是 UCI 片段（不是完整 `/etc/config/` 替换，是与默认合并），切换时仅写 network / firewall / dhcp 三个文件。

#### 3.3.1 profile 概览

**pppoe-main**
- WAN（`eth0`）：proto=pppoe，账号/密码从 `/etc/config/mode-switch` 读取
- LAN（`eth1`）：static，192.168.2.1/24，DHCP 启用
- 防火墙：默认 `wan` zone masquerade

**switch-equal**（默认初始模式）
- `br-lan`：bridge ports = `eth0 eth1`
- LAN：static，192.168.2.1/24，DHCP 启用
- WAN zone：禁用
- 防火墙：仅 LAN zone，`input=ACCEPT, output=ACCEPT, forward=ACCEPT`

**bypass-gateway**
- LAN（`eth0`）：static，IP 与上级网段同段（默认 192.168.1.2/24，从 `/etc/config/mode-switch` 读取）
- WAN：禁用
- DHCP：`option ignore '1'`（不分配 IP）
- 网关 / DNS：指向上级（默认 192.168.1.1）
- 防火墙：`forwarding lan -> lan`，`zone lan` 加 `masq '1'`（透明代理需要）

### 3.4 mode-switch 组件

**前端（LuCI）**：`luci-app-mode-switch`

- 自定义页面位于 `状态 → Mode Switch`
- 三个 tab：当前模式 / PPPoE 配置 / 旁路由配置
- 当前模式 tab：
  - 显示当前激活模式（徽章）
  - 三个切换按钮（PPPoE 主路由 / 双口对等 / 旁路由）
  - 显示最近一次切换日志（`/var/log/mode-switch.log` 末 50 行）
- PPPoE 配置 tab：账号、密码、MTU（默认 1492）、服务名（可空）
- 旁路由配置 tab：本机 IP、子网掩码、上级网关、上游 DNS

所有配置写入 UCI：`/etc/config/mode-switch`。

```
config mode 'current'
    option name 'switch-equal'

config pppoe 'pppoe'
    option username ''
    option password ''
    option mtu '1492'
    option service ''

config bypass 'bypass'
    option ipaddr '192.168.1.2'
    option netmask '255.255.255.0'
    option gateway '192.168.1.1'
    option dns '192.168.1.1'
```

**后端（shell）**：`/usr/bin/mode-switch`

- 用法：`mode-switch [pppoe|switch|bypass]`（也可 `mode-switch status`）
- 步骤：
  1. 校验参数
  2. 备份 `/etc/config/{network,firewall,dhcp}` 至 `/etc/config.bak.<timestamp>/`
  3. 把对应 profile 复制到 `/etc/config/`
  4. 从 `/etc/config/mode-switch` 读取动态参数（PPPoE 账号、旁路由 IP 等）通过 `uci set` 注入
  5. `uci commit && /etc/init.d/network restart && /etc/init.d/firewall restart && /etc/init.d/dnsmasq restart`
  6. 写 `current` 模式至 `/etc/config/mode-switch`
  7. 5 秒内未拿到任何 carrier 则自动回滚到上一备份并报警
  8. 全程日志至 `/var/log/mode-switch.log`

LuCI 页面通过 `luci.sys.exec("/usr/bin/mode-switch <name>")` 调用后端，失败信息回显到页面。

### 3.5 PID 风扇控制

**硬件假设**：风扇 PWM 走 GPIO（具体引脚以 ImmortalWrt R2S DTS 为准，目前常见为 `pwm0`）。
**温度源**：`/sys/class/thermal/thermal_zone0/temp`。

**配置**（`/etc/config/fan`）：

```
config fan 'pid'
    option enabled '1'
    option setpoint '55'      # 目标温度（°C）
    option kp '4.0'
    option ki '0.2'
    option kd '1.0'
    option interval '5'       # 采样间隔（秒）
    option pwm_min '0'
    option pwm_max '255'
    option pwm_path '/sys/class/pwm/pwmchip0/pwm0'
```

**实现**（`/etc/init.d/fan-pid` + 后台脚本）：

- procd 启动一个常驻 shell（或编译期决定换 C，先 shell 起步）
- 主循环：
  - 读温度（millidegree → °C）
  - PID 计算：`error = T_now - setpoint; integ += error * dt; deriv = (error - prev_error) / dt; out = Kp*error + Ki*integ + Kd*deriv`
  - 输出夹紧到 `[pwm_min, pwm_max]`，写入 `pwm_path/duty_cycle`
  - 积分抗饱和：当输出夹紧时不累加 integ
  - 写入 `/var/run/fan-pid.state`（当前温度、PWM 值）便于 LuCI 显示
- 关停时把 PWM 设为 max（保险），并 disable

**LuCI 页面**：`系统 → Fan PID` 显示当前温度/PWM、可调四个参数、保存即热加载。

### 3.6 首次开机初始化（uci-defaults/99-r2s-init）

OpenWRT 的 `uci-defaults` 机制：脚本在第一次开机时执行，成功后自我删除。`99-r2s-init` 负责：

1. 写入主机名、时区、NTP 服务器
2. 把默认 LAN 段改成 192.168.2.0/24（覆盖发行版默认）
3. 把 `/etc/profiles/switch-equal/{network,firewall,dhcp}` 复制到 `/etc/config/`，设默认初始模式
4. 在 `/etc/config/mode-switch` 写入 `current=switch-equal`
5. 启用并启动 `fan-pid` 服务
6. 不预设 root 密码（保留空，触发 LuCI 强制改密）

### 3.7 默认网络参数

| 项 | 值 |
| --- | --- |
| 默认初始模式 | `switch-equal`（双口对等交换） |
| LAN 网段 | 192.168.2.0/24 |
| LAN IP | 192.168.2.1 |
| 主机名 | `NanoPi-R2S` |
| 时区 | `Asia/Shanghai`（CST-8） |
| NTP | `ntp.aliyun.com`、`ntp1.aliyun.com`、`time.cloudflare.com` |
| root 密码 | 不预设；首次访问 LuCI 强制设置 |

## 4. 编译流程

### 4.1 主机环境

- 主机 OS：macOS（Apple Silicon 或 Intel）
- 编译宿主：Docker 容器
- 镜像：自建 Dockerfile，基于 `debian:bookworm-slim` + ImmortalWrt 编译依赖（`build-essential gawk gcc-multilib flex git gettext libncurses-dev libssl-dev python3 unzip zlib1g-dev file wget rsync`）
- apt 源：默认切到 `mirrors.tuna.tsinghua.edu.cn`，可通过 build-arg 切换
- 容器内非 root 用户编译（`builder` UID 1000）
- 平台：Apple Silicon 上原生跑 linux/arm64 容器；Intel macOS 上原生跑 linux/amd64 容器。两种平台都能从源码编译 ImmortalWrt（host arch 不影响 target，target 始终是 aarch64）。Apple Silicon 上若强制 linux/amd64 走 QEMU 模拟，编译会显著变慢，不推荐。

### 4.2 编译入口

```bash
./build/build.sh                    # 在容器外，自动起容器并执行内部 build
./build/build.sh --no-cache         # 强制重编
./build/build.sh --shell            # 进入容器交互调试
./build/build.sh --update-feeds     # 仅刷新 feeds
```

容器内步骤：

1. 若 `immortalwrt/` 不存在则 `git clone`，否则 `git fetch && git checkout <commit>`
2. `cp build/feeds.conf.default immortalwrt/feeds.conf.default`
3. `./scripts/feeds update -a && ./scripts/feeds install -a`
4. 把 `files/` 软链到 `immortalwrt/files/`
5. `cp build/.config.seed immortalwrt/.config && make defconfig`
6. `make download -j8`
7. `make -j$(nproc)`，失败重试一次 `make -j1 V=s` 收集详细日志
8. 产物拷贝到 `out/<date>-<commit>/`

### 4.3 配置种子

`build/.config.seed` 仅记录与 defconfig 的**差异**（diffconfig 思路），保持精简、便于审阅 PR。完整 `.config` 不进 git。

### 4.4 GitHub Actions CI

`.github/workflows/build.yml`：

- 触发：`push` 到 `main`、`workflow_dispatch`、tag `v*`
- runner：`ubuntu-latest`
- 步骤：
  1. checkout
  2. 释放磁盘（删 dotnet/android/swap，腾 ~30 GB）
  3. apt 装编译依赖
  4. clone ImmortalWrt（与本地相同 commit）
  5. 软链 `files/`、写入 `.config`、`make defconfig`
  6. `make download -j8`
  7. `make -j$(nproc) || make -j1 V=s`
  8. upload-artifact: `out/`
  9. tag 触发时附带 GitHub Release，附固件 sysupgrade.img.gz + sha256
- 缓存：`ccache` + `dl/` 目录用 actions/cache

## 5. 目录结构

```
OpenWRT_R2S/
├── README.md
├── docker/
│   ├── Dockerfile
│   └── compose.yaml
├── build/
│   ├── build.sh
│   ├── feeds.conf.default
│   ├── .config.seed
│   └── IMMORTALWRT_COMMIT
├── files/
│   ├── etc/
│   │   ├── config/
│   │   │   ├── mode-switch
│   │   │   └── fan
│   │   ├── profiles/
│   │   │   ├── pppoe-main/{network,firewall,dhcp}
│   │   │   ├── switch-equal/{network,firewall,dhcp}
│   │   │   └── bypass-gateway/{network,firewall,dhcp}
│   │   ├── init.d/fan-pid
│   │   └── uci-defaults/99-r2s-init
│   └── usr/
│       ├── bin/
│       │   ├── mode-switch
│       │   └── fan-pid-loop
│       └── lib/lua/luci/
│           ├── controller/mode_switch.lua
│           ├── controller/fan_pid.lua
│           ├── view/mode_switch/{status,pppoe,bypass}.htm
│           └── view/fan_pid/main.htm
├── patches/                       # 可选源码补丁（含 R2S DTS 风扇引脚修正）
├── scripts/
│   ├── flash-sd.sh
│   └── pre-deploy-check.sh
├── docs/
│   ├── README.md
│   └── superpowers/specs/
│       └── 2026-04-25-nanopi-r2s-openwrt-design.md
├── .github/workflows/
│   └── build.yml
└── .gitignore
```

## 6. 部署流程

1. macOS 上运行 `./scripts/flash-sd.sh`：
   - 列出可用磁盘（`diskutil list`，过滤 external + physical）
   - 用户选号 → 二次确认（输入磁盘 size 防误选）
   - `diskutil unmountDisk` → `sudo dd if=<image> of=/dev/rdiskN bs=4m`
   - dd 后 sha256 校验；不匹配则报错
2. SD 卡插 R2S → 上电（金属壳风扇短暂全速 → PID 接管平稳）
3. 任意网口连入电脑（默认 switch-equal 模式，两口等效）
4. 浏览器访问 `http://192.168.2.1`
5. 设 root 密码 → `状态 → Mode Switch` 选目标模式（如 PPPoE，先到 PPPoE tab 填账号 → 切换）

## 7. 错误处理

| 场景 | 处理 |
| --- | --- |
| 编译失败 | `build.sh` 保留 `logs/`，回显末 200 行；CI artifact 上传 logs |
| feed/git 网络失败 | 重试 3 次，间隔 10/30/60 秒 |
| mode-switch 网络起不来 | 5 秒超时 → 自动回滚 `/etc/config.bak.<ts>/` |
| LuCI 页面调用 mode-switch 失败 | 页面回显 stderr，并保留 `/var/log/mode-switch.log` |
| fan-pid 读温度失败 | 强制 PWM=pwm_max（保险），日志限流每分钟一条，下个采样周期重试 |
| PWM 写失败 | 日志限流每分钟一条，继续读温度并尝试写；不修改 `enabled`（防止悄无声息地停风扇） |
| SD dd 失败 / 校验不过 | flash-sd.sh 报错并提示重试 |

## 8. 测试策略

### 8.1 编译期

- CI 必须产出 `immortalwrt-rockchip-armv8-friendlyarm_nanopi-r2s-squashfs-sysupgrade.img.gz`，大小落在 30–60 MB
- `make` 退出码 0
- 镜像内通过 `binwalk` 验证关键二进制（passwall2、smartdns、tailscale、mode-switch、fan-pid-loop）存在

### 8.2 单元测试

- `mode-switch`：bash 单测，mock `uci`、`/etc/init.d/network`，验证三种模式 profile 拷贝、回滚路径
- `fan-pid-loop`：注入 `/tmp/fake_thermal`、捕获 PWM 写入序列，验证 setpoint 收敛 / 抗饱和

### 8.3 实机矩阵

| 模式 | 验证项 |
| --- | --- |
| switch-equal（默认） | 两口插电脑各取 192.168.2.x，互 ping 通；网关、DNS 工作 |
| pppoe-main | 拨号成功、LAN 客户端取 IP、能上网、防火墙 NAT 正常 |
| bypass-gateway | 上级路由内客户端把网关改 R2S 后能上网；Passwall2 透明代理生效 |
| 模式切换 | LuCI 切换三种模式，无网络残留、无 IP 冲突；再切回 switch-equal 完全恢复 |
| 风扇 | 烧机（`stress-ng --cpu 4 --timeout 5m`）期间温度收敛 setpoint 附近，PWM 平滑无抖动 |

## 9. 关键取舍

- **不集成 Docker**：1 GB RAM 跑 Passwall2 + SmartDNS + Tailscale 已紧张
- **不集成 AdGuardHome / mwan3 / samba / UPnP**：未列入需求；后期可加
- **mode-switch 的 LuCI 页面用 cbi/template 而非 LuCI2/JS**：与 ImmortalWrt 21.02+ 一致，开发熟悉
- **PID 用 shell 而非 C**：先验证逻辑正确，性能不是瓶颈（5 秒采样）；若发现 shell 抖动大再换 C
- **风扇 PWM 引脚以 ImmortalWrt R2S DTS 为准**：若无现成支持，需在 `patches/` 加 DTS 修正
- **CI runner 用 `ubuntu-latest`**：标准、免费、社区脚本多；不用自托管 runner

## 10. 未来扩展（不在本期）

- AdGuardHome 替换或共存于 SmartDNS
- 多 R2S 节点 Tailscale subnet router 编排
- 镜像差分升级（attendedsysupgrade）
- 风扇 PID 改 C / Rust 实现
- 拨码 / 物理按钮触发模式切换

## 11. 待澄清

无（auto mode 下假设的合理参数已在文中标注，用户可在审阅时调整）。
