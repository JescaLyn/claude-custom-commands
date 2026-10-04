#!/usr/bin/env bash
# Tests for .claude/commands/commands-help.sh

set -euo pipefail

CMD="$(cd "$(dirname "$0")/.." && pwd)/.claude/commands/commands-help.sh"

pass=0; fail=0

check() {
    local desc="$1" expected_exit="$2"
    shift 2
    local actual_exit=0
    "$@" >/dev/null 2>/dev/null || actual_exit=$?
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

no_output() {
    local desc="$1" pattern="$2"
    shift 2
    local output
    output=$("$@" 2>&1 || true)
    if ! printf '%s' "$output" | grep -q "$pattern"; then
        printf '  PASS  %s\n' "$desc"
        (( pass++ )) || true
    else
        printf '  FAIL  %s  (did not expect "%s" in output, got: %s)\n' "$desc" "$pattern" "$output"
        (( fail++ )) || true
    fi
}

printf 'Running commands-help.sh tests...\n\n'

# --- Global only, no commands ---
printf 'Global only, empty:\n'
TEMP_HOME=$(mktemp -d)
mkdir -p "$TEMP_HOME/.claude/commands"

check "exits 0 with no commands" 0 env HOME="$TEMP_HOME" bash "$CMD"
check_output "shows global header" "Global commands" \
    env HOME="$TEMP_HOME" bash "$CMD"
check_output "shows 'No commands found' fallback" "No commands found" \
    env HOME="$TEMP_HOME" bash "$CMD"
no_output "no project header when no project dir" "Project commands" \
    env HOME="$TEMP_HOME" bash "$CMD"
rm -rf "$TEMP_HOME"

# --- Global only, with commands and descriptions ---
printf '\nGlobal only, with commands:\n'
TEMP_HOME=$(mktemp -d)
mkdir -p "$TEMP_HOME/.claude/commands"
printf '#!/usr/bin/env bash\n# description: Say hello\necho hi\n' > "$TEMP_HOME/.claude/commands/hello.sh"

check_output "lists command name" "/hello" \
    env HOME="$TEMP_HOME" bash "$CMD"
check_output "extracts description from '# description:' line" "Say hello" \
    env HOME="$TEMP_HOME" bash "$CMD"
no_output "does not show 'No commands found' when commands exist" "No commands found" \
    env HOME="$TEMP_HOME" bash "$CMD"
rm -rf "$TEMP_HOME"

# --- Name padding: short name (<=22 chars) stays on one line ---
printf '\nName padding — short name:\n'
TEMP_HOME=$(mktemp -d)
mkdir -p "$TEMP_HOME/.claude/commands"
printf '#!/usr/bin/env bash\n# description: Short one\necho hi\n' > "$TEMP_HOME/.claude/commands/short-name.sh"

OUTPUT=$(env HOME="$TEMP_HOME" bash "$CMD")
if printf '%s' "$OUTPUT" | grep -qE '^  /short-name +Short one$'; then
    printf '  PASS  short name padded to single line with description\n'; (( pass++ )) || true
else
    printf '  FAIL  short name not formatted as expected, got: %s\n' "$OUTPUT"; (( fail++ )) || true
fi
rm -rf "$TEMP_HOME"

# --- Name padding: long name (>22 chars) wraps description to its own line ---
printf '\nName padding — long name:\n'
TEMP_HOME=$(mktemp -d)
mkdir -p "$TEMP_HOME/.claude/commands"
LONG_NAME="a-very-long-command-name-here"
printf '#!/usr/bin/env bash\n# description: Wrapped description\necho hi\n' > "$TEMP_HOME/.claude/commands/$LONG_NAME.sh"

OUTPUT=$(env HOME="$TEMP_HOME" bash "$CMD")
if printf '%s' "$OUTPUT" | grep -qF "  /$LONG_NAME" && printf '%s' "$OUTPUT" | grep -q "Wrapped description"; then
    printf '  PASS  long name and description both present\n'; (( pass++ )) || true
else
    printf '  FAIL  long name output missing expected content, got: %s\n' "$OUTPUT"; (( fail++ )) || true
fi
# Description must appear on a line by itself (not appended directly after the name)
if ! printf '%s' "$OUTPUT" | grep -qF "$LONG_NAME Wrapped description"; then
    printf '  PASS  long name description wraps to its own line\n'; (( pass++ )) || true
else
    printf '  FAIL  long name description was appended inline instead of wrapping\n'; (( fail++ )) || true
fi
rm -rf "$TEMP_HOME"

# --- Project and global, different directories ---
printf '\nProject and global, both present:\n'
TEMP_HOME=$(mktemp -d)
TEMP_PROJECT=$(mktemp -d)
mkdir -p "$TEMP_HOME/.claude/commands" "$TEMP_PROJECT/.claude/commands"
printf '#!/usr/bin/env bash\n# description: Global one\necho hi\n' > "$TEMP_HOME/.claude/commands/global-cmd.sh"
printf '#!/usr/bin/env bash\n# description: Project one\necho hi\n' > "$TEMP_PROJECT/.claude/commands/project-cmd.sh"

check_output "shows project header" "Project commands" \
    env HOME="$TEMP_HOME" CLAUDE_PROJECT_DIR="$TEMP_PROJECT" bash "$CMD"
check_output "shows project command" "/project-cmd" \
    env HOME="$TEMP_HOME" CLAUDE_PROJECT_DIR="$TEMP_PROJECT" bash "$CMD"
check_output "shows global header too" "Global commands" \
    env HOME="$TEMP_HOME" CLAUDE_PROJECT_DIR="$TEMP_PROJECT" bash "$CMD"
check_output "shows global command too" "/global-cmd" \
    env HOME="$TEMP_HOME" CLAUDE_PROJECT_DIR="$TEMP_PROJECT" bash "$CMD"
rm -rf "$TEMP_HOME" "$TEMP_PROJECT"

# --- Dedup guard: project dir resolves to the same path as global dir ---
printf '\nDedup guard — project equals global:\n'
TEMP_HOME=$(mktemp -d)
mkdir -p "$TEMP_HOME/.claude/commands"
printf '#!/usr/bin/env bash\n# description: Only one\necho hi\n' > "$TEMP_HOME/.claude/commands/only-one.sh"

# CLAUDE_COMMANDS_DIR (used here as the project-dir override) pointed at the same path as
# $HOME/.claude/commands should not produce a duplicate "Project commands" section.
no_output "no duplicate project section when project dir equals global dir" "Project commands" \
    env HOME="$TEMP_HOME" CLAUDE_COMMANDS_DIR="$TEMP_HOME/.claude/commands" bash "$CMD"
check_output "command still listed once under global" "/only-one" \
    env HOME="$TEMP_HOME" CLAUDE_COMMANDS_DIR="$TEMP_HOME/.claude/commands" bash "$CMD"
rm -rf "$TEMP_HOME"

# --- Command with no description line ---
printf '\nCommand with no description:\n'
TEMP_HOME=$(mktemp -d)
mkdir -p "$TEMP_HOME/.claude/commands"
printf '#!/usr/bin/env bash\necho hi\n' > "$TEMP_HOME/.claude/commands/no-desc.sh"

check "exits 0 for command with no description" 0 env HOME="$TEMP_HOME" bash "$CMD"
check_output "lists command name even without description" "/no-desc" \
    env HOME="$TEMP_HOME" bash "$CMD"
rm -rf "$TEMP_HOME"

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
