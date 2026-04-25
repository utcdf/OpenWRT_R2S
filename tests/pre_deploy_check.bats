#!/usr/bin/env bats

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../scripts/pre-deploy-check.sh"
}

@test "exits 0 when all deps present" {
    run env PATH="${BATS_TEST_DIRNAME}/lib/fakes/all-present:${PATH}" "$SCRIPT" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "exits non-zero when docker missing" {
    run env PATH="${BATS_TEST_DIRNAME}/lib/fakes/no-docker:${PATH}" "$SCRIPT" --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"docker"* ]]
}

@test "prints all missing tools, not just first" {
    run env PATH="${BATS_TEST_DIRNAME}/lib/fakes/empty:${PATH}" "$SCRIPT" --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"docker"* ]]
    [[ "$output" == *"git"* ]]
}
