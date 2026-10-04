#!/usr/bin/env bash
# Unit tests for .claude/hooks/check-slash-conflict.sh.
# Uses env vars to point at temp directories.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$REPO/.claude/hooks/check-slash-conflict.sh"
TEMP_COMMANDS=$(mktemp -d)
TEMP_SKILLS=$(mktemp -d)
TEMP_CONSTANTS=$(mktemp -d)
trap 'rm -rf "$TEMP_COMMANDS" "$TEMP_SKILLS" "$TEMP_CONSTANTS"' EXIT

cp "$REPO/.claude/constants/builtin-commands.txt" "$TEMP_CONSTANTS/builtin-commands.txt"
cp "$REPO/.claude/constants/bundled-skills.txt" "$TEMP_CONSTANTS/bundled-skills.txt"

export CLAUDE_COMMANDS_DIR="$TEMP_COMMANDS"
export CLAUDE_SKILLS_DIR="$TEMP_SKILLS"
export CLAUDE_CONSTANTS_DIR="$TEMP_CONSTANTS"

pass=0; fail=0

# Sync check: global installed copy must match repo copy
GLOBAL_CHECK="$HOME/.claude/hooks/check-slash-conflict.sh"
if [[ -f "$GLOBAL_CHECK" ]]; then
    if diff -q "$CHECK" "$GLOBAL_CHECK" >/dev/null 2>&1; then
        printf '  PASS  global installed copy matches repo copy\n'; (( pass++ )) || true
    else
        printf '  FAIL  global installed copy differs from repo copy — run /install-custom-commands to sync\n'; (( fail++ )) || true
    fi
else
    printf '  SKIP  no global install found (run /install-custom-commands first)\n'
fi

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

# Missing (not just empty) constants files — grep/[[ -f ]] guards should no-op, not error
TEMP_NO_CONSTANTS=$(mktemp -d)
trap 'rm -rf "$TEMP_COMMANDS" "$TEMP_SKILLS" "$TEMP_CONSTANTS" "$TEMP_NO_CONSTANTS"' EXIT
rm -rf "$TEMP_NO_CONSTANTS"
check "exits 0 for clean name when constants dir doesn't exist" 0 \
    bash -c "CLAUDE_CONSTANTS_DIR='$TEMP_NO_CONSTANTS' bash '$CHECK' some-clean-name"

# --- Direct mode: scope args ---
printf '\nDirect mode scope args:\n'

TEMP_SCOPE_HOME=$(mktemp -d)
TEMP_SCOPE_PROJ=$(mktemp -d)
trap 'rm -rf "$TEMP_COMMANDS" "$TEMP_SKILLS" "$TEMP_CONSTANTS" "$TEMP_NO_CONSTANTS" "$TEMP_SCOPE_HOME" "$TEMP_SCOPE_PROJ"' EXIT
mkdir -p "$TEMP_SCOPE_HOME/.claude/commands" "$TEMP_SCOPE_PROJ/.claude/commands"

# --global: clean name exits 0
check "exits 0 for clean name with --global" 0 \
    bash -c "HOME='$TEMP_SCOPE_HOME' CLAUDE_COMMANDS_DIR='' CLAUDE_SKILLS_DIR='' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' fresh-name --global"

# --global: name matches existing global command → exits 1
touch "$TEMP_SCOPE_HOME/.claude/commands/existing-global.sh"
check "exits 1 when name matches existing global command with --global" 1 \
    bash -c "HOME='$TEMP_SCOPE_HOME' CLAUDE_COMMANDS_DIR='' CLAUDE_SKILLS_DIR='' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' existing-global --global"

# project path: clean name exits 0
check "exits 0 for clean name with project path" 0 \
    bash -c "HOME='$TEMP_SCOPE_HOME' CLAUDE_COMMANDS_DIR='' CLAUDE_SKILLS_DIR='' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' fresh-proj-name '$TEMP_SCOPE_PROJ'"

