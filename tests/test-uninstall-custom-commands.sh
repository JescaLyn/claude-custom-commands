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

# --- Project with nothing installed ---
printf '\nProject with nothing installed:\n'
EMPTY_PROJECT=$(mktemp -d)
trap 'cd "$ORIG_DIR"; rm -rf "$TEMP_PROJECT" "$EMPTY_PROJECT"' EXIT
check "exits 0 when project has nothing installed" 0 bash "$CMD" "$EMPTY_PROJECT"

# --- Project uninstall: commands, hooks, skills, settings ---
printf '\nProject uninstall:\n'
PROJECT_CMDS="$TEMP_PROJECT/.claude/commands"
PROJECT_HOOKS="$TEMP_PROJECT/.claude/hooks"
PROJECT_SKILLS="$TEMP_PROJECT/.claude/skills"
PROJECT_CONSTANTS="$TEMP_PROJECT/.claude/constants"
mkdir -p "$PROJECT_CMDS" "$PROJECT_HOOKS" "$PROJECT_SKILLS/create-command" "$PROJECT_CONSTANTS"
# Repo-managed commands — must be removed
printf '#!/usr/bin/env bash\n' > "$PROJECT_CMDS/ping.sh"
printf 'ping\n'               > "$PROJECT_CMDS/ping.md"
# Non-repo command — must NOT be removed
printf '#!/usr/bin/env bash\n' > "$PROJECT_CMDS/my-custom.sh"
# Repo-installed hooks, skills, and constants
printf '#!/usr/bin/env bash\n' > "$PROJECT_HOOKS/dispatch-commands.sh"
printf '#!/usr/bin/env bash\n' > "$PROJECT_HOOKS/check-slash-conflict.sh"
printf 'name: create-command\n' > "$PROJECT_SKILLS/create-command/SKILL.md"
printf 'clear\n' > "$PROJECT_CONSTANTS/builtin-commands.txt"
printf 'review\n' > "$PROJECT_CONSTANTS/bundled-skills.txt"
# settings.json with both hook entries
printf '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"${CLAUDE_PROJECT_DIR}/.claude/hooks/dispatch-commands.sh"}]}],"PreToolUse":[{"matcher":"Write","hooks":[{"type":"command","command":"${CLAUDE_PROJECT_DIR}/.claude/hooks/check-slash-conflict.sh"}]}]}}\n' \
    > "$TEMP_PROJECT/.claude/settings.json"

check "exits 0 for project uninstall" 0 bash "$CMD" "$TEMP_PROJECT"

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
[[ -f "$PROJECT_CMDS/my-custom.sh" ]] && {
    printf '  PASS  non-repo command preserved\n'; (( pass++ )) || true
} || {
    printf '  FAIL  non-repo command was incorrectly removed\n'; (( fail++ )) || true
}
[[ ! -f "$PROJECT_HOOKS/dispatch-commands.sh" ]] && {
    printf '  PASS  dispatch hook removed from project\n'; (( pass++ )) || true
} || {
    printf '  FAIL  dispatch hook still present in project\n'; (( fail++ )) || true
}
[[ ! -d "$PROJECT_SKILLS/create-command" ]] && {
    printf '  PASS  create-command skill removed from project\n'; (( pass++ )) || true
} || {
    printf '  FAIL  create-command skill still present in project\n'; (( fail++ )) || true
}
[[ ! -f "$PROJECT_CONSTANTS/builtin-commands.txt" ]] && {
    printf '  PASS  builtin-commands.txt removed from project\n'; (( pass++ )) || true
} || {
    printf '  FAIL  builtin-commands.txt still present in project\n'; (( fail++ )) || true
}
PROJ_SETTINGS_CONTENT=$(cat "$TEMP_PROJECT/.claude/settings.json" 2>/dev/null || true)
if ! printf '%s' "$PROJ_SETTINGS_CONTENT" | grep -q 'UserPromptSubmit'; then
    printf '  PASS  dispatch hook entry removed from project settings.json\n'; (( pass++ )) || true
else
    printf '  FAIL  dispatch hook entry still in project settings.json\n'; (( fail++ )) || true
fi
if ! printf '%s' "$PROJ_SETTINGS_CONTENT" | grep -q 'check-slash-conflict'; then
    printf '  PASS  conflict-check hook entry removed from project settings.json\n'; (( pass++ )) || true
else
    printf '  FAIL  conflict-check hook entry still in project settings.json\n'; (( fail++ )) || true
fi

# --- Global uninstall (HOME override, run from /tmp — no repo dir needed) ---
printf '\nGlobal uninstall (from arbitrary directory):\n'
TEMP_HOME=$(mktemp -d)
trap 'cd "$ORIG_DIR"; rm -rf "$TEMP_PROJECT" "$EMPTY_PROJECT" "$TEMP_HOME"' EXIT

