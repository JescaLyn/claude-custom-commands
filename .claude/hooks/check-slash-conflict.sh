#!/usr/bin/env bash
# Checks a command name against Claude Code built-ins, installed skills, and existing
# custom commands. Prints a WARNING: line for each conflict found.
# Exit 0 = no conflicts. Exit 1 = one or more conflicts.
#
# Installed to ~/.claude/hooks/check-slash-conflict.sh by install.sh.
# Override lookup dirs via env vars (mainly for testing):
#   CLAUDE_COMMANDS_DIR   (default: ~/.claude/commands)
#   CLAUDE_SKILLS_DIR     (default: ~/.claude/skills)
#   CLAUDE_CONSTANTS_DIR  (default: ~/.claude/constants)

set -euo pipefail

_PROJ="${CLAUDE_PROJECT_DIR:-}"
COMMAND_DIR="${CLAUDE_COMMANDS_DIR:-${_PROJ:+$_PROJ/.claude/commands}}"
COMMAND_DIR="${COMMAND_DIR:-$HOME/.claude/commands}"
SKILLS_DIR="${CLAUDE_SKILLS_DIR:-${_PROJ:+$_PROJ/.claude/skills}}"
SKILLS_DIR="${SKILLS_DIR:-$HOME/.claude/skills}"
CONSTANTS_DIR="${CLAUDE_CONSTANTS_DIR:-${_PROJ:+$_PROJ/.claude/constants}}"
CONSTANTS_DIR="${CONSTANTS_DIR:-$HOME/.claude/constants}"

if [[ $# -lt 1 ]]; then
    printf 'Usage: check-slash-conflict <name>\n' >&2
    exit 1
fi

NAME="$1"
conflicts=0

# Check built-ins
if [[ -f "$CONSTANTS_DIR/builtin-commands.txt" ]]; then
    if grep -qxF "$NAME" "$CONSTANTS_DIR/builtin-commands.txt"; then
        printf 'WARNING: "/%s" is a Claude Code built-in command. Your custom command will shadow it — the built-in /%s will no longer be reachable.\n' "$NAME" "$NAME"
        (( conflicts++ )) || true
    fi
else
    printf 'WARNING: constants file not found: %s — built-in conflict check skipped.\n' "$CONSTANTS_DIR/builtin-commands.txt" >&2
fi

# Check bundled skills
if [[ -f "$CONSTANTS_DIR/bundled-skills.txt" ]]; then
    if grep -qxF "$NAME" "$CONSTANTS_DIR/bundled-skills.txt"; then
        printf 'WARNING: "/%s" is a bundled Claude Code skill. Your command will shadow it — /%s will run your script instead of the skill.\n' "$NAME" "$NAME"
        (( conflicts++ )) || true
    fi
else
    printf 'WARNING: constants file not found: %s — bundled skill conflict check skipped.\n' "$CONSTANTS_DIR/bundled-skills.txt" >&2
fi

# Check installed skills (~/.claude/skills/<name>/ directories)
if [[ -d "$SKILLS_DIR" ]]; then
    for skill_dir in "$SKILLS_DIR"/*/; do
        [[ -d "$skill_dir" ]] || continue
        skill_name=$(basename "$skill_dir")
        if [[ "$NAME" == "$skill_name" ]]; then
            printf 'WARNING: "/%s" matches installed skill "%s". Your custom command will shadow this skill — /%s will run your script instead of the skill.\n' "$NAME" "$skill_name" "$NAME"
            (( conflicts++ )) || true
        fi
    done
fi

# Check existing custom commands
if [[ -f "${COMMAND_DIR}/${NAME}.sh" ]]; then
    printf 'WARNING: "/%s" already exists as a custom command at %s.\n' "$NAME" "${COMMAND_DIR}/${NAME}.sh"
    (( conflicts++ )) || true
fi

exit $(( conflicts > 0 ? 1 : 0 ))
