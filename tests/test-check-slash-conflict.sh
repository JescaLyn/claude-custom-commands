#!/usr/bin/env bash
# Unit tests for .claude/hooks/check-slash-conflict.sh.
# Uses env vars to point at temp directories.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$REPO/.claude/hooks/check-slash-conflict.sh"
TEMP_COMMANDS=$(mktemp -d)
TEMP_SKILLS=$(mktemp -d)
TEMP_CONSTANTS=$(mktemp -d)

cp "$REPO/.claude/constants/builtin-commands.txt" "$TEMP_CONSTANTS/builtin-commands.txt"
cp "$REPO/.claude/constants/bundled-skills.txt" "$TEMP_CONSTANTS/bundled-skills.txt"

export CLAUDE_COMMANDS_DIR="$TEMP_COMMANDS"
export CLAUDE_SKILLS_DIR="$TEMP_SKILLS"
export CLAUDE_CONSTANTS_DIR="$TEMP_CONSTANTS"

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

printf 'Running check-slash-conflict.sh tests...\n\n'

# Clean name — no conflicts
check "exits 0 for clean name" 0 \
    bash "$CHECK" "my-cool-command"

# Built-in conflicts
check "exits 1 for built-in 'clear'" 1 \
    bash "$CHECK" "clear"

check "exits 1 for built-in 'help'" 1 \
    bash "$CHECK" "help"

check "exits 1 for built-in 'compact'" 1 \
    bash "$CHECK" "compact"

check_output "warns about built-in shadow" "WARNING" \
    bash -c "bash '$CHECK' clear || true"

check_output "warning mentions the command name" "clear" \
    bash -c "bash '$CHECK' clear || true"

# Bundled skill conflicts
check "exits 1 for bundled skill 'review'" 1 \
    bash "$CHECK" "review"

check "exits 1 for bundled skill 'init'" 1 \
    bash "$CHECK" "init"

check_output "warns about bundled skill shadow" "WARNING" \
    bash -c "bash '$CHECK' review || true"

# Installed skill conflicts
mkdir -p "$TEMP_SKILLS/my-skill"
check "exits 1 for name matching installed skill" 1 \
    bash "$CHECK" "my-skill"

check_output "warns about skill shadow" "WARNING" \
    bash -c "bash '$CHECK' my-skill || true"

check_output "warning mentions the skill name" "my-skill" \
    bash -c "bash '$CHECK' my-skill || true"

# No false positive for similar-but-different skill name
mkdir -p "$TEMP_SKILLS/my-other-skill"
check "exits 0 for name that is a prefix of a skill" 0 \
    bash "$CHECK" "my-other"

# Existing custom command conflict
touch "$TEMP_COMMANDS/existing-cmd.sh"
check "exits 1 for name matching existing custom command" 1 \
    bash "$CHECK" "existing-cmd"

check_output "warns about existing command" "WARNING" \
    bash -c "bash '$CHECK' existing-cmd || true"

# Missing argument
check "exits non-zero with no arguments" 1 \
    bash "$CHECK"

# Cleanup
rm -rf "$TEMP_COMMANDS" "$TEMP_SKILLS" "$TEMP_CONSTANTS"

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
