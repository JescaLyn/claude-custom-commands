---
name: refresh-slash-names
description: Update the built-in command and bundled skill lists from the Claude Code documentation.
allowed-tools: [WebSearch, WebFetch, Bash]
model: haiku
effort: low
context: fork
---

Update `builtin-commands.txt` and `bundled-skills.txt` with current names from the Claude Code documentation. Run this when conflict warnings seem stale or after a Claude Code update.

## Steps

**1. Find and fetch the documentation**

Search for the current Claude Code slash commands or CLI reference documentation. Look for a page listing:
- Built-in slash commands (no inference: `/clear`, `/help`, `/model`, etc.)
- Bundled skills (inference-based: `/review`, etc.)

Fetch the page and extract both lists. Built-ins are commands that run without an LLM call; bundled skills use inference.

**2. Run the write script**

Find the script (Bash call):
```bash
WRITER=""
[[ -f "$HOME/.claude/skills/refresh-slash-names/write-slash-names.sh" ]] && WRITER="$HOME/.claude/skills/refresh-slash-names/write-slash-names.sh"
[[ -z "$WRITER" && -f "$PWD/.claude/skills/refresh-slash-names/write-slash-names.sh" ]] && WRITER="$PWD/.claude/skills/refresh-slash-names/write-slash-names.sh"
echo "${WRITER:-none}"
```

Capture the printed path as `WRITER`. If `none`, stop and tell the user the script is not installed — they may need to re-run `/install-custom-commands`.

Otherwise, run this (Bash call), substituting the actual names extracted in step 1 into the `printf` arguments:
```bash
BUILTINS_TMP=$(mktemp)
SKILLS_TMP=$(mktemp)
printf '%s\n' <builtin-name-1> <builtin-name-2> ... > "$BUILTINS_TMP"
printf '%s\n' <skill-name-1> <skill-name-2> ...    > "$SKILLS_TMP"
bash "$WRITER" "$BUILTINS_TMP" "$SKILLS_TMP"
rm -f "$BUILTINS_TMP" "$SKILLS_TMP"
```

Report the counts and paths printed by the script. Note: `check-slash-conflict.sh` reads the files at invocation time, so changes take effect immediately with no restart needed.
