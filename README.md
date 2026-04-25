# NanoPi R2S 多功能定制 OpenWRT

[![build](https://github.com/<user>/<repo>/actions/workflows/build.yml/badge.svg)](https://github.com/<user>/<repo>/actions/workflows/build.yml)

基于 ImmortalWrt master 的 NanoPi R2S 定制固件，**单镜像**在线切换三种工作模式：

| 模式 | 用途 |
| --- | --- |
| `switch-equal`（默认） | 双口对等交换：eth0+eth1 桥接 br-lan，同段 DHCP，互通 |
| `pppoe-main` | PPPoE 主路由：eth0 拨号、eth1 LAN |
| `bypass-gateway` | 旁路由透明网关：eth0 单臂，挂上级路由下 |

## 特性

- ImmortalWrt master（编译时锁定 commit）
- 内置 Passwall2 / SmartDNS / Tailscale / WireGuard / SQM / ttyd
- LuCI 模式切换页面（`状态 → Mode Switch`）
- LuCI PID 风扇控制页面（`系统 → Fan PID`）
- macOS Docker 一键编译 + GitHub Actions CI

## 默认参数

| 项 | 值 |
| --- | --- |
| LAN 网段 | 192.168.2.0/24 |
| LAN IP | 192.168.2.1 |
| 主机名 | `NanoPi-R2S` |
| 时区 | Asia/Shanghai |
| 默认初始模式 | `switch-equal` |

首次开机访问 `http://192.168.2.1` 即提示设置 root 密码。

## 快速开始

### 依赖

```bash
brew install bats-core shellcheck hadolint lua
# 启动 Docker Desktop
./scripts/pre-deploy-check.sh
```

### 编译

```bash
./build/build.sh                 # 完整编译（首次约 1-3 小时）
./build/build.sh --update-feeds  # 只刷新 feeds
./build/build.sh --shell         # 进容器调试
./build/build.sh --no-cache      # 强制重编
```

产物：`out/<date>-<commit>/immortalwrt-rockchip-armv8-friendlyarm_nanopi-r2s-squashfs-sysupgrade.img.gz`

### 烧录

```bash
./scripts/flash-sd.sh --list                                  # 列出外置磁盘
./scripts/flash-sd.sh --image out/.../sysupgrade.img.gz \
                      --target /dev/disk2                     # 二次确认后写卡
```

### 切换模式

启动后浏览器访问 LuCI（默认 `http://192.168.2.1`）：

1. `状态 → Mode Switch`
2. 选目标模式（PPPoE 主路由前请先到 `PPPoE` tab 填账号）
3. 点击切换；网络 5 秒内未起则自动回滚

CLI：
```bash
ssh root@192.168.2.1 mode-switch pppoe   # 或 switch / bypass / status
```

## 目录结构

参见 [`docs/superpowers/specs/2026-04-25-nanopi-r2s-openwrt-design.md`](docs/superpowers/specs/2026-04-25-nanopi-r2s-openwrt-design.md) §5。

## 文档

- 设计 spec: `docs/superpowers/specs/2026-04-25-nanopi-r2s-openwrt-design.md`
- 实施 plan: `docs/superpowers/plans/2026-04-25-nanopi-r2s-openwrt-implementation.md`
- 实机测试清单: `docs/manual-tests.md`
