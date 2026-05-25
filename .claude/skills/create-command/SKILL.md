---
name: create-command
description: Create a new Claude Code custom command from a description. Generates a bash script and installs it to ~/.claude/commands/.
argument-hint: [name] <description>
allowed-tools: [Bash, Write]
---

The user wants a new custom command — a deterministic bash script invoked as `/<name>` in Claude Code with no LLM inference.

## Parse arguments

`$ARGUMENTS` contains an optional name and a description. Parse it:

- If the first token matches `[a-zA-Z][a-zA-Z0-9_-]*` and there are more tokens after it, treat the first token as the name and the remainder as the description.
- Otherwise treat the entire string as the description and infer a short, lowercase, hyphenated name from it (e.g. "show current git branch" → `git-branch`).
- If `$ARGUMENTS` is empty, ask the user to describe what the command should do.

State the name you plan to use before proceeding.

## Steps (max 2 name-negotiation rounds)

**1. Check for conflicts**

```bash
bash ~/.claude/hooks/check-slash-conflict.sh <name>
```

If exit 1: show the warnings and ask whether to proceed or choose a different name. If exit 0: proceed. If the script is missing, skip this step and note it.

**2. Generate the script**

Write a bash script that implements the description:
- `#!/usr/bin/env bash` header
- `# description:` and `# usage:` lines
- `set -euo pipefail` unless the script is trivially short
- Arguments via `$*`; output to stdout

**3. Install**

1. `mkdir -p ~/.claude/commands`
2. Write the generated script to `~/.claude/commands/<name>.sh` using the `Write` tool.
3. `chmod +x ~/.claude/commands/<name>.sh`
4. Write an autocomplete stub to `~/.claude/commands/<name>.md` with the one-line description as its only content (skip if the file already exists).

**4. Confirm**

State the command name and a one-line summary of what it does.
