#!/usr/bin/env bash
# Tests for .claude/commands/install-custom-commands.sh

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CMD="$REPO/.claude/commands/install-custom-commands.sh"
WRAPPER="$REPO/install.sh"

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

printf 'Running install-custom-commands.sh tests...\n\n'

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

# --- Missing python3 ---
printf 'Missing python3:\n'
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

# CLAUDE_PROJECT_DIR overrides PWD (real hook invocation scenario)
printf '\nCLAUDE_PROJECT_DIR override:\n'
check "exits 0 when CLAUDE_PROJECT_DIR points to repo and PWD is ~" 0 \
    bash -c "cd /tmp && CLAUDE_PROJECT_DIR='$REPO' HOME='$TEMP_HOME' bash '$CMD'"

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
[[ -f "$TEMP_HOME/.claude/commands/now.sh" ]] && {
    printf '  PASS  now.sh installed\n'; (( pass++ )) || true
} || {
    printf '  FAIL  now.sh missing\n'; (( fail++ )) || true
}
[[ ! -f "$TEMP_HOME/.claude/commands/install-custom-commands.sh" ]] && {
    printf '  PASS  install-custom-commands.sh not installed (repo-only)\n'; (( pass++ )) || true
} || {
    printf '  FAIL  install-custom-commands.sh was installed but should not be\n'; (( fail++ )) || true
}
[[ -d "$TEMP_HOME/.claude/skills/create-command" ]] && {
    printf '  PASS  skills installed\n'; (( pass++ )) || true
} || {
    printf '  FAIL  skills missing\n'; (( fail++ )) || true
}
[[ -f "$TEMP_HOME/.claude/skills/refresh-slash-names/write-slash-names.sh" ]] && {
    printf '  PASS  write-slash-names.sh installed with skill\n'; (( pass++ )) || true
} || {
    printf '  FAIL  write-slash-names.sh missing from skill\n'; (( fail++ )) || true
}
[[ -f "$TEMP_HOME/.claude/skills/create-command/create-command-preflight.sh" ]] && {
    printf '  PASS  create-command-preflight.sh installed with skill\n'; (( pass++ )) || true
} || {
    printf '  FAIL  create-command-preflight.sh missing from skill\n'; (( fail++ )) || true
}
[[ -f "$TEMP_HOME/.claude/settings.json" ]] && grep -q 'UserPromptSubmit' "$TEMP_HOME/.claude/settings.json" && {
    printf '  PASS  dispatch hook registered in settings.json\n'; (( pass++ )) || true
} || {
    printf '  FAIL  dispatch hook not registered in settings.json\n'; (( fail++ )) || true
}
[[ -f "$TEMP_HOME/.claude/settings.json" ]] && grep -q 'check-slash-conflict' "$TEMP_HOME/.claude/settings.json" && {
    printf '  PASS  conflict-check hook registered in settings.json\n'; (( pass++ )) || true
} || {
    printf '  FAIL  conflict-check hook not registered in settings.json\n'; (( fail++ )) || true
}
grep -q '\$HOME' "$TEMP_HOME/.claude/settings.json" 2>/dev/null && {
    printf '  PASS  hook path uses $HOME literal (not expanded)\n'; (( pass++ )) || true
} || {
    printf '  FAIL  hook path was expanded instead of using $HOME literal\n'; (( fail++ )) || true
}
[[ ! -f "$TEMP_HOME/.claude/commands/install-custom-commands-minimal.sh" ]] && {
    printf '  PASS  install-custom-commands-minimal.sh not installed (repo-only)\n'; (( pass++ )) || true
} || {
    printf '  FAIL  install-custom-commands-minimal.sh was installed but should not be\n'; (( fail++ )) || true
}
[[ ! -f "$TEMP_HOME/.claude/commands/install-custom-commands-minimal.md" ]] && {
    printf '  PASS  install-custom-commands-minimal.md stub not installed (repo-only)\n'; (( pass++ )) || true
} || {
    printf '  FAIL  install-custom-commands-minimal.md was installed but should not be\n'; (( fail++ )) || true
}
cd "$ORIG_DIR"

# --- Reinstall: skip-if-exists and idempotent hook registration ---
printf '\nReinstall (skip-if-exists, idempotent registration):\n'
cd "$REPO"
# Hand-edit an installed command and its stub to prove they are preserved on reinstall
printf '#!/usr/bin/env bash\necho "hand-edited"\n' > "$TEMP_HOME/.claude/commands/ping.sh"
printf 'Hand-edited stub\n' > "$TEMP_HOME/.claude/commands/ping.md"
SETTINGS_BEFORE=$(cat "$TEMP_HOME/.claude/settings.json")

check "exits 0 on reinstall over existing install" 0 env HOME="$TEMP_HOME" bash "$CMD"

PING_CONTENT=$(cat "$TEMP_HOME/.claude/commands/ping.sh")
if printf '%s' "$PING_CONTENT" | grep -q "hand-edited"; then
    printf '  PASS  existing command script skipped (not overwritten) on reinstall\n'; (( pass++ )) || true
