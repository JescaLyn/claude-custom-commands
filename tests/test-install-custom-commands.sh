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
TEMP_HOME=$(mktemp -d)
TEMP_PROJECT=$(mktemp -d)
trap 'cd "$ORIG_DIR"; rm -rf "$TEMP_HOME" "$TEMP_PROJECT"' EXIT

printf 'Running install-custom-commands.sh tests...\n\n'

# --- Wrong directory ---
printf 'Wrong directory:\n'
cd /tmp
check "exits 1 when not in repo dir" 1 bash "$CMD"

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
cd "$REPO"
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
cd "$REPO"
check "exits 0 for global install" 0 env HOME="$TEMP_HOME" bash "$CMD"

[[ -f "$TEMP_HOME/.claude/hooks/dispatch-commands.sh" ]] && {
    printf '  PASS  hook script installed\n'; (( pass++ )) || true
} || {
    printf '  FAIL  hook script missing\n'; (( fail++ )) || true
}
[[ -f "$TEMP_HOME/.claude/commands/ping.sh" ]] && {
    printf '  PASS  commands installed\n'; (( pass++ )) || true
} || {
    printf '  FAIL  commands missing\n'; (( fail++ )) || true
}
[[ -d "$TEMP_HOME/.claude/skills/create-command" ]] && {
    printf '  PASS  skills installed\n'; (( pass++ )) || true
} || {
    printf '  FAIL  skills missing\n'; (( fail++ )) || true
}
[[ -f "$TEMP_HOME/.claude/settings.json" ]] && grep -q 'UserPromptSubmit' "$TEMP_HOME/.claude/settings.json" && {
    printf '  PASS  hook registered in settings.json\n'; (( pass++ )) || true
} || {
    printf '  FAIL  hook not registered in settings.json\n'; (( fail++ )) || true
}
cd "$ORIG_DIR"

# --- Project install ---
printf '\nProject install:\n'
TEMP_HOME2=$(mktemp -d)
trap 'cd "$ORIG_DIR"; rm -rf "$TEMP_HOME" "$TEMP_PROJECT" "$TEMP_HOME2"' EXIT
cd "$REPO"
check "exits 0 for project install" 0 env HOME="$TEMP_HOME2" bash "$CMD" "$TEMP_PROJECT"

[[ -f "$TEMP_PROJECT/.claude/commands/ping.sh" ]] && {
    printf '  PASS  commands installed to project dir\n'; (( pass++ )) || true
} || {
    printf '  FAIL  commands missing from project dir\n'; (( fail++ )) || true
}
[[ -f "$TEMP_PROJECT/.claude/commands/create-command-from-script.sh" ]] && {
    printf '  PASS  create-command-from-script.sh in project dir\n'; (( pass++ )) || true
} || {
    printf '  FAIL  create-command-from-script.sh missing from project dir\n'; (( fail++ )) || true
}
[[ -f "$TEMP_PROJECT/.claude/commands/remove-command.sh" ]] && {
    printf '  PASS  remove-command.sh in project dir\n'; (( pass++ )) || true
} || {
    printf '  FAIL  remove-command.sh missing from project dir\n'; (( fail++ )) || true
}
[[ ! -f "$TEMP_HOME2/.claude/commands/ping.sh" ]] && {
    printf '  PASS  commands not duplicated in global dir\n'; (( pass++ )) || true
} || {
    printf '  FAIL  commands incorrectly placed in global dir\n'; (( fail++ )) || true
}
[[ -f "$TEMP_HOME2/.claude/hooks/dispatch-commands.sh" ]] && {
    printf '  PASS  hooks always go to global dir\n'; (( pass++ )) || true
} || {
    printf '  FAIL  hooks missing from global dir\n'; (( fail++ )) || true
}
[[ -d "$TEMP_HOME2/.claude/skills/create-command" ]] && {
    printf '  PASS  skills always go to global dir\n'; (( pass++ )) || true
} || {
    printf '  FAIL  skills missing from global dir\n'; (( fail++ )) || true
}
cd "$ORIG_DIR"

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
