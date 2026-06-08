#!/usr/bin/env bash
# Tests for .claude/skills/refresh-slash-names/write-slash-names.sh

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CMD="$REPO/.claude/skills/refresh-slash-names/write-slash-names.sh"

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

TEMP=$(mktemp -d)
ORIG_DIR="$PWD"
trap 'cd "$ORIG_DIR"; rm -rf "$TEMP"' EXIT
cd "$TEMP"  # run from neutral dir so $PWD/.claude/constants is absent by default

printf 'Running write-slash-names.sh tests...\n\n'

# --- Argument validation ---
printf 'Argument validation:\n'
check "exits 1 with no args"    1 env HOME="$TEMP/home" bash "$CMD"
check "exits 1 with one arg"    1 env HOME="$TEMP/home" bash "$CMD" "$TEMP/a.txt"
check "exits 1 with three args" 1 env HOME="$TEMP/home" bash "$CMD" a b c

STDERR=$(env HOME="$TEMP/home" bash "$CMD" 2>&1 1>/dev/null || true)
if printf '%s' "$STDERR" | grep -q 'Usage'; then
    printf '  PASS  usage message on stderr\n'; (( pass++ )) || true
else
    printf '  FAIL  expected usage on stderr, got: %s\n' "$STDERR"; (( fail++ )) || true
fi

# --- Missing input files ---
printf '\nMissing input files:\n'
printf 'clear\nhelp\n' > "$TEMP/builtins.txt"
check "exits 1 when skills file missing"   1 env HOME="$TEMP/home" bash "$CMD" "$TEMP/builtins.txt" "$TEMP/nonexistent.txt"
check "exits 1 when builtins file missing" 1 env HOME="$TEMP/home" bash "$CMD" "$TEMP/nonexistent.txt" "$TEMP/builtins.txt"

STDERR=$(env HOME="$TEMP/home" bash "$CMD" "$TEMP/builtins.txt" "$TEMP/nonexistent.txt" 2>&1 1>/dev/null || true)
if printf '%s' "$STDERR" | grep -q 'not found'; then
    printf '  PASS  error message goes to stderr\n'; (( pass++ )) || true
else
    printf '  FAIL  expected stderr "not found", got: %s\n' "$STDERR"; (( fail++ )) || true
fi

# --- Global write ---
printf '\nGlobal write:\n'
rm -rf "$TEMP/home"
printf 'clear\nhelp\nmodel\n' > "$TEMP/builtins.txt"
printf 'review\ninit\n'        > "$TEMP/skills.txt"
check "exits 0 for basic write" 0 env HOME="$TEMP/home" bash "$CMD" "$TEMP/builtins.txt" "$TEMP/skills.txt"

[[ -f "$TEMP/home/.claude/constants/builtin-commands.txt" ]] && {
    printf '  PASS  builtin-commands.txt created\n'; (( pass++ )) || true
} || { printf '  FAIL  builtin-commands.txt missing\n'; (( fail++ )) || true; }

[[ -f "$TEMP/home/.claude/constants/bundled-skills.txt" ]] && {
    printf '  PASS  bundled-skills.txt created\n'; (( pass++ )) || true
} || { printf '  FAIL  bundled-skills.txt missing\n'; (( fail++ )) || true; }

CONTENT=$(cat "$TEMP/home/.claude/constants/builtin-commands.txt")
if printf '%s' "$CONTENT" | grep -qx 'clear' && printf '%s' "$CONTENT" | grep -qx 'help' && printf '%s' "$CONTENT" | grep -qx 'model'; then
    printf '  PASS  builtin content correct\n'; (( pass++ )) || true
else
    printf '  FAIL  builtin content wrong: %s\n' "$CONTENT"; (( fail++ )) || true
fi

OUTPUT=$(env HOME="$TEMP/home" bash "$CMD" "$TEMP/builtins.txt" "$TEMP/skills.txt")
if printf '%s' "$OUTPUT" | grep -q 'builtin-commands: 3'; then
    printf '  PASS  builtin count in output\n'; (( pass++ )) || true
else
    printf '  FAIL  expected "builtin-commands: 3", got: %s\n' "$OUTPUT"; (( fail++ )) || true
fi
if printf '%s' "$OUTPUT" | grep -q 'bundled-skills: 2'; then
    printf '  PASS  skill count in output\n'; (( pass++ )) || true
else
    printf '  FAIL  expected "bundled-skills: 2", got: %s\n' "$OUTPUT"; (( fail++ )) || true
fi
if ! printf '%s' "$OUTPUT" | grep -q 'project-local'; then
    printf '  PASS  no project-local line when no project dir\n'; (( pass++ )) || true
else
    printf '  FAIL  unexpected project-local line in output\n'; (( fail++ )) || true
fi

