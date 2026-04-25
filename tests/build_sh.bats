#!/usr/bin/env bats

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../build/build.sh"
}

@test "shows help with --help" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"--shell"* ]]
    [[ "$output" == *"--no-cache"* ]]
    [[ "$output" == *"--update-feeds"* ]]
}

@test "rejects unknown flag" {
    run "$SCRIPT" --bogus
    [ "$status" -ne 0 ]
}

@test "passes shellcheck" {
    run shellcheck "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "--dry-run prints planned actions without docker" {
    run env DRY_RUN=1 "$SCRIPT" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"would run"* ]]
}
