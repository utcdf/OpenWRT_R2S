#!/usr/bin/env bats

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../files/usr/bin/fan-pid-loop"

    export THERMAL="${BATS_TMPDIR}/thermal/temp"
    export PWM_DIR="${BATS_TMPDIR}/pwm"
    export STATE="${BATS_TMPDIR}/fan-pid.state"
    mkdir -p "$(dirname "$THERMAL")" "$PWM_DIR"
    : > "$PWM_DIR/duty_cycle"
    echo 50000 > "$THERMAL"
}

teardown() {
    rm -rf "${BATS_TMPDIR}/thermal" "$PWM_DIR" "$STATE"
}

@test "passes shellcheck" {
    run shellcheck "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "single iteration computes pwm and writes duty_cycle + state" {
    run env FAN_THERMAL="$THERMAL" FAN_PWM_DIR="$PWM_DIR" FAN_STATE="$STATE" \
        FAN_SETPOINT=55 FAN_KP=4.0 FAN_KI=0.2 FAN_KD=1.0 FAN_INTERVAL=1 \
        FAN_PWM_MIN=0 FAN_PWM_MAX=255 FAN_ONCE=1 \
        "$SCRIPT"
    [ "$status" -eq 0 ]
    [ -f "$STATE" ]
    grep -q "temp_c=50" "$STATE"
    grep -q "pwm=" "$STATE"
}

@test "below setpoint at 50C with positive Kp keeps pwm at min" {
    run env FAN_THERMAL="$THERMAL" FAN_PWM_DIR="$PWM_DIR" FAN_STATE="$STATE" \
        FAN_SETPOINT=55 FAN_KP=4.0 FAN_KI=0 FAN_KD=0 FAN_INTERVAL=1 \
        FAN_PWM_MIN=0 FAN_PWM_MAX=255 FAN_ONCE=1 \
        "$SCRIPT"
    pwm=$(awk -F= '/^pwm/{print $2}' "$STATE")
    [ "$pwm" = "0" ]
}

@test "above setpoint clamps to pwm_max if extreme" {
    echo 90000 > "$THERMAL"
    run env FAN_THERMAL="$THERMAL" FAN_PWM_DIR="$PWM_DIR" FAN_STATE="$STATE" \
        FAN_SETPOINT=55 FAN_KP=20 FAN_KI=0 FAN_KD=0 FAN_INTERVAL=1 \
        FAN_PWM_MIN=0 FAN_PWM_MAX=255 FAN_ONCE=1 \
        "$SCRIPT"
    pwm=$(awk -F= '/^pwm/{print $2}' "$STATE")
    [ "$pwm" = "255" ]
}

@test "missing thermal forces pwm_max and continues" {
    rm -f "$THERMAL"
    run env FAN_THERMAL="$THERMAL" FAN_PWM_DIR="$PWM_DIR" FAN_STATE="$STATE" \
        FAN_SETPOINT=55 FAN_KP=4 FAN_KI=0 FAN_KD=0 FAN_INTERVAL=1 \
        FAN_PWM_MIN=0 FAN_PWM_MAX=200 FAN_ONCE=1 \
        "$SCRIPT"
    [ "$status" -eq 0 ]
    pwm=$(awk -F= '/^pwm/{print $2}' "$STATE")
    [ "$pwm" = "200" ]
}

@test "integrator accumulates pwm under sustained overshoot" {
    echo 70000 > "$THERMAL"
    last_pwm=0
    for i in $(seq 1 30); do
        env FAN_THERMAL="$THERMAL" FAN_PWM_DIR="$PWM_DIR" FAN_STATE="$STATE" \
            FAN_SETPOINT=55 FAN_KP=4.0 FAN_KI=0.5 FAN_KD=1.0 FAN_INTERVAL=1 \
            FAN_PWM_MIN=0 FAN_PWM_MAX=255 FAN_ONCE=1 \
            "$SCRIPT"
        last_pwm=$(awk -F= '/^pwm/{print $2}' "$STATE")
    done
    [ "$last_pwm" -ge 200 ]
}
