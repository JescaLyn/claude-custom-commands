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

CURRENT_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
PROJECT_COMMANDS_DIR="${CURRENT_PROJECT_DIR:+$CURRENT_PROJECT_DIR/.claude/commands}"
GLOBAL_COMMANDS_DIR="$HOME/.claude/commands"
PROJECT_SKILLS_DIR="${CURRENT_PROJECT_DIR:+$CURRENT_PROJECT_DIR/.claude/skills}"
GLOBAL_SKILLS_DIR="$HOME/.claude/skills"
# Constants are facts about Claude Code itself — prefer global, fall back to project-local.
if [[ -n "${CLAUDE_CONSTANTS_DIR:-}" ]]; then
    CONSTANTS_DIR="$CLAUDE_CONSTANTS_DIR"
elif [[ -d "$HOME/.claude/constants" ]]; then
    CONSTANTS_DIR="$HOME/.claude/constants"
elif [[ -n "$CURRENT_PROJECT_DIR" ]]; then
    CONSTANTS_DIR="$CURRENT_PROJECT_DIR/.claude/constants"
else
    CONSTANTS_DIR="$HOME/.claude/constants"
fi

IS_GLOBAL=false
HOOK_MODE=false
APPROVAL_FILE=""

if [[ $# -ge 1 ]]; then
    NAME="$1"
    # Determine scope: test-override env var > second arg (--global | project-path) > default global
    if [[ -n "${CLAUDE_COMMANDS_DIR:-}" ]]; then
        if [[ "$CLAUDE_COMMANDS_DIR" == "$HOME/.claude/"* ]]; then IS_GLOBAL=true; else IS_GLOBAL=false; fi
    elif [[ "${2:-}" == "--global" ]]; then
        IS_GLOBAL=true
    elif [[ -n "${2:-}" ]]; then
        TARGET_PROJECT_DIR="${2/#~/$HOME}"
        PROJECT_COMMANDS_DIR="$TARGET_PROJECT_DIR/.claude/commands"
        PROJECT_SKILLS_DIR="$TARGET_PROJECT_DIR/.claude/skills"
        IS_GLOBAL=false
    else
        IS_GLOBAL=true
    fi
    if [[ -n "${CLAUDE_COMMANDS_DIR:-}" ]]; then
        RESOLVED_COMMANDS_DIR="$CLAUDE_COMMANDS_DIR"
    elif [[ "$IS_GLOBAL" == "true" ]]; then
        RESOLVED_COMMANDS_DIR="$GLOBAL_COMMANDS_DIR"
    else
        RESOLVED_COMMANDS_DIR="${PROJECT_COMMANDS_DIR:-$GLOBAL_COMMANDS_DIR}"
    fi
    if [[ -n "${CLAUDE_SKILLS_DIR:-}" ]]; then
        RESOLVED_SKILLS_DIR="$CLAUDE_SKILLS_DIR"
    elif [[ "$IS_GLOBAL" == "true" ]]; then
        RESOLVED_SKILLS_DIR="$GLOBAL_SKILLS_DIR"
    else
        RESOLVED_SKILLS_DIR="${PROJECT_SKILLS_DIR:-$GLOBAL_SKILLS_DIR}"
    fi
else
    HOOK_MODE=true

    if ! command -v python3 &>/dev/null; then
        printf 'check-slash-conflict.sh: python3 not found on PATH; conflict checking disabled for this write.\n' >&2
        exit 0
    fi

    INPUT=$(cat)
    set +e
    PARSED=$(printf '%s' "$INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(3)
if d.get('tool_name') != 'Write':
    sys.exit(1)
fp = d.get('tool_input', {}).get('file_path', '')
sid = d.get('session_id', 'shared')
print(fp)
print(sid)
")
    PARSE_EC=$?
    set -e

    if [[ $PARSE_EC -eq 1 ]]; then
        exit 0  # not a Write tool call
    elif [[ $PARSE_EC -ne 0 ]]; then
        printf 'check-slash-conflict.sh: failed to parse hook input JSON (exit %d); conflict check skipped for this write.\n' "$PARSE_EC" >&2
        exit 0
    fi

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

    if [[ "$IS_GLOBAL" == "true" ]]; then
        RESOLVED_COMMANDS_DIR="$GLOBAL_COMMANDS_DIR"
        RESOLVED_SKILLS_DIR="$GLOBAL_SKILLS_DIR"
    else
        RESOLVED_COMMANDS_DIR="${PROJECT_COMMANDS_DIR:-$GLOBAL_COMMANDS_DIR}"
        RESOLVED_SKILLS_DIR="${PROJECT_SKILLS_DIR:-$GLOBAL_SKILLS_DIR}"
    fi

    # Skill writes have different conflict semantics from command writes.
    if [[ "$IS_COMMAND" == "false" ]]; then
        SKILL_BLOCKS=()  # require user confirmation before proceeding
        SKILL_NOTES=()   # informational — model can auto-approve

        # Custom command at same name: the command script intercepts typed /name entirely.
        if [[ -f "$RESOLVED_COMMANDS_DIR/$NAME.sh" ]]; then
            SKILL_BLOCKS+=("A custom command exists at $RESOLVED_COMMANDS_DIR/$NAME.sh. The command script will run instead of this skill when /$NAME is typed directly. Remove the custom command first if you want the skill to take effect.")
        fi
        if [[ "$IS_GLOBAL" == "false" ]] && [[ -f "$GLOBAL_COMMANDS_DIR/$NAME.sh" ]]; then
            SKILL_BLOCKS+=("A global custom command exists at $GLOBAL_COMMANDS_DIR/$NAME.sh. It will intercept typed /$NAME in all sessions.")
        fi

        # Built-in/bundled at same name: both appear in the slash menu — informational only.
        if [[ -f "$CONSTANTS_DIR/builtin-commands.txt" ]] && grep -qxF "$NAME" "$CONSTANTS_DIR/builtin-commands.txt" 2>/dev/null; then
            SKILL_NOTES+=("/$NAME is also a Claude Code built-in command — both will appear in the slash menu.")
        fi
        if [[ -f "$CONSTANTS_DIR/bundled-skills.txt" ]] && grep -qxF "$NAME" "$CONSTANTS_DIR/bundled-skills.txt" 2>/dev/null; then
            SKILL_NOTES+=("/$NAME is also a bundled Claude Code skill — both will appear in the slash menu.")
        fi

        [[ ${#SKILL_BLOCKS[@]} -eq 0 ]] && [[ ${#SKILL_NOTES[@]} -eq 0 ]] && exit 0

        if [[ ${#SKILL_BLOCKS[@]} -gt 0 ]]; then
            {
                printf 'Slash command conflict: /%s\n\n' "$NAME"
                for b in "${SKILL_BLOCKS[@]}"; do printf '  • %s\n' "$b"; done
                [[ ${#SKILL_NOTES[@]} -gt 0 ]] && { printf '\nAlso note:\n'; for n in "${SKILL_NOTES[@]}"; do printf '  • %s\n' "$n"; done; }
                printf '\nUse AskUserQuestion to ask the user:\n'
                printf '  "/%s already has a custom command that will intercept it. Remove the command first, or create the skill anyway?"\n' "$NAME"
                printf '  Options: "Remove the command first" / "Create the skill anyway"\n\n'
                printf 'If the user confirms, run this before retrying the write:\n'
                printf '  mkdir -p "%s" && touch "%s"\n' "$(dirname "$APPROVAL_FILE")" "$APPROVAL_FILE"
            } >&2
            exit 2
        else
            {
                printf 'Slash command note: /%s\n\n' "$NAME"
                for n in "${SKILL_NOTES[@]}"; do printf '  • %s\n' "$n"; done
                printf '\nBoth will appear in the slash menu — no action needed.\n'
            } >&2
            exit 0
        fi
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
    if [[ -d "$GLOBAL_SKILLS_DIR/$NAME" ]]; then
        CONFLICTS+=("Project-scope /$NAME will shadow global skill $GLOBAL_SKILLS_DIR/$NAME/.")
    fi
    if [[ -f "$GLOBAL_COMMANDS_DIR/$NAME.sh" ]]; then
        CONFLICTS+=("Project-scope /$NAME will shadow global command $GLOBAL_COMMANDS_DIR/$NAME.sh.")
    fi
fi

# Cross-scope: global won't take effect in current project
if [[ "$IS_GLOBAL" == "true" ]] && [[ -n "$PROJECT_COMMANDS_DIR" ]]; then
    if [[ -d "$PROJECT_SKILLS_DIR/$NAME" ]]; then
        CONFLICTS+=("Global /$NAME won't take effect in this project — $PROJECT_SKILLS_DIR/$NAME/ already exists.")
    fi
    if [[ -f "$PROJECT_COMMANDS_DIR/$NAME.sh" ]]; then
        CONFLICTS+=("Global /$NAME won't take effect in this project — $PROJECT_COMMANDS_DIR/$NAME.sh already exists.")
    fi
fi

# Same-scope: skill with this name already exists
if [[ -d "$RESOLVED_SKILLS_DIR/$NAME" ]]; then
    CONFLICTS+=("/$NAME already exists as a skill at $RESOLVED_SKILLS_DIR/$NAME/.")
fi

# Same-scope: command with this name already exists
if [[ -f "$RESOLVED_COMMANDS_DIR/$NAME.sh" ]]; then
    CONFLICTS+=("/$NAME already exists as a custom command at $RESOLVED_COMMANDS_DIR/$NAME.sh.")
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
