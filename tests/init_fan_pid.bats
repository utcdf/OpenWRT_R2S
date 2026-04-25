#!/usr/bin/env bats

INIT="${BATS_TEST_DIRNAME}/../files/etc/init.d/fan-pid"

@test "passes shellcheck" {
    run shellcheck -s sh "$INIT"
    [ "$status" -eq 0 ]
}

@test "uses procd start_service convention" {
    grep -q "USE_PROCD=1" "$INIT"
    grep -q "start_service" "$INIT"
}

@test "honors uci enabled flag" {
    grep -q "config_load 'fan'" "$INIT"
    grep -q "fan\\.pid\\.enabled" "$INIT" || grep -q "config_get .*enabled" "$INIT"
}

@test "respawns on crash" {
    grep -q "respawn" "$INIT"
}