# Simulate a prior install
mkdir -p "$TEMP_HOME/.claude/hooks" "$TEMP_HOME/.claude/commands" \
         "$TEMP_HOME/.claude/constants" \
         "$TEMP_HOME/.claude/skills/create-command" \
         "$TEMP_HOME/.claude/skills/refresh-slash-names"
printf '#!/usr/bin/env bash\n' > "$TEMP_HOME/.claude/hooks/dispatch-commands.sh"
printf '#!/usr/bin/env bash\n' > "$TEMP_HOME/.claude/hooks/check-slash-conflict.sh"
printf '#!/usr/bin/env bash\n' > "$TEMP_HOME/.claude/commands/ping.sh"
printf 'clear\n' > "$TEMP_HOME/.claude/constants/builtin-commands.txt"
printf 'review\n' > "$TEMP_HOME/.claude/constants/bundled-skills.txt"
# User's own command — must NOT be removed
printf '#!/usr/bin/env bash\n' > "$TEMP_HOME/.claude/commands/my-custom.sh"
printf '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"$HOME/.claude/hooks/dispatch-commands.sh"}]}],"PreToolUse":[{"matcher":"Write","hooks":[{"type":"command","command":"$HOME/.claude/hooks/check-slash-conflict.sh"}]}]}}\n' \
    > "$TEMP_HOME/.claude/settings.json"

cd /tmp
check "exits 0 for global uninstall from /tmp" 0 env HOME="$TEMP_HOME" bash "$CMD"

[[ ! -f "$TEMP_HOME/.claude/hooks/dispatch-commands.sh" ]] && {
    printf '  PASS  dispatch hook removed\n'; (( pass++ )) || true
} || {
    printf '  FAIL  dispatch hook still present\n'; (( fail++ )) || true
}
[[ ! -f "$TEMP_HOME/.claude/commands/ping.sh" ]] && {
    printf '  PASS  ping.sh removed from global commands\n'; (( pass++ )) || true
} || {
    printf '  FAIL  ping.sh still present in global commands\n'; (( fail++ )) || true
}
[[ -f "$TEMP_HOME/.claude/commands/my-custom.sh" ]] && {
    printf '  PASS  non-repo global command preserved\n'; (( pass++ )) || true
} || {
    printf '  FAIL  non-repo global command was incorrectly removed\n'; (( fail++ )) || true
}
[[ ! -f "$TEMP_HOME/.claude/constants/builtin-commands.txt" ]] && {
    printf '  PASS  builtin-commands.txt removed\n'; (( pass++ )) || true
} || {
    printf '  FAIL  builtin-commands.txt still present\n'; (( fail++ )) || true
}
[[ ! -d "$TEMP_HOME/.claude/skills/create-command" ]] && {
    printf '  PASS  create-command skill removed\n'; (( pass++ )) || true
} || {
    printf '  FAIL  create-command skill still present\n'; (( fail++ )) || true
}
SETTINGS_CONTENT=$(cat "$TEMP_HOME/.claude/settings.json" 2>/dev/null || true)
if ! printf '%s' "$SETTINGS_CONTENT" | grep -q 'UserPromptSubmit'; then
    printf '  PASS  dispatch hook entry removed from settings.json\n'; (( pass++ )) || true
else
    printf '  FAIL  dispatch hook entry still in settings.json\n'; (( fail++ )) || true
fi
if ! printf '%s' "$SETTINGS_CONTENT" | grep -q 'check-slash-conflict'; then
    printf '  PASS  conflict-check hook entry removed from settings.json\n'; (( pass++ )) || true
else
    printf '  FAIL  conflict-check hook entry still in settings.json\n'; (( fail++ )) || true
fi

# Settings.json with $HOME literal (as written by install-custom-commands.sh) — must also be removed
TEMP_HOME2=$(mktemp -d)
trap 'cd "$ORIG_DIR"; rm -rf "$TEMP_PROJECT" "$EMPTY_PROJECT" "$TEMP_HOME" "$TEMP_HOME2"' EXIT
mkdir -p "$TEMP_HOME2/.claude/hooks"
printf '#!/usr/bin/env bash\n' > "$TEMP_HOME2/.claude/hooks/dispatch-commands.sh"
printf '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"$HOME/.claude/hooks/dispatch-commands.sh"}]}]}}\n' \
    > "$TEMP_HOME2/.claude/settings.json"
env HOME="$TEMP_HOME2" bash "$CMD" >/dev/null 2>&1 || true
SETTINGS2_CONTENT=$(cat "$TEMP_HOME2/.claude/settings.json" 2>/dev/null || true)
if ! printf '%s' "$SETTINGS2_CONTENT" | grep -q 'UserPromptSubmit'; then
    printf '  PASS  hook entry removed when stored as $HOME literal\n'; (( pass++ )) || true
else
    printf '  FAIL  hook entry not removed when stored as $HOME literal\n'; (( fail++ )) || true
fi

cd "$ORIG_DIR"

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
