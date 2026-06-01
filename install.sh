#!/usr/bin/env bash
# Installs the custom command dispatcher into ~/.claude.
#
# What this does:
#   - Copies .claude/hooks/             → ~/.claude/hooks/
#   - Copies .claude/commands/   → ~/.claude/commands/ (skips existing)
#   - Copies .claude/skills/            → ~/.claude/skills/
#   - Adds UserPromptSubmit hook to ~/.claude/settings.json

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$HOME/.claude/hooks"
HOOK_SCRIPT="$HOOKS_DIR/dispatch-commands.sh"
CHECK_SCRIPT="$HOOKS_DIR/check-slash-conflict.sh"
COMMAND_DIR="${CLAUDE_COMMANDS_DIR:-$HOME/.claude/commands}"
CONSTANTS_DIR="$HOME/.claude/constants"
SKILLS_DIR="$HOME/.claude/skills"
SETTINGS="$HOME/.claude/settings.json"

if ! command -v python3 &>/dev/null; then
    printf 'Error: python3 is required but not found.\n' >&2
    exit 1
fi

printf 'Installing custom command dispatcher...\n\n'

# Directories
mkdir -p "$HOOKS_DIR" "$COMMAND_DIR" "$CONSTANTS_DIR" "$SKILLS_DIR"

# Copy hooks
cp "$REPO_DIR/.claude/hooks/dispatch-commands.sh" "$HOOK_SCRIPT"
cp "$REPO_DIR/.claude/hooks/check-slash-conflict.sh" "$CHECK_SCRIPT"
chmod +x "$HOOK_SCRIPT" "$CHECK_SCRIPT"
printf '  Installed: %s\n' "$HOOK_SCRIPT"
printf '  Installed: %s\n' "$CHECK_SCRIPT"

# Copy constants
cp "$REPO_DIR/.claude/constants/builtin-commands.txt" "$CONSTANTS_DIR/builtin-commands.txt"
cp "$REPO_DIR/.claude/constants/bundled-skills.txt" "$CONSTANTS_DIR/bundled-skills.txt"
printf '  Installed: %s\n' "$CONSTANTS_DIR/builtin-commands.txt"
printf '  Installed: %s\n' "$CONSTANTS_DIR/bundled-skills.txt"

# Copy built-in commands (skip if the user already has a version)
printf '\nBuilt-in commands:\n'
for cmd in "$REPO_DIR/.claude/commands/"*.sh; do
    name=$(basename "$cmd")
    dest="$COMMAND_DIR/$name"
    if [[ -f "$dest" ]]; then
        printf '  Skipped (exists): /%s\n' "${name%.sh}"
    else
        cp "$cmd" "$dest"
        chmod +x "$dest"
        printf '  Installed: /%s\n' "${name%.sh}"
    fi
done
# Copy autocomplete stubs (skip if present; silently, no separate output)
for stub in "$REPO_DIR/.claude/commands/"*.md; do
    [[ -f "$stub" ]] || continue
    dest="$COMMAND_DIR/$(basename "$stub")"
    [[ -f "$dest" ]] || cp "$stub" "$dest"
done

# Install skills (all subdirectories of .claude/skills/)
printf '\nSkills:\n'
for skill_dir in "$REPO_DIR/.claude/skills/"/*/; do
    [[ -d "$skill_dir" ]] || continue
    skill=$(basename "$skill_dir")
    SKILL_DEST_DIR="$SKILLS_DIR/$skill"
    mkdir -p "$SKILL_DEST_DIR"
    cp "$skill_dir/SKILL.md" "$SKILL_DEST_DIR/SKILL.md"
    printf '  Installed: %s\n' "$SKILL_DEST_DIR/SKILL.md"
done

# Register hook in settings.json
printf '\nHook registration:\n'
UPDATED=$(python3 - "$SETTINGS" "$HOOK_SCRIPT" << 'PYEOF'
import json, sys, os
settings_path, hook_cmd = sys.argv[1], sys.argv[2]
try:
    s = json.loads(open(settings_path).read()) if os.path.exists(settings_path) else {}
except ValueError:
    s = {}
ups = s.setdefault("hooks", {}).setdefault("UserPromptSubmit", [])
for entry in ups:
    for h in entry.get("hooks", []):
        if h.get("command") == hook_cmd:
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

printf '\nDone. Restart Claude Code for the hook to take effect.\n\n'
printf 'Try it:\n'
printf '  /ping         — smoke test\n'
printf '  /now          — current date and time\n'
printf '  /commands-help — list all commands\n\n'
printf 'Create or remove a command:\n'
printf '  /create-command <description>             — AI writes the script\n'
printf '  /create-command-from-script <name> <path> — register your own script\n'
printf '  /remove-command <name>                    — uninstall a command\n'
