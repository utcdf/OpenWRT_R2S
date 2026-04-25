#!/usr/bin/env bats

PROFILE_DIR="${BATS_TEST_DIRNAME}/../files/etc/profiles/switch-equal"

@test "network has br-lan with eth0+eth1" {
    grep -q "list ports 'eth0'" "$PROFILE_DIR/network"
    grep -q "list ports 'eth1'" "$PROFILE_DIR/network"
    grep -q "option type 'bridge'" "$PROFILE_DIR/network"
}

@test "lan static 192.168.2.1/24" {
    grep -q "option ipaddr '192.168.2.1'" "$PROFILE_DIR/network"
    grep -q "option netmask '255.255.255.0'" "$PROFILE_DIR/network"
}

@test "wan interface disabled or absent" {
    ! grep -q "config interface 'wan'" "$PROFILE_DIR/network" || \
        grep -A4 "config interface 'wan'" "$PROFILE_DIR/network" | grep -q "option auto '0'"
}

@test "firewall has lan zone with input/output/forward ACCEPT" {
    grep -q "option name 'lan'" "$PROFILE_DIR/firewall"
    grep -q "option input 'ACCEPT'" "$PROFILE_DIR/firewall"
    grep -q "option output 'ACCEPT'" "$PROFILE_DIR/firewall"
    grep -q "option forward 'ACCEPT'" "$PROFILE_DIR/firewall"
}

@test "dhcp serves on br-lan" {
    grep -q "option interface 'lan'" "$PROFILE_DIR/dhcp"
    grep -q "option ignore '0'" "$PROFILE_DIR/dhcp" || \
        ! grep -q "option ignore '1'" "$PROFILE_DIR/dhcp"
}
