#!/usr/bin/env bash
# Unit tests for .claude/hooks/dispatch-commands.sh.
# Uses CLAUDE_COMMANDS_DIR to point at a temp directory.

set -euo pipefail

DISPATCH="$(cd "$(dirname "$0")/.." && pwd)/.claude/hooks/dispatch-commands.sh"
TEMP_DIR=$(mktemp -d)
export CLAUDE_COMMANDS_DIR="$TEMP_DIR"

pass=0; fail=0

check() {
    local desc="$1" expected_exit="$2"
    shift 2
    local actual_exit=0
    "$@" >/dev/null 2>/dev/null || actual_exit=$?
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

printf 'Running dispatch.sh tests...\n\n'

# Pass-through: regular prose
check "passes through regular prompt" 0 \
    bash -c "printf '{\"prompt\":\"hello world\"}' | bash '$DISPATCH'"

# Pass-through: unknown slash command (no script registered)
check "passes through unregistered /command" 0 \
    bash -c "printf '{\"prompt\":\"/unknown-xyz\"}' | bash '$DISPATCH'"

# Pass-through: empty prompt
check "passes through empty prompt" 0 \
    bash -c "printf '{\"prompt\":\"\"}' | bash '$DISPATCH'"

# Pass-through: malformed JSON (python3 parse fails, should not error)
check "passes through malformed JSON" 0 \
    bash -c "printf 'not json' | bash '$DISPATCH'"

# Pass-through: slash-only (/) is not a valid command
check "passes through bare slash" 0 \
    bash -c "printf '{\"prompt\":\"/\"}' | bash '$DISPATCH'"

# Register /ping and verify block decision is returned
cat > "$TEMP_DIR/ping.sh" << 'EOF'
#!/usr/bin/env bash
echo "pong"
EOF

check_output "outputs block decision for registered /ping" '"decision"' \
    bash -c "printf '{\"prompt\":\"/ping\"}' | bash '$DISPATCH'"

check_output "block decision value is block" '"block"' \
    bash -c "printf '{\"prompt\":\"/ping\"}' | bash '$DISPATCH'"

check_output "command output appears in reason" 'pong' \
    bash -c "printf '{\"prompt\":\"/ping\"}' | bash '$DISPATCH'"

# Command with arguments
cat > "$TEMP_DIR/echo-args.sh" << 'EOF'
#!/usr/bin/env bash
printf 'args: %s\n' "$*"
EOF

check_output "outputs block decision for /echo-args with args" '"block"' \
    bash -c "printf '{\"prompt\":\"/echo-args foo bar\"}' | bash '$DISPATCH'"

check_output "arguments are passed to command" 'args: foo bar' \
    bash -c "printf '{\"prompt\":\"/echo-args foo bar\"}' | bash '$DISPATCH'"

# Failed command: still returns block decision, error in reason
cat > "$TEMP_DIR/fail-cmd.sh" << 'EOF'
#!/usr/bin/env bash
echo "something went wrong"
exit 1
EOF

check_output "outputs block decision even when command script fails" '"block"' \
    bash -c "printf '{\"prompt\":\"/fail-cmd\"}' | bash '$DISPATCH'"

check_output "failed command output appears in reason" 'failed' \
    bash -c "printf '{\"prompt\":\"/fail-cmd\"}' | bash '$DISPATCH'"

# Pass-through: name collision with built-in format (e.g. /clear — no script, passes through)
check "passes through /clear when no clear.sh exists" 0 \
    bash -c "printf '{\"prompt\":\"/clear\"}' | bash '$DISPATCH'"

# Cleanup
rm -rf "$TEMP_DIR"

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
