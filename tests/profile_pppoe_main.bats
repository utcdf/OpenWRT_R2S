#!/usr/bin/env bats

PROFILE_DIR="${BATS_TEST_DIRNAME}/../files/etc/profiles/pppoe-main"

@test "wan uses pppoe on eth0" {
    grep -q "config interface 'wan'" "$PROFILE_DIR/network"
    grep -A6 "config interface 'wan'" "$PROFILE_DIR/network" | grep -q "option proto 'pppoe'"
    grep -A6 "config interface 'wan'" "$PROFILE_DIR/network" | grep -q "option device 'eth0'"
}

@test "lan static 192.168.2.1 on eth1" {
    grep -A6 "config interface 'lan'" "$PROFILE_DIR/network" | grep -q "option device 'eth1'"
    grep -A6 "config interface 'lan'" "$PROFILE_DIR/network" | grep -q "192.168.2.1"
}

@test "firewall has wan zone with masquerade" {
    grep -q "option name 'wan'" "$PROFILE_DIR/firewall"
    grep -q "option masq '1'" "$PROFILE_DIR/firewall"
    grep -q "option mtu_fix '1'" "$PROFILE_DIR/firewall"
}

@test "firewall has forwarding lan -> wan" {
    grep -q "option src 'lan'" "$PROFILE_DIR/firewall"
    grep -q "option dest 'wan'" "$PROFILE_DIR/firewall"
}

@test "dhcp serves on lan" {
    grep -q "option interface 'lan'" "$PROFILE_DIR/dhcp"
    grep -q "option ignore '0'" "$PROFILE_DIR/dhcp" || \
        ! grep -q "option ignore '1'" "$PROFILE_DIR/dhcp"
}
