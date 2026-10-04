#!/usr/bin/env bash
# Tests for .claude/commands/install-custom-commands-minimal.sh

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CMD="$REPO/.claude/commands/install-custom-commands-minimal.sh"

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

# Builds a PATH with every directory that contains a python3 executable stripped out,
# to simulate "python3 not installed" without touching the real PATH. Resolve bash's own
# absolute path first so the stripped PATH can never accidentally break bash's own lookup.
BASH_BIN=$(command -v bash)
strip_python3_from_path() {
    local dir result=""
    IFS=':' read -ra dirs <<< "$PATH"
    for dir in "${dirs[@]}"; do
        [[ -x "$dir/python3" ]] && continue
        result="${result:+$result:}$dir"
    done
    printf '%s' "$result"
}

printf 'Running install-custom-commands-minimal.sh tests...\n\n'

# --- Help ---
printf 'Help:\n'
cd /tmp
check "-h shows usage and exits 0 from any directory" 0 bash "$CMD" -h
check "--help shows usage and exits 0 from any directory" 0 bash "$CMD" --help
HELP_OUTPUT=$(bash "$CMD" -h)
printf '%s' "$HELP_OUTPUT" | grep -q 'Usage' && {
    printf '  PASS  -h shows usage text\n'; (( pass++ )) || true
} || {
    printf '  FAIL  -h did not show usage text\n'; (( fail++ )) || true
}
cd "$ORIG_DIR"

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
cd "$ORIG_DIR"

# --- Missing python3 ---
printf '\nMissing python3:\n'
cd "$REPO"
NO_PYTHON3_PATH=$(strip_python3_from_path)
TEMP_HOME_NOPY=$(mktemp -d)
trap 'cd "$ORIG_DIR"; rm -rf "$TEMP_HOME" "$TEMP_PROJECT" "$TEMP_HOME_NOPY"' EXIT
check "exits 1 when python3 is missing" 1 \
    env HOME="$TEMP_HOME_NOPY" PATH="$NO_PYTHON3_PATH" "$BASH_BIN" "$CMD"
STDERR=$(env HOME="$TEMP_HOME_NOPY" PATH="$NO_PYTHON3_PATH" "$BASH_BIN" "$CMD" 2>&1 1>/dev/null || true)
if printf '%s' "$STDERR" | grep -q 'python3 is required'; then
    printf '  PASS  clear python3-required error on stderr\n'; (( pass++ )) || true
else
    printf '  FAIL  expected stderr about python3, got: %s\n' "$STDERR"; (( fail++ )) || true
fi
cd "$ORIG_DIR"

# --- Invalid project path ---
printf '\nInvalid project path:\n'
cd "$REPO"
check "exits 1 for nonexistent project path" 1 bash "$CMD" "/nonexistent/$$"
cd "$ORIG_DIR"

# --- Global install ---
printf '\nGlobal install:\n'
cd "$REPO"
check "exits 0 for global install" 0 env HOME="$TEMP_HOME" bash "$CMD"

[[ -f "$TEMP_HOME/.claude/hooks/dispatch-commands.sh" ]] && {
    printf '  PASS  dispatch hook installed\n'; (( pass++ )) || true
} || {
    printf '  FAIL  dispatch hook missing\n'; (( fail++ )) || true
}
[[ ! -f "$TEMP_HOME/.claude/hooks/check-slash-conflict.sh" ]] && {
    printf '  PASS  conflict-check hook NOT installed (minimal install)\n'; (( pass++ )) || true
} || {
    printf '  FAIL  conflict-check hook was installed but should not be\n'; (( fail++ )) || true
}
[[ ! -d "$TEMP_HOME/.claude/skills" ]] && {
    printf '  PASS  no skills installed (minimal install)\n'; (( pass++ )) || true
} || {
    printf '  FAIL  skills were installed but should not be\n'; (( fail++ )) || true
}
[[ ! -f "$TEMP_HOME/.claude/constants/builtin-commands.txt" ]] && {
    printf '  PASS  no constants installed (minimal install)\n'; (( pass++ )) || true
} || {
    printf '  FAIL  constants were installed but should not be\n'; (( fail++ )) || true
}
[[ -d "$TEMP_HOME/.claude/commands" ]] && {
    printf '  PASS  empty commands directory created\n'; (( pass++ )) || true
} || {
    printf '  FAIL  commands directory not created\n'; (( fail++ )) || true
}
[[ -f "$TEMP_HOME/.claude/settings.json" ]] && grep -q 'UserPromptSubmit' "$TEMP_HOME/.claude/settings.json" && {
    printf '  PASS  dispatch hook registered in settings.json\n'; (( pass++ )) || true
} || {
    printf '  FAIL  dispatch hook not registered in settings.json\n'; (( fail++ )) || true
}
[[ -f "$TEMP_HOME/.claude/settings.json" ]] && ! grep -q 'PreToolUse' "$TEMP_HOME/.claude/settings.json" && {
    printf '  PASS  no PreToolUse hook registered (minimal install)\n'; (( pass++ )) || true
} || {
    printf '  FAIL  PreToolUse hook was registered but should not be\n'; (( fail++ )) || true
}
cd "$ORIG_DIR"

