#!/usr/bin/env bash
# description: Remove an installed custom command by name
# usage: /remove-command <name>

set -euo pipefail

_PROJ="${CLAUDE_PROJECT_DIR:-}"
COMMAND_DIR="${CLAUDE_COMMANDS_DIR:-${_PROJ:+$_PROJ/.claude/commands}}"
COMMAND_DIR="${COMMAND_DIR:-$HOME/.claude/commands}"
if [[ -n "${CLAUDE_CONSTANTS_DIR:-}" ]]; then
    CONSTANTS_DIR="$CLAUDE_CONSTANTS_DIR"
elif [[ -d "$HOME/.claude/constants" ]]; then
    CONSTANTS_DIR="$HOME/.claude/constants"
elif [[ -n "$_PROJ" ]]; then
    CONSTANTS_DIR="$_PROJ/.claude/constants"
else
    CONSTANTS_DIR="$HOME/.claude/constants"
fi

if [[ $# -eq 0 ]]; then
    printf 'Usage: /remove-command <name>\n\n'
    printf '  name  Name of the custom command to remove (without leading slash)\n'
    exit 0
fi

NAME="$1"

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

SH_FILE="$COMMAND_DIR/$NAME.sh"
MD_FILE="$COMMAND_DIR/$NAME.md"

if [[ ! -f "$SH_FILE" ]]; then
    printf 'Command /%s is not installed in %s.\n' "$NAME" "$COMMAND_DIR"
    exit 1
fi

rm -f "$SH_FILE" "$MD_FILE"
printf 'Removed /%s from %s.\n' "$NAME" "$COMMAND_DIR"
