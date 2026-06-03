#!/usr/bin/env bash
# description: Uninstall custom commands globally, or remove them from a project directory
# usage: /uninstall-custom-commands [project-path]
#
# Global uninstall (no args) works from any directory — all paths are known constants.
# Project uninstall removes the fixed set of commands this repo installs.

set -euo pipefail

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
    for name in ping now commands-help install-custom-commands uninstall-custom-commands \
                create-command-from-script remove-command; do
        removed=0
        [[ -f "$COMMANDS_DIR/$name.sh" ]] && { rm "$COMMANDS_DIR/$name.sh"; removed=1; }
        [[ -f "$COMMANDS_DIR/$name.md" ]] && { rm "$COMMANDS_DIR/$name.md"; removed=1; }
        [[ $removed -eq 1 ]] && printf '  Removed: /%s\n' "$name"
    done
    printf '\nDone.\n'
else
    HOOKS_DIR="$HOME/.claude/hooks"
    HOOK_SCRIPT="$HOOKS_DIR/dispatch-commands.sh"
    CHECK_SCRIPT="$HOOKS_DIR/check-slash-conflict.sh"
    SETTINGS="$HOME/.claude/settings.json"
    SKILLS_DIR="$HOME/.claude/skills"

    printf 'Uninstalling custom command dispatcher...\n\n'

    for f in "$HOOK_SCRIPT" "$CHECK_SCRIPT"; do
        if [[ -f "$f" ]]; then
            rm "$f"
            printf '  Removed: %s\n' "$f"
        else
            printf '  Not found (skipped): %s\n' "$f"
        fi
    done

    for skill in create-command refresh-slash-names; do
        target="$SKILLS_DIR/$skill"
        if [[ -d "$target" ]]; then
            rm -rf "$target"
            printf '  Removed: %s\n' "$target"
        else
            printf '  Not found (skipped): %s\n' "$target"
        fi
    done

    if [[ -f "$SETTINGS" ]]; then
        UPDATED=$(python3 - "$SETTINGS" "$HOOK_SCRIPT" << 'PYEOF'
import json, sys, os
settings_path, hook_cmd = sys.argv[1], sys.argv[2]
try:
    s = json.loads(open(settings_path).read())
except (ValueError, OSError):
    print("NO_CHANGE")
    sys.exit(0)
ups = s.get("hooks", {}).get("UserPromptSubmit", [])
filtered = [
    entry for entry in ups
    if not any(h.get("command") == hook_cmd for h in entry.get("hooks", []))
]
if len(filtered) == len(ups):
    print("NOT_FOUND")
    sys.exit(0)
if filtered:
    s["hooks"]["UserPromptSubmit"] = filtered
else:
    s["hooks"].pop("UserPromptSubmit", None)
    if not s["hooks"]:
        del s["hooks"]
print(json.dumps(s, indent=2))
PYEOF
        )
        if [[ "$UPDATED" == "NO_CHANGE" ]]; then
            printf '  settings.json unreadable or invalid JSON -- skipped\n' >&2
        elif [[ "$UPDATED" == "NOT_FOUND" ]]; then
            printf '  Hook not found in %s -- skipped\n' "$SETTINGS"
        else
            printf '%s\n' "$UPDATED" > "$SETTINGS"
            printf '  Removed hook entry from %s\n' "$SETTINGS"
        fi
    fi

    printf '\nDone.\n\n'
    printf 'Your command scripts in ~/.claude/commands/ were not removed.\n'
    printf 'To also remove them: rm -rf ~/.claude/commands/\n'
fi
