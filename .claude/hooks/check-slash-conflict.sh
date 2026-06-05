#!/usr/bin/env bash
# Checks a slash command name for conflicts with built-ins, bundled skills, installed
# skills, and existing custom commands. Cross-scope aware.
#
# Direct mode:  check-slash-conflict <name>
#   Exit 0 = no conflicts. Exit 1 = conflicts found (prints each as WARNING).
#   Used by create-command-from-script.sh before registering a command.
#
# Hook mode:  (no args) — registered as PreToolUse:Write in settings.json
#   Reads tool JSON from stdin. Fires only on Write calls to commands/*.md or
#   skills/*/SKILL.md, and only for new files (not updates).
#   On conflict: blocks (exit 2) with approval instructions. If a session approval
#   file exists, clears it and allows the write.
#
# Override lookup dirs for testing:
#   CLAUDE_COMMANDS_DIR, CLAUDE_SKILLS_DIR, CLAUDE_CONSTANTS_DIR

set -euo pipefail

cd "$HOME"  # python3 needs an accessible CWD to import modules

_PROJ="${CLAUDE_PROJECT_DIR:-}"
COMMAND_DIR="${CLAUDE_COMMANDS_DIR:-${_PROJ:+$_PROJ/.claude/commands}}"
COMMAND_DIR="${COMMAND_DIR:-$HOME/.claude/commands}"
SKILLS_DIR="${CLAUDE_SKILLS_DIR:-${_PROJ:+$_PROJ/.claude/skills}}"
SKILLS_DIR="${SKILLS_DIR:-$HOME/.claude/skills}"
# Constants are facts about Claude Code itself — prefer global, fall back to project-local.
if [[ -n "${CLAUDE_CONSTANTS_DIR:-}" ]]; then
    CONSTANTS_DIR="$CLAUDE_CONSTANTS_DIR"
elif [[ -d "$HOME/.claude/constants" ]]; then
    CONSTANTS_DIR="$HOME/.claude/constants"
elif [[ -n "$_PROJ" ]]; then
    CONSTANTS_DIR="$_PROJ/.claude/constants"
else
    CONSTANTS_DIR="$HOME/.claude/constants"
fi

IS_GLOBAL=false
HOOK_MODE=false
APPROVAL_FILE=""

