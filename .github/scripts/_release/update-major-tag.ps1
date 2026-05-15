<#
.SYNOPSIS
    Force-moves a rolling major-version tag to match a strict SemVer release tag.

.DESCRIPTION
    Called from the `update-major-tag` job in `_release.yaml` after a release has
    been published. Resolves the commit SHA that the release tag points to (peeling
    annotated tag objects when necessary) and creates or force-updates the
    corresponding rolling major tag (e.g. v1.2.3 -> v1) via the GitHub REST API.

    Required environment variables:
      GH_TOKEN            GitHub token with contents:write permission.
                          Must be set explicitly in the workflow step via
                          env: GH_TOKEN: ${{ github.token }}; the runner
                          does not populate this name automatically.
      GITHUB_REPOSITORY   Repository in "owner/repo" format.
                          Populated automatically by the GitHub Actions runner.

.PARAMETER Tag
    The release tag name (e.g. v1.2.3). Must be strict SemVer (vX.Y.Z).
    Tags that do not match are skipped with a log message. The workflow-level
    `if: !contains(github.ref_name, '-')` guard handles pre-release filtering
    upstream; this check is a safety net for direct calls.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Tag
)

# Fail-fast: cmdlet errors and non-zero exit codes from native commands both
# become terminating errors. Equivalent to bash `set -euo pipefail`.
# Requires PowerShell 7.4+ ($PSNativeCommandUseErrorActionPreference was
# experimental in 7.3), which ships on GitHub-hosted runners.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

# ----- Step 1: validate tag format -----------------------------------------
# Pre-releases (vX.Y.Z-rc.N, etc.) are already filtered at the workflow level
# via the job's `if:` guard. This check acts as a safety net for direct calls.
if ($Tag -notmatch '^v(\d+)\.\d+\.\d+$') {
    Write-Host "Tag '$Tag' does not match strict SemVer (vX.Y.Z); skipping major-tag roll."
    exit 0
}
$major = "v$($Matches[1])"
Write-Host "Rolling $major to $Tag."

# ----- Step 2: resolve target commit SHA ------------------------------------
# Tags created by `gh release create` are annotated tag objects. The ref points
# to the tag object itself, not the commit. Follow the indirection so the major
# tag always points to a commit, not a tag object.
$tagRef = gh api "repos/$env:GITHUB_REPOSITORY/git/refs/tags/$Tag" | ConvertFrom-Json
$sha    = $tagRef.object.sha
if ($tagRef.object.type -eq 'tag') {
    $sha = (gh api "repos/$env:GITHUB_REPOSITORY/git/tags/$sha" | ConvertFrom-Json).object.sha
}
Write-Host "Resolved commit: $sha."

# ----- Step 3: create or force-update the major tag ------------------------
# Check whether the major tag already exists. A 404 ("Not Found") is expected
# on the first release of a new major version (e.g. v2.0.0 when v2 is absent).
# Any other non-zero exit (auth failure, network error, 5xx) is a real failure
# and must not be silently treated as "tag not found".
$PSNativeCommandUseErrorActionPreference = $false
$checkOutput = gh api "repos/$env:GITHUB_REPOSITORY/git/refs/tags/$major" 2>&1
$checkExit   = $LASTEXITCODE
$PSNativeCommandUseErrorActionPreference = $true

if ($checkExit -ne 0 -and "$checkOutput" -notmatch 'Not Found') {
    Write-Error "Unexpected error checking for tag ${major}: $([string]$checkOutput)" -ErrorAction Continue
    exit 1
}
$refExists = ($checkExit -eq 0)

if ($refExists) {
    gh api --method PATCH "repos/$env:GITHUB_REPOSITORY/git/refs/tags/$major" `
        -f sha=$sha -f force=true | Out-Null
    Write-Host "Updated $major -> $sha."
} else {
    gh api --method POST "repos/$env:GITHUB_REPOSITORY/git/refs" `
        -f "ref=refs/tags/$major" -f sha=$sha | Out-Null
    Write-Host "Created $major -> $sha."
}
