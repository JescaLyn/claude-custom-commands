# claude-custom-commands

## Problem

Claude Code has two kinds of slash commands: built-in commands (Anthropic-defined, no inference) and skills (user- or Anthropic-defined, inference-based). There is no native way for users to define their own no-inference slash commands — the user-facing equivalent of built-ins. Every user-defined command routes through the skill/inference layer, so even a utility that just prints the current date spends a model call and adds latency.

## Approach

A `UserPromptSubmit` hook intercepts all prompts before they reach the model. If the prompt matches `/<name>` and a script exists at `~/.claude/commands/<name>.sh`, the hook runs the script and returns JSON `{"decision":"block"}` to suppress inference. Everything else passes through transparently in ~5ms.

This is not a plugin — the plugin format requires marketplace infrastructure. It is a git repo with an `install.sh` that registers the hook in `~/.claude/settings.json`.

## Architecture

```
.claude/                                   mirrors ~/.claude/; install.sh copies these into place
  hooks/
    dispatch-commands.sh             UserPromptSubmit hook; runs scripts, returns JSON {decision:block}
    check-slash-conflict.sh                warns if a name shadows a built-in or installed skill
  constants/
    builtin-commands.txt                   one built-in name per line; read by check-slash-conflict.sh
    bundled-skills.txt                     one bundled skill name per line; read by check-slash-conflict.sh
  commands/
    ping.sh                                /ping — smoke test
    now.sh                                 /now  — current date/time
    commands-help.sh                       /commands-help — list registered commands
    install-custom-commands.sh             /install-custom-commands — install globally or into a project
    uninstall-custom-commands.sh           /uninstall-custom-commands — uninstall globally or remove from a project
    create-command-from-script.sh          /create-command-from-script — register a script as a command
    remove-command.sh                      /remove-command — uninstall a custom command
  skills/
    create-command/SKILL.md                /create-command — AI generates script from description, installs it
    refresh-slash-names/SKILL.md           /refresh-slash-names — update built-in and skill constant lists

install.sh                                 thin wrapper; delegates to install-custom-commands.sh
uninstall.sh                               thin wrapper; delegates to uninstall-custom-commands.sh

tests/test-dispatch.sh
tests/test-check-slash-conflict.sh
tests/test-create-command-from-script.sh
tests/test-remove-command.sh
tests/test-install-custom-commands.sh
tests/test-uninstall-custom-commands.sh
tests/test-integration.sh
```

## Key Decisions

**`UserPromptSubmit` over `UserPromptExpansion`**: `UserPromptExpansion` fires specifically for slash commands and supports per-command matchers, but cannot block inference (no exit 2 support). `UserPromptSubmit` fires on every prompt but can block. The performance cost is negligible — one python3 call plus a file existence check on non-matching prompts.

**Convention over registry**: Commands are discovered by filename. `reset.sh` → `/reset`. No registry file to maintain.

**Direct global install over plugin**: Plugin format is tied to Claude Code's marketplace/cache infrastructure, which is not designed for self-hosted packages. An install script that edits settings.json is simpler and fully self-contained.

**install-custom-commands.sh is the install implementation**: `install.sh` and `uninstall.sh` at the project root are thin wrappers that delegate to the command scripts. The command scripts contain the actual logic so `/install-custom-commands` and `/uninstall-custom-commands` are self-contained — no delegation to a separate file required.

**Project install scope**: Installing with a path arg (`/install-custom-commands /path/to/project`) is fully isolated — hooks, commands, skills, and constants all go to the project's `.claude/` directory. The hook is registered in the project's `.claude/settings.json` using `${CLAUDE_PROJECT_DIR}/.claude/hooks/dispatch-commands.sh` so it resolves correctly regardless of working directory. Nothing is written to `~/.claude/`.

**Global uninstall requires no repo dir**: `uninstall-custom-commands.sh` hardcodes all paths it removes (hooks, skill names, hook entry). Project uninstall hardcodes the list of command names this repo manages. Neither mode needs the repo to be present.

**Scripts receive args via unquoted `$ARGS`**: Intentional word-splitting works for flag-style args. Commands that need structured arg parsing receive the raw args string in `$1`.

## Hook Output Rendering

**How output works**: The dispatcher uses exit 0 with JSON `{"decision": "block", "reason": "..."}` rather than exit 2 + stderr. This blocks inference and surfaces the command output via the `reason` field. Exit 2 also works but always triggers the "operation blocked" banner with no control over its content.

**Suppressing the footer**: `suppressOriginalPrompt: true` inside `hookSpecificOutput` (not top-level — the docs example is misleading) removes the "Original prompt: /foo" footer line.

**The banner is hardcoded**: `UserPromptSubmit operation blocked by hook: [command]: <reason>` cannot be suppressed. There is no documented or undocumented field that removes the header line or the `[command]:` identifier prefix. The minimum visible output is one banner line plus the reason content.

**`/commands-help` instead of `/help`**: Avoided `/help` to prevent shadowing Claude Code's built-in. The command is named `/commands-help` to be unambiguous.
