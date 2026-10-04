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
    check-slash-conflict.sh          PreToolUse:Write hook; name conflict checker (same-scope and cross-scope); approval-file override
  constants/
    builtin-commands.txt             built-in command names; read by conflict checker; updated by /refresh-slash-names
    bundled-skills.txt               bundled skill names; read by conflict checker; updated by /refresh-slash-names
  commands/
    ping.sh                          /ping — smoke test
    now.sh                           /now — show current date and time
    commands-help.sh                 /commands-help — list registered commands
    install-custom-commands.sh       not installed globally — repo-only; requires repo dir to be present
    install-custom-commands-minimal.sh  not installed globally — repo-only; dispatcher + hook only; annotates project README
    uninstall-custom-commands.sh     /uninstall-custom-commands — uninstall globally or remove from a project
    create-command-from-script.sh    /create-command-from-script — register a script globally (default) or into [project-path]
    remove-command.sh                /remove-command — progressive lookup (project → global); [project-path] restricts scope
  skills/
    create-command/SKILL.md          /create-command — shell substitution calls preflight, then AI generates script and installs
    create-command/create-command-preflight.sh  parses args, detects scope, locates tools, checks conflicts; runs before inference
    refresh-slash-names/SKILL.md     /refresh-slash-names — fetches docs (inference), delegates write to script
    refresh-slash-names/write-slash-names.sh  helper script; writes, normalizes, and confirms constants files

install.sh                                 thin wrapper; delegates to install-custom-commands.sh
uninstall.sh                                thin wrapper; delegates to uninstall-custom-commands.sh
VERSION                                     current version string (semver); no git tag cut yet
.shellcheckrc                               disables SC2016 and SC2015 (both intentional in this repo; see Key Decisions)
CONTRIBUTING.md                             PR workflow, testing/shellcheck requirements, naming conventions
CODE_OF_CONDUCT.md                          Contributor Covenant 2.1
SECURITY.md                                 private vulnerability reporting via GitHub Security tab

.github/workflows/test.yml                  CI: runs tests/run-all.sh and a separate shellcheck job

tests/run-all.sh                           runs all suites below in order; this is what CI invokes
tests/run-repeated.sh                      runs run-all.sh N times (default 3) to catch flaky/non-deterministic failures
tests/sample-hello.sh                      fixture script used by test-integration.sh (and manually, per DEVELOPMENT.md)
tests/test-shellcheck.sh                   runs shellcheck across the repo the same way CI does
tests/test-dispatch.sh
tests/test-check-slash-conflict.sh
tests/test-create-command-from-script.sh
tests/test-remove-command.sh
tests/test-commands-help.sh
tests/test-install-custom-commands.sh
tests/test-install-custom-commands-minimal.sh
tests/test-uninstall-custom-commands.sh
tests/test-write-slash-names.sh
tests/test-create-command-preflight.sh
tests/test-integration.sh
```

## Key Decisions

**`UserPromptSubmit` over `UserPromptExpansion`**: `UserPromptExpansion` fires specifically for slash commands and supports per-command matchers, but cannot block inference (no exit 2 support). `UserPromptSubmit` fires on every prompt but can block. The performance cost is negligible — one python3 call plus a file existence check on non-matching prompts.

**Convention over registry**: Commands are discovered by filename. `reset.sh` → `/reset`. No registry file to maintain.

**Direct global install over plugin**: Plugin format is tied to Claude Code's marketplace/cache infrastructure, which is not designed for self-hosted packages. An install script that edits settings.json is simpler and fully self-contained.

**install-custom-commands.sh is the install implementation**: `install.sh` and `uninstall.sh` at the project root are thin wrappers that delegate to the command scripts. The command scripts contain the actual logic so `/install-custom-commands` and `/uninstall-custom-commands` are self-contained — no delegation to a separate file required.

**Project install scope**: Installing with a path arg (`/install-custom-commands /path/to/project`) is fully isolated — hooks, commands, skills, and constants all go to the project's `.claude/` directory. The hook is registered in the project's `.claude/settings.json` using `${CLAUDE_PROJECT_DIR}/.claude/hooks/dispatch-commands.sh` so it resolves correctly regardless of working directory. Nothing is written to `~/.claude/`.

**Positional project-path over `--global` flag**: `create-command-from-script` and `remove-command` accept an optional positional `[project-path]` argument rather than a `--global` flag, matching the pattern of `install-custom-commands` and `uninstall-custom-commands`. Global is the default; passing a path opts into project scope. A `--global` flag was rejected because it would be the implicit default and its absence would be ambiguous — "no flag" and "explicit global" would mean the same thing.

**`remove-command` progressive lookup**: Removal searches project scope first, then global — the command is found wherever it lives, one scope at a time. Pass an explicit `[project-path]` to restrict removal to that location with no fallback. Running remove twice removes from both scopes. This differs from install operations (which target a specific scope up front) because the goal of removal is "find it and remove it" rather than "install into a specific location."

**Explicit scope variable naming**: All scripts use `PROJECT_*`, `GLOBAL_*`, and `RESOLVED_*` prefixes (e.g. `PROJECT_COMMANDS_DIR`, `GLOBAL_COMMANDS_DIR`, `RESOLVED_COMMANDS_DIR`) rather than a single collapsed variable. The explicit naming makes the active scope visible at every decision point and eliminates the ambiguity that comes with a single `COMMANDS_DIR` that conflated scope determination with lookup result.

**`check-slash-conflict.sh` cross-scope awareness**: The conflict checker validates both same-scope and cross-scope conflicts, for both commands and skills. A project-scope write is blocked if a same-name entry already exists globally (the project entry would shadow it). A global write is blocked if a same-name entry already exists in the currently open project (the global entry would be unreachable there). This prevents silent dispatch mismatches where a command or skill appears to install successfully but is never reachable because another entry intercepts the name first.

**Install fails loud on corrupt `settings.json`; uninstall skips quietly**: If `settings.json` exists but isn't valid JSON, `install-custom-commands.sh` / `install-custom-commands-minimal.sh` print an error and exit 1 without touching the file — install has a hook to register and can't safely proceed without a parseable file to merge into. `uninstall-custom-commands.sh` instead prints `NO_CHANGE` and leaves the file alone, because uninstall has nothing it needs to write; there's no reason to fail a removal over a settings file it doesn't need to touch. Neither path silently resets the file to `{}` and overwrites, which would discard unrelated configuration.

**Shellcheck disables specific codes, not a severity threshold**: `.shellcheckrc` has no `severity=` directive — that's a CLI-only flag (`-S`), confirmed by testing against shellcheck 0.11.0. The repo instead disables SC2016 and SC2015 by code: SC2016 fires on every intentionally-unexpanded single-quoted literal like `'${CLAUDE_PROJECT_DIR}/...'`, and SC2015 fires on the `[[ cond ]] && { } || { }` idiom used throughout `tests/` where both branches are plain literal blocks. Both are real patterns in this repo, not mistakes, so they're disabled by code rather than filtered by a severity cutoff that doesn't exist. CI calls plain `shellcheck` with no flags; `.shellcheckrc` auto-discovery applies the same disables there as locally.

**Global-first constants lookup**: `check-slash-conflict.sh` always reads `~/.claude/constants/`, falling back to project-local constants only if the global directory does not exist. Built-in command names and bundled skill names are facts about Claude Code itself — one global update benefits all sessions. Project installs still copy constants locally so the hook works even without a global install.

**`refresh-slash-names` dual-write**: Always writes to `~/.claude/constants/`. Additionally, if run from a project that has `.claude/constants/`, writes there too. This keeps the repo's bundled constants current so users who clone it get an up-to-date baseline without needing to run the skill themselves first.

**`create-command` shell substitution preflight**: SKILL.md uses a `` ```! `` shell substitution block to run `create-command-preflight.sh` before inference. The script parses `$ARGUMENTS`, detects scope (`$PWD/.claude`), locates the installer and conflict checker, creates a tmpfile, and checks for conflicts (when the name is explicit and `--force` is absent). Output is key-value lines embedded in the skill body; Claude reads them and acts deterministically on stop conditions. Inference is reserved for name inference (when omitted) and script generation. The preflight is a sibling file in `.claude/skills/create-command/` and is installed with the skill.

