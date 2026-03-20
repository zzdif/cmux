#!/usr/bin/env bash
set -euo pipefail

# Security audit script for upstream sync PRs.
# Scans a unified diff file for patterns that indicate security-relevant changes.
# Outputs a Markdown report section.
#
# Usage: security-audit.sh <diff-file>

DIFF_FILE="${1:?Usage: security-audit.sh <diff-file>}"

if [ ! -f "$DIFF_FILE" ]; then
  echo "## 🔒 Security Audit"
  echo ""
  echo "⚠️ Diff file not found: ${DIFF_FILE}"
  exit 0
fi

# We only look at added lines (lines starting with +, excluding +++ file headers)
ADDED_LINES=$(grep -E '^\+[^+]' "$DIFF_FILE" || true)

declare -a FINDINGS=()
FINDING_COUNT=0

# Helper: search added lines for a pattern, record findings with context
check_pattern() {
  local category="$1"
  local severity="$2"   # CRITICAL, HIGH, MEDIUM, LOW, INFO
  local pattern="$3"
  local description="$4"
  local icon=""

  case "$severity" in
    CRITICAL) icon="🔴" ;;
    HIGH)     icon="🔴" ;;
    MEDIUM)   icon="🟡" ;;
    LOW)      icon="🟢" ;;
    INFO)     icon="ℹ️" ;;
  esac

  # Search the diff for the pattern (case-insensitive where appropriate)
  local matches
  matches=$(grep -n -i -E "$pattern" "$DIFF_FILE" | grep -E '^\d+:\+' | head -10 || true)

  if [ -n "$matches" ]; then
    FINDING_COUNT=$((FINDING_COUNT + 1))
    FINDINGS+=("${icon} **${severity}** — ${category}: ${description}")

    # Extract file context for each match
    while IFS= read -r match_line; do
      # Find which file this line belongs to
      local line_num
      line_num=$(echo "$match_line" | cut -d: -f1)
      local file_header
      file_header=$(head -n "$line_num" "$DIFF_FILE" | grep -E '^\+\+\+ b/' | tail -1 | sed 's|^+++ b/||')
      local code
      code=$(echo "$match_line" | cut -d: -f2- | sed 's/^\+//')

      if [ -n "$file_header" ]; then
        FINDINGS+=("  - \`${file_header}\`: \`${code:0:120}\`")
      fi
    done <<< "$matches"

    FINDINGS+=("")
  fi
}

# ============================================================
# Security Pattern Checks
# ============================================================

# --- Network / Data Exfiltration ---
check_pattern "New URL endpoints" "MEDIUM" \
  'https?://[a-zA-Z0-9]' \
  "New HTTP(S) URLs added — verify these are expected endpoints"

check_pattern "WebSocket connections" "MEDIUM" \
  'wss?://' \
  "New WebSocket URLs added"

check_pattern "DNS / network resolution" "MEDIUM" \
  '(CFHost|getaddrinfo|gethostbyname|nslookup|dig |NSHost)' \
  "New DNS/host resolution calls"

# --- Process Execution ---
check_pattern "Shell execution" "HIGH" \
  '(/bin/(sh|bash|zsh)|NSTask|Process\(\)|launchPath|executableURL.*fileURLWithPath)' \
  "New shell/process execution — could run arbitrary commands"

check_pattern "Dynamic code execution" "HIGH" \
  '(dlopen|dlsym|NSBundle.*load|objc_msgSend|performSelector|eval\(|Function\()' \
  "Dynamic code loading or eval — potential code injection vector"

# --- Credential / Secret Access ---
check_pattern "Keychain access" "HIGH" \
  '(SecItem|SecKeychain|kSecClass|kSecAttr|kSecValue|Security\.framework)' \
  "Keychain API usage — accessing stored credentials"

check_pattern "Hardcoded secrets" "HIGH" \
  '(api_key|apikey|secret_key|private_key|bearer |authorization.*:)' \
  "Potential hardcoded secrets or API keys"

check_pattern "New Sentry/analytics DSN" "MEDIUM" \
  '(dsn.*=.*https://|ingest\..*sentry\.io|posthog\.com|analytics|telemetry.*endpoint)' \
  "Analytics/telemetry endpoint changes"

# --- Entitlements / Permissions ---
check_pattern "Entitlement changes" "HIGH" \
  '(com\.apple\.security|com\.apple\.developer)' \
  "App entitlement changes — affects macOS security sandbox"

