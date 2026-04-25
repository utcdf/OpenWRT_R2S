#!/usr/bin/env bats

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../scripts/flash-sd.sh"
    export FAKE_BIN="${BATS_TMPDIR}/bin"
    mkdir -p "$FAKE_BIN"

    cat > "$FAKE_BIN/diskutil" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    list)
        cat <<'OUT'
/dev/disk2 (external, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:                                                   *15.9 GB    disk2
OUT
        ;;
    info)  echo "Total Size: 15.9 GB"; echo "Internal: No" ;;
    unmountDisk) ;;
    *) ;;
esac
EOF
    chmod +x "$FAKE_BIN/diskutil"

    cat > "$FAKE_BIN/dd" <<'EOF'
#!/usr/bin/env bash
echo "would dd: $*" >&2
exit 0
EOF
    chmod +x "$FAKE_BIN/dd"

    cat > "$FAKE_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF
    chmod +x "$FAKE_BIN/sudo"

    cat > "$FAKE_BIN/shasum" <<'EOF'
#!/usr/bin/env bash
echo "deadbeef00000000000000000000000000000000000000000000000000000000  -"
EOF
    chmod +x "$FAKE_BIN/shasum"

    export PATH="$FAKE_BIN:$PATH"

    export FAKE_IMG="${BATS_TMPDIR}/fake.img.gz"
    echo "fake-data" | gzip > "$FAKE_IMG"
    export FAKE_SHA="${BATS_TMPDIR}/fake.img.gz.sha256"
    echo "deadbeef00000000000000000000000000000000000000000000000000000000  $(basename "$FAKE_IMG")" > "$FAKE_SHA"
}

@test "passes shellcheck" {
    run shellcheck "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "shows help" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "lists disks" {
    run "$SCRIPT" --list
    [ "$status" -eq 0 ]
    [[ "$output" == *"disk2"* ]]
}

@test "writes when target + image given (dry-run mode)" {
    run env DRY_RUN=1 "$SCRIPT" --image "$FAKE_IMG" --target /dev/disk2 --yes
    [ "$status" -eq 0 ]
    [[ "$output" == *"would dd"* ]] || [[ "$output" == *"DRY"* ]]
}

@test "refuses non-external disk" {
    cat > "$FAKE_BIN/diskutil" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    info) echo "Total Size: 500 GB"; echo "Internal: Yes" ;;
    *) echo "/dev/disk0 (internal, physical):" ;;
esac
EOF
    chmod +x "$FAKE_BIN/diskutil"
    run env DRY_RUN=1 "$SCRIPT" --image "$FAKE_IMG" --target /dev/disk0 --yes
    [ "$status" -ne 0 ]
}
