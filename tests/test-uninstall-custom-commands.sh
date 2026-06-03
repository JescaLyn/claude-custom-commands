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
TEMP_PROJECT=$(mktemp -d)
trap 'cd "$ORIG_DIR"; rm -rf "$TEMP_PROJECT"' EXIT

printf 'Running uninstall-custom-commands.sh tests...\n\n'

# --- Invalid project path ---
printf 'Invalid project path:\n'
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

# --- Project with no commands directory ---
printf '\nProject with no commands directory:\n'
EMPTY_PROJECT=$(mktemp -d)
trap 'cd "$ORIG_DIR"; rm -rf "$TEMP_PROJECT" "$EMPTY_PROJECT"' EXIT
check "exits 0 when project has no commands dir" 0 bash "$CMD" "$EMPTY_PROJECT"
OUTPUT=$(bash "$CMD" "$EMPTY_PROJECT" 2>&1 || true)
if printf '%s' "$OUTPUT" | grep -qi 'nothing to remove\|No commands'; then
    printf '  PASS  helpful message when nothing to remove\n'; (( pass++ )) || true
else
    printf '  FAIL  expected helpful message, got: %s\n' "$OUTPUT"; (( fail++ )) || true
fi

# --- Project with matching commands (hardcoded list) ---
printf '\nProject with matching commands:\n'
PROJECT_CMDS="$TEMP_PROJECT/.claude/commands"
mkdir -p "$PROJECT_CMDS"
# Repo-managed commands — must be removed
printf '#!/usr/bin/env bash\n' > "$PROJECT_CMDS/ping.sh"
printf 'ping\n'               > "$PROJECT_CMDS/ping.md"
printf '#!/usr/bin/env bash\n' > "$PROJECT_CMDS/now.sh"
# Non-repo command — must NOT be removed
printf '#!/usr/bin/env bash\n' > "$PROJECT_CMDS/my-custom.sh"

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

# --- Global uninstall (HOME override, run from /tmp — no repo dir needed) ---
printf '\nGlobal uninstall (from arbitrary directory):\n'
TEMP_HOME=$(mktemp -d)
trap 'cd "$ORIG_DIR"; rm -rf "$TEMP_PROJECT" "$EMPTY_PROJECT" "$TEMP_HOME"' EXIT

# Simulate a prior install
mkdir -p "$TEMP_HOME/.claude/hooks" "$TEMP_HOME/.claude/skills/create-command" \
         "$TEMP_HOME/.claude/skills/refresh-slash-names"
printf '#!/usr/bin/env bash\n' > "$TEMP_HOME/.claude/hooks/dispatch-commands.sh"
printf '#!/usr/bin/env bash\n' > "$TEMP_HOME/.claude/hooks/check-slash-conflict.sh"
printf '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"%s/.claude/hooks/dispatch-commands.sh"}]}]}}\n' \
    "$TEMP_HOME" > "$TEMP_HOME/.claude/settings.json"

cd /tmp
check "exits 0 for global uninstall from /tmp" 0 env HOME="$TEMP_HOME" bash "$CMD"

[[ ! -f "$TEMP_HOME/.claude/hooks/dispatch-commands.sh" ]] && {
    printf '  PASS  dispatch hook removed\n'; (( pass++ )) || true
} || {
    printf '  FAIL  dispatch hook still present\n'; (( fail++ )) || true
}
[[ ! -d "$TEMP_HOME/.claude/skills/create-command" ]] && {
    printf '  PASS  create-command skill removed\n'; (( pass++ )) || true
} || {
    printf '  FAIL  create-command skill still present\n'; (( fail++ )) || true
}
SETTINGS_CONTENT=$(cat "$TEMP_HOME/.claude/settings.json" 2>/dev/null || true)
if ! printf '%s' "$SETTINGS_CONTENT" | grep -q 'UserPromptSubmit'; then
    printf '  PASS  hook entry removed from settings.json\n'; (( pass++ )) || true
else
    printf '  FAIL  hook entry still in settings.json\n'; (( fail++ )) || true
fi
cd "$ORIG_DIR"

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