if [[ $# -ge 1 ]]; then
    NAME="$1"
    # Infer scope from install target
    [[ "$COMMAND_DIR" == "$HOME/.claude/"* ]] && IS_GLOBAL=true
else
    HOOK_MODE=true
    INPUT=$(cat)
    PARSED=$(printf '%s' "$INPUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
if d.get('tool_name') != 'Write':
    sys.exit(1)
fp = d.get('tool_input', {}).get('file_path', '')
sid = d.get('session_id', 'shared')
print(fp)
print(sid)
" 2>/dev/null) || exit 0

    FILE_PATH=$(printf '%s\n' "$PARSED" | head -1)
    SESSION_ID=$(printf '%s\n' "$PARSED" | tail -1)

    IS_COMMAND=false
    if [[ "$FILE_PATH" =~ \.claude/commands/([^/]+)\.md$ ]]; then
        NAME="${BASH_REMATCH[1]}"
        IS_COMMAND=true
    elif [[ "$FILE_PATH" =~ \.claude/skills/([^/]+)/SKILL\.md$ ]]; then
        NAME="${BASH_REMATCH[1]}"
    else
        exit 0
    fi

    [[ -f "$FILE_PATH" ]] && exit 0  # updating an existing file, not creating

    [[ "$FILE_PATH" == "$HOME/.claude/"* ]] && IS_GLOBAL=true

    APPROVAL_FILE="$HOME/.claude/.tmp/sessions/$SESSION_ID/slash-conflict-approved-$NAME"
    if [[ -f "$APPROVAL_FILE" ]]; then
        rm -f "$APPROVAL_FILE"
        exit 0
    fi

    # Skill writes have different conflict semantics from command writes.
    if [[ "$IS_COMMAND" == "false" ]]; then
        SKILL_BLOCKS=()  # require user confirmation before proceeding
        SKILL_NOTES=()   # informational — model can auto-approve

        # Custom command at same name: the command script intercepts typed /name entirely.
        if [[ -f "$COMMAND_DIR/$NAME.sh" ]]; then
            SKILL_BLOCKS+=("A custom command exists at $COMMAND_DIR/$NAME.sh. The command script will run instead of this skill when /$NAME is typed directly. Remove the custom command first if you want the skill to take effect.")
        fi
        if [[ "$IS_GLOBAL" == "false" ]] && [[ -f "$HOME/.claude/commands/$NAME.sh" ]]; then
            SKILL_BLOCKS+=("A global custom command exists at ~/.claude/commands/$NAME.sh. It will intercept typed /$NAME in all sessions.")
        fi

        # Built-in/bundled at same name: both appear in the slash menu — informational only.
        if [[ -f "$CONSTANTS_DIR/builtin-commands.txt" ]] && grep -qxF "$NAME" "$CONSTANTS_DIR/builtin-commands.txt" 2>/dev/null; then
            SKILL_NOTES+=("/$NAME is also a Claude Code built-in command — both will appear in the slash menu.")
        fi
        if [[ -f "$CONSTANTS_DIR/bundled-skills.txt" ]] && grep -qxF "$NAME" "$CONSTANTS_DIR/bundled-skills.txt" 2>/dev/null; then
            SKILL_NOTES+=("/$NAME is also a bundled Claude Code skill — both will appear in the slash menu.")
        fi

        [[ ${#SKILL_BLOCKS[@]} -eq 0 ]] && [[ ${#SKILL_NOTES[@]} -eq 0 ]] && exit 0

        {
            if [[ ${#SKILL_BLOCKS[@]} -gt 0 ]]; then
                printf 'Slash command conflict: /%s\n\n' "$NAME"
                for b in "${SKILL_BLOCKS[@]}"; do printf '  • %s\n' "$b"; done
                [[ ${#SKILL_NOTES[@]} -gt 0 ]] && { printf '\nAlso note:\n'; for n in "${SKILL_NOTES[@]}"; do printf '  • %s\n' "$n"; done; }
                printf '\nUse AskUserQuestion to ask the user:\n'
                printf '  "/%s already has a custom command that will intercept it. Remove the command first, or create the skill anyway?"\n' "$NAME"
                printf '  Options: "Remove the command first" / "Create the skill anyway"\n\n'
            else
                printf 'Slash command note: /%s\n\n' "$NAME"
                for n in "${SKILL_NOTES[@]}"; do printf '  • %s\n' "$n"; done
                printf '\nBoth will be available in the slash menu — no action needed from the user.\n\n'
            fi
            printf 'If proceeding, run this before retrying the write:\n'
            printf '  mkdir -p "%s" && touch "%s"\n' "$(dirname "$APPROVAL_FILE")" "$APPROVAL_FILE"
        } >&2
        exit 2
    fi
fi

# --- Conflict checks ---

CONFLICTS=()

# Built-in CLI commands
if [[ -f "$CONSTANTS_DIR/builtin-commands.txt" ]]; then
    if grep -qxF "$NAME" "$CONSTANTS_DIR/builtin-commands.txt" 2>/dev/null; then
        CONFLICTS+=("/$NAME is a Claude Code built-in command — typing /$NAME will run this custom command instead of the built-in.")
    fi
fi

# Bundled skills
if [[ -f "$CONSTANTS_DIR/bundled-skills.txt" ]]; then
    if grep -qxF "$NAME" "$CONSTANTS_DIR/bundled-skills.txt" 2>/dev/null; then
        CONFLICTS+=("/$NAME is a Claude Code bundled skill — typing /$NAME will run this custom command instead of the bundled skill.")
    fi
fi

# Cross-scope: project-scope shadows global
if [[ "$IS_GLOBAL" == "false" ]]; then
    if [[ -d "$HOME/.claude/skills/$NAME" ]]; then
        CONFLICTS+=("Project-scope /$NAME will shadow global skill ~/.claude/skills/$NAME/.")
    fi
    if [[ -f "$HOME/.claude/commands/$NAME.sh" ]]; then
        CONFLICTS+=("Project-scope /$NAME will shadow global command ~/.claude/commands/$NAME.sh.")
    fi
fi

# Cross-scope: global won't take effect in current project
if [[ "$IS_GLOBAL" == "true" ]] && [[ -n "$_PROJ" ]]; then
    if [[ -d "$_PROJ/.claude/skills/$NAME" ]]; then
        CONFLICTS+=("Global /$NAME won't take effect in this project — $_PROJ/.claude/skills/$NAME/ already exists.")
    fi
    if [[ -f "$_PROJ/.claude/commands/$NAME.sh" ]]; then
        CONFLICTS+=("Global /$NAME won't take effect in this project — $_PROJ/.claude/commands/$NAME.sh already exists.")
    fi
fi

# Same-scope: skill with this name already exists
if [[ -d "$SKILLS_DIR/$NAME" ]]; then
    CONFLICTS+=("/$NAME already exists as a skill at $SKILLS_DIR/$NAME/.")
fi

# Same-scope: command with this name already exists
if [[ -f "$COMMAND_DIR/$NAME.sh" ]]; then
    CONFLICTS+=("/$NAME already exists as a custom command at $COMMAND_DIR/$NAME.sh.")
fi

[[ ${#CONFLICTS[@]} -eq 0 ]] && exit 0

# --- Output ---

if [[ "$HOOK_MODE" == "true" ]]; then
    {
        printf 'Slash command conflict: /%s\n\n' "$NAME"
        for c in "${CONFLICTS[@]}"; do
            printf '  • %s\n' "$c"
        done
        printf '\nUse AskUserQuestion to ask the user:\n'
        printf '  "/%s conflicts with existing slash commands. Proceed anyway?"\n' "$NAME"
        printf '  Options: "Yes, proceed" / "No, pick a different name"\n\n'
        printf 'If the user confirms, run this before retrying the write:\n'
        printf '  mkdir -p "%s" && touch "%s"\n' "$(dirname "$APPROVAL_FILE")" "$APPROVAL_FILE"
    } >&2
    exit 2
else
    for c in "${CONFLICTS[@]}"; do
        printf 'WARNING: %s\n' "$c"
    done
    exit 1
fi
