#!/usr/bin/env bash
# Unit tests for .claude/hooks/check-slash-conflict.sh.
# Uses env vars to point at temp directories.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$REPO/.claude/hooks/check-slash-conflict.sh"
TEMP_COMMANDS=$(mktemp -d)
TEMP_SKILLS=$(mktemp -d)
TEMP_CONSTANTS=$(mktemp -d)

cp "$REPO/.claude/constants/builtin-commands.txt" "$TEMP_CONSTANTS/builtin-commands.txt"
cp "$REPO/.claude/constants/bundled-skills.txt" "$TEMP_CONSTANTS/bundled-skills.txt"

export CLAUDE_COMMANDS_DIR="$TEMP_COMMANDS"
export CLAUDE_SKILLS_DIR="$TEMP_SKILLS"
export CLAUDE_CONSTANTS_DIR="$TEMP_CONSTANTS"

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

printf 'Running check-slash-conflict.sh tests...\n\n'

# Clean name — no conflicts
check "exits 0 for clean name" 0 \
    bash "$CHECK" "my-cool-command"

# Built-in conflicts
check "exits 1 for built-in 'clear'" 1 \
    bash "$CHECK" "clear"

check "exits 1 for built-in 'help'" 1 \
    bash "$CHECK" "help"

check "exits 1 for built-in 'compact'" 1 \
    bash "$CHECK" "compact"

check_output "warns about built-in shadow" "WARNING" \
    bash -c "bash '$CHECK' clear || true"

check_output "warning mentions the command name" "clear" \
    bash -c "bash '$CHECK' clear || true"

# Bundled skill conflicts
check "exits 1 for bundled skill 'review'" 1 \
    bash "$CHECK" "review"

check "exits 1 for bundled skill 'init'" 1 \
    bash "$CHECK" "init"

check_output "warns about bundled skill shadow" "WARNING" \
    bash -c "bash '$CHECK' review || true"

# Installed skill conflicts
mkdir -p "$TEMP_SKILLS/my-skill"
check "exits 1 for name matching installed skill" 1 \
    bash "$CHECK" "my-skill"

check_output "warns about skill shadow" "WARNING" \
    bash -c "bash '$CHECK' my-skill || true"

check_output "warning mentions the skill name" "my-skill" \
    bash -c "bash '$CHECK' my-skill || true"

# No false positive for similar-but-different skill name
mkdir -p "$TEMP_SKILLS/my-other-skill"
check "exits 0 for name that is a prefix of a skill" 0 \
    bash "$CHECK" "my-other"

# Existing custom command conflict
touch "$TEMP_COMMANDS/existing-cmd.sh"
check "exits 1 for name matching existing custom command" 1 \
    bash "$CHECK" "existing-cmd"

check_output "warns about existing command" "WARNING" \
    bash -c "bash '$CHECK' existing-cmd || true"

# --- Hook mode ---
printf '\nHook mode:\n'

TEMP_HOME=$(mktemp -d)
trap 'rm -rf "$TEMP_COMMANDS" "$TEMP_SKILLS" "$TEMP_CONSTANTS" "$TEMP_HOME"' EXIT
# Hook mode derives paths from HOME; unset scope overrides so there's no bleed from direct mode tests
unset CLAUDE_COMMANDS_DIR CLAUDE_SKILLS_DIR CLAUDE_CONSTANTS_DIR

write_json() {
    local tool="$1" file_path="$2" session="${3:-test-session}"
    printf '{"tool_name":"%s","tool_input":{"file_path":"%s","content":""},"session_id":"%s"}' \
        "$tool" "$file_path" "$session"
}

# Non-Write tool — silent pass
check "non-Write tool exits 0" 0 \
    bash -c "printf '%s' '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo hi\"}}' | bash '$CHECK'"

# Write to unrelated path — silent pass
check "Write to unrelated path exits 0" 0 \
    bash -c "printf '%s' '$(write_json Write /tmp/foo.sh)' | HOME='$TEMP_HOME' bash '$CHECK'"

