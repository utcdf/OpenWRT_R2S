#!/usr/bin/env bats

CFG="${BATS_TEST_DIRNAME}/../files/etc/config/mode-switch"

@test "has current mode set to switch-equal" {
    grep -q "config mode 'current'" "$CFG"
    grep -A2 "config mode 'current'" "$CFG" | grep -q "option name 'switch-equal'"
}

@test "has pppoe section with empty username/password and mtu 1492" {
    grep -q "config pppoe 'pppoe'" "$CFG"
    grep -A6 "config pppoe 'pppoe'" "$CFG" | grep -q "option username ''"
    grep -A6 "config pppoe 'pppoe'" "$CFG" | grep -q "option password ''"
    grep -A6 "config pppoe 'pppoe'" "$CFG" | grep -q "option mtu '1492'"
}

@test "has bypass section with placeholder upstream gateway" {
    grep -q "config bypass 'bypass'" "$CFG"
    grep -A6 "config bypass 'bypass'" "$CFG" | grep -q "option ipaddr '192.168.1.2'"
    grep -A6 "config bypass 'bypass'" "$CFG" | grep -q "option gateway '192.168.1.1'"
    grep -A6 "config bypass 'bypass'" "$CFG" | grep -q "option dns '192.168.1.1'"
}
