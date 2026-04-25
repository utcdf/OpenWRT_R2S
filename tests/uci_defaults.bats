#!/usr/bin/env bats

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../files/etc/uci-defaults/99-r2s-init"
    export UCI_LOG="${BATS_TMPDIR}/uci.log"
    : > "$UCI_LOG"
    export PATH="${BATS_TEST_DIRNAME}/lib/fakes/uci-recorder:${PATH}"
    export TEST_PROFILES_SRC="${BATS_TEST_DIRNAME}/../files/etc/profiles"
    export TEST_CONFIG_DIR="${BATS_TMPDIR}/config"
    mkdir -p "$TEST_CONFIG_DIR"
}

@test "passes shellcheck" {
    run shellcheck "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "sets hostname" {
    run env CONFIG_DIR="$TEST_CONFIG_DIR" PROFILES_DIR="$TEST_PROFILES_SRC" "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -q "uci set system.@system\[0\].hostname='NanoPi-R2S'" "$UCI_LOG"
}

@test "sets timezone Asia/Shanghai (CST-8)" {
    run env CONFIG_DIR="$TEST_CONFIG_DIR" PROFILES_DIR="$TEST_PROFILES_SRC" "$SCRIPT"
    grep -q "timezone='CST-8'" "$UCI_LOG"
    grep -q "zonename='Asia/Shanghai'" "$UCI_LOG"
}

@test "sets aliyun NTP servers" {
    run env CONFIG_DIR="$TEST_CONFIG_DIR" PROFILES_DIR="$TEST_PROFILES_SRC" "$SCRIPT"
    grep -q "ntp.aliyun.com" "$UCI_LOG"
}

@test "writes mode-switch current=switch-equal" {
    run env CONFIG_DIR="$TEST_CONFIG_DIR" PROFILES_DIR="$TEST_PROFILES_SRC" "$SCRIPT"
    grep -q "mode-switch.current.name='switch-equal'" "$UCI_LOG"
}

@test "enables fan-pid service" {
    run env CONFIG_DIR="$TEST_CONFIG_DIR" PROFILES_DIR="$TEST_PROFILES_SRC" "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -q "fan-pid.*enable" "$UCI_LOG" || \
        [ -e "$TEST_CONFIG_DIR/.fan_pid_enabled_marker" ]
}