# project path: name matches existing project command → exits 1
touch "$TEMP_SCOPE_PROJ/.claude/commands/existing-proj.sh"
check "exits 1 when name matches existing project command with project path" 1 \
    bash -c "HOME='$TEMP_SCOPE_HOME' CLAUDE_COMMANDS_DIR='' CLAUDE_SKILLS_DIR='' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' existing-proj '$TEMP_SCOPE_PROJ'"

# project path: name shadows global command → exits 1 with shadow warning
touch "$TEMP_SCOPE_HOME/.claude/commands/shadowed-by-proj.sh"
check "exits 1 when project-scope command would shadow global" 1 \
    bash -c "HOME='$TEMP_SCOPE_HOME' CLAUDE_COMMANDS_DIR='' CLAUDE_SKILLS_DIR='' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' shadowed-by-proj '$TEMP_SCOPE_PROJ'"

check_output "shadow warning mentions 'shadow'" "shadow" \
    bash -c "HOME='$TEMP_SCOPE_HOME' CLAUDE_COMMANDS_DIR='' CLAUDE_SKILLS_DIR='' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' shadowed-by-proj '$TEMP_SCOPE_PROJ' || true"

# --global with open project that already has the same command → exits 1 ("won't take effect")
touch "$TEMP_SCOPE_PROJ/.claude/commands/wont-effect.sh"
check "exits 1 when global install won't take effect in open project" 1 \
    bash -c "HOME='$TEMP_SCOPE_HOME' CLAUDE_PROJECT_DIR='$TEMP_SCOPE_PROJ' CLAUDE_COMMANDS_DIR='' CLAUDE_SKILLS_DIR='' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' wont-effect --global"

check_output "won't-take-effect warning in direct mode" "won.t take effect" \
    bash -c "HOME='$TEMP_SCOPE_HOME' CLAUDE_PROJECT_DIR='$TEMP_SCOPE_PROJ' CLAUDE_COMMANDS_DIR='' CLAUDE_SKILLS_DIR='' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' wont-effect --global || true"

# project path: name shadows global skill dir → exits 1 with shadow warning
mkdir -p "$TEMP_SCOPE_HOME/.claude/skills/shadow-skill"
check "exits 1 when project-scope command would shadow global skill" 1 \
    bash -c "HOME='$TEMP_SCOPE_HOME' CLAUDE_COMMANDS_DIR='' CLAUDE_SKILLS_DIR='' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' shadow-skill '$TEMP_SCOPE_PROJ'"

check_output "shadow-skill warning mentions 'shadow'" "shadow" \
    bash -c "HOME='$TEMP_SCOPE_HOME' CLAUDE_COMMANDS_DIR='' CLAUDE_SKILLS_DIR='' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' shadow-skill '$TEMP_SCOPE_PROJ' || true"

# --global with open project that has a skill dir for the same name → exits 1 ("won't take effect")
mkdir -p "$TEMP_SCOPE_PROJ/.claude/skills/wont-effect-skill"
check "exits 1 when global install won't take effect because project has skill" 1 \
    bash -c "HOME='$TEMP_SCOPE_HOME' CLAUDE_PROJECT_DIR='$TEMP_SCOPE_PROJ' CLAUDE_COMMANDS_DIR='' CLAUDE_SKILLS_DIR='' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' wont-effect-skill --global"

check_output "won't-take-effect skill warning in direct mode" "won.t take effect" \
    bash -c "HOME='$TEMP_SCOPE_HOME' CLAUDE_PROJECT_DIR='$TEMP_SCOPE_PROJ' CLAUDE_COMMANDS_DIR='' CLAUDE_SKILLS_DIR='' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' wont-effect-skill --global || true"

rm -rf "$TEMP_SCOPE_HOME" "$TEMP_SCOPE_PROJ"

