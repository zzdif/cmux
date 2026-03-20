#!/usr/bin/env bash
set -euo pipefail

# Generates a categorized diff summary for upstream sync PRs.
# Groups changed files by area and provides statistics.
#
# Usage: diff-summary.sh <base-ref> <head-ref>

BASE_REF="${1:?Usage: diff-summary.sh <base-ref> <head-ref>}"
HEAD_REF="${2:?Usage: diff-summary.sh <base-ref> <head-ref>}"

# Get changed files with stats
CHANGED_FILES=$(git diff --name-status "${BASE_REF}..${HEAD_REF}")
DIFFSTAT=$(git diff --shortstat "${BASE_REF}..${HEAD_REF}")
COMMIT_COUNT=$(git rev-list --count "${BASE_REF}..${HEAD_REF}")

# Categorize files
declare -A CATEGORIES
CATEGORIES=(
  ["App Core (Sources/)"]=""
  ["CLI"]=""
  ["Panels & Browser"]=""
  ["Auto-Update"]=""
  ["Find/Search"]=""
  ["Shell Integration"]=""
  ["Remote Daemon"]=""
  ["Tests"]=""
  ["CI/CD"]=""
  ["Scripts"]=""
  ["Web"]=""
  ["Resources & Config"]=""
  ["Documentation"]=""
  ["Other"]=""
)

categorize_file() {
  local status="$1"
  local file="$2"
  local icon=""

  case "$status" in
    A) icon="🆕" ;;
    M) icon="📝" ;;
    D) icon="🗑️" ;;
    R*) icon="📛" ;;
    *) icon="❓" ;;
  esac

  local entry="${icon} \`${file}\`"

  case "$file" in
    Sources/Panels/*|Sources/*/Browser*|Sources/*/CmuxWeb*)
      CATEGORIES["Panels & Browser"]+="${entry}\n" ;;
    Sources/Update/*)
      CATEGORIES["Auto-Update"]+="${entry}\n" ;;
    Sources/Find/*)
      CATEGORIES["Find/Search"]+="${entry}\n" ;;
    Sources/*)
      CATEGORIES["App Core (Sources/)"]+="${entry}\n" ;;
    CLI/*)
      CATEGORIES["CLI"]+="${entry}\n" ;;
    Resources/shell-integration/*|Resources/bin/*)
      CATEGORIES["Shell Integration"]+="${entry}\n" ;;
    daemon/*)
      CATEGORIES["Remote Daemon"]+="${entry}\n" ;;
    tests/*|tests_v2/*|cmuxTests/*|cmuxUITests/*)
      CATEGORIES["Tests"]+="${entry}\n" ;;
    .github/*)
      CATEGORIES["CI/CD"]+="${entry}\n" ;;
    scripts/*)
      CATEGORIES["Scripts"]+="${entry}\n" ;;
    web/*)
      CATEGORIES["Web"]+="${entry}\n" ;;
    Resources/*|*.entitlements|*.plist|*.xcstrings|*.sdef|*.xcodeproj/*|*.xcconfig|Package.swift|Package.resolved)
      CATEGORIES["Resources & Config"]+="${entry}\n" ;;
    *.md|docs/*|LICENSE|CONTRIBUTING*)
      CATEGORIES["Documentation"]+="${entry}\n" ;;
    *)
      CATEGORIES["Other"]+="${entry}\n" ;;
  esac
}

# Process each changed file
while IFS=$'\t' read -r status file rest; do
  [ -z "$status" ] && continue
  # Handle renames (R100 old new)
  if [[ "$status" == R* ]]; then
    file="${rest:-$file}"
  fi
  categorize_file "$status" "$file"
done <<< "$CHANGED_FILES"

# Count files per category
TOTAL_FILES=$(echo "$CHANGED_FILES" | grep -c '.' || echo 0)

# ============================================================
# Output Report
# ============================================================

echo "## 📋 Diff Summary"
echo ""
echo "**${COMMIT_COUNT} commits** | ${DIFFSTAT}"
echo ""

# Output non-empty categories in priority order
PRIORITY_ORDER=(
  "App Core (Sources/)"
  "Panels & Browser"
  "CLI"
  "Auto-Update"
  "Find/Search"
  "Shell Integration"
  "Remote Daemon"
  "Resources & Config"
  "Scripts"
  "CI/CD"
  "Tests"
  "Web"
  "Documentation"
  "Other"
)

for category in "${PRIORITY_ORDER[@]}"; do
  content="${CATEGORIES[$category]}"
  if [ -n "$content" ]; then
    FILE_COUNT=$(echo -e "$content" | grep -c '.' || echo 0)
    echo "<details>"
    echo "<summary><strong>${category}</strong> (${FILE_COUNT} files)</summary>"
    echo ""
    echo -e "$content"
    echo "</details>"
    echo ""
  fi
done

# Highlight key areas for manual review
echo "### Areas requiring attention"
echo ""

ATTENTION_ITEMS=0

if [ -n "${CATEGORIES["App Core (Sources/)"]}" ]; then
  echo "- **App core** changed — review for behavioral changes, new network calls, new permissions"
  ATTENTION_ITEMS=$((ATTENTION_ITEMS + 1))
fi

if [ -n "${CATEGORIES["CLI"]}" ]; then
  echo "- **CLI** changed — review socket command changes, new telemetry"
  ATTENTION_ITEMS=$((ATTENTION_ITEMS + 1))
fi

if [ -n "${CATEGORIES["Shell Integration"]}" ]; then
  echo "- **Shell integration** changed — review environment modifications, PATH changes"
  ATTENTION_ITEMS=$((ATTENTION_ITEMS + 1))
fi

if [ -n "${CATEGORIES["Remote Daemon"]}" ]; then
  echo "- **Remote daemon** changed — review network, auth, proxy changes"
  ATTENTION_ITEMS=$((ATTENTION_ITEMS + 1))
fi

if [ -n "${CATEGORIES["Resources & Config"]}" ]; then
  echo "- **Resources/config** changed — review entitlements, plist, localization"
  ATTENTION_ITEMS=$((ATTENTION_ITEMS + 1))
fi

if [ -n "${CATEGORIES["Scripts"]}" ]; then
  echo "- **Build scripts** changed — review for new downloads, binary fetches"
  ATTENTION_ITEMS=$((ATTENTION_ITEMS + 1))
fi

if [ $ATTENTION_ITEMS -eq 0 ]; then
  echo "No high-priority areas changed (tests, docs, CI only)."
fi
