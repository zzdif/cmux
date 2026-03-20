#!/usr/bin/env bash
set -euo pipefail

# Contribution workflow helper for fork → upstream PRs.
#
# Usage:
#   scripts/contrib.sh new <branch-name>     Create a new contrib branch from latest upstream/main
#   scripts/contrib.sh rebase [branch-name]  Rebase current (or named) contrib branch onto upstream/main
#   scripts/contrib.sh pr [branch-name]      Open a PR from contrib branch to upstream
#   scripts/contrib.sh sync-personal         Rebase the 'personal' branch onto latest main
#   scripts/contrib.sh status                Show status of all contrib/* branches
#
# Branch naming convention:
#   contrib/<name>   — feature branches intended for upstream contribution
#   personal         — long-lived branch for personal customizations (never sent upstream)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

UPSTREAM_REMOTE="upstream"
UPSTREAM_URL="https://github.com/manaflow-ai/cmux.git"
UPSTREAM_BRANCH="main"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}==> ${NC}$*"; }
ok()    { echo -e "${GREEN}==> ${NC}$*"; }
warn()  { echo -e "${YELLOW}==> ${NC}$*"; }
err()   { echo -e "${RED}==> ${NC}$*" >&2; }

ensure_upstream_remote() {
  if ! git remote get-url "$UPSTREAM_REMOTE" &>/dev/null; then
    info "Adding upstream remote: ${UPSTREAM_URL}"
    git remote add "$UPSTREAM_REMOTE" "$UPSTREAM_URL"
  fi
  info "Fetching upstream..."
  git fetch "$UPSTREAM_REMOTE" --quiet
}

current_branch() {
  git branch --show-current
}