# --- Direct mode: CLAUDE_COMMANDS_DIR scope inference ---
printf '\nDirect mode: CLAUDE_COMMANDS_DIR scope inference:\n'

# When CLAUDE_COMMANDS_DIR is set and falls under $HOME/.claude/, direct mode infers IS_GLOBAL=true
# and applies the cross-scope "won't take effect in project" check accordingly.
TEMP_INFER_HOME=$(mktemp -d)
TEMP_INFER_PROJ=$(mktemp -d)
trap 'rm -rf "$TEMP_COMMANDS" "$TEMP_SKILLS" "$TEMP_CONSTANTS" "$TEMP_NO_CONSTANTS" "$TEMP_SCOPE_HOME" "$TEMP_SCOPE_PROJ" "$TEMP_INFER_HOME" "$TEMP_INFER_PROJ"' EXIT
mkdir -p "$TEMP_INFER_HOME/.claude/commands" "$TEMP_INFER_PROJ/.claude/commands"
touch "$TEMP_INFER_PROJ/.claude/commands/infer-global.sh"
check "exits 1 when CLAUDE_COMMANDS_DIR under \$HOME/.claude infers global scope" 1 \
    bash -c "HOME='$TEMP_INFER_HOME' CLAUDE_PROJECT_DIR='$TEMP_INFER_PROJ' CLAUDE_COMMANDS_DIR='$TEMP_INFER_HOME/.claude/commands' CLAUDE_SKILLS_DIR='' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' infer-global"
check_output "infers global scope shows won't-take-effect warning" "won.t take effect" \
    bash -c "HOME='$TEMP_INFER_HOME' CLAUDE_PROJECT_DIR='$TEMP_INFER_PROJ' CLAUDE_COMMANDS_DIR='$TEMP_INFER_HOME/.claude/commands' CLAUDE_SKILLS_DIR='' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' infer-global || true"
rm -rf "$TEMP_INFER_HOME" "$TEMP_INFER_PROJ"

# --- CONSTANTS_DIR fallback chain ---
printf '\nCONSTANTS_DIR fallback chain:\n'

# With no CLAUDE_CONSTANTS_DIR override, the checker falls back to $HOME/.claude/constants.
TEMP_FALLBACK_HOME=$(mktemp -d)
trap 'rm -rf "$TEMP_COMMANDS" "$TEMP_SKILLS" "$TEMP_CONSTANTS" "$TEMP_NO_CONSTANTS" "$TEMP_SCOPE_HOME" "$TEMP_SCOPE_PROJ" "$TEMP_INFER_HOME" "$TEMP_INFER_PROJ" "$TEMP_FALLBACK_HOME"' EXIT
mkdir -p "$TEMP_FALLBACK_HOME/.claude/constants"
printf 'fallback-builtin\n' > "$TEMP_FALLBACK_HOME/.claude/constants/builtin-commands.txt"
printf '' > "$TEMP_FALLBACK_HOME/.claude/constants/bundled-skills.txt"
check "falls back to \$HOME/.claude/constants when CLAUDE_CONSTANTS_DIR unset" 1 \
    bash -c "HOME='$TEMP_FALLBACK_HOME' CLAUDE_COMMANDS_DIR='' CLAUDE_SKILLS_DIR='' CLAUDE_CONSTANTS_DIR= bash '$CHECK' fallback-builtin"
rm -rf "$TEMP_FALLBACK_HOME"

# --- Hook mode ---
printf '\nHook mode:\n'

TEMP_HOME=$(mktemp -d)
trap 'rm -rf "$TEMP_COMMANDS" "$TEMP_SKILLS" "$TEMP_CONSTANTS" "$TEMP_NO_CONSTANTS" "$TEMP_SCOPE_HOME" "$TEMP_SCOPE_PROJ" "$TEMP_INFER_HOME" "$TEMP_INFER_PROJ" "$TEMP_FALLBACK_HOME" "$TEMP_HOME"' EXIT
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

