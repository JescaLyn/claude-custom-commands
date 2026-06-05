#!/usr/bin/env bash
# Unit tests for .claude/commands/create-command-from-script.sh.
# Uses CLAUDE_COMMANDS_DIR to point at a temp directory.

set -euo pipefail

CMD="$(cd "$(dirname "$0")/.." && pwd)/.claude/commands/create-command-from-script.sh"
TEMP_DIR=$(mktemp -d)
TEMP_COMMANDS=$(mktemp -d)

export CLAUDE_COMMANDS_DIR="$TEMP_COMMANDS"

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

printf 'Running create-command-from-script.sh tests...\n\n'

# Missing args — shows usage, exits 0
check "no args shows usage and exits 0" 0 \
    bash "$CMD"

check "one arg shows usage and exits 0" 0 \
    bash "$CMD" "only-name"

check_output "usage shows command syntax" "Usage" \
    bash "$CMD"

check_output "usage mentions --force flag" "force" \
    bash "$CMD"

# Invalid name
check "rejects name starting with digit" 1 \
    bash "$CMD" "1bad" "/dev/null"

check_output "invalid name shows error" "Invalid" \
    bash -c "bash '$CMD' '1bad' /dev/null || true"

# Make a real script to register
REAL_SCRIPT=$(mktemp "$TEMP_DIR/script-XXXX.sh")
printf '#!/usr/bin/env bash\necho "hello from copied script"\n' > "$REAL_SCRIPT"
chmod +x "$REAL_SCRIPT"

check "registers script under given name" 0 \
    bash "$CMD" "from-file" "$REAL_SCRIPT"

check_output "reports the created command name" "report-check" \
    bash -c "bash '$CMD' 'report-check' '$REAL_SCRIPT'"

[[ -f "$TEMP_COMMANDS/from-file.sh" ]] && {
    printf '  PASS  registered file exists on disk\n'; (( pass++ )) || true
} || {
    printf '  FAIL  registered file not found\n'; (( fail++ )) || true
}

[[ -x "$TEMP_COMMANDS/from-file.sh" ]] && {
    printf '  PASS  registered file is executable\n'; (( pass++ )) || true
} || {
    printf '  FAIL  registered file is not executable\n'; (( fail++ )) || true
}

[[ -f "$TEMP_COMMANDS/from-file.md" ]] && {
    printf '  PASS  autocomplete stub created\n'; (( pass++ )) || true
} || {
    printf '  FAIL  autocomplete stub not created\n'; (( fail++ )) || true
}

COPIED_CONTENT=$(cat "$TEMP_COMMANDS/from-file.sh" 2>/dev/null || true)
if printf '%s' "$COPIED_CONTENT" | grep -q "hello from copied script"; then
    printf '  PASS  registered file content matches source\n'; (( pass++ )) || true
else
    printf '  FAIL  registered file content does not match source\n'; (( fail++ )) || true
fi

# Duplicate name — should fail
check "refuses to overwrite existing command" 1 \
    bash "$CMD" "from-file" "$REAL_SCRIPT"

check_output "explains why it refused" "already exists" \
    bash -c "bash '$CMD' 'from-file' '$REAL_SCRIPT' || true"

# Non-existent script path
check "fails when script path does not exist" 1 \
    bash "$CMD" "phantom" "/nonexistent/path/script.sh"

# Conflict check — uses a stub via CLAUDE_CHECK_SLASH_SCRIPT
STUB_CHECK=$(mktemp "$TEMP_DIR/check-XXXX.sh")
printf '#!/usr/bin/env bash\nprintf "WARNING: conflict detected for %%s\\n" "$1"\nexit 1\n' > "$STUB_CHECK"
chmod +x "$STUB_CHECK"

check "conflict blocks command creation" 1 \
    bash -c "CLAUDE_CHECK_SLASH_SCRIPT='$STUB_CHECK' bash '$CMD' 'blocked-cmd' '$REAL_SCRIPT'"

check_output "conflict shows warning" "WARNING" \
    bash -c "CLAUDE_CHECK_SLASH_SCRIPT='$STUB_CHECK' bash '$CMD' 'blocked-cmd' '$REAL_SCRIPT' || true"

check_output "conflict shows --force instructions" "force" \
    bash -c "CLAUDE_CHECK_SLASH_SCRIPT='$STUB_CHECK' bash '$CMD' 'blocked-cmd' '$REAL_SCRIPT' || true"

[[ ! -f "$TEMP_COMMANDS/blocked-cmd.sh" ]] && {
    printf '  PASS  command not created when conflict blocks\n'; (( pass++ )) || true
} || {
    printf '  FAIL  command was created despite conflict\n'; (( fail++ )) || true
}

# --force bypasses conflict check and creates anyway
check "--force creates command despite conflict" 0 \
    bash -c "CLAUDE_CHECK_SLASH_SCRIPT='$STUB_CHECK' bash '$CMD' --force 'forced-cmd' '$REAL_SCRIPT'"

[[ -f "$TEMP_COMMANDS/forced-cmd.sh" ]] && {
    printf '  PASS  command created with --force despite conflict\n'; (( pass++ )) || true
} || {
    printf '  FAIL  command not created with --force\n'; (( fail++ )) || true
}

# Cleanup
rm -rf "$TEMP_DIR" "$TEMP_COMMANDS"

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
