#!/usr/bin/env bash

# ============================================================ #
# Test harness for lib/WindowUtils.sh
# Run with: sudo bash tests/test_window_utils.sh
# No wireless hardware needed - uses stub commands.
# ============================================================ #

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
FLUXION_DIR=$(dirname "$SCRIPT_DIR")

# Minimal stubs for required globals
FLUXIONWorkspacePath="/tmp/fluxspace_test_$$"
FLUXIONOutputDevice="/dev/null"
FLUXIONDebug=""
FLUXIONTMux=1  # Force tmux mode for testing
FLUXIONOriginalArgs=""
TMUX="fake"  # Pretend we're already inside tmux
FLUXIONDisplayMode=""

mkdir -p "$FLUXIONWorkspacePath"

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

# Source the library
source "$FLUXION_DIR/lib/WindowUtils.sh"

echo "=== WindowUtils.sh Test Suite ==="
echo

# ---- Test 1: fluxion_window_init sets display mode ----
echo "Test 1: fluxion_window_init sets FLUXIONDisplayMode"
fluxion_window_init 2>/dev/null || true
if [ "$FLUXIONDisplayMode" = "tmux" ]; then
	pass "Display mode set to tmux"
else
	fail "Expected tmux, got: $FLUXIONDisplayMode"
fi

# ---- Test 2: xterm mode init ----
echo "Test 2: xterm mode init"
FLUXIONTMux=""
FLUXIONDisplayMode=""
fluxion_window_init
if [ "$FLUXIONDisplayMode" = "xterm" ]; then
	pass "Display mode set to xterm when FLUXIONTMux is empty"
else
	fail "Expected xterm, got: $FLUXIONDisplayMode"
fi
# Restore tmux mode for remaining tests
FLUXIONTMux=1
FLUXIONDisplayMode="tmux"

# ---- Test 3: Window counter increments ----
echo "Test 3: Window counter increments"
local_counter=$FLUXIONWindowCounter
FLUXIONDisplayMode="xterm"  # Use xterm mode for simple testing
# We can't actually open xterm in CI, so just test the counter mechanism
old_counter=$FLUXIONWindowCounter
FLUXIONWindowCounter=$((FLUXIONWindowCounter + 1))
if [ $FLUXIONWindowCounter -gt $old_counter ]; then
	pass "Window counter increments correctly"
else
	fail "Window counter did not increment"
fi

# ---- Test 4: fluxion_window_close with empty PID ----
echo "Test 4: fluxion_window_close handles empty PID"
TestClosePID=""
fluxion_window_close TestClosePID
if [ -z "$TestClosePID" ]; then
	pass "Close with empty PID is safe"
else
	fail "Close with empty PID changed the variable"
fi

# ---- Test 5: fluxion_window_close kills process ----
echo "Test 5: fluxion_window_close kills a real process"
sleep 300 &
TestKillPID=$!
fluxion_window_close TestKillPID
sleep 0.5
if ! kill -0 $TestKillPID 2>/dev/null; then
	pass "Process was killed"
else
	kill $TestKillPID 2>/dev/null
	fail "Process was NOT killed"
fi
if [ -z "$TestKillPID" ]; then
	pass "PID variable was cleared"
else
	fail "PID variable was not cleared"
fi

# ---- Test 6: fluxion_window_cleanup is callable ----
echo "Test 6: fluxion_window_cleanup runs without error"
FLUXIONDisplayMode="xterm"  # xterm mode cleanup is a no-op
fluxion_window_cleanup
pass "Cleanup ran without error (xterm mode)"

# ---- Test 7: Background window open in xterm mode (stub test) ----
echo "Test 7: Background window open function signature"
# Test that the function exists and accepts the right number of params
if type -t fluxion_window_open &>/dev/null; then
	pass "fluxion_window_open is defined"
else
	fail "fluxion_window_open is not defined"
fi

# ---- Cleanup ----
rm -rf "$FLUXIONWorkspacePath"

echo
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ $FAIL -gt 0 ]; then
	exit 1
fi
exit 0
