#!/usr/bin/env bash
# Run all test suites.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0

run_suite() {
    local name="$1"
    printf '\n=== %s ===\n' "$name"
    if bash "$REPO/tests/$name"; then
        (( pass++ )) || true
    else
        (( fail++ )) || true
    fi
}

# Snapshot top-level mktemp dirs before running, to catch a suite that creates a
# temp directory and forgets to include it in its cleanup trap (a leak, not a
# correctness failure, so no individual assertion would otherwise catch it).
TMP_CHECK_DIR="${TMPDIR:-/tmp}"
BEFORE_TMP=$(find "$TMP_CHECK_DIR" -maxdepth 1 -name 'tmp.*' 2>/dev/null | sort)

run_suite test-shellcheck.sh
run_suite test-dispatch.sh
run_suite test-check-slash-conflict.sh
run_suite test-create-command-from-script.sh
run_suite test-remove-command.sh
run_suite test-commands-help.sh
run_suite test-install-custom-commands.sh
run_suite test-install-custom-commands-minimal.sh
run_suite test-uninstall-custom-commands.sh
run_suite test-write-slash-names.sh
run_suite test-create-command-preflight.sh
run_suite test-integration.sh

printf '\n=== tmp leak check ===\n'
AFTER_TMP=$(find "$TMP_CHECK_DIR" -maxdepth 1 -name 'tmp.*' 2>/dev/null | sort)
LEAKED=$(comm -13 <(printf '%s\n' "$BEFORE_TMP") <(printf '%s\n' "$AFTER_TMP") 2>/dev/null || true)
if [[ -z "$LEAKED" ]]; then
    printf '  PASS  no leftover temp directories in %s\n' "$TMP_CHECK_DIR"
    (( pass++ )) || true
else
    printf '  FAIL  leftover temp directories (a suite above did not clean one up):\n'
    printf '%s\n' "$LEAKED" | sed 's/^/    /'
    (( fail++ )) || true
fi

printf '\nSuites: %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
