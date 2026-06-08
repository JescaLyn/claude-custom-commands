---
name: create-command
description: Create a new Claude Code custom command from a description. Generates a bash script and installs it to the project or global commands directory.
argument-hint: "[--force] [name] <description>"
allowed-tools: [Bash, Write]
---

```!
bash "${CLAUDE_SKILL_DIR}/create-command-preflight.sh" "$ARGUMENTS"
```

Read the preflight output above and act on it.

**Stop now if any of these apply:**
- `error:` line present: tell the user and stop.
- `installer: none`: stop — tell the user `create-command-from-script` is not installed and to re-run `/install-custom-commands`.
- `conflict: blocked` with `force: false`: show the WARNING lines from the preflight output and stop — tell the user to re-run with `--force` to override, or choose a different name.

**If `name: infer`:** infer a short, lowercase, hyphenated name from `desc:` (e.g., "show current git branch" → `git-branch`). If `checker:` is not `none`, check for conflicts (one Bash call):
```bash
bash "<checker>" "<inferred-name>"
```
If exit 1: show the output and stop.

State the name you will use before generating the script.

## Generate the script

Write a bash script implementing `desc:`:
- `#!/usr/bin/env bash` header
- `# description:` and `# usage:` lines
- `set -euo pipefail`
- Arguments via `$*`; output to stdout

## Install

Write the generated script to the `tmpfile:` path using the Write tool. Then run (one Bash call):
```bash
bash "<installer>" --force <name> "<tmpfile>"
rm -f "<tmpfile>"
```

## Confirm

State the command name and a one-line summary of what it does.
