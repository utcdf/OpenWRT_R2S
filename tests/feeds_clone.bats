#!/usr/bin/env bats

setup() {
    INNER="${BATS_TEST_DIRNAME}/../build/build-inner.sh"
}

@test "build-inner.sh passes shellcheck" {
    run shellcheck "$INNER"
    [ "$status" -eq 0 ]
}

@test "reads commit from IMMORTALWRT_COMMIT file" {
    run env DRY_RUN=1 BUILD_INSIDE=1 \
        "${BATS_TEST_DIRNAME}/../build/build.sh" --update-feeds
    [ "$status" -eq 0 ]
    [[ "$output" == *"checkout"* ]]
}

@test "IMMORTALWRT_COMMIT file is 40-char sha1" {
    commit=$(cat "${BATS_TEST_DIRNAME}/../build/IMMORTALWRT_COMMIT")
    [[ "$commit" =~ ^[a-f0-9]{40}$ ]]
}

@test "feeds.conf.default has all required feeds" {
    feeds="${BATS_TEST_DIRNAME}/../build/feeds.conf.default"
    grep -q "^src-git packages" "$feeds"
    grep -q "^src-git luci" "$feeds"
    grep -q "passwall2" "$feeds"
    grep -q "smartdns" "$feeds"
}
