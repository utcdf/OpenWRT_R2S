#!/usr/bin/env bats

SEED="${BATS_TEST_DIRNAME}/../build/.config.seed"

@test "selects nanopi-r2s device" {
    grep -q "CONFIG_TARGET_rockchip_armv8_DEVICE_friendlyarm_nanopi-r2s=y" "$SEED"
}

@test "includes USB rtl8152 driver" {
    grep -q "CONFIG_PACKAGE_kmod-usb-net-rtl8152=y" "$SEED"
}

@test "includes rockchip pwm driver" {
    grep -q "CONFIG_PACKAGE_kmod-pwm-rockchip=y" "$SEED"
}

@test "includes passwall2, smartdns, tailscale" {
    grep -q "CONFIG_PACKAGE_luci-app-passwall2=y" "$SEED"
    grep -q "CONFIG_PACKAGE_smartdns=y" "$SEED"
    grep -q "CONFIG_PACKAGE_tailscale=y" "$SEED"
}

@test "includes argon theme and zh-cn base" {
    grep -q "CONFIG_PACKAGE_luci-theme-argon=y" "$SEED"
    grep -q "CONFIG_PACKAGE_luci-i18n-base-zh-cn=y" "$SEED"
}
