#!/usr/bin/env bash
# Tests for .claude/skills/create-command/create-command-preflight.sh

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CMD="$REPO/.claude/skills/create-command/create-command-preflight.sh"

pass=0; fail=0

check() {
    local desc="$1" expected_exit="$2"
    shift 2
    local actual_exit=0
    "$@" 2>&1 || actual_exit=$?
    if [[ $actual_exit -eq $expected_exit ]]; then
        printf '  PASS  %s\n' "$desc"
        (( pass++ )) || true
    else
        printf '  FAIL  %s  (expected exit %d, got %d)\n' "$desc" "$expected_exit" "$actual_exit"
        (( fail++ )) || true
    fi
}

has_line() {
    local desc="$1" pattern="$2"
    shift 2
    local output
    output=$("$@" 2>/dev/null || true)
    if printf '%s' "$output" | grep -q "$pattern"; then
        printf '  PASS  %s\n' "$desc"
        (( pass++ )) || true
    else
        printf '  FAIL  %s  (expected "%s" in output, got: %s)\n' "$desc" "$pattern" "$output"
        (( fail++ )) || true
    fi
}

no_line() {
    local desc="$1" pattern="$2"
    shift 2
    local output
    output=$("$@" 2>/dev/null || true)
    if ! printf '%s' "$output" | grep -q "$pattern"; then
        printf '  PASS  %s\n' "$desc"
        (( pass++ )) || true
    else
        printf '  FAIL  %s  (did not expect "%s" in output, got: %s)\n' "$desc" "$pattern" "$output"
        (( fail++ )) || true
    fi
}

TEMP=$(mktemp -d)
ORIG_DIR="$PWD"
trap 'cd "$ORIG_DIR"; rm -rf "$TEMP"' EXIT
cd "$TEMP"  # neutral dir — no $PWD/.claude, prevents scope false-positives

printf 'Running create-command-preflight.sh tests...\n\n'

# -----------------------------------------------------------------------
printf 'Empty / missing args:\n'
# -----------------------------------------------------------------------

check "exits 0 with no args"            0 env HOME="$TEMP/home" bash "$CMD" ""
check "exits 0 with only --force"       0 env HOME="$TEMP/home" bash "$CMD" "--force"
has_line "error line when no desc"      "error:" env HOME="$TEMP/home" bash "$CMD" ""
has_line "error line after --force only" "error:" env HOME="$TEMP/home" bash "$CMD" "--force"

# -----------------------------------------------------------------------
printf '\n--force parsing:\n'
# -----------------------------------------------------------------------

has_line "force: false without flag"  "force: false" env HOME="$TEMP/home" bash "$CMD" "show date"
has_line "force: true with flag"      "force: true"  env HOME="$TEMP/home" bash "$CMD" "--force show date"
no_line  "--force not in desc"        "desc: --force" env HOME="$TEMP/home" bash "$CMD" "--force show date"
has_line "--forceful stays force: false"  "force: false"  env HOME="$TEMP/home" bash "$CMD" "--forceful show date"
has_line "--forceful stays in desc"      "desc: --forceful show date" env HOME="$TEMP/home" bash "$CMD" "--forceful show date"

# -----------------------------------------------------------------------
printf '\n--global parsing:\n'
# -----------------------------------------------------------------------

has_line "global: false without flag"   "global: false" env HOME="$TEMP/home" bash "$CMD" "show date"
has_line "global: true with flag"       "global: true"  env HOME="$TEMP/home" bash "$CMD" "--global show date"
no_line  "--global not in desc"         "desc: --global" env HOME="$TEMP/home" bash "$CMD" "--global show date"

# Combined flags in either order
has_line "--force --global: force true"  "force: true"  env HOME="$TEMP/home" bash "$CMD" "--force --global show date"
has_line "--force --global: global true" "global: true" env HOME="$TEMP/home" bash "$CMD" "--force --global show date"
has_line "--global --force: force true"  "force: true"  env HOME="$TEMP/home" bash "$CMD" "--global --force show date"
has_line "--global --force: global true" "global: true" env HOME="$TEMP/home" bash "$CMD" "--global --force show date"

# --global overrides project scope
mkdir -p "$TEMP/myproject/.claude"
(cd "$TEMP/myproject" && has_line "--global overrides project scope" "scope: global" env HOME="$TEMP/home" bash "$CMD" "--global show date")
(cd "$TEMP/myproject" && no_line  "--global: scope not project"      "scope: project" env HOME="$TEMP/home" bash "$CMD" "--global show date")

