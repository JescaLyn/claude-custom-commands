#!/usr/bin/env bash
# description: Remove an installed custom command by name
# usage: /remove-command <name> [project-path]

set -euo pipefail

CURRENT_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
PROJECT_COMMANDS_DIR="${CURRENT_PROJECT_DIR:+$CURRENT_PROJECT_DIR/.claude/commands}"
GLOBAL_COMMANDS_DIR="$HOME/.claude/commands"
if [[ -n "${CLAUDE_CONSTANTS_DIR:-}" ]]; then
    CONSTANTS_DIR="$CLAUDE_CONSTANTS_DIR"
elif [[ -d "$HOME/.claude/constants" ]]; then
    CONSTANTS_DIR="$HOME/.claude/constants"
elif [[ -n "$CURRENT_PROJECT_DIR" ]]; then
    CONSTANTS_DIR="$CURRENT_PROJECT_DIR/.claude/constants"
else
    CONSTANTS_DIR="$HOME/.claude/constants"
fi

if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
    printf 'Usage: /remove-command <name> [project-path]\n\n'
    printf '  name          Name of the custom command to remove (without leading slash)\n'
    printf '  project-path  Optional; restricts removal to <project>/.claude/commands/\n'
    printf '                Omit to search the current project then global (progressive).\n'
    exit 0
fi

NAME="$1"
TARGET_PROJECT_DIR="${2:+${2/#~/$HOME}}"

if [[ ! "$NAME" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
    printf 'Invalid name: %s\n' "$NAME"
    printf 'Must start with a letter; only letters, digits, hyphens, and underscores allowed.\n'
    exit 1
fi

if [[ -f "$CONSTANTS_DIR/builtin-commands.txt" ]] && grep -qxF "$NAME" "$CONSTANTS_DIR/builtin-commands.txt" 2>/dev/null; then
    printf '/%s is a Claude Code built-in and cannot be removed here.\n' "$NAME"
    exit 1
fi

if [[ -f "$CONSTANTS_DIR/bundled-skills.txt" ]] && grep -qxF "$NAME" "$CONSTANTS_DIR/bundled-skills.txt" 2>/dev/null; then
    printf '/%s is a bundled Claude Code skill and cannot be removed here.\n' "$NAME"
    exit 1
fi

# Resolve the target directory
if [[ -n "${CLAUDE_COMMANDS_DIR:-}" ]]; then
    # Test override: look only here
    if [[ ! -f "$CLAUDE_COMMANDS_DIR/$NAME.sh" ]]; then
        printf 'Command /%s is not installed in %s.\n' "$NAME" "$CLAUDE_COMMANDS_DIR"
        exit 1
    fi
    RESOLVED_DIR="$CLAUDE_COMMANDS_DIR"
elif [[ -n "$TARGET_PROJECT_DIR" ]]; then
    # Explicit project path: only look there
    EXPLICIT_DIR="$TARGET_PROJECT_DIR/.claude/commands"
    if [[ ! -f "$EXPLICIT_DIR/$NAME.sh" ]]; then
        printf 'Command /%s is not installed in %s.\n' "$NAME" "$EXPLICIT_DIR"
        exit 1
    fi
    RESOLVED_DIR="$EXPLICIT_DIR"
elif [[ -n "$PROJECT_COMMANDS_DIR" && -f "$PROJECT_COMMANDS_DIR/$NAME.sh" ]]; then
    RESOLVED_DIR="$PROJECT_COMMANDS_DIR"
elif [[ -f "$GLOBAL_COMMANDS_DIR/$NAME.sh" ]]; then
    RESOLVED_DIR="$GLOBAL_COMMANDS_DIR"
else
    if [[ -n "$PROJECT_COMMANDS_DIR" ]]; then
        printf 'Command /%s is not installed in %s or %s.\n' "$NAME" "$PROJECT_COMMANDS_DIR" "$GLOBAL_COMMANDS_DIR"
    else
        printf 'Command /%s is not installed in %s.\n' "$NAME" "$GLOBAL_COMMANDS_DIR"
    fi
    exit 1
fi

rm -f "$RESOLVED_DIR/$NAME.sh" "$RESOLVED_DIR/$NAME.md"
printf 'Removed /%s from %s.\n' "$NAME" "$RESOLVED_DIR"
