#!/usr/bin/env bash
# description: Uninstall custom commands globally, or remove them from a project directory
# usage: /uninstall-custom-commands [project-path]

set -euo pipefail

UNINSTALL_SCRIPT="$PWD/uninstall.sh"

if [[ ! -f "$UNINSTALL_SCRIPT" ]]; then
    printf 'Open Claude Code from the claude-custom-commands repo directory, then retry.\n' >&2
    printf 'Current directory: %s\n' "$PWD" >&2
    exit 1
fi

if [[ -n "${1:-}" ]]; then
    PROJECT="$1"
    if [[ ! -d "$PROJECT" ]]; then
        printf 'Error: project directory not found: %s\n' "$PROJECT" >&2
        exit 1
    fi
    COMMANDS_DIR="$PROJECT/.claude/commands"
    if [[ ! -d "$COMMANDS_DIR" ]]; then
        printf 'No commands directory at %s -- nothing to remove.\n' "$COMMANDS_DIR"
        exit 0
    fi
    printf 'Removing repo commands from %s\n\n' "$COMMANDS_DIR"
    for cmd in "$PWD/.claude/commands/"*.sh; do
        name=$(basename "${cmd%.sh}")
        removed=0
        [[ -f "$COMMANDS_DIR/$name.sh" ]] && { rm "$COMMANDS_DIR/$name.sh"; removed=1; }
        [[ -f "$COMMANDS_DIR/$name.md" ]] && rm "$COMMANDS_DIR/$name.md"
        [[ $removed -eq 1 ]] && printf '  Removed: /%s\n' "$name"
    done
    printf '\nDone.\n'
else
    bash "$UNINSTALL_SCRIPT"
fi