**Global uninstall requires no repo dir**: `uninstall-custom-commands.sh` hardcodes all paths it removes (hooks, skill names, hook entry). Project uninstall hardcodes the list of command names this repo manages. Neither mode needs the repo to be present.

**Scripts receive args via unquoted `$ARGS`**: Intentional word-splitting works for flag-style args. Commands that need structured arg parsing receive the raw args string in `$1`.

**`run-all.sh` checks for leaked temp dirs; `run-repeated.sh` checks for flakiness; neither is a "suite"**: Several real bugs in this test suite (a forgotten `mktemp -d` in an `EXIT` trap, a SIGPIPE race in a piped `grep -q`) left no failing assertion behind — the leak just sits in `/tmp`, and the race only shows up some fraction of runs. `run-all.sh` snapshots `$TMPDIR` before and after all suites and fails if anything new persists. `run-repeated.sh` reruns `run-all.sh` itself N times (default 3) and fails if any run's result differs. Neither lives in `run-all.sh`'s own suite list — the leak check wraps the whole run, and `run-repeated.sh` wraps `run-all.sh`, so including it in `run-all.sh` would recurse.

## Hook Output Rendering

**How output works**: The dispatcher uses exit 0 with JSON `{"decision": "block", "reason": "..."}` rather than exit 2 + stderr. This blocks inference and surfaces the command output via the `reason` field. Exit 2 also works but always triggers the "operation blocked" banner with no control over its content.

**Suppressing the footer**: `suppressOriginalPrompt: true` inside `hookSpecificOutput` (not top-level — the docs example is misleading) removes the "Original prompt: /foo" footer line.

**The banner is hardcoded**: `UserPromptSubmit operation blocked by hook: [command]: <reason>` cannot be suppressed. There is no documented or undocumented field that removes the header line or the `[command]:` identifier prefix. The minimum visible output is one banner line plus the reason content.

**`/commands-help` instead of `/help`**: Avoided `/help` to prevent shadowing Claude Code's built-in. The command is named `/commands-help` to be unambiguous.

## Known Gaps / Follow-Up

- **No git tag for the current `VERSION`.** `VERSION` holds `0.1.0`, but no `v0.1.0` tag has been pushed yet — that's a release action for whoever publishes the first cut, not something to script.
