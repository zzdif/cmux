# Fork Workflow: Upstream Sync & Contribution Guide

This document describes the complete workflow for maintaining a personal fork of
cmux (upstream: `manaflow-ai/cmux`) — including how upstream changes are synced,
reviewed, and merged, and how to contribute changes back to upstream.

## Table of Contents

- [Branch Strategy](#branch-strategy)
- [Upstream Sync Pipeline](#upstream-sync-pipeline)
  - [How the Sync Works](#how-the-sync-works)
  - [Automated Review Report](#automated-review-report)
  - [Manual Trigger](#manual-trigger)
  - [Handling Divergence](#handling-divergence)
- [OpenCode AI Review (Zen)](#opencode-ai-review-zen)
  - [Setup](#setup)
  - [How It Works](#how-it-works)
  - [On-Demand Review](#on-demand-review)
  - [Review Output Format](#review-output-format)
  - [Cost Estimates](#cost-estimates)
- [Contributing Back to Upstream](#contributing-back-to-upstream)
  - [Creating a Contribution Branch](#creating-a-contribution-branch)
  - [Submitting a PR to Upstream](#submitting-a-pr-to-upstream)
  - [Rebasing After Upstream Advances](#rebasing-after-upstream-advances)
- [Personal Customizations & Feature Development](#personal-customizations--feature-development)
  - [Setting Up the Personal Branch](#setting-up-the-personal-branch)
  - [Developing Features](#developing-features)
  - [Keeping Personal in Sync](#keeping-personal-in-sync)
  - [Building the App](#building-the-app)
  - [Contributing a Feature to Upstream](#contributing-a-feature-to-upstream)
- [Checking Branch Status](#checking-branch-status)
- [Disabled Upstream Workflows](#disabled-upstream-workflows)
- [Security Review Details](#security-review-details)
  - [Security Audit](#security-audit)
  - [Supply Chain Check](#supply-chain-check)
  - [Diff Summary](#diff-summary)
- [File Reference](#file-reference)
- [Troubleshooting](#troubleshooting)

---

## Branch Strategy

The fork uses a strict branch convention to keep upstream sync clean,
personal development organized, and contribution flow simple:

```
upstream (manaflow-ai/cmux:main)
    │
    │  weekly auto-sync (reviewed via PR)
    ▼
fork/main ◄─── upstream-sync/<date> PR (auto-reviewed, you merge)
    │
    ├──► personal  ◄─── feature/<name> (your dev work merges here)
    │    (your build target — customizations + features)
    │
    └──► contrib/<name>  ──► PR to upstream (cherry-picked from personal)
         (branched from upstream/main, NOT from personal)
```

| Branch | Purpose | Rule |
|--------|---------|------|
| `main` | Reviewed mirror of upstream | **Never commit directly.** Only merge upstream-sync PRs and pipeline changes. |
| `personal` | Your build target — all customizations and features | Rebase onto `main` after each sync. Build the app from here. |
| `feature/<name>` | Development branches for new features | Branch from `personal`. Merge into `personal` when done. Delete after merge. |
| `contrib/<name>` | Branches for upstream contributions | Branch from `upstream/main`. Cherry-pick selected commits. PR to upstream. Delete after merge. |
| `upstream-sync/<date>` | Automated sync branches | Created by CI. Merged to `main` after review. |

---

## Upstream Sync Pipeline

### How the Sync Works

The sync runs automatically every **Sunday at 08:00 UTC** via GitHub Actions:

1. The `upstream-sync` workflow fetches `manaflow-ai/cmux:main`.
2. If there are new commits, it creates a branch `upstream-sync/YYYY-MM-DD`
   and opens a PR to your fork's `main`.
3. The `review-upstream` workflow triggers on that PR and runs three analysis
   scripts in parallel:
   - **Diff summary** — categorized file changes with stats
   - **Security audit** — pattern-based scan of added lines
   - **Supply chain check** — dependency, submodule, CI, and binary changes
4. Results are posted as a single consolidated PR comment.
5. You review the comment and merge (or reject) the PR.

```
┌─────────────────────────────────────────────────────────┐
│  upstream-sync.yml (Sunday 08:00 UTC / manual)          │
│  - Fetches manaflow-ai/cmux:main                       │
│  - Detects divergence on fork/main                      │
│  - Detects conflicts with open contrib/* branches       │
│  - Opens PR: upstream-sync/YYYY-MM-DD → main            │
└───────────────────────┬─────────────────────────────────┘
                        │ PR opened
                        ▼
┌─────────────────────────────────────────────────────────┐
│  review-upstream.yml (auto on upstream-sync/* PRs)      │
│                                                         │
│  ┌──────────────┐ ┌───────────────┐ ┌────────────────┐ │
│  │ Diff Summary │ │ Security      │ │ Supply Chain   │ │
│  │              │ │ Audit         │ │ Check          │ │
│  └──────┬───────┘ └──────┬────────┘ └───────┬────────┘ │
│         └────────────┬───┴──────────────────┘           │
│                      ▼                                  │
│           Posts consolidated PR comment                  │
│           with all findings                              │
└─────────────────────────────────────────────────────────┘
```

All jobs run on `ubuntu-latest` (free GitHub Actions tier). No macOS runner
needed — the pipeline analyzes diffs, not builds.

### Automated Review Report

The PR comment contains three sections:

**1. Diff Summary** — files grouped by area:
- App Core (Sources/), CLI, Panels & Browser, Auto-Update, Find/Search
- Shell Integration, Remote Daemon, Resources & Config, Scripts
- CI/CD, Tests, Web, Documentation

**2. Security Audit** — flags added lines matching 20+ patterns:
- New URLs / WebSocket endpoints
- Shell/process execution (`Process()`, `/bin/sh`, `NSTask`)
- Keychain access, hardcoded secrets
- Entitlement / TCC permission changes
- Socket permission changes (especially `0o666`/`0o777`)
- Clipboard access, JavaScript bridges, persistence mechanisms
- Cryptographic operations, base64 encoding, AppleScript execution

Severity levels: CRITICAL / HIGH (red), MEDIUM (yellow), LOW (green), INFO

**3. Supply Chain Check** — detects:
- `.gitmodules` changes (submodule URL swaps)
- Submodule pointer updates (SHA changes)
- New package dependencies (Swift, Go, npm)
- CI/CD workflow changes (especially new secrets references, self-hosted runners)
- Build script changes (especially new `curl`/`wget`/download commands)
- Entitlement and Info.plist changes
- New binary/compiled files
- Checksum file changes

### Manual Trigger

To sync on-demand instead of waiting for the weekly schedule:

```bash
# Sync from upstream main (default)
gh workflow run upstream-sync.yml

# Sync from a specific upstream branch
gh workflow run upstream-sync.yml -f upstream_branch=some-branch
```

### Handling Divergence

The sync workflow detects two types of problems:

**Fork main diverged:** If your `main` has commits not in upstream (someone
committed directly to `main`), the sync PR will warn you. Fix by:

```bash
# Option A: Move the commits to a branch
git checkout main
git checkout -b accidental-commits
git checkout main
git reset --hard upstream/main
git push --force-with-lease origin main

# Option B: Rebase them onto upstream
git checkout main
git rebase upstream/main
git push --force-with-lease origin main
```

**Contrib branches may conflict:** If any `contrib/*` branches touch the same
files as new upstream changes, the sync PR will list them. After merging the
sync PR, rebase those branches:

```bash
scripts/contrib.sh rebase contrib/my-feature
```

---

## OpenCode AI Review (Zen)

In addition to the pattern-based bash scripts, an AI-powered review runs via
[OpenCode Zen](https://opencode.ai/zen) using `anthropic/claude-sonnet-4.6`.
The AI review reads the script outputs, verifies findings against the actual
code, investigates deeper, and catches things pattern matching cannot.

### Setup

1. Sign up at [opencode.ai/zen](https://opencode.ai/zen) and add balance ($20 minimum)
2. Copy your API key from the Zen dashboard
3. Add it as a GitHub Secret in your fork:
   - Go to **Settings > Secrets and variables > Actions**
   - Click **New repository secret**
   - Name: `OPENCODE_API_KEY`
   - Value: your Zen API key
4. (Optional) Set a monthly spend limit in the Zen dashboard

### How It Works

The AI review is a **two-tier** system:

```
Tier 1: Bash Scripts (fast, free, deterministic)
  │
  │ Artifacts uploaded (security-audit.md, supply-chain.md, diff-summary.md)
  ▼
Tier 2: OpenCode AI Review (deeper, uses Zen credits)
  │
  │ Reads script outputs + actual code diff
  │ Verifies findings, investigates deeper, finds what scripts missed
  ▼
Posts consolidated AI review comment on the PR
```

**For upstream-sync PRs (automatic):**

1. `review-upstream.yml` runs the bash scripts and uploads artifacts
2. `opencode-review.yml` triggers automatically when the script job completes
3. OpenCode downloads the artifacts, reads them, reviews the actual diff
4. Posts a single consolidated AI review comment

**For any PR (on-demand):**

Comment `/opencode-review` on any PR to trigger an AI review.

### On-Demand Review

To request an AI review on any PR (including your own contrib/* PRs):

1. Open the PR on GitHub
2. Post a comment: `/opencode-review`
3. The bot reacts with :eyes: to acknowledge
4. The workflow runs the bash scripts, then OpenCode reviews everything
5. The bot reacts with :rocket: when complete
6. A consolidated AI review comment is posted

### Review Output Format

The AI review comment follows this structure:

```markdown
## OpenCode AI Review

### Script Findings Verification
For each script finding: CONFIRMED / FALSE POSITIVE / NEEDS CONTEXT
With file path and line number.

### Additional Findings
Issues the scripts missed, with:
- File: `path/to/file:line_number`
- Severity: CRITICAL / HIGH / MEDIUM / LOW / INFO
- Description and context

### Architectural Impact
How changes affect app architecture, security, or privacy.

### Verdict
- SAFE TO MERGE
- SAFE TO MERGE WITH NOTES
- REVIEW RECOMMENDED
- DO NOT MERGE
```

The AI review is **read-only** — it posts comments but never approves,
requests changes, or modifies code. You make the final merge decision.

### Cost Estimates

OpenCode Zen charges per request with zero markup. Estimates for typical
upstream-sync PRs:

| Scenario | Est. Cost | Frequency |
|----------|-----------|-----------|
| Weekly upstream sync (auto) | ~$0.10-0.30 | Weekly |
| On-demand review | ~$0.10-0.30 | As needed |
| Monthly total (auto only) | ~$0.40-1.20 | Monthly |

Set a spend limit in the Zen dashboard to cap costs.

---

## Contributing Back to Upstream

### Creating a Contribution Branch

```bash
# Creates contrib/fix-typing-lag from latest upstream/main
scripts/contrib.sh new fix-typing-lag
```

This:
1. Fetches latest upstream
2. Creates `contrib/fix-typing-lag` branched from `upstream/main`
3. Checks out the branch

Then make your changes and commit normally:

```bash
# ... edit files ...
git add -A
git commit -m "fix: reduce typing latency in hitTest path"
git push -u origin contrib/fix-typing-lag
```

### Submitting a PR to Upstream

```bash
# Opens the GitHub PR creation page in your browser
scripts/contrib.sh pr

# Or specify a branch explicitly
scripts/contrib.sh pr contrib/fix-typing-lag
```

This:
1. Checks the branch is pushed to your fork
2. Warns if the branch is behind upstream (suggests rebasing)
3. Opens the GitHub PR form: `your-fork:contrib/fix-typing-lag` → `manaflow-ai/cmux:main`

### Rebasing After Upstream Advances

If upstream gets new commits while your PR is open:

```bash
# Rebase current contrib branch onto latest upstream/main
scripts/contrib.sh rebase

# Or specify a branch
scripts/contrib.sh rebase contrib/fix-typing-lag

# Then force-push
git push --force-with-lease origin contrib/fix-typing-lag
```

---

## Personal Customizations & Feature Development

### Setting Up the Personal Branch

The `personal` branch is your **build target** — it holds all your customizations
and features. You build the app from this branch.

```bash
# Create from current main
git checkout -b personal main

# Make your initial customizations (e.g., disable auto-update, telemetry)
# ... edit files ...
git add -A
git commit -m "personal: disable auto-update, remove camera entitlement"

git push -u origin personal
```

### Developing Features

When working on a new feature, create a feature branch from `personal`:

```bash
# Create a feature branch
git checkout -b feature/my-cool-thing personal

# ... develop, commit as usual ...
git add -A
git commit -m "feat: add my cool thing"

# When done, merge into personal
git checkout personal
git merge feature/my-cool-thing

# Clean up
git branch -d feature/my-cool-thing
git push origin personal
```

### Keeping Personal in Sync

After merging an upstream sync PR into `main`, rebase your personal branch:

```bash
scripts/contrib.sh sync-personal

# Then force-push
git push --force-with-lease origin personal
```

This replays all your personal commits (customizations + merged features) on top
of the latest upstream code. If conflicts arise, they'll only be in files where
your changes overlap with upstream changes — resolve and continue the rebase.

### Building the App

Always build from the `personal` branch:

```bash
git checkout personal
# Then follow the standard build instructions
```

### Contributing a Feature to Upstream

If you develop a feature on `personal` that you think upstream would want:

```bash
# 1. Create a clean contrib branch from upstream/main
scripts/contrib.sh new my-feature

# 2. Cherry-pick the relevant commits from personal
git cherry-pick <commit-sha>   # pick specific commits, not merge commits

# 3. Clean up if needed (squash, adjust commit messages for upstream standards)
git rebase -i upstream/main

# 4. Push and open PR to upstream
scripts/contrib.sh pr
```

The key: `contrib/<name>` branches always start from `upstream/main` (clean
upstream code), and you cherry-pick only the commits you want to contribute.
This keeps the PR clean and independent of your personal customizations.

---

## Checking Branch Status

```bash
scripts/contrib.sh status
```

Example output:

```
Branch status (relative to upstream/main):

  main  3 commits behind upstream (sync needed)
  personal  2 commits ahead of main

Contrib branches:
  contrib/fix-typing-lag  1 commits, up to date
  contrib/add-theme  3 commits, 5 behind upstream (rebase needed)
```

---

## Security Review Details

### Security Audit

File: `.github/scripts/security-audit.sh`

Scans the unified diff for added lines matching security-relevant patterns.
Each match includes the file path and a code snippet for quick assessment.

| Category | Severity | What it detects |
|----------|----------|-----------------|
| New URL endpoints | MEDIUM | `https://`, `http://` URLs |
| WebSocket connections | MEDIUM | `wss://`, `ws://` URLs |
| Shell execution | HIGH | `/bin/sh`, `Process()`, `NSTask`, `executableURL` |
| Dynamic code execution | HIGH | `dlopen`, `eval()`, `performSelector` |
| Keychain access | HIGH | `SecItem`, `SecKeychain`, `kSecClass` |
| Hardcoded secrets | HIGH | `api_key`, `secret_key`, `bearer` |
| Entitlement changes | HIGH | `com.apple.security.*`, `com.apple.developer.*` |
| TCC permissions | HIGH | `NSCamera`, `NSMicrophone`, `NSLocation`, etc. |
| Socket changes | MEDIUM | `.sock`, `bind()`, permission modes |
| Permissive permissions | HIGH | `0o666`, `0o777`, `worldReadable` |
| Clipboard access | MEDIUM | `NSPasteboard`, `pbcopy` |
| JavaScript bridge | MEDIUM | `WKScriptMessageHandler`, `messageHandlers` |
| Persistence mechanisms | HIGH | `LaunchAgent`, `LoginItem`, `SMAppService` |
| AppleScript execution | MEDIUM | `NSAppleScript`, `osascript` |
| URL scheme registration | MEDIUM | `CFBundleURLSchemes`, `UTExportedTypeDeclarations` |
| App Transport Security | MEDIUM | `NSAllowsArbitraryLoads` |
| Crypto operations | MEDIUM | `CryptoKit`, `AES`, `SHA256`, `HMAC` |
| Base64 encoding | LOW | `base64Encoded`, `btoa()` |
| Home directory access | LOW | `.ssh`, `.aws`, `.config`, `.env` |
| Temp file operations | LOW | `/tmp/`, `mktemp` |

### Supply Chain Check

File: `.github/scripts/supply-chain-check.sh`

Compares two git refs and flags changes to:

1. **Submodule URLs** (`.gitmodules` changes) — HIGH if URLs changed
2. **Submodule pointers** (SHA changes) — MEDIUM
3. **Package dependencies** (`Package.swift`, `go.mod`, `package.json`) — MEDIUM/HIGH
4. **CI/CD workflows** (`.github/workflows/`, `.github/scripts/`) — MEDIUM/HIGH
5. **Build scripts** (`scripts/`) — MEDIUM, HIGH if new downloads added
6. **Entitlements & Info.plist** — HIGH
7. **Xcode project** (`.xcodeproj/`, `.xcconfig`) — LOW, HIGH if new Run Script phases
8. **Binary files** (`.dylib`, `.framework`, `.app`, etc.) — HIGH
9. **Checksum files** — MEDIUM

### Diff Summary

File: `.github/scripts/diff-summary.sh`

Groups changed files into categories with icons:
- New files, modified files, deleted files, renamed files
- Categories: App Core, Panels & Browser, CLI, Auto-Update, Find/Search,
  Shell Integration, Remote Daemon, Resources & Config, Scripts, CI/CD,
  Tests, Web, Documentation

Also lists which high-priority areas changed (App Core, CLI, Shell Integration,
Remote Daemon, Resources, Scripts) with review guidance.

---

## Disabled Upstream Workflows

The following workflows inherited from upstream are **disabled** on this fork
because they reference upstream-specific resources (paid CI runners, Apple
signing credentials, upstream repos, Sentry/Homebrew accounts):

| Workflow | Why Disabled |
|----------|-------------|
| `nightly.yml` | Pushes releases to `manaflow-ai/cmux`, uses paid runner, uploads to Sentry |
| `release.yml` | Signs/notarizes with upstream Apple credentials, publishes to upstream releases |
| `update-homebrew.yml` | Pushes to `manaflow-ai/homebrew-cmux` |
| `build-ghosttykit.yml` | Publishes to `manaflow-ai/ghostty`, uses paid runner |
| `claude.yml` | Uses upstream's Claude Code OAuth token |
| `test-e2e.yml` | Posts to `manaflow-ai/cmux-dev-artifacts`, uses paid runner |
| `test-depot.yml` | Uses paid runner, downloads from upstream |
| `ci-macos-compat.yml` | Uses paid runner, downloads from upstream |

The **CI** workflow (`ci.yml`) is kept enabled — its ubuntu-based jobs
(`workflow-guard-tests`, `remote-daemon-tests`, `web-typecheck`) run for free.
Its macOS jobs are gated by a fork guard and will skip automatically.

To re-enable any workflow:

```bash
gh workflow enable "<workflow name>" --repo <your-fork>
```

---

## File Reference

| File | Purpose |
|------|---------|
| `.github/workflows/upstream-sync.yml` | Scheduled + manual upstream sync workflow |
| `.github/workflows/review-upstream.yml` | Script-based review + artifact upload for sync PRs |
| `.github/workflows/opencode-review.yml` | Automatic AI review via OpenCode Zen (upstream-sync PRs) |
| `.github/workflows/opencode-on-demand.yml` | On-demand AI review via `/opencode-review` comment |
| `.github/scripts/security-audit.sh` | Pattern-based security scanner |
| `.github/scripts/supply-chain-check.sh` | Dependency and supply chain checker |
| `.github/scripts/diff-summary.sh` | Categorized diff summary generator |
| `scripts/contrib.sh` | Contribution workflow helper (CLI) |
| `docs/fork-workflow.md` | This document |

---

## Troubleshooting

### Sync PR has merge conflicts

Your fork's `main` has diverged from upstream. This means someone committed
directly to `main`. See [Handling Divergence](#handling-divergence).

### Review workflow doesn't run on sync PR

The `review-upstream` workflow only triggers on PRs where the head branch
matches `upstream-sync/*`. Verify the branch name in the PR.

### `contrib.sh pr` says "Could not determine fork owner"

Make sure `gh` (GitHub CLI) is authenticated:

```bash
gh auth status
gh auth login  # if not authenticated
```

### Sync workflow says "already up to date" but I know there are changes

The workflow compares `HEAD` of your fork's `main` with `upstream/main`.
If the fetch failed silently, re-run the workflow. You can also check locally:

```bash
git fetch upstream
git rev-list --count main..upstream/main
```

### OpenCode AI review doesn't run after scripts complete

The `opencode-review.yml` workflow triggers on `workflow_run` completion of
"Review Upstream Changes". Check:
- The triggering workflow name matches exactly: `Review Upstream Changes`
- The branch starts with `upstream-sync/`
- The `OPENCODE_API_KEY` secret is set in repo settings

### OpenCode on-demand review doesn't respond to /opencode-review

Verify:
- The comment is on a pull request (not an issue)
- The comment text starts with `/opencode-review` (no leading spaces)
- The `OPENCODE_API_KEY` secret is set

### OpenCode review fails with authentication error

Your Zen API key may be expired or have insufficient balance:
1. Check your balance at [opencode.ai/zen](https://opencode.ai/zen)
2. Regenerate the API key if needed
3. Update the `OPENCODE_API_KEY` secret in GitHub

### I accidentally committed to main

Move the commits to a branch and reset main:

```bash
git checkout main
git branch save-accidental-commits  # save them
git reset --hard upstream/main
git push --force-with-lease origin main
```

Then cherry-pick or rebase those commits onto the appropriate branch
(`personal` or `contrib/<name>`).

### contrib.sh rebase shows conflicts

Resolve conflicts as git instructs, then:

```bash
git rebase --continue
git push --force-with-lease origin contrib/<name>
```

If the conflicts are too complex, you can abort and start fresh:

```bash
git rebase --abort
```
