#!/usr/bin/env bats

PROFILE_DIR="${BATS_TEST_DIRNAME}/../files/etc/profiles/bypass-gateway"

@test "lan on eth0 with placeholder ip 192.168.1.2" {
    grep -A6 "config interface 'lan'" "$PROFILE_DIR/network" | grep -q "option device 'eth0'"
    grep -A6 "config interface 'lan'" "$PROFILE_DIR/network" | grep -q "192.168.1.2"
    grep -A6 "config interface 'lan'" "$PROFILE_DIR/network" | grep -q "option gateway '192.168.1.1'"
}

@test "wan disabled or absent" {
    ! grep -q "config interface 'wan'" "$PROFILE_DIR/network" || \
        grep -A6 "config interface 'wan'" "$PROFILE_DIR/network" | grep -q "option auto '0'"
}

@test "firewall lan zone allows masquerade for transparent proxy" {
    grep -q "option name 'lan'" "$PROFILE_DIR/firewall"
    grep -q "option masq '1'" "$PROFILE_DIR/firewall"
}

@test "firewall has forwarding lan -> lan" {
    grep -q "option src 'lan'" "$PROFILE_DIR/firewall"
    grep -q "option dest 'lan'" "$PROFILE_DIR/firewall"
}

@test "dhcp ignored on lan (option ignore '1')" {
    grep -q "option interface 'lan'" "$PROFILE_DIR/dhcp"
    grep -q "option ignore '1'" "$PROFILE_DIR/dhcp"
}
