#!/usr/bin/env bash
set -euo pipefail

# fork-build.sh — Build the personal fork
#
# Usage:
#   ./scripts/fork-build.sh              # full build: sync, setup, build, launch
#   ./scripts/fork-build.sh --quick      # skip git sync and setup, just build + launch
#   ./scripts/fork-build.sh --setup-only # only run git sync and setup (no build)
#
# The app will show as "cmux DEV zz" and launch automatically.

TAG="zz"
QUICK=0
SETUP_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick) QUICK=1; shift ;;
    --setup-only) SETUP_ONLY=1; shift ;;
    -h|--help)
      echo "Usage: ./scripts/fork-build.sh [--quick] [--setup-only]"
      echo ""
      echo "  --quick        Skip git sync and setup, just build + launch"
      echo "  --setup-only   Only run git sync and setup (no build)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

# Check we're on the personal branch
CURRENT_BRANCH=$(git branch --show-current)
if [[ "$CURRENT_BRANCH" != "personal" ]]; then
  echo "Error: must be on 'personal' branch (currently on '${CURRENT_BRANCH}')" >&2
  echo "Run: git checkout personal" >&2
  exit 1
fi

# Step 1: Sync
if [[ "$QUICK" -eq 0 ]]; then
  echo "==> Syncing personal branch..."
  git pull --rebase origin personal

  echo "==> Updating submodules..."
  git submodule update --init --recursive

  echo "==> Running setup (builds GhosttyKit if needed)..."
  ./scripts/setup.sh
fi

if [[ "$SETUP_ONLY" -eq 1 ]]; then
  echo "==> Setup complete (--setup-only, skipping build)."
  exit 0
fi

# Step 2: Build and launch
echo "==> Building and launching (tag: ${TAG})..."
./scripts/reload.sh --tag "$TAG"

# Step 3: Copy to /Applications
APP_NAME="cmux DEV ${TAG}"
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/cmux-${TAG}"
BUILT_APP="${DERIVED_DATA}/Build/Products/Debug/${APP_NAME}.app"

if [[ -d "$BUILT_APP" ]]; then
  echo "==> Copying to /Applications..."
  rm -rf "/Applications/${APP_NAME}.app"
  cp -R "$BUILT_APP" "/Applications/${APP_NAME}.app"
  touch "/Applications/${APP_NAME}.app"
  echo "==> Installed: /Applications/${APP_NAME}.app"
else
  echo "Warning: built app not found at ${BUILT_APP}, skipping /Applications copy"
fi