# --- Normalization: leading slashes ---
printf '\nNormalization — leading slashes:\n'
rm -rf "$TEMP/home"
printf '/clear\n/help\n/model\n' > "$TEMP/builtins.txt"
printf '/review\n/init\n'        > "$TEMP/skills.txt"
env HOME="$TEMP/home" bash "$CMD" "$TEMP/builtins.txt" "$TEMP/skills.txt" > /dev/null
if ! grep -q '^/' "$TEMP/home/.claude/constants/builtin-commands.txt" 2>/dev/null; then
    printf '  PASS  leading slashes stripped from builtins\n'; (( pass++ )) || true
else
    printf '  FAIL  leading slashes not stripped from builtins\n'; (( fail++ )) || true
fi
if ! grep -q '^/' "$TEMP/home/.claude/constants/bundled-skills.txt" 2>/dev/null; then
    printf '  PASS  leading slashes stripped from skills\n'; (( pass++ )) || true
else
    printf '  FAIL  leading slashes not stripped from skills\n'; (( fail++ )) || true
fi

# --- Normalization: sorting ---
printf '\nNormalization — sorting:\n'
rm -rf "$TEMP/home"
printf 'zebra\napple\nmiddle\n' > "$TEMP/builtins.txt"
printf 'zzz\naaa\nmmm\n'        > "$TEMP/skills.txt"
env HOME="$TEMP/home" bash "$CMD" "$TEMP/builtins.txt" "$TEMP/skills.txt" > /dev/null
SORTED=$(cat "$TEMP/home/.claude/constants/builtin-commands.txt")
EXPECTED="$(printf 'apple\nmiddle\nzebra')"
if [[ "$SORTED" == "$EXPECTED" ]]; then
    printf '  PASS  builtins sorted alphabetically\n'; (( pass++ )) || true
else
    printf '  FAIL  builtins not sorted — got: %s\n' "$SORTED"; (( fail++ )) || true
fi

# --- Normalization: deduplication ---
printf '\nNormalization — deduplication:\n'
rm -rf "$TEMP/home"
printf 'clear\nclear\nhelp\nclear\n' > "$TEMP/builtins.txt"
printf 'review\nreview\n'            > "$TEMP/skills.txt"
env HOME="$TEMP/home" bash "$CMD" "$TEMP/builtins.txt" "$TEMP/skills.txt" > /dev/null
COUNT=$(awk 'END{print NR}' "$TEMP/home/.claude/constants/builtin-commands.txt")
if [[ "$COUNT" -eq 2 ]]; then
    printf '  PASS  duplicates removed from builtins\n'; (( pass++ )) || true
else
    printf '  FAIL  expected 2 unique builtins, got %s\n' "$COUNT"; (( fail++ )) || true
fi
COUNT=$(awk 'END{print NR}' "$TEMP/home/.claude/constants/bundled-skills.txt")
if [[ "$COUNT" -eq 1 ]]; then
    printf '  PASS  duplicates removed from skills\n'; (( pass++ )) || true
else
    printf '  FAIL  expected 1 unique skill, got %s\n' "$COUNT"; (( fail++ )) || true
fi

# --- Normalization: blank lines stripped ---
printf '\nNormalization — blank lines:\n'
rm -rf "$TEMP/home"
printf 'clear\n\nhelp\n\n\nmodel\n' > "$TEMP/builtins.txt"
printf 'review\n\ninit\n'           > "$TEMP/skills.txt"
env HOME="$TEMP/home" bash "$CMD" "$TEMP/builtins.txt" "$TEMP/skills.txt" > /dev/null
COUNT=$(awk 'END{print NR}' "$TEMP/home/.claude/constants/builtin-commands.txt")
if [[ "$COUNT" -eq 3 ]]; then
    printf '  PASS  blank lines stripped\n'; (( pass++ )) || true
else
    printf '  FAIL  expected 3 builtins after blank-line removal, got %s\n' "$COUNT"; (( fail++ )) || true
fi

# --- Normalization: combined (slashes + unsorted + duplicates) ---
printf '\nNormalization — combined:\n'
rm -rf "$TEMP/home"
printf '/zebra\n/apple\n/zebra\n/middle\n' > "$TEMP/builtins.txt"
printf '/zzz\n/aaa\n/aaa\n'               > "$TEMP/skills.txt"
env HOME="$TEMP/home" bash "$CMD" "$TEMP/builtins.txt" "$TEMP/skills.txt" > /dev/null
RESULT=$(cat "$TEMP/home/.claude/constants/builtin-commands.txt")
EXPECTED="$(printf 'apple\nmiddle\nzebra')"
if [[ "$RESULT" == "$EXPECTED" ]]; then
    printf '  PASS  combined normalization correct\n'; (( pass++ )) || true
