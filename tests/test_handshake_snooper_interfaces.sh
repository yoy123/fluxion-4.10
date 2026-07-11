#!/usr/bin/env bash

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
FLUXION_DIR=$(dirname "$SCRIPT_DIR")

FLUXIONPath="$FLUXION_DIR"
FLUXIONLibPath="$FLUXION_DIR/lib"
HandshakeSnooperCLIArguments=1

source "$FLUXION_DIR/attacks/Handshake Snooper/attack.sh"

PASS=0
FAIL=0

pass() {
	echo "  PASS: $1"
	PASS=$((PASS + 1))
}

fail() {
	echo "  FAIL: $1"
	FAIL=$((FAIL + 1))
}

interface_list_wireless() {
	InterfaceListWireless=("${TestWirelessInterfaces[@]}")
}

available_interfaces() {
	handshake_snooper_available_jammer_interfaces | sed '/^$/d'
}

candidate_list() {
	local IFS=,
	echo "$*"
}

echo "=== Handshake Snooper Interface Test Suite ==="
echo

echo "Test 1: Free adapters remain selectable without a tracker"
TestWirelessInterfaces=(fluxwl0 wlan1 wlan2)
declare -A FluxionInterfaces=(
	[wlan0]=fluxwl0
	[fluxwl0]=wlan0
)
HandshakeSnooperJammerInterface=fluxwl0
HandshakeSnooperJammerInterfaceOriginal=wlan0
FluxionTargetTrackerInterface=""
HandshakeSnooperRelatedBSSIDJammers=()
mapfile -t candidates < <(available_interfaces)
if [ "$(candidate_list "${candidates[@]}")" = "wlan1,wlan2" ]; then
	pass "Free adapters are listed"
else
	fail "Free adapters were filtered when the tracker was unset"
fi

echo "Test 2: Existing related jammers are excluded from later choices"
TestWirelessInterfaces=(fluxwl0 fluxwl1 wlan2)
declare -A FluxionInterfaces=(
	[wlan0]=fluxwl0
	[fluxwl0]=wlan0
	[wlan1]=fluxwl1
	[fluxwl1]=wlan1
)
HandshakeSnooperJammerInterface=fluxwl0
HandshakeSnooperJammerInterfaceOriginal=wlan0
FluxionTargetTrackerInterface=""
HandshakeSnooperRelatedBSSIDJammers=(fluxwl1)
mapfile -t candidates < <(available_interfaces)
if [ "$(candidate_list "${candidates[@]}")" = "wlan2" ]; then
	pass "Previously selected related jammer is excluded"
else
	fail "Previously selected related jammer was offered again"
fi

echo "Test 3: Configured tracker remains excluded"
TestWirelessInterfaces=(fluxwl0 fluxwl1 wlan2)
declare -A FluxionInterfaces=(
	[wlan0]=fluxwl0
	[fluxwl0]=wlan0
	[wlan1]=fluxwl1
	[fluxwl1]=wlan1
)
HandshakeSnooperJammerInterface=fluxwl0
HandshakeSnooperJammerInterfaceOriginal=wlan0
FluxionTargetTrackerInterface=fluxwl1
HandshakeSnooperRelatedBSSIDJammers=()
mapfile -t candidates < <(available_interfaces)
if [ "$(candidate_list "${candidates[@]}")" = "wlan2" ]; then
	pass "Tracker interface is not offered as a jammer"
else
	fail "Tracker interface was offered as a jammer"
fi

echo
echo "=== Results: $PASS passed, $FAIL failed ==="

if (( FAIL > 0 )); then
	exit 1
fi
exit 0