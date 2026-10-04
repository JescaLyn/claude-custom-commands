#!/usr/bin/env bash
# Runs shellcheck across the repo the same way CI does, so a shellcheck
# regression shows up locally via run-all.sh instead of only in CI.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0

printf 'Running shellcheck...\n\n'

if ! command -v shellcheck &>/dev/null; then
    printf '  SKIP  shellcheck not installed locally -- CI runs it separately; install via your package manager to check locally (e.g. brew install shellcheck)\n'
    printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
    exit 0
fi

cd "$REPO"
set +e
OUTPUT=$(find . -name '*.sh' -not -path './.git/*' -print0 | xargs -0 shellcheck 2>&1)
EC=$?
set -e

if [[ $EC -eq 0 ]]; then
    printf '  PASS  shellcheck clean across all .sh files\n'; (( pass++ )) || true
else
    printf '  FAIL  shellcheck found issues:\n'
    printf '%s\n' "$OUTPUT" | sed 's/^/    /'
    (( fail++ )) || true
fi

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
