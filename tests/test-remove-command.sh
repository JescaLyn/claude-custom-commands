#!/usr/bin/env bash
# Unit tests for .claude/commands/remove-command.sh.
# Uses CLAUDE_COMMANDS_DIR and CLAUDE_CONSTANTS_DIR to point at temp directories.

set -euo pipefail

CMD="$(cd "$(dirname "$0")/.." && pwd)/.claude/commands/remove-command.sh"
TEMP_COMMANDS=$(mktemp -d)
TEMP_CONSTANTS=$(mktemp -d)

export CLAUDE_COMMANDS_DIR="$TEMP_COMMANDS"
export CLAUDE_CONSTANTS_DIR="$TEMP_CONSTANTS"

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

printf 'Running remove-command.sh tests...\n\n'

# No args — shows usage, exits 0
check "no args shows usage and exits 0" 0 \
    bash "$CMD"

check_output "usage shows command syntax" "Usage" \
    bash "$CMD"

# Command not installed
check "fails when command not installed" 1 \
    bash "$CMD" "ghost"

check_output "explains command not found" "not installed" \
    bash -c "bash '$CMD' 'ghost' || true"

# Invalid name
check "rejects name with path traversal" 1 \
    bash "$CMD" "../etc"

check_output "invalid name shows error" "Invalid" \
    bash -c "bash '$CMD' '../etc' || true"

# Install a real command to remove
printf '#!/usr/bin/env bash\necho "test"\n' > "$TEMP_COMMANDS/removable.sh"
printf 'Removable test command\n' > "$TEMP_COMMANDS/removable.md"
chmod +x "$TEMP_COMMANDS/removable.sh"

check "removes installed command, exits 0" 0 \
    bash "$CMD" "removable"

[[ ! -f "$TEMP_COMMANDS/removable.sh" ]] && {
    printf '  PASS  .sh file is gone after removal\n'; (( pass++ )) || true
} || {
    printf '  FAIL  .sh file still exists after removal\n'; (( fail++ )) || true
}

[[ ! -f "$TEMP_COMMANDS/removable.md" ]] && {
    printf '  PASS  .md stub is gone after removal\n'; (( pass++ )) || true
} || {
    printf '  FAIL  .md stub still exists after removal\n'; (( fail++ )) || true
}

# Already removed
check "fails when command already removed" 1 \
    bash "$CMD" "removable"

# Built-in protection
printf 'clear\nhelp\nmodel\n' > "$TEMP_CONSTANTS/builtin-commands.txt"
printf '' > "$TEMP_CONSTANTS/bundled-skills.txt"

check "refuses to remove a built-in command" 1 \
    bash "$CMD" "clear"

check_output "explains it is a built-in" "built-in" \
    bash -c "bash '$CMD' 'clear' || true"

# Bundled skill protection
printf 'review\n' > "$TEMP_CONSTANTS/bundled-skills.txt"

check "refuses to remove a bundled skill" 1 \
    bash "$CMD" "review"

check_output "explains it is a bundled skill" "skill" \
    bash -c "bash '$CMD' 'review' || true"

# Progressive lookup: project then global
printf '\nProgressive lookup:\n'

TEMP_HOME=$(mktemp -d)
TEMP_PROJ_DIR=$(mktemp -d)
mkdir -p "$TEMP_HOME/.claude/commands" "$TEMP_PROJ_DIR/.claude/commands"

# Global-only command: found via fallback when in a project session
printf '#!/usr/bin/env bash\necho hi\n' > "$TEMP_HOME/.claude/commands/glob-only.sh"
chmod +x "$TEMP_HOME/.claude/commands/glob-only.sh"

check "removes global command from project session" 0 \
    bash -c "HOME='$TEMP_HOME' CLAUDE_PROJECT_DIR='$TEMP_PROJ_DIR' CLAUDE_COMMANDS_DIR='' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CMD' glob-only"
[[ ! -f "$TEMP_HOME/.claude/commands/glob-only.sh" ]] && {
    printf '  PASS  global .sh gone after removal\n'; (( pass++ )) || true
} || {
    printf '  FAIL  global .sh still exists\n'; (( fail++ )) || true
}

# Command in both scopes: project takes priority
printf '#!/usr/bin/env bash\necho project\n' > "$TEMP_PROJ_DIR/.claude/commands/both.sh"
printf '#!/usr/bin/env bash\necho global\n'  > "$TEMP_HOME/.claude/commands/both.sh"
chmod +x "$TEMP_PROJ_DIR/.claude/commands/both.sh" "$TEMP_HOME/.claude/commands/both.sh"

check "removes project copy when command exists in both scopes" 0 \
    bash -c "HOME='$TEMP_HOME' CLAUDE_PROJECT_DIR='$TEMP_PROJ_DIR' CLAUDE_COMMANDS_DIR='' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CMD' both"
[[ ! -f "$TEMP_PROJ_DIR/.claude/commands/both.sh" ]] && {
    printf '  PASS  project copy removed\n'; (( pass++ )) || true
} || {
    printf '  FAIL  project copy still exists\n'; (( fail++ )) || true
}
[[ -f "$TEMP_HOME/.claude/commands/both.sh" ]] && {
    printf '  PASS  global copy preserved\n'; (( pass++ )) || true
} || {
    printf '  FAIL  global copy was incorrectly removed\n'; (( fail++ )) || true
}

