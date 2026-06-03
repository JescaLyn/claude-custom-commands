# Contributing

## Architecture

A `UserPromptSubmit` hook (`~/.claude/hooks/dispatch-commands.sh`) intercepts every prompt before the model sees it. If the prompt matches `/<name>` and `~/.claude/commands/<name>.sh` exists, the hook runs that script and returns `{"decision":"block"}` to suppress inference. All other prompts pass through in under 5ms.

Commands are discovered by filename — there is no registry. `deploy.sh` → `/deploy`.

Output is formatted into an ASCII box (`╭─ /name ─`, `│ line`, `╰───`) by the dispatcher. Command scripts write plain text to stdout.

Conflict detection (`check-slash-conflict.sh`) warns before a command shadows a Claude Code built-in or bundled skill. The lists live in `~/.claude/constants/`.

## Running Tests

```bash
bash tests/test-dispatch.sh
bash tests/test-check-slash-conflict.sh
bash tests/test-create-command-from-script.sh
bash tests/test-remove-command.sh
bash tests/test-install-custom-commands.sh
bash tests/test-uninstall-custom-commands.sh
bash tests/test-integration.sh
```

Each script is self-contained and uses temporary directories — no install required.

## Adding a Command

Use `/create-command <description>` to generate the script, or `/create-command-from-script <name> <path>` to register an existing one. Both write the script and autocomplete stub to `.claude/commands/` automatically.

Then:

1. Write tests in `tests/test-<name>.sh` following the pattern in `tests/test-create-command-from-script.sh`.
2. Add the command to the table in `README.md`.
3. Update the architecture diagram in `CLAUDE.md`.

`/install-custom-commands` picks up all `.sh` scripts and `.md` autocomplete stubs in `.claude/commands/` automatically.

## Adding a Skill

1. Create `.claude/skills/<name>/SKILL.md` with YAML frontmatter (`name`, `description`, `allowed-tools`).
2. Add the skill to the table in `README.md`.
3. Update the architecture diagram in `CLAUDE.md`.

`/install-custom-commands` discovers skills automatically from `.claude/skills/` — no changes needed there.

## Pull Requests

- One logical change per PR.
- Tests are required for new commands. Run all test scripts before opening a PR.
- If a new Claude Code built-in or bundled skill isn't in the conflict-check constants, add it to `builtin-commands.txt` or `bundled-skills.txt`.
