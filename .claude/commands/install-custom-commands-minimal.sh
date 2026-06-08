#!/usr/bin/env bash
# description: Install just the custom command dispatcher into a project or globally
# usage: /install-custom-commands-minimal [project-path]
#
# Minimal install: copies only dispatch-commands.sh and registers the
# UserPromptSubmit hook. No built-in commands, constants, skills, or
# conflict-check hook. Use /install-custom-commands for the full package.
#
# Must be run from the claude-custom-commands repo directory.

set -euo pipefail

REPO_DIR="$PWD"

if [[ ! -f "$REPO_DIR/.claude/hooks/dispatch-commands.sh" ]]; then
    printf 'Run /install-custom-commands-minimal from the claude-custom-commands repo directory.\n' >&2
    printf 'Current directory: %s\n' "$REPO_DIR" >&2
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    printf 'Error: python3 is required but not found.\n' >&2
    exit 1
fi

IS_PROJECT=false
if [[ -n "${1:-}" ]]; then
    IS_PROJECT=true
    PROJECT="${1/#~/$HOME}"
    if [[ ! -d "$PROJECT" ]]; then
        printf 'Error: project directory not found: %s\n' "$PROJECT" >&2
        exit 1
    fi
    HOOKS_DIR="$PROJECT/.claude/hooks"
    COMMAND_DIR="$PROJECT/.claude/commands"
    SETTINGS="$PROJECT/.claude/settings.json"
    HOOK_CMD='${CLAUDE_PROJECT_DIR}/.claude/hooks/dispatch-commands.sh'
else
    HOOKS_DIR="$HOME/.claude/hooks"
    COMMAND_DIR="$HOME/.claude/commands"
    SETTINGS="$HOME/.claude/settings.json"
    HOOK_CMD='$HOME/.claude/hooks/dispatch-commands.sh'
fi

HOOK_SCRIPT="$HOOKS_DIR/dispatch-commands.sh"

printf 'Installing minimal custom command dispatcher...\n\n'

mkdir -p "$HOOKS_DIR" "$COMMAND_DIR"

cp "$REPO_DIR/.claude/hooks/dispatch-commands.sh" "$HOOK_SCRIPT"
chmod +x "$HOOK_SCRIPT"
printf '  Installed: %s\n' "$HOOK_SCRIPT"

printf '\nHook registration:\n'
UPDATED=$(python3 - "$SETTINGS" "$HOOK_CMD" << 'PYEOF'
import json, sys, os
settings_path, hook_cmd = sys.argv[1], sys.argv[2]
try:
    s = json.loads(open(settings_path).read()) if os.path.exists(settings_path) else {}
except ValueError:
    s = {}
home = os.environ.get("HOME", "")
def norm(cmd):
    return cmd.replace("$HOME", home) if home else cmd
ups = s.setdefault("hooks", {}).setdefault("UserPromptSubmit", [])
for entry in ups:
    for h in entry.get("hooks", []):
        if norm(h.get("command", "")) == norm(hook_cmd):
            print("ALREADY_REGISTERED")
            sys.exit(0)
ups.append({"hooks": [{"type": "command", "command": hook_cmd}]})
print(json.dumps(s, indent=2))
PYEOF
)
if [[ "$UPDATED" == "ALREADY_REGISTERED" ]]; then
    printf '  Hook already registered in %s\n' "$SETTINGS"
else
    printf '%s\n' "$UPDATED" > "$SETTINGS"
    printf '  Registered UserPromptSubmit hook in %s\n' "$SETTINGS"
fi

if [[ "$IS_PROJECT" == "true" ]]; then
    README="$PROJECT/README.md"
    NOTE='## Custom Commands

This project has [custom commands](https://github.com/JescaLyn/claude-custom-commands) installed. Type `/name` in Claude Code to run deterministic bash scripts from `.claude/commands/`.'
    if [[ -f "$README" ]]; then
        if ! grep -q 'JescaLyn/claude-custom-commands' "$README" 2>/dev/null; then
            printf '\n\n%s\n' "$NOTE" >> "$README"
            printf '\n  Added custom commands note to %s\n' "$README"
        else
            printf '\n  README already mentions custom commands -- skipped\n'
        fi
    else
        printf '%s\n' "$NOTE" > "$README"
        printf '\n  Created %s with custom commands note\n' "$README"
    fi
fi

printf '\nDone. Restart Claude Code for the hook to take effect.\n\n'
printf 'Place scripts in %s/<name>.sh to register a command.\n' "$COMMAND_DIR"
