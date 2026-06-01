#!/usr/bin/env bash
# description: Install custom commands globally, or into a project directory
# usage: /install-custom-commands [project-path]

set -euo pipefail

INSTALL_SCRIPT="$PWD/install.sh"

if [[ ! -f "$INSTALL_SCRIPT" ]]; then
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
    CLAUDE_COMMANDS_DIR="$PROJECT/.claude/commands" bash "$INSTALL_SCRIPT"
else
    bash "$INSTALL_SCRIPT"
fi