is_contrib_branch() {
  [[ "$1" == contrib/* ]]
}

# ────────────────────────────────────────────────────
# Command: new
# ────────────────────────────────────────────────────
cmd_new() {
  local name="${1:?Usage: contrib.sh new <branch-name>}"
  local branch="contrib/${name}"

  ensure_upstream_remote

  if git show-ref --verify --quiet "refs/heads/${branch}"; then
    err "Branch '${branch}' already exists locally"
    exit 1
  fi

  info "Creating '${branch}' from upstream/${UPSTREAM_BRANCH}..."
  git checkout -b "${branch}" "${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}"

  ok "Branch '${branch}' created and checked out"
  echo ""
  echo "Next steps:"
  echo "  1. Make your changes"
  echo "  2. Commit as usual"
  echo "  3. Push:  git push -u origin ${branch}"
  echo "  4. Open PR to upstream:  scripts/contrib.sh pr"
}

# ────────────────────────────────────────────────────
# Command: rebase
# ────────────────────────────────────────────────────
cmd_rebase() {
  local branch="${1:-$(current_branch)}"

  if ! is_contrib_branch "$branch"; then
    err "'${branch}' is not a contrib/* branch"
    echo "Only contrib/* branches should be rebased onto upstream."
    echo "For the personal branch, use: scripts/contrib.sh sync-personal"
    exit 1
  fi

  ensure_upstream_remote

  # Ensure we're on the branch
  if [ "$(current_branch)" != "$branch" ]; then
    info "Switching to ${branch}..."
    git checkout "$branch"
  fi

  info "Rebasing '${branch}' onto upstream/${UPSTREAM_BRANCH}..."
  if git rebase "${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}"; then
    ok "Rebase successful"
    echo ""
    echo "If this branch is already pushed, you'll need to force-push:"
    echo "  git push --force-with-lease origin ${branch}"
  else
    warn "Rebase has conflicts. Resolve them, then:"
    echo "  git rebase --continue"
    echo "  git push --force-with-lease origin ${branch}"
    exit 1
  fi
}

# ────────────────────────────────────────────────────
# Command: pr
# ────────────────────────────────────────────────────
cmd_pr() {
  local branch="${1:-$(current_branch)}"

  if ! is_contrib_branch "$branch"; then
    err "'${branch}' is not a contrib/* branch"
    echo "Only contrib/* branches should be sent upstream."
    exit 1
  fi

  ensure_upstream_remote

  # Check if branch is pushed
  if ! git rev-parse --verify "origin/${branch}" &>/dev/null; then
    info "Pushing '${branch}' to origin..."
    git push -u origin "$branch"
  fi

  # Check if branch is up to date with upstream
  local behind
  behind=$(git rev-list --count "${branch}..${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}")
  if [ "$behind" -gt 0 ]; then
    warn "Branch is ${behind} commits behind upstream/${UPSTREAM_BRANCH}"
    echo "Consider rebasing first: scripts/contrib.sh rebase"
    echo ""
  fi

  # Get the fork owner (for cross-fork PR)
  local fork_owner
  fork_owner=$(gh repo view --json owner -q '.owner.login' 2>/dev/null || true)

  if [ -z "$fork_owner" ]; then
    err "Could not determine fork owner. Make sure 'gh' is authenticated."
    exit 1
  fi

  info "Opening PR from ${fork_owner}:${branch} → manaflow-ai/cmux:${UPSTREAM_BRANCH}"
  echo ""

  gh pr create \
    --repo "manaflow-ai/cmux" \
    --base "${UPSTREAM_BRANCH}" \
    --head "${fork_owner}:${branch}" \
    --web

  ok "PR creation page opened in browser"
}

# ────────────────────────────────────────────────────
# Command: sync-personal
# ────────────────────────────────────────────────────
cmd_sync_personal() {
  local personal_branch="personal"

  # Check if personal branch exists
  if ! git show-ref --verify --quiet "refs/heads/${personal_branch}"; then
    warn "No '${personal_branch}' branch found."
    echo ""
    echo "To create one:"
    echo "  git checkout -b personal main"
    echo "  # Add your customizations"
    echo "  git push -u origin personal"
    exit 1
  fi

  ensure_upstream_remote

  local was_on
  was_on=$(current_branch)

  info "Switching to '${personal_branch}'..."
  git checkout "$personal_branch"

  info "Rebasing '${personal_branch}' onto origin/main..."
  if git rebase origin/main; then
    ok "Personal branch rebased onto latest main"
    echo ""
    echo "Force-push to update remote:"
    echo "  git push --force-with-lease origin personal"
  else
    warn "Rebase has conflicts. Resolve them, then:"
    echo "  git rebase --continue"
    echo "  git push --force-with-lease origin personal"
  fi
}

# ────────────────────────────────────────────────────
# Command: status
# ────────────────────────────────────────────────────
cmd_status() {
  ensure_upstream_remote

  echo "Branch status (relative to upstream/${UPSTREAM_BRANCH}):"
  echo ""

  # Check main
  local main_ahead main_behind
  main_ahead=$(git rev-list --count "${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}..origin/main" 2>/dev/null || echo "?")
  main_behind=$(git rev-list --count "origin/main..${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}" 2>/dev/null || echo "?")

  if [ "$main_ahead" = "0" ] && [ "$main_behind" = "0" ]; then
    echo -e "  ${GREEN}main${NC}  up to date with upstream"
  elif [ "$main_ahead" = "0" ]; then
    echo -e "  ${YELLOW}main${NC}  ${main_behind} commits behind upstream (sync needed)"
  else
    echo -e "  ${RED}main${NC}  ${main_ahead} commits ahead of upstream (DIVERGED — fix this!)"
  fi

  # Check personal branch
  if git show-ref --verify --quiet "refs/heads/personal" 2>/dev/null || \
     git show-ref --verify --quiet "refs/remotes/origin/personal" 2>/dev/null; then
    local personal_ref="personal"
    git show-ref --verify --quiet "refs/heads/personal" || personal_ref="origin/personal"
    local p_ahead
    p_ahead=$(git rev-list --count "origin/main..${personal_ref}" 2>/dev/null || echo "?")
    echo -e "  ${BLUE}personal${NC}  ${p_ahead} commits ahead of main"
  fi

  # Check contrib branches
  local contrib_branches
  contrib_branches=$(git branch -a --list '*contrib/*' 2>/dev/null | sed 's|remotes/origin/||; s|^[* ]*||' | sort -u || true)

  if [ -n "$contrib_branches" ]; then
    echo ""
    echo "Contrib branches:"
    while IFS= read -r branch; do
      [ -z "$branch" ] && continue
      local ref="$branch"
      git show-ref --verify --quiet "refs/heads/${branch}" || ref="origin/${branch}"
      local c_ahead c_behind
      c_ahead=$(git rev-list --count "${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}..${ref}" 2>/dev/null || echo "?")
      c_behind=$(git rev-list --count "${ref}..${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}" 2>/dev/null || echo "?")

      if [ "$c_behind" = "0" ]; then
        echo -e "  ${GREEN}${branch}${NC}  ${c_ahead} commits, up to date"
      else
        echo -e "  ${YELLOW}${branch}${NC}  ${c_ahead} commits, ${c_behind} behind upstream (rebase needed)"
      fi
    done <<< "$contrib_branches"
  fi

  echo ""
}

# ────────────────────────────────────────────────────
# Main dispatcher
# ────────────────────────────────────────────────────
case "${1:-help}" in
  new)             shift; cmd_new "$@" ;;
  rebase)          shift; cmd_rebase "$@" ;;
  pr)              shift; cmd_pr "$@" ;;
  sync-personal)   shift; cmd_sync_personal "$@" ;;
  status)          shift; cmd_status "$@" ;;
  help|--help|-h)
    echo "Usage: scripts/contrib.sh <command> [args]"
    echo ""
    echo "Commands:"
    echo "  new <name>          Create contrib/<name> branch from latest upstream/main"
    echo "  rebase [branch]     Rebase a contrib branch onto latest upstream/main"
    echo "  pr [branch]         Open a PR from a contrib branch to upstream"
    echo "  sync-personal       Rebase the 'personal' branch onto latest main"
    echo "  status              Show status of all branches vs upstream"
    echo ""
    echo "Branch convention:"
    echo "  main                Reviewed mirror of upstream (never commit directly)"
    echo "  personal            Your personal customizations (rebase onto main)"
    echo "  contrib/<name>      Feature branches for upstream contributions"
    ;;
  *)
    err "Unknown command: $1"
    echo "Run 'scripts/contrib.sh help' for usage"
    exit 1
    ;;
esac
