#!/usr/bin/env bash

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
FLUXION_DIR=$(dirname "$SCRIPT_DIR")

source "$FLUXION_DIR/lib/TargetUtils.sh"

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

candidate() {
	printf '%s,first,last,6,54,WPA2,CCMP,PSK,%s,10,0,0,0,%s,\n' \
		"$1" "$2" "$3"
}

candidate_order() {
	local row
	local bssids=()
	for row in "$@"; do
		bssids+=("${row%%,*}")
	done
	local IFS=,
	echo "${bssids[*]}"
}

echo "=== TargetUtils.sh Test Suite ==="
echo

echo "Test 1: Valid signals are sorted from strongest to weakest"
mapfile -t sortedCandidates < <(
	{
		candidate "00:00:00:00:00:01" "-80" "weak"
		candidate "00:00:00:00:00:02" "-45" "strong"
		candidate "00:00:00:00:00:03" "-65" "medium"
	} | target_sort_candidates_by_signal
)
if [ "$(candidate_order "${sortedCandidates[@]}")" = \
	"00:00:00:00:00:02,00:00:00:00:00:03,00:00:00:00:00:01" ]; then
	pass "Valid signal strengths are descending"
else
	fail "Valid signal strengths were not descending"
fi

echo "Test 2: Unknown signal strength is listed last"
mapfile -t sortedCandidates < <(
	{
		candidate "00:00:00:00:00:01" "-1" "unknown"
		candidate "00:00:00:00:00:02" "-95" "weak"
		candidate "00:00:00:00:00:03" "-60" "strong"
	} | target_sort_candidates_by_signal
)
if [ "$(candidate_order "${sortedCandidates[@]}")" = \
	"00:00:00:00:00:03,00:00:00:00:00:02,00:00:00:00:00:01" ]; then
	pass "Unknown signal strength is last"
else
	fail "Unknown signal strength was not last"
fi

echo "Test 3: Equal signals preserve scanner order"
mapfile -t sortedCandidates < <(
	{
		candidate "00:00:00:00:00:01" "-70" "first"
		candidate "00:00:00:00:00:02" "-70" "second"
		candidate "00:00:00:00:00:03" "-80" "third"
	} | target_sort_candidates_by_signal
)
if [ "$(candidate_order "${sortedCandidates[@]}")" = \
	"00:00:00:00:00:01,00:00:00:00:00:02,00:00:00:00:00:03" ]; then
	pass "Equal strengths retain scanner order"
else
	fail "Equal strengths changed scanner order"
fi

echo "Test 4: Empty records are ignored"
mapfile -t sortedCandidates < <(
	{
		echo
		candidate "00:00:00:00:00:01" "-60" "only"
		echo
	} | target_sort_candidates_by_signal
)
if [ "${#sortedCandidates[@]}" -eq 1 ] &&
		[ "${sortedCandidates[0]%%,*}" = "00:00:00:00:00:01" ]; then
	pass "Empty records are ignored"
else
	fail "Empty records were returned"
fi

echo
echo "=== Results: $PASS passed, $FAIL failed ==="

if (( FAIL > 0 )); then
	exit 1
fi
exit 0
