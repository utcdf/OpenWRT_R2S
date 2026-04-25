#!/usr/bin/env bats

CFG="${BATS_TEST_DIRNAME}/../files/etc/config/fan"

@test "has pid section enabled" {
    grep -q "config fan 'pid'" "$CFG"
    grep -q "option enabled '1'" "$CFG"
}

@test "setpoint is 55" {
    grep -q "option setpoint '55'" "$CFG"
}

@test "PID gains present" {
    grep -q "option kp" "$CFG"
    grep -q "option ki" "$CFG"
    grep -q "option kd" "$CFG"
}

@test "interval and pwm bounds present" {
    grep -q "option interval" "$CFG"
    grep -q "option pwm_min" "$CFG"
    grep -q "option pwm_max" "$CFG"
    grep -q "option pwm_path" "$CFG"
}
