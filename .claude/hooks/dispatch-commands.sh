#!/usr/bin/env bash
# UserPromptSubmit hook — dispatches slash commands to local scripts without inference.
#
# If the user types /foo, looks for foo.sh in the project-local commands dir first,
# then falls back to ~/.claude/commands/foo.sh. Runs the script and outputs
# JSON {decision:block} to suppress inference. All other prompts exit 0 and pass through.
#
# Installed to ~/.claude/hooks/dispatch-commands.sh by install.sh.

set -euo pipefail

cd "$HOME"  # python3 needs an accessible CWD to import modules

_PROJ="${CLAUDE_PROJECT_DIR:-}"
COMMAND_DIR="${CLAUDE_COMMANDS_DIR:-${_PROJ:+$_PROJ/.claude/commands}}"
COMMAND_DIR="${COMMAND_DIR:-$HOME/.claude/commands}"

INPUT=$(cat)
PROMPT=$(printf '%s' "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('prompt',''))" 2>/dev/null) || PROMPT=""

# Pass through: not a slash command
[[ "$PROMPT" =~ ^/ ]] || exit 0

# Extract command name: first word after /
COMMAND="${PROMPT#/}"
COMMAND="${COMMAND%% *}"

# Pass through: not a plain identifier (e.g., //, /123, /-flag)
[[ "$COMMAND" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]] || exit 0

SCRIPT="${COMMAND_DIR}/${COMMAND}.sh"

# If not found project-locally, fall back to global commands.
# Only applies when no explicit CLAUDE_COMMANDS_DIR override is set.
if [[ ! -f "$SCRIPT" && -n "$_PROJ" && -z "${CLAUDE_COMMANDS_DIR:-}" ]]; then
    SCRIPT="$HOME/.claude/commands/${COMMAND}.sh"
fi

# Pass through: no script registered for this command (let Claude handle it)
[[ -f "$SCRIPT" ]] || exit 0

# Extract args: everything after "/<command>", stripping one leading space
ARGS="${PROMPT#"/$COMMAND"}"
ARGS="${ARGS# }"

# Run the command script; word-split $ARGS intentionally for flag-style arguments
# shellcheck disable=SC2086
if OUTPUT=$(bash "$SCRIPT" $ARGS 2>&1); then
    REASON="$OUTPUT"
else
    EC=$?
    REASON="Command /$COMMAND failed (exit $EC):
$OUTPUT"
fi

# Exit 0 + JSON blocks inference via decision:block. suppressOriginalPrompt inside
# hookSpecificOutput removes the "Original prompt:" footer. The one-line banner
# "UserPromptSubmit operation blocked by hook: [command]: <reason>" is hardcoded
# and cannot be suppressed.
python3 -c "
import json, sys
cmd, output = sys.argv[1], sys.argv[2].rstrip('\n')
lines = output.split('\n')
prefix = '╭─ /'
W = max(len(prefix) + len(cmd) + 3, max((len(l) for l in lines), default=0) + 3, 40)
header = prefix + cmd + ' ' + '─' * (W - len(prefix) - len(cmd) - 1)
body   = '│\n' + '\n'.join('│ ' + l for l in lines)
footer = '╰' + '─' * (W - 1)
reason = '\n'.join(['\n' + header, body, footer])
print(json.dumps({
    'decision': 'block',
    'reason': reason,
    'hookSpecificOutput': {'hookEventName': 'UserPromptSubmit', 'suppressOriginalPrompt': True},
}))
" "$COMMAND" "$REASON"
exit 0
