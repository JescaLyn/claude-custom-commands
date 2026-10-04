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
bash tests/test-integration.sh
```

To test `/create-command-from-script` end-to-end in Claude Code, open Claude Code from the repo root and type:

```
/create-command-from-script hello tests/sample-hello.sh
```

## Checking for Flaky Tests

`tests/run-all.sh` runs once and can pass by luck on a non-deterministic bug (e.g. a SIGPIPE race). To check for that, run the suite multiple times and confirm every run produces the same result:

```bash
bash tests/run-repeated.sh        # 3 runs (default)
bash tests/run-repeated.sh 10     # or any other count
```

This is a separate entry point from `run-all.sh`, not one of its suites — it wraps `run-all.sh`, so it isn't itself included in that suite list.
