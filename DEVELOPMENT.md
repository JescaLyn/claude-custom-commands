# Development

## Running Tests

```bash
bash tests/run-all.sh
```

To run a single suite:

```bash
bash tests/test-dispatch.sh
bash tests/test-check-slash-conflict.sh
bash tests/test-create-command-from-script.sh
bash tests/test-remove-command.sh
bash tests/test-install-custom-commands.sh
bash tests/test-uninstall-custom-commands.sh
bash tests/test-integration.sh
```

To test `/create-command-from-script` end-to-end in Claude Code, open Claude Code from the repo root and type:

```
/create-command-from-script hello tests/sample-hello.sh
```
