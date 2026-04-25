# NanoPi R2S 多功能定制 OpenWRT

基于 ImmortalWrt master 的 NanoPi R2S 定制固件，单镜像在线切换三种模式：
PPPoE 主路由 / 双口对等交换 / 旁路由透明网关。

## 快速开始

```bash
./scripts/pre-deploy-check.sh   # 检查依赖
./build/build.sh                # 编译固件
./scripts/flash-sd.sh           # 烧入 SD 卡
```

## 文档

- 设计: `docs/superpowers/specs/2026-04-25-nanopi-r2s-openwrt-design.md`
- 实施计划: `docs/superpowers/plans/2026-04-25-nanopi-r2s-openwrt-implementation.md`
