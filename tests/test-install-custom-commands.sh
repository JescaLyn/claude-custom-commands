#!/usr/bin/env bash
# Tests for .claude/commands/install-custom-commands.sh

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CMD="$REPO/.claude/commands/install-custom-commands.sh"

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

ORIG_DIR="$PWD"
TEMP_REPO=$(mktemp -d)
TEMP_PROJECT=$(mktemp -d)
trap 'cd "$ORIG_DIR"; rm -rf "$TEMP_REPO" "$TEMP_PROJECT"' EXIT

# Mock repo: install.sh that prints CLAUDE_COMMANDS_DIR and exits 0
cat > "$TEMP_REPO/install.sh" << 'MOCK'
#!/usr/bin/env bash
printf 'COMMANDS_DIR=%s\n' "${CLAUDE_COMMANDS_DIR:-unset}"
exit 0
MOCK
chmod +x "$TEMP_REPO/install.sh"
# Minimal .claude/commands/ so the project-path glob has something to iterate
mkdir -p "$TEMP_REPO/.claude/commands"
printf '#!/usr/bin/env bash\n' > "$TEMP_REPO/.claude/commands/ping.sh"

printf 'Running install-custom-commands.sh tests...\n\n'

# --- Wrong directory ---
printf 'Wrong directory:\n'
cd /tmp
check "exits 1 when no install.sh in CWD" 1 bash "$CMD"

STDERR=$(bash "$CMD" 2>&1 1>/dev/null || true)
if printf '%s' "$STDERR" | grep -q 'repo directory'; then
    printf '  PASS  error goes to stderr\n'; (( pass++ )) || true
else
    printf '  FAIL  expected stderr about repo directory, got: %s\n' "$STDERR"; (( fail++ )) || true
fi

STDOUT=$(bash "$CMD" 2>/dev/null || true)
if [[ -z "$STDOUT" ]]; then
    printf '  PASS  stdout is empty on error\n'; (( pass++ )) || true
else
    printf '  FAIL  stdout not empty on error: %s\n' "$STDOUT"; (( fail++ )) || true
fi
cd "$ORIG_DIR"

# --- Invalid project path ---
printf '\nInvalid project path:\n'
cd "$TEMP_REPO"
check "exits 1 for nonexistent project path" 1 bash "$CMD" "/nonexistent/$$"

STDERR=$(bash "$CMD" "/nonexistent/$$" 2>&1 1>/dev/null || true)
if printf '%s' "$STDERR" | grep -q 'not found'; then
    printf '  PASS  error goes to stderr\n'; (( pass++ )) || true
else
    printf '  FAIL  expected stderr "not found", got: %s\n' "$STDERR"; (( fail++ )) || true
fi

STDOUT=$(bash "$CMD" "/nonexistent/$$" 2>/dev/null || true)
if [[ -z "$STDOUT" ]]; then
    printf '  PASS  stdout is empty on error\n'; (( pass++ )) || true
else
    printf '  FAIL  stdout not empty on error: %s\n' "$STDOUT"; (( fail++ )) || true
fi
cd "$ORIG_DIR"

# --- Global install ---
printf '\nGlobal install:\n'
cd "$TEMP_REPO"
check "exits 0 for global install" 0 bash "$CMD"

OUTPUT=$(bash "$CMD" 2>&1 || true)
if printf '%s' "$OUTPUT" | grep -q 'COMMANDS_DIR=unset'; then
    printf '  PASS  global install calls install.sh without CLAUDE_COMMANDS_DIR\n'; (( pass++ )) || true
else
    printf '  FAIL  unexpected output: %s\n' "$OUTPUT"; (( fail++ )) || true
fi
cd "$ORIG_DIR"

# --- Project install ---
printf '\nProject install:\n'
cd "$TEMP_REPO"
check "exits 0 for project install" 0 bash "$CMD" "$TEMP_PROJECT"

OUTPUT=$(bash "$CMD" "$TEMP_PROJECT" 2>&1 || true)
EXPECTED="COMMANDS_DIR=$TEMP_PROJECT/.claude/commands"
if printf '%s' "$OUTPUT" | grep -qF "$EXPECTED"; then
    printf '  PASS  sets CLAUDE_COMMANDS_DIR to project/.claude/commands\n'; (( pass++ )) || true
else
    printf '  FAIL  expected "%s", got: %s\n' "$EXPECTED" "$OUTPUT"; (( fail++ )) || true
fi
cd "$ORIG_DIR"

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
