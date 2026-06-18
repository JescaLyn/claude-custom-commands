#!/usr/bin/env bash
# description: List all registered custom commands at the project and global level
# usage: /commands-help

set -euo pipefail

CURRENT_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
PROJECT_COMMANDS_DIR="${CLAUDE_COMMANDS_DIR:-${CURRENT_PROJECT_DIR:+$CURRENT_PROJECT_DIR/.claude/commands}}"
GLOBAL_COMMANDS_DIR="$HOME/.claude/commands"

_found=0
list_commands() {
    local dir="$1"
    _found=0
    for script in "$dir"/*.sh; do
        [[ -f "$script" ]] || continue
        name=$(basename "$script" .sh)
        desc=$(grep -m1 '^# description:' "$script" 2>/dev/null | sed 's/^# description: *//' || true)
        if [[ ${#name} -gt 22 ]]; then
            printf '  /%s\n' "$name"
            [[ -n "$desc" ]] && printf '%26s%s\n' "" "$desc"
        else
            printf '  /%-22s %s\n' "$name" "$desc"
        fi
        _found=1
    done
}

if [[ -n "$PROJECT_COMMANDS_DIR" && "$PROJECT_COMMANDS_DIR" != "$GLOBAL_COMMANDS_DIR" && -d "$PROJECT_COMMANDS_DIR" ]]; then
    printf 'Project commands (%s):\n\n' "$PROJECT_COMMANDS_DIR"
    list_commands "$PROJECT_COMMANDS_DIR"
    [[ "$_found" -eq 0 ]] && printf '  No commands found.\n'
    printf '\n'
fi

printf 'Global commands (%s):\n\n' "$GLOBAL_COMMANDS_DIR"
list_commands "$GLOBAL_COMMANDS_DIR"
[[ "$_found" -eq 0 ]] && printf '  No commands found.\n'