# installer_flags
has_line "installer_flags: --force when not global"      "installer_flags: --force" env HOME="$TEMP/home" bash "$CMD" "show date"
no_line  "installer_flags: no --global when not global"  "installer_flags: --force --global" env HOME="$TEMP/home" bash "$CMD" "show date"
has_line "installer_flags: --force --global when global" "installer_flags: --force --global" env HOME="$TEMP/home" bash "$CMD" "--global show date"

# -----------------------------------------------------------------------
printf '\nName vs description parsing:\n'
# -----------------------------------------------------------------------

has_line "explicit name extracted"    "name: git-branch"   env HOME="$TEMP/home" bash "$CMD" "git-branch show the current git branch"
has_line "desc remainder correct"     "desc: show the current git branch" env HOME="$TEMP/home" bash "$CMD" "git-branch show the current git branch"
has_line "infer when single token"    "name: infer"        env HOME="$TEMP/home" bash "$CMD" "git-branch"
has_line "desc when single token"     "desc: git-branch"   env HOME="$TEMP/home" bash "$CMD" "git-branch"
has_line "first word becomes name in multi-word input" "name: show" env HOME="$TEMP/home" bash "$CMD" "show the current date and time"
has_line "desc is remainder after name"               "desc: the current date and time" env HOME="$TEMP/home" bash "$CMD" "show the current date and time"
has_line "name with --force"          "name: ping"         env HOME="$TEMP/home" bash "$CMD" "--force ping smoke test command"
has_line "desc with --force"          "desc: smoke test command" env HOME="$TEMP/home" bash "$CMD" "--force ping smoke test command"
has_line "name with --global"         "name: ping"         env HOME="$TEMP/home" bash "$CMD" "--global ping smoke test command"
has_line "desc with --global"         "desc: smoke test command" env HOME="$TEMP/home" bash "$CMD" "--global ping smoke test command"

# -----------------------------------------------------------------------
printf '\nScope detection:\n'
# -----------------------------------------------------------------------

has_line "global when no .claude dir"  "scope: global" env HOME="$TEMP/home" bash "$CMD" "show date"

(cd "$TEMP/myproject" && has_line "project when .claude exists" "scope: project" env HOME="$TEMP/home" bash "$CMD" "show date")

# -----------------------------------------------------------------------
printf '\nInstaller detection:\n'
# -----------------------------------------------------------------------

has_line "installer: none when absent" "installer: none" env HOME="$TEMP/home" bash "$CMD" "show date"

# Global installer
rm -rf "$TEMP/home"
mkdir -p "$TEMP/home/.claude/commands"
printf '#!/usr/bin/env bash\n' > "$TEMP/home/.claude/commands/create-command-from-script.sh"
chmod +x "$TEMP/home/.claude/commands/create-command-from-script.sh"
has_line "finds global installer" "installer: $TEMP/home/.claude/commands/create-command-from-script.sh" \
    env HOME="$TEMP/home" bash "$CMD" "show date"

# Project-local installer (home has no installer)
rm -f "$TEMP/home/.claude/commands/create-command-from-script.sh"
mkdir -p "$TEMP/myproject/.claude/commands"
printf '#!/usr/bin/env bash\n' > "$TEMP/myproject/.claude/commands/create-command-from-script.sh"
chmod +x "$TEMP/myproject/.claude/commands/create-command-from-script.sh"
(cd "$TEMP/myproject" && has_line "finds project installer when global absent" \
    "installer: $TEMP/myproject/.claude/commands/create-command-from-script.sh" \
    env HOME="$TEMP/home" bash "$CMD" "show date")

# Global takes precedence over project-local
mkdir -p "$TEMP/home/.claude/commands"
printf '#!/usr/bin/env bash\n' > "$TEMP/home/.claude/commands/create-command-from-script.sh"
chmod +x "$TEMP/home/.claude/commands/create-command-from-script.sh"
(cd "$TEMP/myproject" && has_line "global installer preferred over project" \
    "installer: $TEMP/home/.claude/commands/create-command-from-script.sh" \
    env HOME="$TEMP/home" bash "$CMD" "show date")

# -----------------------------------------------------------------------
printf '\nChecker detection:\n'
# -----------------------------------------------------------------------

rm -rf "$TEMP/home"
has_line "checker: none when absent" "checker: none" env HOME="$TEMP/home" bash "$CMD" "show date"

