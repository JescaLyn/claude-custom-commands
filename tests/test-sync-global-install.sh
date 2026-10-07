#!/usr/bin/env bash
# Tests for the opt-in .githooks/ hooks (post-commit, post-merge, post-rewrite) that sync the global install.
# Clones the repo into a temp dir, overlays the current working tree (so uncommitted edits to
# the hook, install.sh, etc. are what's tested), points HOME at a temp dir, and makes real commits.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR=$(mktemp -d)
trap 'chmod -R u+rwx "$TEMP_DIR" 2>/dev/null || true; rm -rf "$TEMP_DIR"' EXIT

pass=0; fail=0

pass_or_fail() {
    local desc="$1"; shift
    if "$@"; then
        printf '  PASS  %s\n' "$desc"; (( pass++ )) || true
    else
        printf '  FAIL  %s\n' "$desc"; (( fail++ )) || true
    fi
}

printf 'Running sync-global-install hook tests...\n\n'

git clone -q "$REPO" "$TEMP_DIR/repo"
# Overlay uncommitted changes: tracked edits and deletions via the working-tree diff,
# new files via a straight copy.
git -C "$REPO" diff HEAD --binary | git -C "$TEMP_DIR/repo" apply --allow-empty
git -C "$REPO" ls-files --others --exclude-standard -z | while IFS= read -r -d '' f; do
    mkdir -p "$TEMP_DIR/repo/$(dirname "$f")"
    cp -p "$REPO/$f" "$TEMP_DIR/repo/$f"
done
mkdir -p "$TEMP_DIR/home"

cd "$TEMP_DIR/repo"
git config user.email test@example.com
git config user.name test
# The source checkout may be on another branch or detached (CI pull requests), so pin the
# clone to a local main whose origin/HEAD also names main, whatever the source looked like.
git checkout -q -B main
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
# Commit the overlay before enabling the hook, so the baseline commit doesn't sync
git add -A && git commit -qm baseline --allow-empty
git config core.hooksPath .githooks
export HOME="$TEMP_DIR/home"
GLOBAL_COMMANDS_DIR="$HOME/.claude/commands"
GLOBAL_SKILLS_DIR="$HOME/.claude/skills"

# Commit that touches nothing installable: hook does nothing
echo x >> README.md
OUTPUT=$(git commit -qam docs 2>&1)
pass_or_fail "docs-only commit produces no hook output" test -z "$OUTPUT"
pass_or_fail "docs-only commit does not install" test ! -e "$HOME/.claude/hooks/dispatch-commands.sh"

# Commit on a non-default branch: hook does nothing
git checkout -qb feature
echo '# feature-marker' >> .claude/hooks/dispatch-commands.sh
OUTPUT=$(git commit -qam feature 2>&1)
pass_or_fail "feature-branch commit produces no hook output" test -z "$OUTPUT"
pass_or_fail "feature-branch commit does not install" test ! -e "$HOME/.claude/hooks/dispatch-commands.sh"
git checkout -q main

# Hook change: install runs, even with a stale CLAUDE_PROJECT_DIR inherited from a Claude Code session
echo '# hook-marker' >> .claude/hooks/dispatch-commands.sh
OUTPUT=$(CLAUDE_PROJECT_DIR=/nonexistent git commit -qam hook 2>&1)
pass_or_fail "hook commit reports sync" grep -q 'global install synced' <<< "$OUTPUT"
pass_or_fail "hook commit installs updated dispatcher" grep -q 'hook-marker' "$HOME/.claude/hooks/dispatch-commands.sh"

# Command change: overwrites an already-installed copy (install.sh alone would skip it)
pass_or_fail "ping.sh already installed before edit" test -f "$GLOBAL_COMMANDS_DIR/ping.sh"
echo '# ping-marker' >> .claude/commands/ping.sh
git commit -qam ping >/dev/null 2>&1
pass_or_fail "command commit overwrites existing global copy" grep -q 'ping-marker' "$GLOBAL_COMMANDS_DIR/ping.sh"
pass_or_fail "overwritten command stays executable" test -x "$GLOBAL_COMMANDS_DIR/ping.sh"

# Repo-only installer commands are never copied globally
echo '#' >> .claude/commands/install-custom-commands.sh
git commit -qam installer >/dev/null 2>&1
pass_or_fail "repo-only installer is not copied globally" test ! -e "$GLOBAL_COMMANDS_DIR/install-custom-commands.sh"

# Non-ASCII file names: -z parsing means git's path quoting can't hide them from the sync
printf '#!/usr/bin/env bash\necho hi\n' > .claude/commands/héllo.sh
git add .claude/commands/héllo.sh && git commit -qm add-hello >/dev/null 2>&1
echo '# accent-marker' >> .claude/commands/héllo.sh
git commit -qam edit-hello >/dev/null 2>&1
pass_or_fail "non-ASCII command name is force-copied" grep -q 'accent-marker' "$GLOBAL_COMMANDS_DIR/héllo.sh"

# Fast-forward merge into main: no commit is created, so post-merge does the sync
git checkout -qb ff-src
echo '# ff-marker' >> .claude/commands/ping.sh
git commit -qam ff >/dev/null 2>&1
pass_or_fail "change on a branch isn't synced before merging" test "$(grep -c ff-marker "$GLOBAL_COMMANDS_DIR/ping.sh")" -eq 0
git checkout -q main
git merge -q ff-src >/dev/null 2>&1
pass_or_fail "fast-forward merge syncs" grep -q 'ff-marker' "$GLOBAL_COMMANDS_DIR/ping.sh"

