#!/usr/bin/env bats

DIR="${BATS_TEST_DIRNAME}/../files/usr/lib/lua/luci"

@test "controller has lua syntax" {
    run luac -p "$DIR/controller/fan_pid.lua"
    [ "$status" -eq 0 ]
}

@test "controller registers /admin/system/fan_pid" {
    grep -q '"admin", "system", "fan_pid"' "$DIR/controller/fan_pid.lua"
}

@test "controller exposes state action" {
    grep -q "function action_state" "$DIR/controller/fan_pid.lua"
}

@test "cbi main has lua syntax" {
    run luac -p "$DIR/model/cbi/fan_pid/main.lua"
    [ "$status" -eq 0 ]
}

@test "cbi binds setpoint, kp, ki, kd" {
    grep -q "setpoint" "$DIR/model/cbi/fan_pid/main.lua"
    grep -q "\"kp\"" "$DIR/model/cbi/fan_pid/main.lua"
    grep -q "\"ki\"" "$DIR/model/cbi/fan_pid/main.lua"
    grep -q "\"kd\"" "$DIR/model/cbi/fan_pid/main.lua"
}