# Write to a .sh path under commands/ (not .md) — regex requires .md, so this is an unrelated path
check "Write to .sh command path (not .md) exits 0" 0 \
    bash -c "printf '%s' '$(write_json Write "$TEMP_HOME/.claude/commands/deploy.sh")' | HOME='$TEMP_HOME' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK'"

# Malformed JSON on stdin in hook mode — fails open (exit 0) with a diagnostic, not silently
check "malformed JSON in hook mode exits 0" 0 \
    bash -c "printf 'not json' | HOME='$TEMP_HOME' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK'"
check_output "malformed JSON diagnostic goes to stderr" "failed to parse hook input JSON" \
    bash -c "printf 'not json' | HOME='$TEMP_HOME' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK'"

# python3 missing in hook mode — fails open (exit 0) with a diagnostic, not silently
NO_PYTHON3_PATH=$(strip_python3_from_path)
check "python3 missing in hook mode exits 0" 0 \
    bash -c "printf '%s' '$(write_json Write "$TEMP_HOME/.claude/commands/deploy.md")' | HOME='$TEMP_HOME' PATH='$NO_PYTHON3_PATH' '$BASH_BIN' '$CHECK'"
check_output "python3-missing hook diagnostic goes to stderr" "python3 not found" \
    bash -c "printf '%s' '$(write_json Write "$TEMP_HOME/.claude/commands/deploy.md")' | HOME='$TEMP_HOME' PATH='$NO_PYTHON3_PATH' '$BASH_BIN' '$CHECK'"

# session_id defaults to 'shared' when absent from hook input JSON
check_output "missing session_id defaults to 'shared' in approval file path" "sessions/shared/" \
    bash -c "printf '%s' '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TEMP_HOME/.claude/commands/clear.md\",\"content\":\"\"}}' | HOME='$TEMP_HOME' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' 2>&1 || true"

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

# Write new skill, bundled skill conflict — informational note only; write proceeds (exit 0)
check "Write new skill, bundled skill conflict exits 0" 0 \
    bash -c "printf '%s' '$(write_json Write "$TEMP_HOME/.claude/skills/review/SKILL.md")' | HOME='$TEMP_HOME' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK'"

check_output "skill bundled conflict shows note not conflict header" "note" \
    bash -c "printf '%s' '$(write_json Write "$TEMP_HOME/.claude/skills/review/SKILL.md")' | HOME='$TEMP_HOME' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' 2>&1 || true"

# Write new skill, built-in command name conflict — informational note only (same as bundled-skill note)
check "Write new skill, built-in command conflict exits 0" 0 \
    bash -c "printf '%s' '$(write_json Write "$TEMP_HOME/.claude/skills/clear/SKILL.md")' | HOME='$TEMP_HOME' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK'"

check_output "skill built-in conflict shows note not conflict header" "note" \
    bash -c "printf '%s' '$(write_json Write "$TEMP_HOME/.claude/skills/clear/SKILL.md")' | HOME='$TEMP_HOME' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' 2>&1 || true"

# Write new skill named after a bundled skill (informational note) that ALSO has an existing
# custom command of the same name (blocking) — the blocked message should include both, via
# an "Also note:" section, not just the blocking reasons.
mkdir -p "$TEMP_HOME/.claude/commands"
printf '#!/usr/bin/env bash\n' > "$TEMP_HOME/.claude/commands/review.sh"
check "Write new skill named 'review' with existing command exits 2" 2 \
    bash -c "printf '%s' '$(write_json Write "$TEMP_HOME/.claude/skills/review/SKILL.md")' | HOME='$TEMP_HOME' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK'"
check_output "combined block + note shows 'Also note:'" "Also note:" \
    bash -c "printf '%s' '$(write_json Write "$TEMP_HOME/.claude/skills/review/SKILL.md")' | HOME='$TEMP_HOME' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' 2>&1 || true"
rm -f "$TEMP_HOME/.claude/commands/review.sh"

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

