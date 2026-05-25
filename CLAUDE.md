# claude-code-commands

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
    create-command-from-script.sh          /create-command-from-script — register a script as a command
  skills/
    create-command/SKILL.md                /create-command — AI generates script from description, installs it

install.sh                                 copies .claude/ to ~/.claude/, registers UserPromptSubmit hook
uninstall.sh                               removes hook scripts, skill, and hook entry; preserves commands/

tests/test-dispatch.sh
tests/test-check-slash-conflict.sh
tests/test-create-command-from-script.sh
```

## Key Decisions

**`UserPromptSubmit` over `UserPromptExpansion`**: `UserPromptExpansion` fires specifically for slash commands and supports per-command matchers, but cannot block inference (no exit 2 support). `UserPromptSubmit` fires on every prompt but can block. The performance cost is negligible — one python3 call plus a file existence check on non-matching prompts.

**Convention over registry**: Commands are discovered by filename. `reset.sh` → `/reset`. No registry file to maintain.

**Direct global install over plugin**: Plugin format is tied to Claude Code's marketplace/cache infrastructure, which is not designed for self-hosted packages. An install script that edits settings.json is simpler and fully self-contained.

**Scripts receive args via unquoted `$ARGS`**: Intentional word-splitting works for flag-style args. Commands that need structured arg parsing receive the raw args string in `$1`.

## Roadmap

**`/refresh-slash-names`**: A skill (or command) that fetches the current list of Claude Code built-in commands and bundled skills from the Claude Code documentation and rewrites `~/.claude/constants/builtin-commands.txt` and `~/.claude/constants/bundled-skills.txt` in place. The lists are currently hardcoded and will drift as Claude Code ships new built-ins and skills. This command makes the update one invocation instead of a manual edit.

## Hook Output Rendering

**How output works**: The dispatcher uses exit 0 with JSON `{"decision": "block", "reason": "..."}` rather than exit 2 + stderr. This blocks inference and surfaces the command output via the `reason` field. Exit 2 also works but always triggers the "operation blocked" banner with no control over its content.

**Suppressing the footer**: `suppressOriginalPrompt: true` inside `hookSpecificOutput` (not top-level — the docs example is misleading) removes the "Original prompt: /foo" footer line.

**The banner is hardcoded**: `UserPromptSubmit operation blocked by hook: [command]: <reason>` cannot be suppressed. There is no documented or undocumented field that removes the header line or the `[command]:` identifier prefix. The minimum visible output is one banner line plus the reason content.

**`/commands-help` instead of `/help`**: Avoided `/help` to prevent shadowing Claude Code's built-in. The command is named `/commands-help` to be unambiguous.
