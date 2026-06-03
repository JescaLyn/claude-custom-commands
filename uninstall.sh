#!/usr/bin/env bash
# Terminal entry point for uninstallation.
# Primary path: open Claude Code and run /uninstall-custom-commands.
set -euo pipefail
bash "$(dirname "$0")/.claude/commands/uninstall-custom-commands.sh" "$@"