# Not found in either scope: error mentions both dirs
check_output "not found in project session mentions both dirs" "or" \
    bash -c "HOME='$TEMP_HOME' CLAUDE_PROJECT_DIR='$TEMP_PROJ_DIR' CLAUDE_COMMANDS_DIR='' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CMD' notfound || true"

# Explicit project path: only looks in that path, no fallback
printf '\nExplicit project path:\n'

printf '#!/usr/bin/env bash\necho proj-explicit\n' > "$TEMP_PROJ_DIR/.claude/commands/proj-explicit.sh"
printf '#!/usr/bin/env bash\necho global-only\n'  > "$TEMP_HOME/.claude/commands/global-only2.sh"
chmod +x "$TEMP_PROJ_DIR/.claude/commands/proj-explicit.sh" "$TEMP_HOME/.claude/commands/global-only2.sh"

check "explicit project path removes from that project" 0 \
    bash -c "HOME='$TEMP_HOME' CLAUDE_COMMANDS_DIR='' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CMD' proj-explicit '$TEMP_PROJ_DIR'"
[[ ! -f "$TEMP_PROJ_DIR/.claude/commands/proj-explicit.sh" ]] && {
    printf '  PASS  project copy removed with explicit path\n'; (( pass++ )) || true
} || {
    printf '  FAIL  project copy still exists\n'; (( fail++ )) || true
}

check "explicit path does not fall back to global" 1 \
    bash -c "HOME='$TEMP_HOME' CLAUDE_COMMANDS_DIR='' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CMD' global-only2 '$TEMP_PROJ_DIR'"
[[ -f "$TEMP_HOME/.claude/commands/global-only2.sh" ]] && {
    printf '  PASS  global copy preserved when explicit path used\n'; (( pass++ )) || true
} || {
    printf '  FAIL  global copy incorrectly removed\n'; (( fail++ )) || true
}

check_output "explicit path not-found names the given dir" "not installed" \
    bash -c "HOME='$TEMP_HOME' CLAUDE_COMMANDS_DIR='' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CMD' global-only2 '$TEMP_PROJ_DIR' || true"

rm -rf "$TEMP_HOME" "$TEMP_PROJ_DIR"

# Tilde expansion in project path
printf '\nTilde expansion:\n'
TEMP_TILDE_HOME=$(mktemp -d)
mkdir -p "$TEMP_TILDE_HOME/myproject/.claude/commands"
printf '#!/usr/bin/env bash\necho tilde\n' > "$TEMP_TILDE_HOME/myproject/.claude/commands/tilde-cmd.sh"
chmod +x "$TEMP_TILDE_HOME/myproject/.claude/commands/tilde-cmd.sh"

check "tilde-prefixed project path removes correctly" 0 \
    bash -c "HOME='$TEMP_TILDE_HOME' CLAUDE_COMMANDS_DIR='' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CMD' tilde-cmd '~/myproject'"
[[ ! -f "$TEMP_TILDE_HOME/myproject/.claude/commands/tilde-cmd.sh" ]] && {
    printf '  PASS  tilde path resolved and command removed\n'; (( pass++ )) || true
} || {
    printf '  FAIL  tilde path did not resolve correctly\n'; (( fail++ )) || true
}

rm -rf "$TEMP_TILDE_HOME"

# CLAUDE_COMMANDS_DIR test override takes precedence over a project-path positional argument
printf '\nCLAUDE_COMMANDS_DIR overrides project-path argument:\n'
TEMP_OVERRIDE_CMDS=$(mktemp -d)
TEMP_OVERRIDE_PROJ=$(mktemp -d)
mkdir -p "$TEMP_OVERRIDE_PROJ/.claude/commands"
printf '#!/usr/bin/env bash\necho override\n' > "$TEMP_OVERRIDE_CMDS/override-test.sh"
printf '#!/usr/bin/env bash\necho project\n' > "$TEMP_OVERRIDE_PROJ/.claude/commands/override-test.sh"

check "CLAUDE_COMMANDS_DIR wins when both override and project-path are given" 0 \
    bash -c "CLAUDE_COMMANDS_DIR='$TEMP_OVERRIDE_CMDS' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CMD' override-test '$TEMP_OVERRIDE_PROJ'"
[[ ! -f "$TEMP_OVERRIDE_CMDS/override-test.sh" ]] && {
    printf '  PASS  override-scope copy removed\n'; (( pass++ )) || true
} || {
    printf '  FAIL  override-scope copy still exists\n'; (( fail++ )) || true
}
[[ -f "$TEMP_OVERRIDE_PROJ/.claude/commands/override-test.sh" ]] && {
    printf '  PASS  project-path copy untouched (override took precedence)\n'; (( pass++ )) || true
} || {
    printf '  FAIL  project-path copy was incorrectly removed\n'; (( fail++ )) || true
}
rm -rf "$TEMP_OVERRIDE_CMDS" "$TEMP_OVERRIDE_PROJ"

# Cleanup
rm -rf "$TEMP_COMMANDS" "$TEMP_CONSTANTS"

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
