#!/usr/bin/env bash
# Removes the custom command dispatcher from ~/.claude.
# Does NOT remove ~/.claude/commands/ — your scripts are preserved.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$HOME/.claude/hooks"
HOOK_SCRIPT="$HOOKS_DIR/dispatch-commands.sh"
CHECK_SCRIPT="$HOOKS_DIR/check-slash-conflict.sh"
SETTINGS="$HOME/.claude/settings.json"

printf 'Uninstalling custom command dispatcher...\n\n'

# Remove hook scripts
for f in "$HOOK_SCRIPT" "$CHECK_SCRIPT"; do
    if [[ -f "$f" ]]; then
        rm "$f"
        printf '  Removed: %s\n' "$f"
    else
        printf '  Not found (skipped): %s\n' "$f"
    fi
done

# Remove skills
for skill_dir in "$REPO_DIR/.claude/skills/"/*/; do
    [[ -d "$skill_dir" ]] || continue
    skill=$(basename "$skill_dir")
    target="$HOME/.claude/skills/$skill"
    if [[ -d "$target" ]]; then
        rm -rf "$target"
        printf '  Removed: %s\n' "$target"
    else
        printf '  Not found (skipped): %s\n' "$target"
    fi
done

# Remove hook entry from settings.json
if [[ -f "$SETTINGS" ]]; then
    UPDATED=$(python3 - "$SETTINGS" "$HOOK_SCRIPT" << 'PYEOF'
import json, sys, os
settings_path, hook_cmd = sys.argv[1], sys.argv[2]
try:
    s = json.loads(open(settings_path).read())
except (ValueError, OSError):
    sys.exit(0)
ups = s.get("hooks", {}).get("UserPromptSubmit", [])
filtered = [
    entry for entry in ups
    if not any(h.get("command") == hook_cmd for h in entry.get("hooks", []))
]
if filtered:
    s["hooks"]["UserPromptSubmit"] = filtered
else:
    s["hooks"].pop("UserPromptSubmit", None)
    if not s["hooks"]:
        del s["hooks"]
print(json.dumps(s, indent=2))
PYEOF
    )
    printf '%s\n' "$UPDATED" > "$SETTINGS"
    printf '  Removed hook entry from %s\n' "$SETTINGS"
fi

printf '\nDone.\n\n'
printf 'Your command scripts in ~/.claude/commands/ were not removed.\n'
printf 'To also remove them: rm -rf ~/.claude/commands/\n'
