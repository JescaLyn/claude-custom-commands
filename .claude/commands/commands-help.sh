#!/usr/bin/env bash
# description: List all registered custom commands at the project and global level
# usage: /commands-help

set -euo pipefail

_PROJ="${CLAUDE_PROJECT_DIR:-}"
PROJ_DIR="${CLAUDE_COMMANDS_DIR:-${_PROJ:+$_PROJ/.claude/commands}}"
GLOB_DIR="$HOME/.claude/commands"

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

if [[ -n "$PROJ_DIR" && "$PROJ_DIR" != "$GLOB_DIR" && -d "$PROJ_DIR" ]]; then
    printf 'Project commands (%s):\n\n' "$PROJ_DIR"
    list_commands "$PROJ_DIR"
    [[ "$_found" -eq 0 ]] && printf '  No commands found.\n'
    printf '\n'
fi

printf 'Global commands (%s):\n\n' "$GLOB_DIR"
list_commands "$GLOB_DIR"
[[ "$_found" -eq 0 ]] && printf '  No commands found.\n'