# --- Idempotent hook registration on reinstall ---
printf '\nReinstall (idempotent registration):\n'
cd "$REPO"
SETTINGS_BEFORE=$(cat "$TEMP_HOME/.claude/settings.json")
check "exits 0 on reinstall" 0 env HOME="$TEMP_HOME" bash "$CMD"
SETTINGS_AFTER=$(cat "$TEMP_HOME/.claude/settings.json")
if [[ "$SETTINGS_BEFORE" == "$SETTINGS_AFTER" ]]; then
    printf '  PASS  settings.json unchanged on reinstall\n'; (( pass++ )) || true
else
    printf '  FAIL  settings.json changed on reinstall\n'; (( fail++ )) || true
fi
cd "$ORIG_DIR"

# --- Project install ---
printf '\nProject install:\n'
TEMP_HOME2=$(mktemp -d)
trap 'cd "$ORIG_DIR"; rm -rf "$TEMP_HOME" "$TEMP_PROJECT" "$TEMP_HOME_NOPY" "$TEMP_HOME2"' EXIT
cd "$REPO"
check "exits 0 for project install" 0 env HOME="$TEMP_HOME2" bash "$CMD" "$TEMP_PROJECT"

[[ -f "$TEMP_PROJECT/.claude/hooks/dispatch-commands.sh" ]] && {
    printf '  PASS  dispatch hook installed to project dir\n'; (( pass++ )) || true
} || {
    printf '  FAIL  dispatch hook missing from project dir\n'; (( fail++ )) || true
}
[[ -f "$TEMP_PROJECT/.claude/settings.json" ]] && grep -q 'CLAUDE_PROJECT_DIR' "$TEMP_PROJECT/.claude/settings.json" && {
    printf '  PASS  hook registered in project settings.json with ${CLAUDE_PROJECT_DIR}\n'; (( pass++ )) || true
} || {
    printf '  FAIL  hook not registered correctly in project settings.json\n'; (( fail++ )) || true
}
[[ ! -d "$TEMP_HOME2/.claude" ]] && {
    printf '  PASS  global ~/.claude untouched\n'; (( pass++ )) || true
} || {
    printf '  FAIL  project install wrote to global ~/.claude\n'; (( fail++ )) || true
}
cd "$ORIG_DIR"

# --- README.md note handling ---
printf '\nREADME note handling:\n'
TEMP_HOME3=$(mktemp -d)
TEMP_PROJECT_NO_README=$(mktemp -d)
TEMP_PROJECT_WITH_README=$(mktemp -d)
TEMP_PROJECT_ALREADY_NOTED=$(mktemp -d)
trap 'cd "$ORIG_DIR"; rm -rf "$TEMP_HOME" "$TEMP_PROJECT" "$TEMP_HOME_NOPY" "$TEMP_HOME2" "$TEMP_HOME3" "$TEMP_PROJECT_NO_README" "$TEMP_PROJECT_WITH_README" "$TEMP_PROJECT_ALREADY_NOTED"' EXIT
cd "$REPO"

