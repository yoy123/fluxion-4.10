#!/usr/bin/env bash

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
FLUXION_DIR=$(dirname "$SCRIPT_DIR")

source "$FLUXION_DIR/lib/SandboxUtils.sh"

TEST_ROOT=$(mktemp -d /tmp/fluxspace_sandbox_test.XXXXXXXXXX)
SandboxWorkspacePath="$TEST_ROOT/workspace"
SandboxOutputDevice="$TEST_ROOT/sandbox.log"
mkdir -p "$SandboxWorkspacePath"

PASS=0
FAIL=0

cleanup() {
	rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

pass() {
	echo "  PASS: $1"
	PASS=$((PASS + 1))
}

fail() {
	echo "  FAIL: $1"
	FAIL=$((FAIL + 1))
}

echo "=== SandboxUtils.sh Test Suite ==="
echo

echo "Test 1: Literal paths with spaces are removed"
mkdir -p "$SandboxWorkspacePath/literal path"
touch "$SandboxWorkspacePath/literal path/file"
if sandbox_remove_workfile "$SandboxWorkspacePath/literal path" &&
		[[ ! -e "$SandboxWorkspacePath/literal path" ]]; then
	pass "Literal workspace path was removed"
else
	fail "Literal workspace path was not removed"
fi

echo "Test 2: Workspace glob patterns are expanded"
touch "$SandboxWorkspacePath/dump-01" "$SandboxWorkspacePath/dump-02" \
	"$SandboxWorkspacePath/keep"
if sandbox_remove_workfile "$SandboxWorkspacePath/dump-*" &&
		[[ ! -e "$SandboxWorkspacePath/dump-01" ]] &&
		[[ ! -e "$SandboxWorkspacePath/dump-02" ]] &&
		[[ -e "$SandboxWorkspacePath/keep" ]]; then
	pass "Only matching workspace files were removed"
else
	fail "Workspace glob cleanup produced unexpected results"
fi

echo "Test 3: Shell syntax in a path is not executed"
sentinel="$TEST_ROOT/injected"
if sandbox_remove_workfile "$SandboxWorkspacePath/missing; touch $sentinel" &&
		[[ ! -e "$sentinel" ]]; then
	pass "Cleanup target was treated as data"
else
	fail "Cleanup target executed shell syntax"
fi

echo "Test 4: Parent-directory traversal is rejected"
outsideDirectory="$TEST_ROOT/outside"
mkdir -p "$outsideDirectory"
touch "$outsideDirectory/preserve"
if ! sandbox_remove_workfile "$SandboxWorkspacePath/../outside/*" &&
		[[ -e "$outsideDirectory/preserve" ]]; then
	pass "Parent-directory traversal was rejected"
else
	fail "Parent-directory traversal was not rejected"
fi

echo "Test 5: Symlink traversal is rejected"
ln -s "$outsideDirectory" "$SandboxWorkspacePath/outside-link"
if ! sandbox_remove_workfile "$SandboxWorkspacePath/outside-link/*" &&
		[[ -e "$outsideDirectory/preserve" ]]; then
	pass "Symlink traversal was rejected"
else
	fail "Symlink traversal was not rejected"
fi

echo
echo "=== Results: $PASS passed, $FAIL failed ==="

if (( FAIL > 0 )); then
	exit 1
fi
exit 0