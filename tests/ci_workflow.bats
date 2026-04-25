#!/usr/bin/env bats

WF="${BATS_TEST_DIRNAME}/../.github/workflows/build.yml"

@test "yaml is valid (python yaml.safe_load)" {
    run python3 -c "import yaml,sys; yaml.safe_load(open('$WF'))"
    [ "$status" -eq 0 ]
}

@test "triggers on push, workflow_dispatch, tag v*" {
    grep -q "push:" "$WF"
    grep -q "workflow_dispatch:" "$WF"
    grep -q "tags:" "$WF"
}

@test "uses ubuntu-latest runner" {
    grep -q "runs-on: ubuntu-latest" "$WF"
}

@test "frees disk space" {
    grep -qE "free.*disk|jlumbroso/free-disk-space|rm -rf /usr/share/dotnet" "$WF"
}

@test "checks IMMORTALWRT_COMMIT" {
    grep -q "IMMORTALWRT_COMMIT" "$WF"
}

@test "uploads artifact" {
    grep -q "actions/upload-artifact" "$WF"
}

@test "creates release on tag" {
    grep -qE "softprops/action-gh-release|gh release create" "$WF"
}

@test "uses ccache and dl cache" {
    grep -q "actions/cache" "$WF"
    grep -q "ccache" "$WF"
}
