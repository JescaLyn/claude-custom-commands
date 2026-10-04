# Security Policy

## Reporting a Vulnerability

Please do not open a public GitHub issue for a security vulnerability.

Use GitHub's private vulnerability reporting instead: go to the **Security** tab of this repository, then **Report a vulnerability**. This opens a private advisory visible only to the maintainer until a fix is ready.

## Scope

This project installs a `UserPromptSubmit` hook and a `PreToolUse:Write` hook into `~/.claude/` (or a project's `.claude/`) and runs user-supplied bash scripts on every matching slash command. Relevant reports include (but aren't limited to):

- A way for a crafted prompt, file path, or script name to escape the intended `.claude/commands/` or `.claude/skills/` directory (path traversal).
- A way for the conflict checker or installer to write to `settings.json` in a way that corrupts or discards unrelated configuration.
- Any command injection path through `$ARGUMENTS`, a file path, or hook input JSON that isn't already covered by the existing regex/quoting validation described in `CLAUDE.md`.

## Supported Versions

This project doesn't yet maintain parallel release branches; fixes land on `main` and the version in `VERSION`.
