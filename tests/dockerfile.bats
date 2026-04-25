#!/usr/bin/env bats

@test "Dockerfile passes hadolint" {
    run hadolint --config docker/.hadolint.yaml docker/Dockerfile
    [ "$status" -eq 0 ]
}

@test "Dockerfile builds cleanly" {
    skip_if_no_docker
    run docker build -t r2s-builder:test -f docker/Dockerfile docker/
    [ "$status" -eq 0 ]
}

@test "container has builder user uid 1000" {
    skip_if_no_docker
    run docker run --rm r2s-builder:test id -u builder
    [ "$status" -eq 0 ]
    [ "$output" = "1000" ]
}

@test "container has required build tools" {
    skip_if_no_docker
    for tool in gcc make git python3 unzip rsync wget; do
        run docker run --rm r2s-builder:test which "$tool"
        [ "$status" -eq 0 ]
    done
}

skip_if_no_docker() {
    docker info >/dev/null 2>&1 || skip "docker not running"
}
