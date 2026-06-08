---
name: refresh-slash-names
description: Update the built-in command and bundled skill lists from the Claude Code documentation.
allowed-tools: [WebSearch, WebFetch, Write, Bash]
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

**2. Resolve the constants directories (Bash call)**

Always write to the global constants directory. If the current project also has a `.claude/constants/` directory, write there too — this keeps repo-bundled constants current for users who clone the project.

```bash
GLOBAL_CONSTANTS="$HOME/.claude/constants"
mkdir -p "$GLOBAL_CONSTANTS"
PROJECT_CONSTANTS=""
if [[ -d "$PWD/.claude/constants" ]]; then PROJECT_CONSTANTS="$PWD/.claude/constants"; fi
echo "global=$GLOBAL_CONSTANTS"
echo "project=${PROJECT_CONSTANTS:-none}"
```

Capture the two printed paths. Use the `global=` value as `$GLOBAL_CONSTANTS` and the `project=` value as `$PROJECT_CONSTANTS` (empty if output was `project=none`) in all subsequent steps.

**3. Write the files**

Write one name per line (no leading slash, sorted alphabetically) to:
- `$GLOBAL_CONSTANTS/builtin-commands.txt`
- `$GLOBAL_CONSTANTS/bundled-skills.txt`

If `$PROJECT_CONSTANTS` is non-empty, write the same content to the corresponding files there too.

**4. Confirm**

State how many built-ins and skills were written, the source URL, and whether project-local constants were also updated. Note: `check-slash-conflict.sh` reads the files at invocation time, so changes take effect immediately with no restart needed.
