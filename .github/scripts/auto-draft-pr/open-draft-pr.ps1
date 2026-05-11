<#
.SYNOPSIS
    Opens a draft pull request when a feature branch is pushed.

.DESCRIPTION
    Called from the `draft-pr` job in `auto-draft-pr.yaml`. Implements the
    GitLab "auto-MR" pattern for repositories that migrated from GitLab to
    GitHub. Skips protected branches and existing PRs before creating.

    Required environment variables (set automatically by GitHub Actions):
      GH_TOKEN        GitHub token with pull-requests:write and issues:write.
      COMMIT_MSG      Full commit message of the head commit.
      BRANCH          Name of the pushed branch.
      DEFAULT_BRANCH  Default branch of the repository (e.g. main).
      ACTOR           GitHub username of the person who triggered the push.
      REPO            Repository in "owner/repo" format.
#>
[CmdletBinding()]
param()

# Fail-fast: cmdlet errors stop the script, and non-zero exit codes
# from native commands (gh, jq) propagate as terminating errors.
# Equivalent to bash `set -euo pipefail`. Requires PowerShell 7.4+
# ($PSNativeCommandUseErrorActionPreference was experimental in 7.3),
# which ships on GitHub-hosted ubuntu-latest runners.
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
