#!/usr/bin/env bash
# Pre-inference preflight for /create-command.
# Called via SKILL.md shell substitution before Claude processes the prompt.
# Parses arguments, detects scope, locates tools, creates tmpfile, checks conflicts.
#
# Usage: create-command-preflight.sh "<full-arguments-string>"
#   $1 = raw $ARGUMENTS from the skill (the full string, quoted)
#
# Output (key: value):
#   force: true|false
#   global: true|false
#   name:  <name>|infer
#   desc:  <description>
#   scope: project|global
#   installer: <path>|none
#   installer_flags: --force [--global]
#   checker:   <path>|none
#   tmpfile:   <path>
#   conflict:  none|blocked
#   (if blocked, WARNING: lines follow)

set -euo pipefail

FULL_ARGS="${1:-}"

# --- Parse flags (--force, --global) in any order ---
FORCE=false
GLOBAL=false
REST="$FULL_ARGS"

while true; do
    if [[ "$REST" == "--force" || "$REST" == "--force "* ]]; then
        FORCE=true
        REST="${REST#--force}"
        REST="${REST#"${REST%%[! ]*}"}"
    elif [[ "$REST" == "--global" || "$REST" == "--global "* ]]; then
        GLOBAL=true
        REST="${REST#--global}"
        REST="${REST#"${REST%%[! ]*}"}"
    else
        break
    fi
done

# --- Handle empty ---
if [[ -z "$REST" ]]; then
    printf 'error: no description provided — describe what the command should do\n'
    exit 0
fi

# --- Parse name vs description ---
# If string starts with a valid name token followed by a space and more text,
# treat the first token as the name. Otherwise the entire string is the description.
NAME="infer"
DESC="$REST"
if [[ "$REST" =~ ^([a-zA-Z][a-zA-Z0-9_-]*)[[:space:]]+(.+)$ ]]; then
    NAME="${BASH_REMATCH[1]}"
    DESC="${BASH_REMATCH[2]}"
fi

# --- Detect scope ---
SCOPE="global"
PROJ_DIR=""
if [[ -d "$PWD/.claude" ]]; then
    SCOPE="project"
    PROJ_DIR="$PWD"
fi

# --global overrides auto-detected project scope
if [[ "$GLOBAL" == "true" ]]; then
    SCOPE="global"
    PROJ_DIR=""
fi

# --- Find installer ---
INSTALLER="none"
if [[ -f "$HOME/.claude/commands/create-command-from-script.sh" ]]; then
    INSTALLER="$HOME/.claude/commands/create-command-from-script.sh"
elif [[ -n "$PROJ_DIR" && -f "$PROJ_DIR/.claude/commands/create-command-from-script.sh" ]]; then
    INSTALLER="$PROJ_DIR/.claude/commands/create-command-from-script.sh"
fi

# --- Find conflict checker ---
CHECKER="none"
if [[ -f "$HOME/.claude/hooks/check-slash-conflict.sh" ]]; then
    CHECKER="$HOME/.claude/hooks/check-slash-conflict.sh"
elif [[ -n "$PROJ_DIR" && -f "$PROJ_DIR/.claude/hooks/check-slash-conflict.sh" ]]; then
    CHECKER="$PROJ_DIR/.claude/hooks/check-slash-conflict.sh"
fi

# --- Create tmpfile ---
TMPFILE=$(mktemp -t "create-command-XXXX.sh")

# --- Installer flags (--force always; --global when scope is global) ---
INSTALLER_FLAGS="--force"
[[ "$GLOBAL" == "true" ]] && INSTALLER_FLAGS="--force --global"

# --- Check conflicts (explicit name, not --force, checker available) ---
CONFLICT="none"
CONFLICT_DETAIL=""
if [[ "$NAME" != "infer" && "$FORCE" == "false" && "$CHECKER" != "none" ]]; then
    CONFLICT_DETAIL=$(CLAUDE_PROJECT_DIR="$PROJ_DIR" bash "$CHECKER" "$NAME" 2>/dev/null || true)
    if [[ -n "$CONFLICT_DETAIL" ]]; then
        CONFLICT="blocked"
    fi
fi

# --- Output ---
printf 'force: %s\n' "$FORCE"
printf 'global: %s\n' "$GLOBAL"
printf 'name: %s\n' "$NAME"
printf 'desc: %s\n' "$DESC"
printf 'scope: %s\n' "$SCOPE"
printf 'installer: %s\n' "$INSTALLER"
printf 'installer_flags: %s\n' "$INSTALLER_FLAGS"
printf 'checker: %s\n' "$CHECKER"
printf 'tmpfile: %s\n' "$TMPFILE"
printf 'conflict: %s\n' "$CONFLICT"
if [[ -n "$CONFLICT_DETAIL" ]]; then
    printf '%s\n' "$CONFLICT_DETAIL"
fi
