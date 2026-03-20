#!/usr/bin/env bash
set -euo pipefail

# Supply chain / dependency check for upstream sync PRs.
# Compares two refs and flags changes to dependencies, submodules, CI, and scripts.
#
# Usage: supply-chain-check.sh <base-ref> <head-ref>

BASE_REF="${1:?Usage: supply-chain-check.sh <base-ref> <head-ref>}"
HEAD_REF="${2:?Usage: supply-chain-check.sh <base-ref> <head-ref>}"

declare -a FINDINGS=()
FINDING_COUNT=0

add_finding() {
  local severity="$1"
  local message="$2"
  local icon=""
  case "$severity" in
    CRITICAL) icon="🔴" ;;
    HIGH)     icon="🔴" ;;
    MEDIUM)   icon="🟡" ;;
    LOW)      icon="🟢" ;;
    INFO)     icon="ℹ️" ;;
  esac
  FINDING_COUNT=$((FINDING_COUNT + 1))
  FINDINGS+=("${icon} **${severity}** — ${message}")
}

add_detail() {
  FINDINGS+=("  $1")
}

# ============================================================
# 1. Submodule pointer changes
# ============================================================

SUBMODULE_DIFF=$(git diff "${BASE_REF}..${HEAD_REF}" -- .gitmodules || true)
SUBMODULE_CHANGES=$(git diff "${BASE_REF}..${HEAD_REF}" --diff-filter=M -- ghostty vendor/bonsplit homebrew-cmux 2>/dev/null || true)

if [ -n "$SUBMODULE_DIFF" ]; then
  add_finding "HIGH" "**.gitmodules changed** — submodule URLs or branches may have been modified"

  # Check for URL changes specifically
  OLD_URLS=$(git show "${BASE_REF}:.gitmodules" 2>/dev/null | grep 'url = ' || true)
  NEW_URLS=$(git show "${HEAD_REF}:.gitmodules" 2>/dev/null | grep 'url = ' || true)

  if [ "$OLD_URLS" != "$NEW_URLS" ]; then
    add_finding "HIGH" "Submodule URLs changed — **verify the new sources are trusted**"
    add_detail "Old URLs:"
    while IFS= read -r line; do
      add_detail "  \`${line}\`"
    done <<< "$OLD_URLS"
    add_detail "New URLs:"
    while IFS= read -r line; do
      add_detail "  \`${line}\`"
    done <<< "$NEW_URLS"
  fi
  FINDINGS+=("")
fi

if [ -n "$SUBMODULE_CHANGES" ]; then
  add_finding "MEDIUM" "Submodule pointer(s) updated — new commits will be pulled"
  # Show which submodules changed
  CHANGED_SUBS=$(git diff --name-only "${BASE_REF}..${HEAD_REF}" -- ghostty vendor/bonsplit homebrew-cmux 2>/dev/null || true)
  while IFS= read -r sub; do
    [ -z "$sub" ] && continue
    OLD_SHA=$(git ls-tree "${BASE_REF}" -- "$sub" 2>/dev/null | awk '{print $3}' | cut -c1-8)
    NEW_SHA=$(git ls-tree "${HEAD_REF}" -- "$sub" 2>/dev/null | awk '{print $3}' | cut -c1-8)
    add_detail "- \`${sub}\`: \`${OLD_SHA:-new}\` → \`${NEW_SHA:-removed}\`"
  done <<< "$CHANGED_SUBS"
  FINDINGS+=("")
fi

# ============================================================
# 2. Package manager dependency changes
# ============================================================