# Write new command, clean name — pass
check "Write new command, clean name exits 0" 0 \
    bash -c "printf '%s' '$(write_json Write "$TEMP_HOME/.claude/commands/deploy.md")' | HOME='$TEMP_HOME' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK'"

# Write new command, built-in conflict — block (exit 2)
check "Write new command, built-in conflict exits 2" 2 \
    bash -c "printf '%s' '$(write_json Write "$TEMP_HOME/.claude/commands/clear.md")' | HOME='$TEMP_HOME' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK'"

check_output "hook block message mentions conflict" "conflict" \
    bash -c "printf '%s' '$(write_json Write "$TEMP_HOME/.claude/commands/clear.md")' | HOME='$TEMP_HOME' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' 2>&1 || true"

check_output "hook block message includes approval instructions" "touch" \
    bash -c "printf '%s' '$(write_json Write "$TEMP_HOME/.claude/commands/clear.md")' | HOME='$TEMP_HOME' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' 2>&1 || true"

# Write to existing file — skip (not a new creation)
mkdir -p "$TEMP_HOME/.claude/commands"
touch "$TEMP_HOME/.claude/commands/existing.md"
check "Write to existing command file exits 0" 0 \
    bash -c "printf '%s' '$(write_json Write "$TEMP_HOME/.claude/commands/existing.md")' | HOME='$TEMP_HOME' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK'"

# Write new skill, clean name — pass
check "Write new skill, clean name exits 0" 0 \
    bash -c "printf '%s' '$(write_json Write "$TEMP_HOME/.claude/skills/my-skill/SKILL.md")' | HOME='$TEMP_HOME' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK'"

# Write new skill, bundled skill conflict — informational warning (exits 2 so message surfaces, but auto-approvable)
check "Write new skill, bundled skill conflict exits 2" 2 \
    bash -c "printf '%s' '$(write_json Write "$TEMP_HOME/.claude/skills/review/SKILL.md")' | HOME='$TEMP_HOME' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK'"

check_output "skill bundled conflict shows note not conflict header" "note" \
    bash -c "printf '%s' '$(write_json Write "$TEMP_HOME/.claude/skills/review/SKILL.md")' | HOME='$TEMP_HOME' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' 2>&1 || true"

# Write new skill, existing custom command conflict — blocked with user confirmation required
mkdir -p "$TEMP_HOME/.claude/commands"
printf '#!/usr/bin/env bash\n' > "$TEMP_HOME/.claude/commands/deploy.sh"
check "Write new skill, existing command conflict exits 2" 2 \
    bash -c "printf '%s' '$(write_json Write "$TEMP_HOME/.claude/skills/deploy/SKILL.md")' | HOME='$TEMP_HOME' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK'"

check_output "skill command conflict shows AskUserQuestion instruction" "AskUserQuestion" \
    bash -c "printf '%s' '$(write_json Write "$TEMP_HOME/.claude/skills/deploy/SKILL.md")' | HOME='$TEMP_HOME' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' 2>&1 || true"

# Approval file present — allow and remove file
APPROVAL_DIR="$TEMP_HOME/.claude/.tmp/sessions/test-session"
mkdir -p "$APPROVAL_DIR"
touch "$APPROVAL_DIR/slash-conflict-approved-clear"
check "approval file present allows blocked write" 0 \
    bash -c "printf '%s' '$(write_json Write "$TEMP_HOME/.claude/commands/clear.md" test-session)' | HOME='$TEMP_HOME' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK'"
[[ ! -f "$APPROVAL_DIR/slash-conflict-approved-clear" ]] && {
    printf '  PASS  approval file removed after use\n'; (( pass++ )) || true
} || {
    printf '  FAIL  approval file not removed after use\n'; (( fail++ )) || true
}

# Cleanup
rm -rf "$TEMP_COMMANDS" "$TEMP_SKILLS" "$TEMP_CONSTANTS" "$TEMP_HOME"

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
