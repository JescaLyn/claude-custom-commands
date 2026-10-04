# Contributing

## Before you start

Read `CLAUDE.md` for the architecture and the reasoning behind existing design decisions. A change that contradicts a documented decision needs a reason, not just a diff.

## Making a change

1. Run the full test suite before you start, so you know your baseline is green: `bash tests/run-all.sh`.
2. Make your change. If you're adding a new command or hook, add a corresponding `tests/test-<name>.sh` file (see `DEVELOPMENT.md` for the test-running pattern) and wire it into `tests/run-all.sh`.
3. While iterating, run `shellcheck` directly against the one file you're editing — faster feedback than the full suite:
   ```bash
   shellcheck path/to/your-script.sh
   ```
4. Run the full suite again: `bash tests/run-all.sh` (this includes `test-shellcheck.sh`, so step 3 isn't strictly required, just faster per-file).
5. If you added or changed a test that pipes a live command's output into `grep` (or anything else that can exit before consuming all input), run `bash tests/run-repeated.sh` to check for SIGPIPE-style flakiness before assuming it's solid.
6. If your change affects documented behavior, update `README.md` and/or `CLAUDE.md` in the same PR. Stale docs are treated as a bug.

## Conventions this repo follows

- **Scope variable naming**: scripts that resolve a path for both project and global scope use `PROJECT_*`, `GLOBAL_*`, and `RESOLVED_*` prefixes (e.g. `PROJECT_COMMANDS_DIR`, `GLOBAL_COMMANDS_DIR`, `RESOLVED_COMMANDS_DIR`) rather than a single variable reused with different values per branch.
- **`set -euo pipefail`** at the top of every script.
- **Fail loud, not silent**: a missing dependency (e.g. `python3`) or malformed input should print a clear message to stderr before falling back or exiting, never fail quietly.
- **Positional args over flags for scope**: global is the default; a project path is passed positionally to opt into project scope, rather than a `--global`/`--project` flag pair.

## Reporting a security issue

See `SECURITY.md` — do not open a public issue for a security vulnerability.