for dep_file in Package.swift Package.resolved package.json bun.lock web/package.json web/bun.lock web/package-lock.json; do
  CHANGED=$(git diff --name-only "${BASE_REF}..${HEAD_REF}" -- "$dep_file" 2>/dev/null || true)
  if [ -n "$CHANGED" ]; then
    add_finding "MEDIUM" "Dependency file changed: \`${dep_file}\`"

    # For Package.swift, check for new package URLs
    if [ "$dep_file" = "Package.swift" ]; then
      NEW_DEPS=$(git diff "${BASE_REF}..${HEAD_REF}" -- Package.swift | grep '^\+.*\.package(url:' || true)
      if [ -n "$NEW_DEPS" ]; then
        add_finding "HIGH" "New Swift package dependency added"
        while IFS= read -r dep; do
          add_detail "- \`${dep}\`"
        done <<< "$NEW_DEPS"
      fi
    fi

    # For Go modules
    if [ "$dep_file" = "daemon/remote/go.mod" ]; then
      NEW_DEPS=$(git diff "${BASE_REF}..${HEAD_REF}" -- daemon/remote/go.mod | grep '^\+.*require' || true)
      if [ -n "$NEW_DEPS" ]; then
        add_finding "HIGH" "New Go dependency added"
        while IFS= read -r dep; do
          add_detail "- \`${dep}\`"
        done <<< "$NEW_DEPS"
      fi
    fi
    FINDINGS+=("")
  fi
done

# Also check go.mod
GO_MOD_CHANGED=$(git diff --name-only "${BASE_REF}..${HEAD_REF}" -- daemon/remote/go.mod 2>/dev/null || true)
if [ -n "$GO_MOD_CHANGED" ]; then
  add_finding "MEDIUM" "Go module file changed: \`daemon/remote/go.mod\`"
  FINDINGS+=("")
fi

# ============================================================
# 3. CI/CD workflow changes
# ============================================================

CI_CHANGES=$(git diff --name-only "${BASE_REF}..${HEAD_REF}" -- .github/workflows/ .github/scripts/ 2>/dev/null || true)
if [ -n "$CI_CHANGES" ]; then
  add_finding "MEDIUM" "CI/CD workflow or script changes detected"
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    add_detail "- \`${file}\`"
  done <<< "$CI_CHANGES"

  # Check for new secrets references
  CI_DIFF=$(git diff "${BASE_REF}..${HEAD_REF}" -- .github/workflows/ || true)
  NEW_SECRETS=$(echo "$CI_DIFF" | grep '^\+.*\${{.*secrets\.' | grep -v '^\+\+\+' || true)
  if [ -n "$NEW_SECRETS" ]; then
    add_finding "HIGH" "New GitHub secrets references in CI workflows"
    while IFS= read -r secret; do
      add_detail "- \`${secret}\`"
    done <<< "$(echo "$NEW_SECRETS" | head -5)"
  fi

  # Check for self-hosted runner changes
  RUNNER_CHANGES=$(echo "$CI_DIFF" | grep '^\+.*runs-on:.*self-hosted' || true)
  if [ -n "$RUNNER_CHANGES" ]; then
    add_finding "HIGH" "New self-hosted runner usage in CI — could execute on your infrastructure"
  fi
  FINDINGS+=("")
fi

# ============================================================
# 4. Build/release script changes
# ============================================================

SCRIPT_CHANGES=$(git diff --name-only "${BASE_REF}..${HEAD_REF}" -- scripts/ 2>/dev/null || true)
if [ -n "$SCRIPT_CHANGES" ]; then
  add_finding "MEDIUM" "Build/release script changes"
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    add_detail "- \`${file}\`"
  done <<< "$SCRIPT_CHANGES"

  # Check for new curl/wget/download commands
  SCRIPT_DIFF=$(git diff "${BASE_REF}..${HEAD_REF}" -- scripts/ || true)
  NEW_DOWNLOADS=$(echo "$SCRIPT_DIFF" | grep -E '^\+.*(curl |wget |download|fetch)' | grep -v '^\+\+\+' | head -5 || true)
  if [ -n "$NEW_DOWNLOADS" ]; then
    add_finding "HIGH" "New download commands in build scripts — verify sources"
    while IFS= read -r dl; do
      add_detail "- \`${dl:0:120}\`"
    done <<< "$NEW_DOWNLOADS"
  fi
  FINDINGS+=("")
fi

# ============================================================
# 5. Entitlements and Info.plist changes
# ============================================================

