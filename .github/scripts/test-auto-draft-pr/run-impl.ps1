# MIRROR of the inline `run:` block in
# `.github/workflows/auto-draft-pr.yaml`. Kept here as a separate file so
# that `_test-auto-draft-pr.yaml` can drive the implementation against a
# mocked `gh` CLI.
#
# IMPORTANT: When the inline script in the reusable workflow changes,
# update the block between `MIRROR-START` and `MIRROR-END` below in the
# same commit. The drift-detection job in `_test-auto-draft-pr.yaml`
# fails the run if the two diverge byte-for-byte.
#
# Inputs (read from process environment, set by the caller):
#   GH_TOKEN, COMMIT_MSG, BRANCH, DEFAULT_BRANCH, ACTOR, REPO

# MIRROR-START: keep in sync with .github/workflows/auto-draft-pr.yaml inline run-block
# Fail-fast: cmdlet errors stop the script, and non-zero exit codes
# from native commands (gh, jq) propagate as terminating errors.
# Equivalent to bash `set -euo pipefail`. Requires PowerShell 7.4+
# (PS 7.3 had this as an experimental feature that needed an explicit
# opt-in), which ships with GitHub-hosted ubuntu-latest runners.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

# ----- Step 1: skip on protected branches --------------------------
# GitLab parity for `rules: if: $CI_COMMIT_REF_PROTECTED == "true"`.
# URL-encode the branch name so refs containing slashes (e.g.
# `feature/x`) round-trip correctly through the GitHub REST API.
$encodedBranch = [uri]::EscapeDataString($env:BRANCH)
$isProtected = gh api "repos/$($env:REPO)/branches/$encodedBranch" `
                  --jq '.protected'

if ($isProtected -eq 'true') {
    Write-Host "Branch '$($env:BRANCH)' is protected, skipping auto-draft-PR."
    exit 0
}

# ----- Step 2: derive PR title from the head commit ----------------
# Use the first line of the commit message. If it starts with
# `Title:` or `Titel:` (case-insensitive), the trimmed remainder
# becomes the PR title. Otherwise fall back to `Draft: <branch>`.
# `-split '\r?\n', 2` handles both LF and CRLF line endings and
# stops splitting after the first separator for efficiency.
$subject = ($env:COMMIT_MSG -split '\r?\n', 2)[0]

if ($subject -match '^(?:title|titel):\s*(.+)$') {
    $title = $Matches[1]
} else {
    $title = "Draft: $($env:BRANCH)"
}

# ----- Step 3: idempotency check -----------------------------------
# Skip if an open PR with the same head/base already exists. This
# makes re-pushes to the same feature branch safe.
$existing = gh pr list `
    --repo  $env:REPO `
    --head  $env:BRANCH `
    --base  $env:DEFAULT_BRANCH `
    --state open `
    --json  number `
    --jq    '.[0].number // empty'

if ($existing) {
    Write-Host "PR #$existing already exists for '$($env:BRANCH)', skipping."
    exit 0
}

# ----- Step 4: create the draft PR ---------------------------------
# The double-backticks `` produce a literal backtick in the
# double-quoted string, so the rendered Markdown wraps the branch
# name in a code span.
$body = "_Auto-drafted on push to ``$($env:BRANCH)``. Replace this body with details before requesting review._"

gh pr create `
    --repo     $env:REPO `
    --draft `
    --base     $env:DEFAULT_BRANCH `
    --head     $env:BRANCH `
    --title    $title `
    --body     $body `
    --assignee $env:ACTOR
# MIRROR-END
