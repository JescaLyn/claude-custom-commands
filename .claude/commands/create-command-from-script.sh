#!/usr/bin/env bash
# description: Register an existing bash script as a new custom command
# usage: /create-command-from-script [--force] <name> <script-path> [project-path]

set -euo pipefail

usage() {
    printf 'Usage: /create-command-from-script [--force] <name> <script-path> [project-path]\n\n'
    printf '  --force           Create even if name conflicts with a built-in or existing command\n'
    printf '  --name <name>     Flag alternative to positional <name>\n'
    printf '  --script <path>   Flag alternative to positional <script-path>\n'
    printf '  --project <path>  Flag alternative to positional [project-path]\n'
    printf '  name              Name for the new command (becomes /<name>)\n'
    printf '  script-path       Path to an existing bash script\n'
    printf '  project-path      Optional; installs to <project>/.claude/commands/ instead of globally\n'
}

FORCE=false
NAME=""
SCRIPT_PATH=""
TARGET_PROJECT_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --force)   FORCE=true; shift ;;
        --name)    NAME="$2"; shift 2 ;;
        --script)  SCRIPT_PATH="$2"; shift 2 ;;
        --project) TARGET_PROJECT_DIR="${2/#~/$HOME}"; shift 2 ;;
        --*)       printf 'Unknown flag: %s\n' "$1" >&2; exit 1 ;;
        *)
            if   [[ -z "$NAME" ]];               then NAME="$1"
            elif [[ -z "$SCRIPT_PATH" ]];         then SCRIPT_PATH="$1"
            elif [[ -z "$TARGET_PROJECT_DIR" ]];  then TARGET_PROJECT_DIR="${1/#~/$HOME}"
            else printf 'Unexpected argument: %s\n' "$1" >&2; exit 1
            fi
            shift ;;
    esac
done

if [[ -z "$NAME" || -z "$SCRIPT_PATH" ]]; then
    usage
    exit 0
fi

if [[ ! "$NAME" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
    printf 'Invalid name: %s\n' "$NAME"
    printf 'Must start with a letter; only letters, digits, hyphens, and underscores allowed.\n'
    exit 1
fi

if [[ ! -f "$SCRIPT_PATH" ]]; then
    printf 'Script not found: %s\n' "$SCRIPT_PATH"
    exit 1
fi

# Scope: global by default; project when TARGET_PROJECT_DIR is given
GLOBAL_COMMANDS_DIR="$HOME/.claude/commands"
if [[ -n "$TARGET_PROJECT_DIR" ]]; then
    PROJECT_COMMANDS_DIR="$TARGET_PROJECT_DIR/.claude/commands"
    RESOLVED_COMMANDS_DIR="$PROJECT_COMMANDS_DIR"
    IS_GLOBAL=false
else
    RESOLVED_COMMANDS_DIR="$GLOBAL_COMMANDS_DIR"
    IS_GLOBAL=true
fi
RESOLVED_COMMANDS_DIR="${CLAUDE_COMMANDS_DIR:-$RESOLVED_COMMANDS_DIR}"

CHECK_SCRIPT="${CLAUDE_CHECK_SLASH_SCRIPT:-$HOME/.claude/hooks/check-slash-conflict.sh}"

DEST="$RESOLVED_COMMANDS_DIR/$NAME.sh"

if [[ -f "$DEST" ]]; then
    printf 'Command /%s already exists at %s\n' "$NAME" "$DEST"
    printf 'Delete it first, then re-run.\n'
    exit 1
fi

if [[ "$FORCE" == "false" ]] && [[ -x "$CHECK_SCRIPT" ]]; then
    if [[ -n "${CLAUDE_COMMANDS_DIR:-}" ]]; then
        CONFLICTS=$("$CHECK_SCRIPT" "$NAME" 2>/dev/null || true)
    elif [[ "$IS_GLOBAL" == "true" ]]; then
        CONFLICTS=$("$CHECK_SCRIPT" "$NAME" --global 2>/dev/null || true)
    else
        CONFLICTS=$("$CHECK_SCRIPT" "$NAME" "$TARGET_PROJECT_DIR" 2>/dev/null || true)
    fi
    if [[ -n "$CONFLICTS" ]]; then
        printf '%s\n\n' "$CONFLICTS"
        printf 'Command not created. Re-run with --force to override:\n'
        printf '  /create-command-from-script --force %s %s\n' "$NAME" "$SCRIPT_PATH"
        exit 1
    fi
fi

mkdir -p "$RESOLVED_COMMANDS_DIR"
cp "$SCRIPT_PATH" "$DEST"
chmod +x "$DEST"

MD_DEST="$RESOLVED_COMMANDS_DIR/$NAME.md"
if [[ ! -f "$MD_DEST" ]]; then
    DESCRIPTION=$(grep -m1 '^# description:' "$SCRIPT_PATH" 2>/dev/null | sed 's/^# description: *//' || true)
    DESCRIPTION="${DESCRIPTION:-Custom command /$NAME}"
    printf '%s\n\n<!-- Autocomplete stub only. The UserPromptSubmit hook runs %s.sh; this file is never read during command execution. -->\n' \
        "$DESCRIPTION" "$NAME" > "$MD_DEST"
fi

printf 'Created /%s from %s\n' "$NAME" "$SCRIPT_PATH"
printf 'Installed to %s\n' "$RESOLVED_COMMANDS_DIR"
