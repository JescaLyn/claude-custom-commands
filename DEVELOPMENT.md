# Development

## Running Tests

```bash
bash tests/run-all.sh
```

To run a single suite:

```bash
bash tests/test-shellcheck.sh
bash tests/test-dispatch.sh
bash tests/test-check-slash-conflict.sh
bash tests/test-create-command-from-script.sh
bash tests/test-remove-command.sh
bash tests/test-commands-help.sh
bash tests/test-install-custom-commands.sh
bash tests/test-install-custom-commands-minimal.sh
bash tests/test-uninstall-custom-commands.sh
bash tests/test-write-slash-names.sh
bash tests/test-create-command-preflight.sh
bash tests/test-sync-global-install.sh
bash tests/test-integration.sh
```

To test `/create-command-from-script` end-to-end in Claude Code, open Claude Code from the repo root and type:

```
/create-command-from-script hello tests/sample-hello.sh
```

## Auto-Syncing Your Global Install

To keep your global install (`~/.claude/`) in sync with the repo, enable the bundled git hooks once per clone:

```bash
git config core.hooksPath .githooks
```

Whenever the default branch changes through a commit, merge, pull, or rebase, and the change touches `.claude/hooks/`, `.claude/commands/`, `.claude/skills/`, or `.claude/constants/`, the hooks run `./install.sh`. They also force-copy any changed command scripts, which `install.sh` alone skips when they already exist, and remove the global copies of commands and skill files that were deleted or renamed. This overwrites hand edits to the bundled commands in `~/.claude/commands/`. Changes on other branches and in linked worktrees are skipped, so work in progress never reaches your global install; run `./install.sh` by hand to try a branch globally. One case isn't caught: a plain `git rebase` that only fast-forwards `main` fires no usable hook, so use `git pull` or `git merge --ff-only` there, or run `./install.sh` afterward. A failed sync is reported but never fails the git operation. Restart Claude Code to pick up hook changes.

## Checking for Flaky Tests

`tests/run-all.sh` runs once and can pass by luck on a non-deterministic bug (e.g. a SIGPIPE race). To check for that, run the suite multiple times and confirm every run produces the same result:

```bash
bash tests/run-repeated.sh        # 3 runs (default)
bash tests/run-repeated.sh 10     # or any other count
```

This is a separate entry point from `run-all.sh`, not one of its suites — it wraps `run-all.sh`, so it isn't itself included in that suite list.
