---
name: refresh-slash-names
description: Update the built-in command and bundled skill lists from the Claude Code documentation.
allowed-tools: [WebSearch, WebFetch, Write, Bash]
---

Update `~/.claude/constants/builtin-commands.txt` and `~/.claude/constants/bundled-skills.txt` with current names from the Claude Code documentation. Run this when conflict warnings seem stale or after a Claude Code update.

## Steps

**1. Find and fetch the documentation**

Search for the current Claude Code slash commands or CLI reference documentation. Look for a page listing:
- Built-in slash commands (no inference: `/clear`, `/help`, `/model`, etc.)
- Bundled skills (inference-based: `/review`, etc.)

Fetch the page and extract both lists. Built-ins are commands that run without an LLM call; skills use inference.

**2. Resolve the constants directory**

```bash
_PROJ="${CLAUDE_PROJECT_DIR:-}"
CONSTANTS_DIR="${CLAUDE_CONSTANTS_DIR:-${_PROJ:+$_PROJ/.claude/constants}}"
CONSTANTS_DIR="${CONSTANTS_DIR:-$HOME/.claude/constants}"
```

**3. Write the files**

Write one name per line (no leading slash, sorted) to:
- `$CONSTANTS_DIR/builtin-commands.txt`
- `$CONSTANTS_DIR/bundled-skills.txt`

**4. Confirm**

State how many built-ins and skills were written and the source URL. Note: `check-slash-conflict.sh` reads the files at invocation time, so changes take effect immediately with no restart needed.
