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

check_output "usage mentions project-path option" "project" \
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

# Scope: global by default, project via positional path or --project flag
printf '\nScope:\n'
TEMP_HOME_SCOPE=$(mktemp -d)
PROJ_DIR_SCOPE=$(mktemp -d)
mkdir -p "$PROJ_DIR_SCOPE/.claude"
SCOPE_SCRIPT=$(mktemp "$TEMP_DIR/scope-XXXX.sh")
printf '#!/usr/bin/env bash\necho "scope test"\n' > "$SCOPE_SCRIPT"
chmod +x "$SCOPE_SCRIPT"

check "default (no path) installs globally" 0 \
    bash -c "HOME='$TEMP_HOME_SCOPE' CLAUDE_COMMANDS_DIR='' bash '$CMD' 'default-global' '$SCOPE_SCRIPT'"

[[ -f "$TEMP_HOME_SCOPE/.claude/commands/default-global.sh" ]] && {
    printf '  PASS  installed to global home dir\n'; (( pass++ )) || true
} || {
    printf '  FAIL  not installed to global home dir\n'; (( fail++ )) || true
}

check "positional project path installs to project" 0 \
    bash -c "HOME='$TEMP_HOME_SCOPE' CLAUDE_COMMANDS_DIR='' bash '$CMD' 'proj-cmd' '$SCOPE_SCRIPT' '$PROJ_DIR_SCOPE'"

[[ -f "$PROJ_DIR_SCOPE/.claude/commands/proj-cmd.sh" ]] && {
    printf '  PASS  installed to project dir\n'; (( pass++ )) || true
} || {
    printf '  FAIL  not installed to project dir\n'; (( fail++ )) || true
}

[[ ! -f "$TEMP_HOME_SCOPE/.claude/commands/proj-cmd.sh" ]] && {
    printf '  PASS  not installed to global dir\n'; (( pass++ )) || true
} || {
    printf '  FAIL  incorrectly installed to global dir\n'; (( fail++ )) || true
}

check "--project flag installs to project" 0 \
    bash -c "HOME='$TEMP_HOME_SCOPE' CLAUDE_COMMANDS_DIR='' bash '$CMD' 'flag-cmd' '$SCOPE_SCRIPT' --project '$PROJ_DIR_SCOPE'"

[[ -f "$PROJ_DIR_SCOPE/.claude/commands/flag-cmd.sh" ]] && {
    printf '  PASS  --project flag installed to project dir\n'; (( pass++ )) || true
} || {
    printf '  FAIL  --project flag did not install to project dir\n'; (( fail++ )) || true
}

rm -rf "$TEMP_HOME_SCOPE" "$PROJ_DIR_SCOPE"

# Flag alternatives: --name and --script
printf '\nFlag alternatives:\n'

check "--name flag sets command name" 0 \
    bash "$CMD" --name "flag-named" "$REAL_SCRIPT"

[[ -f "$TEMP_COMMANDS/flag-named.sh" ]] && {
    printf '  PASS  --name flag installed under correct name\n'; (( pass++ )) || true
} || {
    printf '  FAIL  --name flag did not install\n'; (( fail++ )) || true
}

check "--name and --script flags work together" 0 \
    bash "$CMD" --name "flag-both" --script "$REAL_SCRIPT"

[[ -f "$TEMP_COMMANDS/flag-both.sh" ]] && {
    printf '  PASS  --name and --script flags installed correctly\n'; (( pass++ )) || true
} || {
    printf '  FAIL  --name and --script flags did not install\n'; (( fail++ )) || true
}

check "unknown flag exits 1" 1 \
    bash "$CMD" "--unknown-flag" "foo" "$REAL_SCRIPT"

# Tilde expansion in project path
printf '\nTilde expansion:\n'
TEMP_TILDE_HOME=$(mktemp -d)
mkdir -p "$TEMP_TILDE_HOME/myproject/.claude"

check "tilde-prefixed project path installs correctly" 0 \
    bash -c "HOME='$TEMP_TILDE_HOME' CLAUDE_COMMANDS_DIR='' bash '$CMD' 'tilde-install' '$REAL_SCRIPT' '~/myproject'"
[[ -f "$TEMP_TILDE_HOME/myproject/.claude/commands/tilde-install.sh" ]] && {
    printf '  PASS  tilde path resolved and command installed\n'; (( pass++ )) || true
} || {
    printf '  FAIL  tilde path did not resolve correctly\n'; (( fail++ )) || true
}

rm -rf "$TEMP_TILDE_HOME"

# Cleanup
rm -rf "$TEMP_DIR" "$TEMP_COMMANDS"

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
