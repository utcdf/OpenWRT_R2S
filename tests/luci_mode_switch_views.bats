#!/usr/bin/env bats

DIR="${BATS_TEST_DIRNAME}/../files/usr/lib/lua/luci"

@test "status template exists and references current mode JS" {
    [ -f "$DIR/view/mode_switch/status.htm" ]
    grep -q "r2s-current" "$DIR/view/mode_switch/status.htm"
    grep -q "r2sSwitch" "$DIR/view/mode_switch/status.htm"
}

@test "pppoe cbi compiles" {
    run luac -p "$DIR/model/cbi/mode_switch/pppoe.lua"
    [ "$status" -eq 0 ]
}

@test "bypass cbi compiles" {
    run luac -p "$DIR/model/cbi/mode_switch/bypass.lua"
    [ "$status" -eq 0 ]
}
