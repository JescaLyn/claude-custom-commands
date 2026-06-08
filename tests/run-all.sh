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

run_suite test-dispatch.sh
run_suite test-check-slash-conflict.sh
run_suite test-create-command-from-script.sh
run_suite test-remove-command.sh
run_suite test-install-custom-commands.sh
run_suite test-uninstall-custom-commands.sh
run_suite test-integration.sh

printf '\nSuites: %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
