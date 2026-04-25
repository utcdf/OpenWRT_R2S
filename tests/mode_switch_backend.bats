#!/usr/bin/env bats

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../files/usr/bin/mode-switch"

    # 隔离环境
    export ROOT="${BATS_TMPDIR}/rootfs"
    rm -rf "$ROOT"
    mkdir -p "$ROOT/etc/config" "$ROOT/etc/init.d" "$ROOT/var/log" "$ROOT/etc/profiles"

    # 复制真实 profiles
    cp -r "${BATS_TEST_DIRNAME}/../files/etc/profiles/"* "$ROOT/etc/profiles/"
    cp "${BATS_TEST_DIRNAME}/../files/etc/config/mode-switch" "$ROOT/etc/config/"

    # 起始 network/firewall/dhcp 用 switch-equal 占位
    cp "$ROOT/etc/profiles/switch-equal/network"  "$ROOT/etc/config/network"
    cp "$ROOT/etc/profiles/switch-equal/firewall" "$ROOT/etc/config/firewall"
    cp "$ROOT/etc/profiles/switch-equal/dhcp"     "$ROOT/etc/config/dhcp"

    # fake init.d
    cat > "$ROOT/etc/init.d/network" <<'EOF'
#!/bin/sh
echo "network $1" >> "$ROOT/var/log/init.log"
EOF
    cp "$ROOT/etc/init.d/network" "$ROOT/etc/init.d/firewall"
    cp "$ROOT/etc/init.d/network" "$ROOT/etc/init.d/dnsmasq"
    chmod +x "$ROOT/etc/init.d/"*

    # fake uci
    mkdir -p "${BATS_TMPDIR}/bin"
    cat > "${BATS_TMPDIR}/bin/uci" <<'EOFUCI'
#!/usr/bin/env bash
file_for() { echo "$ROOT/etc/config/$1"; }
case "$1" in
  -q)
      shift; "$0" "$@" 2>/dev/null
      ;;
  get)
      key="$2"; pkg=${key%%.*}; rest=${key#*.}; sect=${rest%%.*}; opt=${rest#*.}
      grep -E "^[[:space:]]*option ${opt} " "$(file_for "$pkg")" 2>/dev/null \
          | head -1 | sed -E "s/.*option ${opt} '([^']*)'.*/\1/"
      ;;
  set)
      key="${2%=*}"; val="${2#*=}"; pkg=${key%%.*}; rest=${key#*.}; sect=${rest%%.*}; opt=${rest#*.}
      f=$(file_for "$pkg")
      if grep -qE "^[[:space:]]*option ${opt} " "$f"; then
          sed -i.bak -E "s|^([[:space:]]*option ${opt} ).*|\1'${val}'|" "$f" && rm -f "${f}.bak"
      else
          echo "    option ${opt} '${val}'" >> "$f"
      fi
      ;;
  add_list)
      key="${2%=*}"; val="${2#*=}"; pkg=${key%%.*}; rest=${key#*.}; sect=${rest%%.*}; opt=${rest#*.}
      f=$(file_for "$pkg")
      echo "    list ${opt} '${val}'" >> "$f"
      ;;
  delete) ;;
  commit) ;;
  show) cat "$(file_for "$2")" 2>/dev/null ;;
esac
EOFUCI
    chmod +x "${BATS_TMPDIR}/bin/uci"
    export PATH="${BATS_TMPDIR}/bin:${PATH}"
}

teardown() {
    rm -rf "$ROOT"
}

@test "passes shellcheck" {
    run shellcheck "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "shows help" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"pppoe"* ]]
    [[ "$output" == *"switch"* ]]
    [[ "$output" == *"bypass"* ]]
}

@test "rejects unknown mode" {
    run env ROOT="$ROOT" "$SCRIPT" bogus
    [ "$status" -ne 0 ]
}

@test "status reports current mode" {
    run env ROOT="$ROOT" "$SCRIPT" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"switch-equal"* ]]
}

@test "switch to pppoe copies pppoe-main profiles" {
    run env ROOT="$ROOT" SKIP_RESTART=1 "$SCRIPT" pppoe
    [ "$status" -eq 0 ]
    grep -q "proto 'pppoe'" "$ROOT/etc/config/network"
    grep -q "option name 'wan'" "$ROOT/etc/config/firewall"
}

@test "switch to bypass copies bypass-gateway profile" {
    run env ROOT="$ROOT" SKIP_RESTART=1 "$SCRIPT" bypass
    [ "$status" -eq 0 ]
    grep -q "192.168.1.2" "$ROOT/etc/config/network"
}

@test "switch creates timestamped backup" {
    run env ROOT="$ROOT" SKIP_RESTART=1 "$SCRIPT" pppoe
    [ "$status" -eq 0 ]
    found=$(find "$ROOT/etc" -maxdepth 1 -name 'config.bak.*' -type d | wc -l)
    [ "$found" -gt 0 ]
}

@test "switch updates mode-switch.current.name" {
    env ROOT="$ROOT" SKIP_RESTART=1 "$SCRIPT" pppoe
    grep -q "option name 'pppoe-main'" "$ROOT/etc/config/mode-switch"
}

@test "switch injects pppoe creds into network" {
    sed -i.bak -E "s|option username ''|option username 'alice'|" "$ROOT/etc/config/mode-switch"
    sed -i.bak -E "s|option password ''|option password 'secret'|" "$ROOT/etc/config/mode-switch"
    rm -f "$ROOT/etc/config/mode-switch.bak"

    env ROOT="$ROOT" SKIP_RESTART=1 "$SCRIPT" pppoe
    grep -q "option username 'alice'" "$ROOT/etc/config/network"
    grep -q "option password 'secret'" "$ROOT/etc/config/network"
}

@test "switch rolls back on simulated network failure" {
    cat > "$ROOT/etc/init.d/network" <<'EOF'
#!/bin/sh
echo "network $1" >> "$ROOT/var/log/init.log"
exit 1
EOF
    chmod +x "$ROOT/etc/init.d/network"

    run env ROOT="$ROOT" "$SCRIPT" pppoe
    [ "$status" -ne 0 ]
    grep -q "br-lan" "$ROOT/etc/config/network"
}
