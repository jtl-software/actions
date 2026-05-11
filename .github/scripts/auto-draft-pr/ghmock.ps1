<#
.SYNOPSIS
    Installs a mock `gh` binary at $HOME/mock-bin and registers it in $GITHUB_PATH.

.DESCRIPTION
    Behaviour is driven by environment variables set per test job:

      MOCK_PROTECTED   - "true" | "false"  (default: "false")
                         Response for `gh api repos/*/branches/*`.
      MOCK_EXISTING_PR - PR number or ""   (default: "")
                         Response for `gh pr list`.

    `gh pr create` always echoes "MOCK_PR_CREATE <args>" so assert scripts
    can inspect the invocation. Any other `gh` call exits 99 to surface
    unexpected paths through the implementation.
#>
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$mockDir = Join-Path $HOME 'mock-bin'
New-Item -ItemType Directory -Path $mockDir -Force | Out-Null

@'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  api)
    if [[ "${2:-}" == repos/*/branches/* ]]; then
      echo "${MOCK_PROTECTED:-false}"
      exit 0
    fi
    ;;
  pr)
    case "${2:-}" in
      list)
        echo "${MOCK_EXISTING_PR:-}"
        exit 0
        ;;
      create)
        echo "MOCK_PR_CREATE $*"
        exit 0
        ;;
    esac
    ;;
esac

echo "UNEXPECTED gh call: $*" >&2
exit 99
'@ | Set-Content -Path (Join-Path $mockDir 'gh') -Encoding utf8 -NoNewline

chmod +x (Join-Path $mockDir 'gh')
"$mockDir" | Out-File -FilePath $env:GITHUB_PATH -Append -Encoding utf8
