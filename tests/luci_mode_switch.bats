#!/usr/bin/env bats

CTRL="${BATS_TEST_DIRNAME}/../files/usr/lib/lua/luci/controller/mode_switch.lua"

@test "passes lua syntax check" {
    run luac -p "$CTRL"
    [ "$status" -eq 0 ]
}

@test "registers index() entry function" {
    grep -qE "^function index\(\)" "$CTRL"
}

@test "registers /admin/status/mode_switch entry" {
    grep -q '"admin", "status", "mode_switch"' "$CTRL"
}

@test "exposes do_switch action" {
    grep -q "function action_switch" "$CTRL"
    grep -q '"do_switch"' "$CTRL"
}

@test "exposes pppoe and bypass tabs" {
    grep -q '"pppoe"' "$CTRL"
    grep -q '"bypass"' "$CTRL"
}
