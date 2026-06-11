#!/usr/bin/env bash
# description: Register an existing bash script as a new custom command
# usage: /create-command-from-script [--force] [--global] <name> <script-path>

set -euo pipefail

# Parse flags first (before scope detection, so --global can influence it)
FORCE=false
GLOBAL=false
while [[ "${1:-}" == --* ]]; do
    case "${1:-}" in
        --force)  FORCE=true;  shift ;;
        --global) GLOBAL=true; shift ;;
        *) break ;;
    esac
done

_PROJ=""
[[ -d "$PWD/.claude" ]] && _PROJ="$PWD"
[[ "$GLOBAL" == "true" ]] && _PROJ=""

COMMAND_DIR="${CLAUDE_COMMANDS_DIR:-${_PROJ:+$_PROJ/.claude/commands}}"
COMMAND_DIR="${COMMAND_DIR:-$HOME/.claude/commands}"
CHECK_SCRIPT="${CLAUDE_CHECK_SLASH_SCRIPT:-${_PROJ:+$_PROJ/.claude/hooks/check-slash-conflict.sh}}"
CHECK_SCRIPT="${CHECK_SCRIPT:-$HOME/.claude/hooks/check-slash-conflict.sh}"

if [[ $# -lt 2 ]]; then
    printf 'Usage: /create-command-from-script [--force] [--global] <name> <script-path>\n\n'
    printf '  --force      Create even if the name conflicts with a built-in or existing command\n'
    printf '  --global     Install to the global ~/.claude/commands directory\n'
    printf '  name         Name for the new command (becomes /<name>)\n'
    printf '  script-path  Path to an existing bash script\n'
    exit 0
fi

NAME="$1"
SCRIPT_PATH="$2"

if [[ ! "$NAME" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
    printf 'Invalid name: %s\n' "$NAME"
    printf 'Must start with a letter; only letters, digits, hyphens, and underscores allowed.\n'
    exit 1
fi

if [[ ! -f "$SCRIPT_PATH" ]]; then
    printf 'Script not found: %s\n' "$SCRIPT_PATH"
    exit 1
fi

DEST="${COMMAND_DIR}/${NAME}.sh"

if [[ -f "$DEST" ]]; then
    printf 'Command /%s already exists at %s\n' "$NAME" "$DEST"
    printf 'Delete it first, then re-run.\n'
    exit 1
fi

if [[ "$FORCE" == "false" ]] && [[ -x "$CHECK_SCRIPT" ]]; then
    CONFLICTS=$("$CHECK_SCRIPT" "$NAME" 2>/dev/null || true)
    if [[ -n "$CONFLICTS" ]]; then
        printf '%s\n\n' "$CONFLICTS"
        printf 'Command not created. Re-run with --force to override:\n'
        printf '  /create-command-from-script --force %s %s\n' "$NAME" "$SCRIPT_PATH"
        exit 1
    fi
fi

mkdir -p "$COMMAND_DIR"
cp "$SCRIPT_PATH" "$DEST"
chmod +x "$DEST"

MD_DEST="${COMMAND_DIR}/${NAME}.md"
if [[ ! -f "$MD_DEST" ]]; then
    DESCRIPTION=$(grep -m1 '^# description:' "$SCRIPT_PATH" 2>/dev/null | sed 's/^# description: *//' || true)
    DESCRIPTION="${DESCRIPTION:-Custom command /$NAME}"
    printf '%s\n\n<!-- Autocomplete stub only. The UserPromptSubmit hook runs %s.sh; this file is never read during command execution. -->\n' \
        "$DESCRIPTION" "$NAME" > "$MD_DEST"
fi

printf 'Created /%s from %s\n' "$NAME" "$SCRIPT_PATH"