# --- Hook mode: cross-scope ---
printf '\nHook mode cross-scope:\n'

TEMP_CROSS_HOME=$(mktemp -d)
TEMP_CROSS_PROJ=$(mktemp -d)
trap 'rm -rf "$TEMP_COMMANDS" "$TEMP_SKILLS" "$TEMP_CONSTANTS" "$TEMP_NO_CONSTANTS" "$TEMP_SCOPE_HOME" "$TEMP_SCOPE_PROJ" "$TEMP_INFER_HOME" "$TEMP_INFER_PROJ" "$TEMP_FALLBACK_HOME" "$TEMP_HOME" "$TEMP_CROSS_HOME" "$TEMP_CROSS_PROJ"' EXIT
mkdir -p "$TEMP_CROSS_HOME/.claude/commands" "$TEMP_CROSS_PROJ/.claude/commands"

# Project-scope write (FILE_PATH not under $HOME/.claude/) — global command exists → block (exit 2)
touch "$TEMP_CROSS_HOME/.claude/commands/shadow-x.sh"
check "hook: project-scope write shadowing global command exits 2" 2 \
    bash -c "printf '%s' '$(write_json Write "$TEMP_CROSS_PROJ/.claude/commands/shadow-x.md")' | HOME='$TEMP_CROSS_HOME' CLAUDE_PROJECT_DIR='$TEMP_CROSS_PROJ' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK'"

check_output "hook: project-scope shadow warning mentions shadow" "shadow" \
    bash -c "printf '%s' '$(write_json Write "$TEMP_CROSS_PROJ/.claude/commands/shadow-x.md")' | HOME='$TEMP_CROSS_HOME' CLAUDE_PROJECT_DIR='$TEMP_CROSS_PROJ' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' 2>&1 || true"

# Global write (FILE_PATH under $HOME/.claude/) — project already has same-name command → block (exit 2)
touch "$TEMP_CROSS_PROJ/.claude/commands/wont-effect-x.sh"
check "hook: global write won't take effect in project exits 2" 2 \
    bash -c "printf '%s' '$(write_json Write "$TEMP_CROSS_HOME/.claude/commands/wont-effect-x.md")' | HOME='$TEMP_CROSS_HOME' CLAUDE_PROJECT_DIR='$TEMP_CROSS_PROJ' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK'"

check_output "hook: won't-take-effect warning in output" "won.t take effect" \
    bash -c "printf '%s' '$(write_json Write "$TEMP_CROSS_HOME/.claude/commands/wont-effect-x.md")' | HOME='$TEMP_CROSS_HOME' CLAUDE_PROJECT_DIR='$TEMP_CROSS_PROJ' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' 2>&1 || true"

# Project-scope command write shadowing global SKILL dir → block (exit 2)
mkdir -p "$TEMP_CROSS_HOME/.claude/skills/shadow-skill-x"
check "hook: project-scope command write shadowing global skill exits 2" 2 \
    bash -c "printf '%s' '$(write_json Write "$TEMP_CROSS_PROJ/.claude/commands/shadow-skill-x.md")' | HOME='$TEMP_CROSS_HOME' CLAUDE_PROJECT_DIR='$TEMP_CROSS_PROJ' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK'"

check_output "hook: project-scope shadow global skill warning mentions shadow" "shadow" \
    bash -c "printf '%s' '$(write_json Write "$TEMP_CROSS_PROJ/.claude/commands/shadow-skill-x.md")' | HOME='$TEMP_CROSS_HOME' CLAUDE_PROJECT_DIR='$TEMP_CROSS_PROJ' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' 2>&1 || true"

# Global command write that won't take effect — project has skill dir with same name → block (exit 2)
mkdir -p "$TEMP_CROSS_PROJ/.claude/skills/wont-effect-skill-x"
check "hook: global command write won't take effect because project has skill exits 2" 2 \
    bash -c "printf '%s' '$(write_json Write "$TEMP_CROSS_HOME/.claude/commands/wont-effect-skill-x.md")' | HOME='$TEMP_CROSS_HOME' CLAUDE_PROJECT_DIR='$TEMP_CROSS_PROJ' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK'"

