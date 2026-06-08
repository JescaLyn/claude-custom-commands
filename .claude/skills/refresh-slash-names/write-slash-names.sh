#!/usr/bin/env bash
# write-slash-names.sh — write built-in command and bundled skill name lists to constants dirs
# Usage: write-slash-names.sh <builtins-file> <skills-file>
#
# Writes to ~/.claude/constants/ (global) and, if $PWD/.claude/constants/ exists, there too.
# Normalizes each file: strips leading slashes, removes blank lines, sorts, deduplicates.

set -euo pipefail

if [[ $# -ne 2 ]]; then
    printf 'Usage: write-slash-names.sh <builtins-file> <skills-file>\n' >&2
    exit 1
fi

BUILTINS_FILE="$1"
SKILLS_FILE="$2"

[[ -f "$BUILTINS_FILE" ]] || { printf 'Error: builtins file not found: %s\n' "$BUILTINS_FILE" >&2; exit 1; }
[[ -f "$SKILLS_FILE" ]]   || { printf 'Error: skills file not found: %s\n'   "$SKILLS_FILE"   >&2; exit 1; }

normalize() {
    local src="$1" dst="$2"
    local tmp
    tmp=$(mktemp)
    { sed 's|^/||' "$src" | grep -v '^[[:space:]]*$' || true; } | sort -u > "$tmp"
    mv "$tmp" "$dst"
}

GLOBAL_CONSTANTS="$HOME/.claude/constants"
mkdir -p "$GLOBAL_CONSTANTS"

normalize "$BUILTINS_FILE" "$GLOBAL_CONSTANTS/builtin-commands.txt"
normalize "$SKILLS_FILE"   "$GLOBAL_CONSTANTS/bundled-skills.txt"

PROJECT_CONSTANTS=""
if [[ -d "$PWD/.claude/constants" ]]; then
    PROJECT_CONSTANTS="$PWD/.claude/constants"
    normalize "$BUILTINS_FILE" "$PROJECT_CONSTANTS/builtin-commands.txt"
    normalize "$SKILLS_FILE"   "$PROJECT_CONSTANTS/bundled-skills.txt"
fi

BUILTIN_COUNT=$(awk 'END{print NR}' "$GLOBAL_CONSTANTS/builtin-commands.txt")
SKILL_COUNT=$(awk 'END{print NR}'   "$GLOBAL_CONSTANTS/bundled-skills.txt")

printf 'builtin-commands: %d\n' "$BUILTIN_COUNT"
printf 'bundled-skills: %d\n'   "$SKILL_COUNT"
if [[ -n "$PROJECT_CONSTANTS" ]]; then printf 'project-local: %s\n' "$PROJECT_CONSTANTS"; fi