ENTITLEMENT_CHANGES=$(git diff --name-only "${BASE_REF}..${HEAD_REF}" -- '*.entitlements' Resources/Info.plist 2>/dev/null || true)
if [ -n "$ENTITLEMENT_CHANGES" ]; then
  add_finding "HIGH" "Entitlements or Info.plist changed — app permissions may have changed"
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    add_detail "- \`${file}\`"
  done <<< "$ENTITLEMENT_CHANGES"
  FINDINGS+=("")
fi

# ============================================================
# 6. Xcode project file changes
# ============================================================

XCODEPROJ_CHANGES=$(git diff --name-only "${BASE_REF}..${HEAD_REF}" -- '*.xcodeproj/' '*.xcconfig' 2>/dev/null || true)
if [ -n "$XCODEPROJ_CHANGES" ]; then
  add_finding "LOW" "Xcode project/config files changed"
  FILE_COUNT=$(echo "$XCODEPROJ_CHANGES" | wc -l | tr -d ' ')
  add_detail "${FILE_COUNT} file(s) modified in the Xcode project"

  # Check for new build phase scripts (Run Script)
  XCPROJ_DIFF=$(git diff "${BASE_REF}..${HEAD_REF}" -- '*.xcodeproj/' || true)
  NEW_SCRIPTS=$(echo "$XCPROJ_DIFF" | grep '^\+.*shellScript' | head -3 || true)
  if [ -n "$NEW_SCRIPTS" ]; then
    add_finding "HIGH" "New Run Script build phases in Xcode project — executes during build"
    while IFS= read -r script; do
      add_detail "- \`${script:0:120}\`"
    done <<< "$NEW_SCRIPTS"
  fi
  FINDINGS+=("")
fi

# ============================================================
# 7. New executable/binary files
# ============================================================

NEW_FILES=$(git diff --name-only --diff-filter=A "${BASE_REF}..${HEAD_REF}" || true)
BINARY_FILES=""
while IFS= read -r file; do
  [ -z "$file" ] && continue
  # Check common binary extensions
  case "$file" in
    *.dylib|*.so|*.a|*.o|*.framework/*|*.xcframework/*|*.app/*|*.dmg|*.pkg|*.whl|*.bin)
      BINARY_FILES="${BINARY_FILES}${file}\n"
      ;;
  esac
done <<< "$NEW_FILES"

if [ -n "$BINARY_FILES" ]; then
  add_finding "HIGH" "New binary/compiled files added — cannot be reviewed as source"
  echo -e "$BINARY_FILES" | while IFS= read -r bf; do
    [ -z "$bf" ] && continue
    add_detail "- \`${bf}\`"
  done
  FINDINGS+=("")
fi

# ============================================================
# 8. Checksum file changes
# ============================================================

CHECKSUM_CHANGES=$(git diff --name-only "${BASE_REF}..${HEAD_REF}" -- '*checksum*' '*sha256*' '*sha512*' 2>/dev/null || true)
if [ -n "$CHECKSUM_CHANGES" ]; then
  add_finding "MEDIUM" "Checksum/hash pinning files changed — verify integrity"
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    add_detail "- \`${file}\`"
  done <<< "$CHECKSUM_CHANGES"
  FINDINGS+=("")
fi

# ============================================================
# Output Report
# ============================================================

echo "## 📦 Supply Chain & Dependency Check"
echo ""

if [ "$FINDING_COUNT" -eq 0 ]; then
  echo "✅ **No supply chain changes detected.**"
  echo ""
  echo "No modifications to submodules, dependencies, CI workflows, build scripts,"
  echo "entitlements, or binary files."
else
  echo "Found **${FINDING_COUNT} items** to review:"
  echo ""

  for finding in "${FINDINGS[@]}"; do
    echo "$finding"
  done

  echo ""
  echo "> **Action:** Review each item above. Submodule URL changes, new dependencies,"
  echo "> and CI workflow modifications are the highest-priority items to verify."
fi
