#!/usr/bin/env bash
# Integration test: exercises the full create → dispatch → remove → dispatch lifecycle.
# Uses create-command-from-script.sh, dispatch-commands.sh, and remove-command.sh
# end-to-end with a temp commands directory.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DISPATCH="$REPO/.claude/hooks/dispatch-commands.sh"
CREATE="$REPO/.claude/commands/create-command-from-script.sh"
REMOVE="$REPO/.claude/commands/remove-command.sh"
SAMPLE="$REPO/tests/sample-hello.sh"

TEMP_COMMANDS=$(mktemp -d)
export CLAUDE_COMMANDS_DIR="$TEMP_COMMANDS"
trap 'rm -rf "$TEMP_COMMANDS"' EXIT

pass=0; fail=0

check() {
    local desc="$1" expected_exit="$2"
    shift 2
    local actual_exit=0
    "$@" 2>&1 || actual_exit=$?
    if [[ $actual_exit -eq $expected_exit ]]; then
        printf '  PASS  %s\n' "$desc"
        (( pass++ )) || true
    else
        printf '  FAIL  %s  (expected exit %d, got %d)\n' "$desc" "$expected_exit" "$actual_exit"
        (( fail++ )) || true
    fi
}

check_output() {
    local desc="$1" pattern="$2"
    shift 2
    local output
    output=$("$@" 2>&1 || true)
    if printf '%s' "$output" | grep -q "$pattern"; then
        printf '  PASS  %s\n' "$desc"
        (( pass++ )) || true
    else
        printf '  FAIL  %s  (expected "%s" in output, got: %s)\n' "$desc" "$pattern" "$output"
        (( fail++ )) || true
    fi
}

printf 'Running integration tests...\n\n'

# --- Create ---
printf 'Create:\n'

check "registers sample-hello as /int-hello" 0 \
    bash "$CREATE" "int-hello" "$SAMPLE"

[[ -f "$TEMP_COMMANDS/int-hello.sh" ]] && {
    printf '  PASS  .sh file exists\n'; (( pass++ )) || true
} || {
    printf '  FAIL  .sh file missing\n'; (( fail++ )) || true
}

[[ -f "$TEMP_COMMANDS/int-hello.md" ]] && {
    printf '  PASS  .md stub exists\n'; (( pass++ )) || true
} || {
    printf '  FAIL  .md stub missing\n'; (( fail++ )) || true
}

# --- Dispatch (registered) ---
printf '\nDispatch (registered):\n'

check_output "blocks /int-hello" '"block"' \
    bash -c "printf '{\"prompt\":\"/int-hello\"}' | bash '$DISPATCH'"

check_output "output contains Hello, world!" 'Hello, world' \
    bash -c "printf '{\"prompt\":\"/int-hello\"}' | bash '$DISPATCH'"

# --- Remove ---
printf '\nRemove:\n'

check "removes /int-hello" 0 \
    bash "$REMOVE" "int-hello"

[[ ! -f "$TEMP_COMMANDS/int-hello.sh" ]] && {
    printf '  PASS  .sh file gone\n'; (( pass++ )) || true
} || {
    printf '  FAIL  .sh file still present\n'; (( fail++ )) || true
}

[[ ! -f "$TEMP_COMMANDS/int-hello.md" ]] && {
    printf '  PASS  .md stub gone\n'; (( pass++ )) || true
} || {
    printf '  FAIL  .md stub still present\n'; (( fail++ )) || true
}

# --- Dispatch (after removal) ---
printf '\nDispatch (after removal):\n'

AFTER=$(printf '{"prompt":"/int-hello"}' | bash "$DISPATCH" 2>&1 || true)
if printf '%s' "$AFTER" | grep -qF '"block"'; then
    printf '  FAIL  dispatch still blocking /int-hello after removal\n'; (( fail++ )) || true
else
    printf '  PASS  dispatch passes through /int-hello after removal\n'; (( pass++ )) || true
fi

# --- Dispatch (built-in commands, through the real dispatcher) ---
# Regression coverage for the commands-help.sh exit-code bug: that bug only showed up
# through the dispatcher (as "Command /commands-help failed"), never when calling the
# script directly, so this exercises the actual path a user hits.
printf '\nDispatch (built-in commands):\n'

for builtin_cmd in ping now commands-help; do
    RESULT=$(printf '{"prompt":"/%s"}' "$builtin_cmd" | \
        CLAUDE_COMMANDS_DIR="$REPO/.claude/commands" bash "$DISPATCH" 2>&1)

    if printf '%s' "$RESULT" | grep -qF '"block"'; then
        printf '  PASS  /%s dispatches\n' "$builtin_cmd"; (( pass++ )) || true
    else
        printf '  FAIL  /%s did not dispatch: %s\n' "$builtin_cmd" "$RESULT"; (( fail++ )) || true
    fi

    if printf '%s' "$RESULT" | grep -qi 'failed'; then
        printf '  FAIL  /%s reported as failed by the dispatcher: %s\n' "$builtin_cmd" "$RESULT"; (( fail++ )) || true
    else
        printf '  PASS  /%s not reported as failed\n' "$builtin_cmd"; (( pass++ )) || true
    fi
done

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
