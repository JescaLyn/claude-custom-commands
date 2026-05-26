#!/usr/bin/env bash
# Unit tests for .claude/commands/remove-command.sh.
# Uses CLAUDE_COMMANDS_DIR and CLAUDE_CONSTANTS_DIR to point at temp directories.

set -euo pipefail

CMD="$(cd "$(dirname "$0")/.." && pwd)/.claude/commands/remove-command.sh"
TEMP_COMMANDS=$(mktemp -d)
TEMP_CONSTANTS=$(mktemp -d)

export CLAUDE_COMMANDS_DIR="$TEMP_COMMANDS"
export CLAUDE_CONSTANTS_DIR="$TEMP_CONSTANTS"

pass=0; fail=0

check() {
    local desc="$1" expected_exit="$2"
    shift 2
    local actual_exit=0
    "$@" 2>/dev/null || actual_exit=$?
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

printf 'Running remove-command.sh tests...\n\n'

# No args — shows usage, exits 0
check "no args shows usage and exits 0" 0 \
    bash "$CMD"

check_output "usage shows command syntax" "Usage" \
    bash "$CMD"

# Command not installed
check "fails when command not installed" 1 \
    bash "$CMD" "ghost"

check_output "explains command not found" "not installed" \
    bash -c "bash '$CMD' 'ghost' || true"

# Invalid name
check "rejects name with path traversal" 1 \
    bash "$CMD" "../etc"

check_output "invalid name shows error" "Invalid" \
    bash -c "bash '$CMD' '../etc' || true"

# Install a real command to remove
printf '#!/usr/bin/env bash\necho "test"\n' > "$TEMP_COMMANDS/removable.sh"
printf 'Removable test command\n' > "$TEMP_COMMANDS/removable.md"
chmod +x "$TEMP_COMMANDS/removable.sh"

check "removes installed command, exits 0" 0 \
    bash "$CMD" "removable"

[[ ! -f "$TEMP_COMMANDS/removable.sh" ]] && {
    printf '  PASS  .sh file is gone after removal\n'; (( pass++ )) || true
} || {
    printf '  FAIL  .sh file still exists after removal\n'; (( fail++ )) || true
}

[[ ! -f "$TEMP_COMMANDS/removable.md" ]] && {
    printf '  PASS  .md stub is gone after removal\n'; (( pass++ )) || true
} || {
    printf '  FAIL  .md stub still exists after removal\n'; (( fail++ )) || true
}

# Already removed
check "fails when command already removed" 1 \
    bash "$CMD" "removable"

# Built-in protection
printf 'clear\nhelp\nmodel\n' > "$TEMP_CONSTANTS/builtin-commands.txt"
printf '' > "$TEMP_CONSTANTS/bundled-skills.txt"

check "refuses to remove a built-in command" 1 \
    bash "$CMD" "clear"

check_output "explains it is a built-in" "built-in" \
    bash -c "bash '$CMD' 'clear' || true"

# Bundled skill protection
printf 'review\n' > "$TEMP_CONSTANTS/bundled-skills.txt"

check "refuses to remove a bundled skill" 1 \
    bash "$CMD" "review"

check_output "explains it is a bundled skill" "skill" \
    bash -c "bash '$CMD' 'review' || true"

# Cleanup
rm -rf "$TEMP_COMMANDS" "$TEMP_CONSTANTS"

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