# True merge commit: git merge runs post-merge, not post-commit
git checkout -qb merge-src
echo '# merge-marker' >> .claude/commands/ping.sh
git commit -qam merge-src >/dev/null 2>&1
git checkout -q main
echo y >> README.md && git commit -qam diverge >/dev/null 2>&1
git merge -q --no-edit merge-src >/dev/null 2>&1
pass_or_fail "merge commit was created" test "$(git rev-list --parents -n 1 HEAD | wc -w)" -eq 3
pass_or_fail "merge commit syncs" grep -q 'merge-marker' "$GLOBAL_COMMANDS_DIR/ping.sh"

# Rebase of main (as git pull --rebase does): post-rewrite does the sync
git checkout -qb rebase-src
echo '# rebase-marker' >> .claude/commands/ping.sh
git commit -qam rebase-src >/dev/null 2>&1
git checkout -q main
echo z >> README.md && git commit -qam diverge2 >/dev/null 2>&1
git rebase -q rebase-src >/dev/null 2>&1
pass_or_fail "rebase syncs" grep -q 'rebase-marker' "$GLOBAL_COMMANDS_DIR/ping.sh"

# Squash merge: post-merge skips it (HEAD hasn't moved, changes are uncommitted); the commit syncs
git checkout -qb squash-src
echo '# squash-marker' >> .claude/commands/ping.sh
git commit -qam squash-src >/dev/null 2>&1
git checkout -q main
OUTPUT=$(git merge -q --squash squash-src 2>&1)
pass_or_fail "squash merge produces no sync output" test "$(grep -c 'sync-global-install' <<< "$OUTPUT")" -eq 0
pass_or_fail "squash merge doesn't sync uncommitted changes" test "$(grep -c squash-marker "$GLOBAL_COMMANDS_DIR/ping.sh")" -eq 0
git commit -qm squash >/dev/null 2>&1
pass_or_fail "commit after squash merge syncs" grep -q 'squash-marker' "$GLOBAL_COMMANDS_DIR/ping.sh"

# Root commit base: post-commit passes the empty tree, which must be accepted as a base
OUTPUT=$(bash .githooks/sync-global-install.sh "$(git hash-object -t tree /dev/null)" 2>&1)
pass_or_fail "empty-tree base (root commit) syncs" grep -q 'global install synced' <<< "$OUTPUT"

# Invalid base: reported, not silently ignored
OUTPUT=$(bash .githooks/sync-global-install.sh no-such-rev 2>&1)
pass_or_fail "invalid base is reported" grep -q 'not found' <<< "$OUTPUT"

# Rename: new name installed, old name removed
git mv .claude/commands/now.sh .claude/commands/clock.sh
git mv .claude/commands/now.md .claude/commands/clock.md
git commit -qm rename >/dev/null 2>&1
pass_or_fail "renamed command installed under new name" test -x "$GLOBAL_COMMANDS_DIR/clock.sh"
pass_or_fail "renamed command's stub installed under new name" test -f "$GLOBAL_COMMANDS_DIR/clock.md"
pass_or_fail "renamed command's old script removed" test ! -e "$GLOBAL_COMMANDS_DIR/now.sh"
pass_or_fail "renamed command's old stub removed" test ! -e "$GLOBAL_COMMANDS_DIR/now.md"

# Deletion: global copy removed
git rm -q .claude/commands/clock.sh .claude/commands/clock.md
git commit -qm delete >/dev/null 2>&1
pass_or_fail "deleted command removed globally" test ! -e "$GLOBAL_COMMANDS_DIR/clock.sh"

# Skill deletion: files removed and the emptied skill directory cleaned up
pass_or_fail "skill installed before deletion" test -d "$GLOBAL_SKILLS_DIR/refresh-slash-names"
git rm -rq .claude/skills/refresh-slash-names
git commit -qm delete-skill >/dev/null 2>&1
pass_or_fail "deleted skill directory removed globally" test ! -e "$GLOBAL_SKILLS_DIR/refresh-slash-names"
pass_or_fail "skills root kept after skill deletion" test -d "$GLOBAL_SKILLS_DIR"

# Commits in a linked worktree never sync (e.g. a throwaway review worktree), even when its
# branch is treated as the default branch, so the worktree check is what's under test
git worktree add -q "$TEMP_DIR/wt" -b wt-branch
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/wt-branch
echo '# worktree-marker' >> "$TEMP_DIR/wt/.claude/hooks/dispatch-commands.sh"
OUTPUT=$(git -C "$TEMP_DIR/wt" commit -qam worktree 2>&1)
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
pass_or_fail "worktree commit produces no hook output" test -z "$OUTPUT"
pass_or_fail "worktree commit does not touch the global install" test "$(grep -c worktree-marker "$HOME/.claude/hooks/dispatch-commands.sh")" -eq 0

# A failing install does not fail the commit and says so on stderr.
# Root ignores directory permissions, so the failure can't be simulated that way.
if [[ $EUID -eq 0 ]]; then
    printf '  SKIP  install-failure checks (running as root; chmod 000 has no effect)\n'
else
    chmod 000 "$HOME/.claude/hooks"
    echo '# again' >> .claude/hooks/dispatch-commands.sh
    EC=0; OUTPUT=$(git commit -qam broken 2>&1) || EC=$?
    chmod 755 "$HOME/.claude/hooks"
    pass_or_fail "commit still succeeds when install fails" test "$EC" -eq 0
    pass_or_fail "install failure is reported" grep -q 'NOT updated' <<< "$OUTPUT"
fi

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