check_pattern "TCC / Privacy permissions" "HIGH" \
  '(NSCamera|NSMicrophone|NSAppleEvents|NSDesktopFolder|NSDocumentsFolder|NSDownloadsFolder|NSRemovableVolumes|NSContactsUsage|NSCalendarsUsage|NSRemindersUsage|NSPhotoLibrary|NSLocation)' \
  "New privacy permission usage descriptions (TCC)"

# --- File System ---
check_pattern "Home directory access" "LOW" \
  '(NSHomeDirectory|FileManager.*home|\.ssh|\.gnupg|\.aws|\.config|\.env)' \
  "Access to home directory sensitive paths"

check_pattern "Temporary file creation" "LOW" \
  '(NSTemporaryDirectory|/tmp/|mktemp|tmpfile)' \
  "Temporary file operations — check for race conditions"

# --- Crypto / Encoding ---
check_pattern "Cryptographic operations" "MEDIUM" \
  '(CryptoKit|CommonCrypto|CCCrypt|SecKey.*Encrypt|AES|SHA256|HMAC|pbkdf)' \
  "New cryptographic operations — verify correct usage"

check_pattern "Base64 encoding" "LOW" \
  '(base64Encoded|btoa\(|atob\(|Data.*base64)' \
  "Base64 encoding — verify not used for obfuscation"

# --- Socket / IPC ---
check_pattern "Socket changes" "MEDIUM" \
  '(\.sock|unix.*domain|socketPath|bind\(|listen\(|accept\(|0o666|0o777)' \
  "Socket/IPC changes — check permissions and authentication"

check_pattern "Socket permissions" "HIGH" \
  '(chmod.*0o[67]|permissions.*0o[67]|worldReadable|worldWritable)' \
  "Permissive file/socket permissions (world-accessible)"

# --- Clipboard / Pasteboard ---
check_pattern "Clipboard access" "MEDIUM" \
  '(NSPasteboard|UIPasteboard|pbcopy|pbpaste|clipboardData)' \
  "Clipboard access — verify user-initiated only"

# --- WebView / Browser ---
check_pattern "JavaScript bridge" "MEDIUM" \
  '(WKScriptMessageHandler|addScriptMessageHandler|userContentController|webkit\.messageHandlers)' \
  "WebView JavaScript-to-native bridge — potential XSS-to-RCE vector"

check_pattern "WebView configuration" "LOW" \
  '(allowsInlineMediaPlayback|javaScriptEnabled|allowFileAccessFromFileURLs|allowUniversalAccessFromFileURLs)' \
  "WebView security configuration changes"

# --- Info.plist / App Configuration ---
check_pattern "URL scheme registration" "MEDIUM" \
  '(CFBundleURLSchemes|CFBundleURLTypes|UTExportedTypeDeclarations)' \
  "URL scheme or UTType changes — could intercept system URLs"

check_pattern "App Transport Security" "MEDIUM" \
  '(NSAppTransportSecurity|NSAllowsArbitraryLoads|NSExceptionDomains)' \
  "App Transport Security exceptions — weakens HTTPS enforcement"

# --- LaunchAgent / Persistence ---
check_pattern "Persistence mechanisms" "HIGH" \
  '(LaunchAgent|LaunchDaemon|LoginItem|SMAppService|ServiceManagement|launchctl)' \
  "Launch agent/daemon registration — app persistence mechanism"

# --- AppleScript / Automation ---
check_pattern "AppleScript execution" "MEDIUM" \
  '(NSAppleScript|osascript|AppleScript.*execute|NSUserAppleScriptTask)' \
  "AppleScript execution — can automate other apps"

# ============================================================
# Output Report
# ============================================================

echo "## 🔒 Security Audit"
echo ""

if [ "$FINDING_COUNT" -eq 0 ]; then
  echo "✅ **No security-relevant patterns detected in added lines.**"
  echo ""
  echo "The diff does not introduce new URLs, process execution, credential access,"
  echo "entitlement changes, or other flagged patterns."
else
  echo "Found **${FINDING_COUNT} categories** of security-relevant changes:"
  echo ""

  for finding in "${FINDINGS[@]}"; do
    echo "$finding"
  done

  echo ""
  echo "> **Note:** These are pattern-based flags, not confirmed vulnerabilities."
  echo "> Review each finding in the context of the actual code change."
fi