# No README.md — one is created with the note
check "exits 0 when project has no README" 0 env HOME="$TEMP_HOME3" bash "$CMD" "$TEMP_PROJECT_NO_README"
[[ -f "$TEMP_PROJECT_NO_README/README.md" ]] && grep -q 'claude-custom-commands' "$TEMP_PROJECT_NO_README/README.md" && {
    printf '  PASS  README.md created with custom commands note\n'; (( pass++ )) || true
} || {
    printf '  FAIL  README.md not created with note\n'; (( fail++ )) || true
}

# Existing README.md without the note — note is appended
printf '# My Project\n\nSome existing content.\n' > "$TEMP_PROJECT_WITH_README/README.md"
check "exits 0 when project has existing README" 0 env HOME="$TEMP_HOME3" bash "$CMD" "$TEMP_PROJECT_WITH_README"
README_CONTENT=$(cat "$TEMP_PROJECT_WITH_README/README.md")
if printf '%s' "$README_CONTENT" | grep -q 'Some existing content' && printf '%s' "$README_CONTENT" | grep -q 'claude-custom-commands'; then
    printf '  PASS  note appended to existing README, original content preserved\n'; (( pass++ )) || true
else
    printf '  FAIL  README append did not preserve original content and add note: %s\n' "$README_CONTENT"; (( fail++ )) || true
fi

# README.md already mentions the repo — skipped, not duplicated
printf '# My Project\n\nSee [custom commands](https://github.com/JescaLyn/claude-custom-commands).\n' \
    > "$TEMP_PROJECT_ALREADY_NOTED/README.md"
BEFORE_NOTED=$(cat "$TEMP_PROJECT_ALREADY_NOTED/README.md")
check "exits 0 when README already mentions the repo" 0 env HOME="$TEMP_HOME3" bash "$CMD" "$TEMP_PROJECT_ALREADY_NOTED"
AFTER_NOTED=$(cat "$TEMP_PROJECT_ALREADY_NOTED/README.md")
if [[ "$BEFORE_NOTED" == "$AFTER_NOTED" ]]; then
    printf '  PASS  README left unchanged when already mentioning the repo (no duplicate note)\n'; (( pass++ )) || true
else
    printf '  FAIL  README was modified even though it already mentioned the repo\n'; (( fail++ )) || true
fi
cd "$ORIG_DIR"

# --- Corrupt settings.json ---
printf '\nCorrupt settings.json:\n'
cd "$REPO"
TEMP_HOME_CORRUPT=$(mktemp -d)
trap 'cd "$ORIG_DIR"; rm -rf "$TEMP_HOME" "$TEMP_PROJECT" "$TEMP_HOME_NOPY" "$TEMP_HOME2" "$TEMP_HOME3" "$TEMP_PROJECT_NO_README" "$TEMP_PROJECT_WITH_README" "$TEMP_PROJECT_ALREADY_NOTED" "$TEMP_HOME_CORRUPT"' EXIT
mkdir -p "$TEMP_HOME_CORRUPT/.claude"
printf '{not valid json' > "$TEMP_HOME_CORRUPT/.claude/settings.json"

check "exits 1 when settings.json is corrupt" 1 env HOME="$TEMP_HOME_CORRUPT" bash "$CMD"

STDERR=$(env HOME="$TEMP_HOME_CORRUPT" bash "$CMD" 2>&1 1>/dev/null || true)
if printf '%s' "$STDERR" | grep -q 'not valid JSON'; then
    printf '  PASS  clear not-valid-JSON error on stderr\n'; (( pass++ )) || true
else
    printf '  FAIL  expected stderr about invalid JSON, got: %s\n' "$STDERR"; (( fail++ )) || true
fi

CORRUPT_AFTER=$(cat "$TEMP_HOME_CORRUPT/.claude/settings.json" 2>/dev/null || true)
if [[ "$CORRUPT_AFTER" == "{not valid json" ]]; then
    printf '  PASS  corrupt settings.json left untouched, not overwritten\n'; (( pass++ )) || true
else
    printf '  FAIL  corrupt settings.json was modified: %s\n' "$CORRUPT_AFTER"; (( fail++ )) || true
fi
cd "$ORIG_DIR"

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
