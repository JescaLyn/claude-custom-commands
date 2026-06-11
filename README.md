# Custom Commands for Claude Code

User-defined slash commands that run deterministic bash scripts, with no LLM inference. Invoked exactly like skills — type `/name` — but backed by a shell script instead of a model call.

## Quick Start

Requires `bash` and `python3`.

```bash
git clone https://github.com/JescaLyn/claude-custom-commands
cd claude-custom-commands
claude
```

### Install

```
/install-custom-commands                    # global — writes to ~/.claude/
/install-custom-commands /path/to/project   # project — writes to .claude/ only
```

Restart Claude Code after installing (`/exit`, then `claude` again).

### Try It Out

```
# custom commands (no inference):
/ping                                                    # confirm the dispatcher is active
/now                                                     # current date and time
/commands-help                                           # list all registered commands
/create-command-from-script deploy ./deploy.sh           # register your own script

# skill (uses inference):
/create-command show the current git branch              # describe it; Claude writes the script
/create-command git-branch show the current git branch   # same, with an explicit name
```

## Uninstall

```
/uninstall-custom-commands                    # global uninstall
/uninstall-custom-commands /path/to/project   # remove from a specific project
```

If Claude Code isn't available: `./uninstall.sh`. Your scripts in `~/.claude/commands/` are preserved — remove them manually if needed.

## Minimal Install

Installs just the dispatcher hook and an empty `commands/` directory — no management commands, skills, constants, or conflict-check hook. For project installs, adds a note to the project's README pointing to this repo.

Run from the repo directory:

```
/install-custom-commands-minimal /path/to/project
/install-custom-commands-minimal
```

**Use this** when you're adding custom command support to a project with its own bespoke commands and don't need the management scaffolding (`/ping`, `/commands-help`, `/create-command-from-script`, etc.). `/uninstall-custom-commands` works on both full and minimal installs.

## Included Commands and Skills

### Commands

Deterministic scripts available via slash command — no inference.

| Command                                       | What it does |
|-----------------------------------------------|---|
| `/commands-help`                              | List all registered custom commands |
| `/create-command-from-script <name> <path>`   | Register an existing script as a command |
| `/now`                                        | Show the current date and time |
| `/ping`                                       | Confirm the dispatcher is active |
| `/remove-command <name>`                      | Remove a custom command by name |
| `/uninstall-custom-commands`                  | Uninstall globally; works from any directory |
| `/uninstall-custom-commands <project-path>`   | Remove from a specific project |

### Skills

Use inference. Loaded from `.claude/skills/` or `~/.claude/skills/`.

| Skill                                         | What it does |
|-----------------------------------------------|---|
| `/create-command [name] <description>`        | AI writes a bash script from your description and installs it |
| `/refresh-slash-names`                        | Update the built-in command and bundled skill name lists |

### This Repo Only

Available only when running Claude Code from within this repository. Not installed globally or into projects.

| Command                              | What it does |
|--------------------------------------|---|
| `/install-custom-commands`           | Full install — hooks, commands, skills, and constants |
| `/install-custom-commands-minimal`   | Minimal install — dispatcher hook and empty `commands/` directory |

## How It Works

A `UserPromptSubmit` hook intercepts all prompts before the model sees them. If you type `/deploy` and `~/.claude/commands/deploy.sh` exists, the hook runs that script and returns its output, suppressing inference entirely. Every other prompt passes through untouched in under 5ms.

### Slash command types

Claude Code has four kinds of slash commands:

| Type | Defined by | Inference | Examples |
|---|---|---|---|
| Built-in commands | Anthropic (hardcoded in CLI) | No | `/clear`, `/compact`, `/model` |
| Bundled skills | Anthropic | Yes | `/review`, `/init` |
| Custom skills | User | Yes | `/create-command`, `/my-workflow` |
| **Custom commands** | **User (this project)** | **No** | **`/ping`, `/deploy`** |

Custom commands are the user-definable equivalent of built-in commands: fixed-logic operations backed by bash scripts, invoked with the same `/name` syntax as skills.

### Command output

Every command output is preceded by a header line that Claude Code injects:

```
UserPromptSubmit operation blocked by hook:

╭─ /ping ────────────────────────────────────
│
│ pong — custom command dispatcher is active
╰────────────────────────────────────────────
```

The banner line is hardcoded by Claude Code and cannot be suppressed. The box-framed output that follows is from the command script.

### Conflict checking

A `PreToolUse:Write` hook (`check-slash-conflict.sh`) fires whenever Claude Code writes a new command or skill file. It checks the name against Claude Code's built-in commands and bundled skills, as well as any existing commands and skills at the same scope, and blocks the write if a conflict would cause a command to silently shadow something else. You can override the block when prompted.

The `constants/` directory holds `builtin-commands.txt` and `bundled-skills.txt` — one name per line. These are what `check-slash-conflict.sh` reads to detect conflicts.

## Refreshing Slash Names

Claude Code's built-in commands and bundled skills change between versions. The `constants/` directory stores the current lists; `check-slash-conflict.sh` reads them when checking for naming conflicts.

```
/refresh-slash-names
```

Run this after updating Claude Code, or any time the conflict checker flags a name that doesn't seem like a real conflict. When run from within this repository, it also updates `.claude/constants/` in the repo so the bundled constants stay current for users who clone it.

## Creating a Command

**Let Claude write it** — describe what you want, with an optional name:

```
/create-command show the current git branch
/create-command git-branch show the current git branch
```

Claude checks for name conflicts with built-in commands and installed skills, generates the script, and installs it.

**Register your own script:**

```
/create-command-from-script deploy ~/scripts/deploy.sh
```

Both default to project scope when run inside a project (i.e. when `$PWD/.claude` exists), and global scope otherwise. Pass `--global` to force global install regardless. Both check for name conflicts: `/create-command` asks whether to proceed; `/create-command-from-script` blocks and requires `--force` to override.

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

To edit an included command, modify the script in `~/.claude/commands/` directly. The install script skips files that already exist, so edits survive reinstalls.

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_COMMANDS_DIR` | project-local `.claude/commands/`, or `~/.claude/commands` outside a project | Override the directory where command scripts are looked up. Setting this suppresses the project-to-global fallback. |

## Manual Install

Use the terminal directly when Claude Code isn't available:

```bash
./install.sh                    # global
./install.sh /path/to/project   # project
```

Hook and constant files are always overwritten on reinstall. Command scripts are skipped if they already exist. After `git pull`, re-run `./install.sh` to pick up hook and constant updates.
