#!/usr/bin/env bash
# Runs tests/run-all.sh multiple times to catch non-deterministic failures
# (e.g. a SIGPIPE race from piping a live command into `grep -q`) that a
# single run has decent odds of missing entirely.
#
# Usage: run-repeated.sh [count]   (default: 3)
#
# Not invoked by run-all.sh itself -- it wraps run-all.sh, so including it in
# run-all.sh's own suite list would recurse.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
COUNT="${1:-3}"

printf 'Running tests/run-all.sh %d times to check for flakiness...\n' "$COUNT"

FIRST_RESULT=""
FIRST_EC=""
INCONSISTENT=0

for (( i = 1; i <= COUNT; i++ )); do
    printf '\n--- Run %d/%d ---\n' "$i" "$COUNT"
    OUTPUT=$(bash "$REPO/tests/run-all.sh" 2>&1)
    EC=$?
    RESULT_LINE=$(printf '%s' "$OUTPUT" | grep '^Suites:' || true)
    printf '%s (exit %d)\n' "$RESULT_LINE" "$EC"

    if [[ -z "$FIRST_RESULT" ]]; then
        FIRST_RESULT="$RESULT_LINE"
        FIRST_EC="$EC"
    elif [[ "$RESULT_LINE" != "$FIRST_RESULT" || "$EC" != "$FIRST_EC" ]]; then
        INCONSISTENT=1
        printf '  Differs from run 1 (%s, exit %d) -- possible flaky test. Full output:\n' "$FIRST_RESULT" "$FIRST_EC"
        printf '%s\n' "$OUTPUT" | sed 's/^/    /'
    fi
done

if [[ "$INCONSISTENT" -eq 1 ]]; then
    printf '\nFLAKY: results differed across %d runs.\n' "$COUNT"
    exit 1
else
    printf '\nSTABLE: all %d runs produced %s (exit %d).\n' "$COUNT" "$FIRST_RESULT" "$FIRST_EC"
fi