else
    printf '  FAIL  combined normalization wrong — got "%s", expected "%s"\n' "$RESULT" "$EXPECTED"; (( fail++ )) || true
fi

# --- Empty input files ---
printf '\nEmpty input files:\n'
rm -rf "$TEMP/home"
: > "$TEMP/empty.txt"
env HOME="$TEMP/home" bash "$CMD" "$TEMP/empty.txt" "$TEMP/empty.txt" > /dev/null
[[ -f "$TEMP/home/.claude/constants/builtin-commands.txt" ]] && {
    printf '  PASS  empty input still creates output file\n'; (( pass++ )) || true
} || { printf '  FAIL  output file not created for empty input\n'; (( fail++ )) || true; }
COUNT=$(awk 'END{print NR}' "$TEMP/home/.claude/constants/builtin-commands.txt")
if [[ "$COUNT" -eq 0 ]]; then
    printf '  PASS  empty input produces 0-line output\n'; (( pass++ )) || true
else
    printf '  FAIL  expected 0 lines, got %s\n' "$COUNT"; (( fail++ )) || true
fi
OUTPUT=$(env HOME="$TEMP/home" bash "$CMD" "$TEMP/empty.txt" "$TEMP/empty.txt")
if printf '%s' "$OUTPUT" | grep -q 'builtin-commands: 0'; then
    printf '  PASS  count output shows 0 for empty input\n'; (( pass++ )) || true
else
    printf '  FAIL  expected "builtin-commands: 0", got: %s\n' "$OUTPUT"; (( fail++ )) || true
fi

# --- Project-local write ---
printf '\nProject-local write:\n'
rm -rf "$TEMP/home" "$TEMP/project"
mkdir -p "$TEMP/project/.claude/constants"
printf 'clear\nhelp\n' > "$TEMP/builtins.txt"
printf 'review\n'       > "$TEMP/skills.txt"
(cd "$TEMP/project" && env HOME="$TEMP/home" bash "$CMD" "$TEMP/builtins.txt" "$TEMP/skills.txt") > "$TEMP/proj-output.txt"

[[ -f "$TEMP/project/.claude/constants/builtin-commands.txt" ]] && {
    printf '  PASS  project-local builtin-commands.txt created\n'; (( pass++ )) || true
} || { printf '  FAIL  project-local builtin-commands.txt missing\n'; (( fail++ )) || true; }

[[ -f "$TEMP/project/.claude/constants/bundled-skills.txt" ]] && {
    printf '  PASS  project-local bundled-skills.txt created\n'; (( pass++ )) || true
} || { printf '  FAIL  project-local bundled-skills.txt missing\n'; (( fail++ )) || true; }

if grep -q 'project-local' "$TEMP/proj-output.txt" 2>/dev/null; then
    printf '  PASS  project-local path reported in output\n'; (( pass++ )) || true
else
    printf '  FAIL  project-local path not in output\n'; (( fail++ )) || true
fi

[[ -f "$TEMP/home/.claude/constants/builtin-commands.txt" ]] && {
    printf '  PASS  global constants also written when project dir present\n'; (( pass++ )) || true
} || { printf '  FAIL  global constants not written when project dir present\n'; (( fail++ )) || true; }

GLOBAL_CONTENT=$(cat "$TEMP/home/.claude/constants/builtin-commands.txt")
PROJECT_CONTENT=$(cat "$TEMP/project/.claude/constants/builtin-commands.txt")
if [[ "$GLOBAL_CONTENT" == "$PROJECT_CONTENT" ]]; then
    printf '  PASS  global and project-local content match\n'; (( pass++ )) || true
else
    printf '  FAIL  global and project-local content differ\n'; (( fail++ )) || true
fi

# --- No project-local write when .claude/constants absent ---
printf '\nNo project-local write when .claude/constants absent:\n'
rm -rf "$TEMP/home" "$TEMP/project2"
mkdir -p "$TEMP/project2/.claude"
printf 'clear\n'  > "$TEMP/builtins.txt"
printf 'review\n' > "$TEMP/skills.txt"
(cd "$TEMP/project2" && env HOME="$TEMP/home" bash "$CMD" "$TEMP/builtins.txt" "$TEMP/skills.txt") > "$TEMP/proj2-output.txt"

[[ ! -d "$TEMP/project2/.claude/constants" ]] && {
    printf '  PASS  project-local constants dir not created when absent\n'; (( pass++ )) || true
} || { printf '  FAIL  project-local constants dir created unexpectedly\n'; (( fail++ )) || true; }

if ! grep -q 'project-local' "$TEMP/proj2-output.txt" 2>/dev/null; then
    printf '  PASS  no project-local line when .claude/constants absent\n'; (( pass++ )) || true
else
    printf '  FAIL  unexpected project-local line in output\n'; (( fail++ )) || true
fi

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
