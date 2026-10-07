#!/usr/bin/env bash
# Shared logic for the opt-in dev hooks in this directory (post-commit, post-merge,
# post-rewrite): keeps the global install in sync with this repo.
# Enable with: git config core.hooksPath .githooks
#
# Usage: sync-global-install.sh <base-rev>
#   Syncs the changes between <base-rev> and HEAD. Each hook passes its own base: the first
#   parent for a commit, ORIG_HEAD for a merge, pull, or rebase.
#
# Runs install.sh when the change on the default branch touched installable files under .claude/.
# install.sh skips command scripts and .md stubs that already exist globally (to preserve user
# edits) and never removes anything, so this also force-copies command files that were added or
# changed, and removes global copies of command and skill files that were deleted — the repo is
# the source of truth for its own files when you're developing it.

set -euo pipefail

BASE="${1:?usage: sync-global-install.sh <base-rev>}"

# Linked worktrees share core.hooksPath (and --no-verify doesn't skip post-commit), so without
# this a commit in a throwaway review worktree would overwrite ~/.claude/ with its contents.
if [[ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ]]; then
    exit 0
fi

# Only the default branch syncs: ~/.claude/ affects every Claude Code session, so work-in-progress
# branches shouldn't reach it. Run ./install.sh by hand to try a branch globally.
DEFAULT_BRANCH=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
DEFAULT_BRANCH="${DEFAULT_BRANCH#origin/}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
CURRENT_BRANCH=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)
[[ "$CURRENT_BRANCH" == "$DEFAULT_BRANCH" ]] || exit 0

if ! git rev-parse --quiet --verify "$BASE^{commit}" >/dev/null && ! git rev-parse --quiet --verify "$BASE^{tree}" >/dev/null; then
    printf 'sync-global-install: base %s not found; global install NOT updated. Run ./install.sh by hand.\n' "$BASE" >&2
    exit 0
fi

REPO_DIR=$(git rev-parse --show-toplevel)
GLOBAL_COMMANDS_DIR="$HOME/.claude/commands"
GLOBAL_SKILLS_DIR="$HOME/.claude/skills"

# Collect installable changes as parallel status/path arrays. -z output is NUL-separated and
# unquoted, so unusual file names parse correctly. A rename must arrive as a delete plus an add
# so both halves get synced; --no-renames guarantees that regardless of git config.
STATUSES=(); FILES=()
while IFS= read -r -d '' status && IFS= read -r -d '' file; do
    case "$status" in A | M | D) ;; *) continue ;; esac
    case "$file" in .claude/hooks/* | .claude/constants/* | .claude/skills/* | .claude/commands/*) ;; *) continue ;; esac
    STATUSES+=("$status"); FILES+=("$file")
done < <(git diff-tree -r -z --no-renames --name-status "$BASE" HEAD)

[[ ${#FILES[@]} -gt 0 ]] || exit 0

printf 'sync-global-install: syncing global custom-commands install...\n'
# CLAUDE_PROJECT_DIR (inherited when committing from a Claude Code session) overrides $PWD in
# the installer, so pin it to the repo being committed.
if ! (cd "$REPO_DIR" && CLAUDE_PROJECT_DIR="$REPO_DIR" bash install.sh >/dev/null); then
    printf 'sync-global-install: install.sh failed; global install NOT updated. Run ./install.sh to see the error.\n' >&2
    exit 0
fi

for i in "${!FILES[@]}"; do
    status="${STATUSES[$i]}"; file="${FILES[$i]}"
    case "$file" in
        .claude/commands/*/*) continue ;;
        .claude/commands/install-custom-commands.* | .claude/commands/install-custom-commands-minimal.*) continue ;;
        .claude/commands/*.sh | .claude/commands/*.md) dest="$GLOBAL_COMMANDS_DIR/${file#.claude/commands/}" ;;
        .claude/skills/*) dest="$GLOBAL_SKILLS_DIR/${file#.claude/skills/}" ;;
        *) continue ;;
    esac

    if [[ "$status" == D ]]; then
        [[ -e "$dest" ]] || continue
        if rm -f "$dest"; then
            printf 'sync-global-install: removed %s\n' "$dest"
            # Drop now-empty skill directories, stopping at the skills root
            dir=$(dirname "$dest")
            while [[ "$dir" == "$GLOBAL_SKILLS_DIR"/* ]] && rmdir "$dir" 2>/dev/null; do
                dir=$(dirname "$dir")
            done
        else
            printf 'sync-global-install: failed to remove %s\n' "$dest" >&2
        fi
    elif [[ "$file" == .claude/commands/* ]]; then
        # Skills are already overwritten by install.sh; only commands need the force-copy.
        if ! cp "$REPO_DIR/$file" "$dest"; then
            printf 'sync-global-install: failed to copy %s to %s\n' "$file" "$dest" >&2
            continue
        fi
        if [[ "$dest" == *.sh ]]; then chmod +x "$dest"; fi
        printf 'sync-global-install: updated %s\n' "$dest"
    fi
done

printf 'sync-global-install: global install synced. Restart Claude Code to pick up hook changes.\n'
