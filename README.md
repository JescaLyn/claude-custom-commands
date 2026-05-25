# Custom Commands for Claude Code

User-defined slash commands that run deterministic bash scripts, with no LLM inference. Invoked exactly like skills — type `/name` — but backed by a shell script instead of a model call.

## Quick Start

Requires `bash` and `python3`.

```bash
git clone https://github.com/<your-username>/claude-custom-commands
cd claude-custom-commands
./install.sh
```

Restart Claude Code, then try:

```
/ping                                              confirm the hook is active
/create-command show the current git branch        Claude writes and installs a command
/create-command-from-script deploy ./deploy.sh     register your own script
```

## How It Works

A `UserPromptSubmit` hook intercepts all prompts before the model sees them. If you type `/deploy` and `~/.claude/commands/deploy.sh` exists, the hook runs that script and returns its output, suppressing inference entirely. Every other prompt passes through untouched in under 5ms.

## Included Commands

Four commands and one skill are installed:

| Command | Type | What it does |
|---|---|---|
| `/ping` | custom command | Confirm the dispatcher is active |
| `/now` | custom command | Current date and time |
| `/commands-help` | custom command | List all registered custom commands |
| `/create-command-from-script` | custom command | Register an existing script as a command |
| `/create-command` | skill (uses inference) | Describe a command; Claude writes and installs it |

## Creating a Command

**Let Claude write it** — describe what you want, with an optional name:

```
/create-command show the current git branch
/create-command git-branch show the current git branch
```

Claude checks for name conflicts with built-ins and installed skills, generates the script, and installs it.

**Register your own script:**

```
/create-command-from-script deploy ~/scripts/deploy.sh
```

Both methods warn if the name shadows a Claude Code built-in or an installed skill.

**What a command script looks like:**

```bash
#!/usr/bin/env bash
# description: Reset the dev environment to a clean state
# usage: /reset [--hard]

echo "Stopping containers..."
docker compose down 2>&1

echo "Clearing cache..."
rm -rf .build/

echo "Done."
```

Scripts receive arguments as `$*`. Write output to stdout. Exit 0 = success, non-zero = error.

## Slash Command Types in Claude Code

| Type | Defined by | Inference | Examples |
|---|---|---|---|
| Built-in commands | Anthropic (hardcoded in CLI) | No | `/clear`, `/compact`, `/model` |
| Skills | User or Anthropic | Yes | `/review`, `/create-command` |
| **Custom commands** | **User (this project)** | **No** | `/ping`, `/now`, `/deploy` |

Custom commands are the user-definable equivalent of built-in commands: fixed-logic operations backed by bash scripts, invoked with the same `/name` syntax as skills.

## Overriding an Included Command

Edit any script in `~/.claude/commands/` directly. The install script skips files that already exist, so your edits survive reinstalls.

## Testing

```bash
bash tests/test-dispatch.sh
bash tests/test-check-slash-conflict.sh
bash tests/test-create-command-from-script.sh
```

## Uninstall

```bash
./uninstall.sh
```

Your scripts in `~/.claude/commands/` are preserved. Remove them manually if needed:

```bash
rm -rf ~/.claude/commands/
```

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_COMMANDS_DIR` | `~/.claude/commands` | Where command scripts are looked up |

---

## Reference: Claude Code Built-In Commands

Built-in commands run without inference. If you register a custom command with the same name as a built-in, the dispatcher will intercept it and the built-in will no longer be reachable — `check-slash-conflict.sh` warns you when this would happen.

| Command | Purpose |
|---|---|
| `/clear` | Clear conversation history |
| `/compact` | Compact conversation context |
| `/config` | Open the config editor |
| `/context` | Show context window usage |
| `/help` | Show available commands |
| `/hooks` | View active hooks and their sources |
| `/memory` | View and edit memory files |
| `/model` | Switch models |
| `/permissions` | View permission settings |
| `/settings` | View and edit settings |
| `/skills` | Browse available skills |
| `/usage` | Show token and cost usage for the session |

Type `/help` in Claude Code for the authoritative list — the built-ins above are current as of May 2026 but may not be exhaustive.