else
    printf '  FAIL  existing command script was overwritten on reinstall\n'; (( fail++ )) || true
fi
PING_MD_CONTENT=$(cat "$TEMP_HOME/.claude/commands/ping.md")
if printf '%s' "$PING_MD_CONTENT" | grep -q "Hand-edited stub"; then
    printf '  PASS  existing .md stub skipped (not overwritten) on reinstall\n'; (( pass++ )) || true
else
    printf '  FAIL  existing .md stub was overwritten on reinstall\n'; (( fail++ )) || true
fi
SETTINGS_AFTER=$(cat "$TEMP_HOME/.claude/settings.json")
if [[ "$SETTINGS_BEFORE" == "$SETTINGS_AFTER" ]]; then
    printf '  PASS  settings.json unchanged on reinstall (hooks already registered)\n'; (( pass++ )) || true
else
    printf '  FAIL  settings.json changed on reinstall — hook registration is not idempotent\n'; (( fail++ )) || true
fi
UPSUBMIT_COUNT=$(grep -o 'UserPromptSubmit' "$TEMP_HOME/.claude/settings.json" | wc -l | tr -d ' ')
if [[ "$UPSUBMIT_COUNT" -eq 1 ]]; then
    printf '  PASS  dispatch hook registered exactly once after reinstall\n'; (( pass++ )) || true
else
    printf '  FAIL  expected exactly one UserPromptSubmit registration, found %s\n' "$UPSUBMIT_COUNT"; (( fail++ )) || true
fi
# Skill directories are always overwritten (cp -r, no existence check) — document that behavior
printf 'hand-edited skill content\n' >> "$TEMP_HOME/.claude/skills/create-command/SKILL.md"
env HOME="$TEMP_HOME" bash "$CMD" >/dev/null
if grep -q 'hand-edited skill content' "$TEMP_HOME/.claude/skills/create-command/SKILL.md" 2>/dev/null; then
    printf '  FAIL  skill file was NOT overwritten on reinstall (behavior changed — update README if intentional)\n'; (( fail++ )) || true
else
    printf '  PASS  skill directory is overwritten on reinstall (matches documented behavior)\n'; (( pass++ )) || true
fi
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
[[ -f "$TEMP_PROJECT/.claude/hooks/dispatch-commands.sh" ]] && {
    printf '  PASS  hooks installed to project dir\n'; (( pass++ )) || true
} || {
    printf '  FAIL  hooks missing from project dir\n'; (( fail++ )) || true
}
[[ -d "$TEMP_PROJECT/.claude/skills/create-command" ]] && {
    printf '  PASS  skills installed to project dir\n'; (( pass++ )) || true
} || {
    printf '  FAIL  skills missing from project dir\n'; (( fail++ )) || true
}
[[ -f "$TEMP_PROJECT/.claude/skills/refresh-slash-names/write-slash-names.sh" ]] && {
    printf '  PASS  write-slash-names.sh installed to project dir\n'; (( pass++ )) || true
} || {
    printf '  FAIL  write-slash-names.sh missing from project dir\n'; (( fail++ )) || true
}
[[ -f "$TEMP_PROJECT/.claude/skills/create-command/create-command-preflight.sh" ]] && {
    printf '  PASS  create-command-preflight.sh installed to project dir\n'; (( pass++ )) || true
} || {
    printf '  FAIL  create-command-preflight.sh missing from project dir\n'; (( fail++ )) || true
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

# --- Corrupt settings.json ---
printf '\nCorrupt settings.json:\n'
cd "$REPO"
TEMP_HOME_CORRUPT=$(mktemp -d)
trap 'cd "$ORIG_DIR"; rm -rf "$TEMP_HOME" "$TEMP_PROJECT" "$TEMP_HOME2" "$TEMP_HOME_NOPY" "$TEMP_HOME_CORRUPT"' EXIT
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

# --- Root wrapper (install.sh) delegates to install-custom-commands.sh ---
printf '\nRoot wrapper (install.sh):\n'
TEMP_HOME_WRAPPER=$(mktemp -d)
TEMP_PROJECT_WRAPPER=$(mktemp -d)
trap 'cd "$ORIG_DIR"; rm -rf "$TEMP_HOME" "$TEMP_PROJECT" "$TEMP_HOME2" "$TEMP_HOME_NOPY" "$TEMP_HOME_CORRUPT" "$TEMP_HOME_WRAPPER" "$TEMP_PROJECT_WRAPPER"' EXIT
cd "$REPO"
check "install.sh exits 0 for project install (args pass through)" 0 \
    env HOME="$TEMP_HOME_WRAPPER" bash "$WRAPPER" "$TEMP_PROJECT_WRAPPER"
[[ -f "$TEMP_PROJECT_WRAPPER/.claude/hooks/dispatch-commands.sh" ]] && {
    printf '  PASS  install.sh delegates and installs to project dir\n'; (( pass++ )) || true
} || {
    printf '  FAIL  install.sh did not install to project dir\n'; (( fail++ )) || true
}
cd "$ORIG_DIR"

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