check_output "hook: won't-take-effect project skill warning in output" "won.t take effect" \
    bash -c "printf '%s' '$(write_json Write "$TEMP_CROSS_HOME/.claude/commands/wont-effect-skill-x.md")' | HOME='$TEMP_CROSS_HOME' CLAUDE_PROJECT_DIR='$TEMP_CROSS_PROJ' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' 2>&1 || true"

# Project SKILL write (IS_GLOBAL=false in skill block) when global command exists → block (exit 2)
touch "$TEMP_CROSS_HOME/.claude/commands/skill-cmd-x.sh"
check "hook: project skill write blocked when global command exists exits 2" 2 \
    bash -c "printf '%s' '$(write_json Write "$TEMP_CROSS_PROJ/.claude/skills/skill-cmd-x/SKILL.md")' | HOME='$TEMP_CROSS_HOME' CLAUDE_PROJECT_DIR='$TEMP_CROSS_PROJ' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK'"

check_output "hook: project skill write global command warning mentions global" "global custom command" \
    bash -c "printf '%s' '$(write_json Write "$TEMP_CROSS_PROJ/.claude/skills/skill-cmd-x/SKILL.md")' | HOME='$TEMP_CROSS_HOME' CLAUDE_PROJECT_DIR='$TEMP_CROSS_PROJ' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' 2>&1 || true"

# Project-scope SKILL write shadowing an existing global SKILL of the same name → block (exit 2)
mkdir -p "$TEMP_CROSS_HOME/.claude/skills/skill-shadow-x"
check "hook: project skill write shadowing global skill exits 2" 2 \
    bash -c "printf '%s' '$(write_json Write "$TEMP_CROSS_PROJ/.claude/skills/skill-shadow-x/SKILL.md")' | HOME='$TEMP_CROSS_HOME' CLAUDE_PROJECT_DIR='$TEMP_CROSS_PROJ' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK'"

check_output "hook: project skill shadow global skill warning mentions shadow" "shadow" \
    bash -c "printf '%s' '$(write_json Write "$TEMP_CROSS_PROJ/.claude/skills/skill-shadow-x/SKILL.md")' | HOME='$TEMP_CROSS_HOME' CLAUDE_PROJECT_DIR='$TEMP_CROSS_PROJ' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' 2>&1 || true"

# Global SKILL write that won't take effect because the open project already has a skill of the same name → block (exit 2)
mkdir -p "$TEMP_CROSS_PROJ/.claude/skills/skill-wont-effect-x"
check "hook: global skill write won't take effect because project has skill exits 2" 2 \
    bash -c "printf '%s' '$(write_json Write "$TEMP_CROSS_HOME/.claude/skills/skill-wont-effect-x/SKILL.md")' | HOME='$TEMP_CROSS_HOME' CLAUDE_PROJECT_DIR='$TEMP_CROSS_PROJ' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK'"

check_output "hook: global skill won't-take-effect warning in output" "won.t take effect" \
    bash -c "printf '%s' '$(write_json Write "$TEMP_CROSS_HOME/.claude/skills/skill-wont-effect-x/SKILL.md")' | HOME='$TEMP_CROSS_HOME' CLAUDE_PROJECT_DIR='$TEMP_CROSS_PROJ' CLAUDE_CONSTANTS_DIR='$TEMP_CONSTANTS' bash '$CHECK' 2>&1 || true"

rm -rf "$TEMP_CROSS_HOME" "$TEMP_CROSS_PROJ"

# Cleanup
rm -rf "$TEMP_COMMANDS" "$TEMP_SKILLS" "$TEMP_CONSTANTS" "$TEMP_HOME"

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
