#!/usr/bin/env bash
# description: Uninstall custom commands globally, or remove them from a project directory
# usage: /uninstall-custom-commands [project-path]
#
# Global uninstall (no args) works from any directory — all paths are known constants.
# Project uninstall removes everything this repo installed into the project.

set -euo pipefail

if ! command -v python3 &>/dev/null; then
    printf 'Error: python3 is required but not found.\n' >&2
    exit 1
fi

# Remove the repo's hook entry from a settings.json file.
remove_hook_entry() {
    local settings_path="$1" hook_cmd="$2"
    [[ -f "$settings_path" ]] || return 0
    local updated
    updated=$(python3 - "$settings_path" "$hook_cmd" << 'PYEOF'
import json, os, sys
settings_path, hook_cmd = sys.argv[1], sys.argv[2]
try:
    s = json.loads(open(settings_path).read())
except (ValueError, OSError):
    print("NO_CHANGE")
    sys.exit(0)
home = os.environ.get("HOME", "")
def norm(cmd):
    return cmd.replace("$HOME", home) if home else cmd
ups = s.get("hooks", {}).get("UserPromptSubmit", [])
filtered = [
    entry for entry in ups
    if not any(norm(h.get("command", "")) == norm(hook_cmd) for h in entry.get("hooks", []))
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
    if [[ "$updated" == "NO_CHANGE" ]]; then
        printf '  settings.json unreadable or invalid JSON -- skipped\n'
    elif [[ "$updated" == "NOT_FOUND" ]]; then
        printf '  Hook not found in %s -- skipped\n' "$settings_path"
    else
        printf '%s\n' "$updated" > "$settings_path"
        printf '  Removed hook entry from %s\n' "$settings_path"
    fi
}

# Remove the repo's PreToolUse:Write hook entry from a settings.json file.
remove_pretooluse_entry() {
    local settings_path="$1" hook_cmd="$2"
    [[ -f "$settings_path" ]] || return 0
    local updated
    updated=$(python3 - "$settings_path" "$hook_cmd" << 'PYEOF'
import json, os, sys
settings_path, hook_cmd = sys.argv[1], sys.argv[2]
try:
    s = json.loads(open(settings_path).read())
except (ValueError, OSError):
    print("NO_CHANGE")
    sys.exit(0)
home = os.environ.get("HOME", "")
def norm(cmd):
    return cmd.replace("$HOME", home) if home else cmd
pre = s.get("hooks", {}).get("PreToolUse", [])
filtered = [
    entry for entry in pre
    if not (
        entry.get("matcher") == "Write" and
        any(norm(h.get("command", "")) == norm(hook_cmd) for h in entry.get("hooks", []))
    )
]
if len(filtered) == len(pre):
    print("NOT_FOUND")
    sys.exit(0)
if filtered:
    s["hooks"]["PreToolUse"] = filtered
else:
    s["hooks"].pop("PreToolUse", None)
    if not s["hooks"]:
        del s["hooks"]
print(json.dumps(s, indent=2))
PYEOF
    )
    if [[ "$updated" == "NO_CHANGE" ]]; then
        printf '  settings.json unreadable or invalid JSON -- skipped\n'
    elif [[ "$updated" == "NOT_FOUND" ]]; then
        printf '  Conflict-check hook not found in %s -- skipped\n' "$settings_path"
    else
        printf '%s\n' "$updated" > "$settings_path"
        printf '  Removed conflict-check hook entry from %s\n' "$settings_path"
    fi
}

if [[ -n "${1:-}" ]]; then
    PROJECT="${1/#~/$HOME}"
    if [[ ! -d "$PROJECT" ]]; then
        printf 'Error: project directory not found: %s\n' "$PROJECT" >&2
        exit 1
    fi

    printf 'Removing custom commands from %s\n\n' "$PROJECT"

    # Remove command files
    COMMANDS_DIR="$PROJECT/.claude/commands"
    if [[ -d "$COMMANDS_DIR" ]]; then
        for name in ping commands-help uninstall-custom-commands \
                    create-command-from-script remove-command; do
            removed=0
            [[ -f "$COMMANDS_DIR/$name.sh" ]] && { rm "$COMMANDS_DIR/$name.sh"; removed=1; }
            [[ -f "$COMMANDS_DIR/$name.md" ]] && { rm "$COMMANDS_DIR/$name.md"; removed=1; }
            [[ $removed -eq 1 ]] && printf '  Removed: /%s\n' "$name"
        done
    fi

    # Remove constants
    for f in "$PROJECT/.claude/constants/builtin-commands.txt" \
             "$PROJECT/.claude/constants/bundled-skills.txt"; do
        [[ -f "$f" ]] && { rm "$f"; printf '  Removed: %s\n' "$f"; }
    done

    # Remove hook scripts
    for f in "$PROJECT/.claude/hooks/dispatch-commands.sh" \
             "$PROJECT/.claude/hooks/check-slash-conflict.sh"; do
        [[ -f "$f" ]] && { rm "$f"; printf '  Removed: %s\n' "$f"; }
    done

    # Remove skills
    for skill in create-command refresh-slash-names; do
        target="$PROJECT/.claude/skills/$skill"
        [[ -d "$target" ]] && { rm -rf "$target"; printf '  Removed: %s\n' "$target"; }
    done

    # Remove hook entries from project settings.json
    remove_hook_entry "$PROJECT/.claude/settings.json" \
        '${CLAUDE_PROJECT_DIR}/.claude/hooks/dispatch-commands.sh'
    remove_pretooluse_entry "$PROJECT/.claude/settings.json" \
        '${CLAUDE_PROJECT_DIR}/.claude/hooks/check-slash-conflict.sh'

    printf '\nDone.\n'
else
    COMMANDS_DIR="$HOME/.claude/commands"
    HOOKS_DIR="$HOME/.claude/hooks"
    HOOK_SCRIPT="$HOOKS_DIR/dispatch-commands.sh"
    CHECK_SCRIPT="$HOOKS_DIR/check-slash-conflict.sh"
    SETTINGS="$HOME/.claude/settings.json"
    SKILLS_DIR="$HOME/.claude/skills"

    printf 'Uninstalling custom command dispatcher...\n\n'

    # Remove command files
    if [[ -d "$COMMANDS_DIR" ]]; then
        for name in ping commands-help uninstall-custom-commands \
                    create-command-from-script remove-command; do
            removed=0
            [[ -f "$COMMANDS_DIR/$name.sh" ]] && { rm "$COMMANDS_DIR/$name.sh"; removed=1; }
            [[ -f "$COMMANDS_DIR/$name.md" ]] && { rm "$COMMANDS_DIR/$name.md"; removed=1; }
            [[ $removed -eq 1 ]] && printf '  Removed: /%s\n' "$name"
        done
    fi

    # Remove constants
    for f in "$HOME/.claude/constants/builtin-commands.txt" \
             "$HOME/.claude/constants/bundled-skills.txt"; do
        if [[ -f "$f" ]]; then
            rm "$f"
            printf '  Removed: %s\n' "$f"
        else
            printf '  Not found (skipped): %s\n' "$f"
        fi
    done

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
    for skill in create-command refresh-slash-names; do
        target="$SKILLS_DIR/$skill"
        if [[ -d "$target" ]]; then
            rm -rf "$target"
            printf '  Removed: %s\n' "$target"
        else
            printf '  Not found (skipped): %s\n' "$target"
        fi
    done

    remove_hook_entry "$SETTINGS" "$HOOK_SCRIPT"
    remove_pretooluse_entry "$SETTINGS" "$CHECK_SCRIPT"

    printf '\nDone.\n'
fi
