#!/usr/bin/env bash
# description: Install custom commands globally, or into a project directory
# usage: /install-custom-commands [project-path]
#
# Must be run from the claude-custom-commands repo directory — source files
# (hooks, commands, skills) are copied from there.
# Project installs are fully isolated: nothing is written to ~/.claude/.

set -euo pipefail

REPO_DIR="$PWD"

if [[ ! -f "$REPO_DIR/.claude/hooks/dispatch-commands.sh" ]]; then
    printf 'Run /install-custom-commands from the claude-custom-commands repo directory.\n' >&2
    printf 'Current directory: %s\n' "$REPO_DIR" >&2
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    printf 'Error: python3 is required but not found.\n' >&2
    exit 1
fi

if [[ -n "${1:-}" ]]; then
    PROJECT="${1/#~/$HOME}"
    if [[ ! -d "$PROJECT" ]]; then
        printf 'Error: project directory not found: %s\n' "$PROJECT" >&2
        exit 1
    fi
    COMMAND_DIR="$PROJECT/.claude/commands"
    HOOKS_DIR="$PROJECT/.claude/hooks"
    CONSTANTS_DIR="$PROJECT/.claude/constants"
    SKILLS_DIR="$PROJECT/.claude/skills"
    SETTINGS="$PROJECT/.claude/settings.json"
    # ${CLAUDE_PROJECT_DIR} is resolved by Claude Code at runtime — use it as a literal
    # so the hook path stays correct regardless of working directory.
    HOOK_CMD='${CLAUDE_PROJECT_DIR}/.claude/hooks/dispatch-commands.sh'
    CONFLICT_HOOK_CMD='${CLAUDE_PROJECT_DIR}/.claude/hooks/check-slash-conflict.sh'
else
    COMMAND_DIR="$HOME/.claude/commands"
    HOOKS_DIR="$HOME/.claude/hooks"
    CONSTANTS_DIR="$HOME/.claude/constants"
    SKILLS_DIR="$HOME/.claude/skills"
    SETTINGS="$HOME/.claude/settings.json"
    HOOK_CMD='$HOME/.claude/hooks/dispatch-commands.sh'
    CONFLICT_HOOK_CMD='$HOME/.claude/hooks/check-slash-conflict.sh'
fi

HOOK_SCRIPT="$HOOKS_DIR/dispatch-commands.sh"
CHECK_SCRIPT="$HOOKS_DIR/check-slash-conflict.sh"

printf 'Installing custom command dispatcher...\n\n'

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

# Copy commands (skip if the user already has a version)
# now.sh is intentionally excluded — it lives in the repo as an example only
printf '\nBuilt-in commands:\n'
for cmd in "$REPO_DIR/.claude/commands/"*.sh; do
    name=$(basename "${cmd%.sh}")
    [[ "$name" == "now" ]] && continue
    [[ "$name" == "install-custom-commands" ]] && continue
    dest="$COMMAND_DIR/$name.sh"
    if [[ -f "$dest" ]]; then
        printf '  Skipped (exists): /%s\n' "$name"
    else
        cp "$cmd" "$dest"
        chmod +x "$dest"
        printf '  Installed: /%s\n' "$name"
    fi
done
# Copy autocomplete stubs (skip if present; silently, no separate output)
for stub in "$REPO_DIR/.claude/commands/"*.md; do
    [[ -f "$stub" ]] || continue
    [[ "$(basename "$stub" .md)" == "now" ]] && continue
    [[ "$(basename "$stub" .md)" == "install-custom-commands" ]] && continue
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

UPDATED=$(python3 - "$SETTINGS" "$CONFLICT_HOOK_CMD" << 'PYEOF'
import json, sys, os
settings_path, hook_cmd = sys.argv[1], sys.argv[2]
try:
    s = json.loads(open(settings_path).read()) if os.path.exists(settings_path) else {}
except ValueError:
    s = {}
home = os.environ.get("HOME", "")
def norm(cmd):
    return cmd.replace("$HOME", home) if home else cmd
pre = s.setdefault("hooks", {}).setdefault("PreToolUse", [])
for entry in pre:
    if entry.get("matcher") == "Write":
        for h in entry.get("hooks", []):
            if norm(h.get("command", "")) == norm(hook_cmd):
                print("ALREADY_REGISTERED")
                sys.exit(0)
pre.append({"matcher": "Write", "hooks": [{"type": "command", "command": hook_cmd}]})
print(json.dumps(s, indent=2))
PYEOF
)
if [[ "$UPDATED" == "ALREADY_REGISTERED" ]]; then
    printf '  Conflict-check hook already registered in %s\n' "$SETTINGS"
else
    printf '%s\n' "$UPDATED" > "$SETTINGS"
    printf '  Registered PreToolUse:Write hook in %s\n' "$SETTINGS"
fi

printf '\nDone. Restart Claude Code for the hook to take effect.\n\n'
printf 'Try it:\n'
printf '  /ping          -- smoke test\n'
printf '  /commands-help -- list all commands\n\n'
printf 'Create or remove a command:\n'
printf '  /create-command <description>             -- AI writes the script\n'
printf '  /create-command-from-script <name> <path> -- register your own script\n'
printf '  /remove-command <name>                    -- uninstall a command\n'
