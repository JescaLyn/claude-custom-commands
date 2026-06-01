#!/usr/bin/env bash
# Tests for .claude/commands/uninstall-custom-commands.sh

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CMD="$REPO/.claude/commands/uninstall-custom-commands.sh"

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

# Mock repo: uninstall.sh that prints a marker and exits 0
cat > "$TEMP_REPO/uninstall.sh" << 'MOCK'
#!/usr/bin/env bash
printf 'mock-uninstall-ran\n'
exit 0
MOCK
chmod +x "$TEMP_REPO/uninstall.sh"
mkdir -p "$TEMP_REPO/.claude/commands"
printf '#!/usr/bin/env bash\n' > "$TEMP_REPO/.claude/commands/ping.sh"
printf 'ping\n'               > "$TEMP_REPO/.claude/commands/ping.md"
printf '#!/usr/bin/env bash\n' > "$TEMP_REPO/.claude/commands/now.sh"

printf 'Running uninstall-custom-commands.sh tests...\n\n'

# --- Wrong directory ---
printf 'Wrong directory:\n'
cd /tmp
check "exits 1 when no uninstall.sh in CWD" 1 bash "$CMD"

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

# --- Project with no commands directory ---
printf '\nProject with no commands directory:\n'
EMPTY_PROJECT=$(mktemp -d)
trap 'cd "$ORIG_DIR"; rm -rf "$TEMP_REPO" "$TEMP_PROJECT" "$EMPTY_PROJECT"' EXIT
cd "$TEMP_REPO"
check "exits 0 when project has no commands dir" 0 bash "$CMD" "$EMPTY_PROJECT"
OUTPUT=$(bash "$CMD" "$EMPTY_PROJECT" 2>&1 || true)
if printf '%s' "$OUTPUT" | grep -qi 'nothing to remove\|No commands'; then
    printf '  PASS  helpful message when nothing to remove\n'; (( pass++ )) || true
else
    printf '  FAIL  expected helpful message, got: %s\n' "$OUTPUT"; (( fail++ )) || true
fi
cd "$ORIG_DIR"

# --- Project with matching commands ---
printf '\nProject with matching commands:\n'
PROJECT_CMDS="$TEMP_PROJECT/.claude/commands"
mkdir -p "$PROJECT_CMDS"
cp "$TEMP_REPO/.claude/commands/ping.sh" "$PROJECT_CMDS/ping.sh"
cp "$TEMP_REPO/.claude/commands/ping.md" "$PROJECT_CMDS/ping.md"
cp "$TEMP_REPO/.claude/commands/now.sh"  "$PROJECT_CMDS/now.sh"
# Non-repo command — must NOT be removed
printf '#!/usr/bin/env bash\n' > "$PROJECT_CMDS/my-custom.sh"

cd "$TEMP_REPO"
check "exits 0 removing matching commands" 0 bash "$CMD" "$TEMP_PROJECT"

[[ ! -f "$PROJECT_CMDS/ping.sh" ]] && {
    printf '  PASS  ping.sh removed\n'; (( pass++ )) || true
} || {
    printf '  FAIL  ping.sh still present\n'; (( fail++ )) || true
}
[[ ! -f "$PROJECT_CMDS/ping.md" ]] && {
    printf '  PASS  ping.md removed\n'; (( pass++ )) || true
} || {
    printf '  FAIL  ping.md still present\n'; (( fail++ )) || true
}
[[ ! -f "$PROJECT_CMDS/now.sh" ]] && {
    printf '  PASS  now.sh removed\n'; (( pass++ )) || true
} || {
    printf '  FAIL  now.sh still present\n'; (( fail++ )) || true
}
[[ -f "$PROJECT_CMDS/my-custom.sh" ]] && {
    printf '  PASS  non-repo command preserved\n'; (( pass++ )) || true
} || {
    printf '  FAIL  non-repo command was incorrectly removed\n'; (( fail++ )) || true
}
cd "$ORIG_DIR"

# --- Global uninstall ---
printf '\nGlobal uninstall:\n'
cd "$TEMP_REPO"
check "exits 0 for global uninstall" 0 bash "$CMD"
OUTPUT=$(bash "$CMD" 2>&1 || true)
if printf '%s' "$OUTPUT" | grep -q 'mock-uninstall-ran'; then
    printf '  PASS  global uninstall delegates to uninstall.sh\n'; (( pass++ )) || true
else
    printf '  FAIL  unexpected output: %s\n' "$OUTPUT"; (( fail++ )) || true
fi
cd "$ORIG_DIR"

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
