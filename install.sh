#!/usr/bin/env bash
# Terminal entry point for installation.
# Primary path: open Claude Code from this directory and run /install-custom-commands.
set -euo pipefail
bash "$(dirname "$0")/.claude/commands/install-custom-commands.sh" "$@"