# Global checker
mkdir -p "$TEMP/home/.claude/hooks"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TEMP/home/.claude/hooks/check-slash-conflict.sh"
chmod +x "$TEMP/home/.claude/hooks/check-slash-conflict.sh"
has_line "finds global checker" "checker: $TEMP/home/.claude/hooks/check-slash-conflict.sh" \
    env HOME="$TEMP/home" bash "$CMD" "show date"

# Project-local checker (home has no checker)
rm -f "$TEMP/home/.claude/hooks/check-slash-conflict.sh"
mkdir -p "$TEMP/myproject/.claude/hooks"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TEMP/myproject/.claude/hooks/check-slash-conflict.sh"
chmod +x "$TEMP/myproject/.claude/hooks/check-slash-conflict.sh"
(cd "$TEMP/myproject" && has_line "finds project checker when global absent" \
    "checker: $TEMP/myproject/.claude/hooks/check-slash-conflict.sh" \
    env HOME="$TEMP/home" bash "$CMD" "show date")

# -----------------------------------------------------------------------
printf '\nTmpfile:\n'
# -----------------------------------------------------------------------

rm -rf "$TEMP/home"
OUTPUT=$(env HOME="$TEMP/home" bash "$CMD" "show date" || true)
TMPFILE=$(printf '%s' "$OUTPUT" | grep '^tmpfile:' | sed 's/^tmpfile: //')
if [[ -f "$TMPFILE" ]]; then
    printf '  PASS  tmpfile created on disk\n'; (( pass++ )) || true
    rm -f "$TMPFILE"
else
    printf '  FAIL  tmpfile not created: %s\n' "$TMPFILE"; (( fail++ )) || true
fi

# -----------------------------------------------------------------------
printf '\nConflict checking:\n'
# -----------------------------------------------------------------------

# Mock checker: exits 1 with WARNING for "conflicted", 0 otherwise
MOCK_CHECKER="$TEMP/mock-checker.sh"
printf '#!/usr/bin/env bash\ncase "${1:-}" in\n  conflicted) printf "WARNING: %%s is a test conflict\\n" "$1"; exit 1;;\n  *) exit 0;;\nesac\n' > "$MOCK_CHECKER"
chmod +x "$MOCK_CHECKER"

rm -rf "$TEMP/home"
mkdir -p "$TEMP/home/.claude/hooks"
cp "$MOCK_CHECKER" "$TEMP/home/.claude/hooks/check-slash-conflict.sh"
mkdir -p "$TEMP/home/.claude/commands"
printf '#!/usr/bin/env bash\n' > "$TEMP/home/.claude/commands/create-command-from-script.sh"
chmod +x "$TEMP/home/.claude/commands/create-command-from-script.sh"

# Explicit name, no conflict
has_line  "conflict: none for clean name"    "conflict: none"    env HOME="$TEMP/home" bash "$CMD" "my-cmd do something"
no_line   "no WARNING for clean name"        "WARNING"           env HOME="$TEMP/home" bash "$CMD" "my-cmd do something"

# Explicit name, conflict found
has_line  "conflict: blocked when found"     "conflict: blocked" env HOME="$TEMP/home" bash "$CMD" "conflicted do something"
has_line  "WARNING line in output"           "WARNING"           env HOME="$TEMP/home" bash "$CMD" "conflicted do something"

# --force skips conflict check even when name conflicts
has_line  "conflict: none with --force"      "conflict: none"    env HOME="$TEMP/home" bash "$CMD" "--force conflicted do something"
no_line   "no WARNING with --force"          "WARNING"           env HOME="$TEMP/home" bash "$CMD" "--force conflicted do something"

# --global alone does NOT skip conflict check — only --force does.
# --global sets scope=global and adds --global to installer_flags, but conflict check still runs.
has_line  "conflict: blocked with --global alone"  "conflict: blocked" env HOME="$TEMP/home" bash "$CMD" "--global conflicted do something"
has_line  "conflict: none with --force --global"   "conflict: none"    env HOME="$TEMP/home" bash "$CMD" "--force --global conflicted do something"

# Infer name: no conflict check (name unknown at preflight time)
has_line  "conflict: none for infer"         "conflict: none"    env HOME="$TEMP/home" bash "$CMD" "this is just a description"
no_line   "no WARNING for infer"             "WARNING"           env HOME="$TEMP/home" bash "$CMD" "this is just a description"

# No checker: no conflict check
rm -f "$TEMP/home/.claude/hooks/check-slash-conflict.sh"
has_line  "conflict: none when checker absent" "conflict: none"  env HOME="$TEMP/home" bash "$CMD" "my-cmd do something"

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
