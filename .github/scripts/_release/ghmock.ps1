<#
.SYNOPSIS
    Installs a mock `gh` binary at $HOME/gh-mock and registers it in $GITHUB_PATH.

.DESCRIPTION
    Behaviour is driven by environment variables set per test job:

      MOCK_TAG_TYPE        "lightweight" (default) | "annotated"
      MOCK_MAJOR_EXISTS    "false" (default) | "true"
      MOCK_MAJOR_TAG_ERROR Non-empty string => the major-tag existence check fails
                           with this message on stderr (simulates 5xx / auth errors).
                           Takes precedence over MOCK_MAJOR_EXISTS.
      MOCK_TAG_SHA         40-char hex (default: aaaa0000...0000)
      MOCK_COMMIT_SHA      40-char hex returned after peeling (default: bbbb0000...0000)
                           Only relevant when MOCK_TAG_TYPE=annotated.
#>
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$mockDir = Join-Path $HOME 'gh-mock'
New-Item -ItemType Directory -Path $mockDir -Force | Out-Null

@'
#!/usr/bin/env bash
set -euo pipefail

MOCK_TAG_TYPE="${MOCK_TAG_TYPE:-lightweight}"
MOCK_MAJOR_EXISTS="${MOCK_MAJOR_EXISTS:-false}"
MOCK_MAJOR_TAG_ERROR="${MOCK_MAJOR_TAG_ERROR:-}"
MOCK_TAG_SHA="${MOCK_TAG_SHA:-aaaa000000000000000000000000000000000000}"
MOCK_COMMIT_SHA="${MOCK_COMMIT_SHA:-bbbb000000000000000000000000000000000000}"

[[ "${1:-}" == "api" ]] || { echo "MOCK: unexpected gh subcommand: $*" >&2; exit 1; }
shift

METHOD="GET"
ENDPOINT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --method)        METHOD="$2"; shift 2 ;;
    -f|--field)      shift 2 ;;
    -F|--raw-field)  shift 2 ;;
    --)              shift; break ;;
    -*)              shift ;;
    *)               [[ -z "$ENDPOINT" ]] && ENDPOINT="$1"; shift ;;
  esac
done

case "$METHOD" in
  GET)
    case "$ENDPOINT" in
      # Release tag ref: vX.Y.Z (two dots -> full SemVer)
      *git/refs/tags/v*.*.*)
        if [[ "$MOCK_TAG_TYPE" == "annotated" ]]; then
          printf '{"object":{"sha":"%s","type":"tag"}}\n' "$MOCK_TAG_SHA"
        else
          printf '{"object":{"sha":"%s","type":"commit"}}\n' "$MOCK_TAG_SHA"
        fi ;;
      # Annotated tag object lookup (peel step)
      *git/tags/*)
        printf '{"object":{"sha":"%s","type":"commit"}}\n' "$MOCK_COMMIT_SHA" ;;
      # Major tag existence check: vN (no dots)
      *git/refs/tags/v*)
        if [[ -n "$MOCK_MAJOR_TAG_ERROR" ]]; then
          printf '%s\n' "$MOCK_MAJOR_TAG_ERROR" >&2; exit 1
        elif [[ "$MOCK_MAJOR_EXISTS" == "true" ]]; then
          printf '{"ref":"refs/tags/v1","object":{"sha":"%s"}}\n' "$MOCK_TAG_SHA"
        else
          printf '{"message":"Not Found","documentation_url":"https://docs.github.com/rest"}\n' >&2
          exit 1
        fi ;;
      *) echo "MOCK: unhandled GET $ENDPOINT" >&2; exit 1 ;;
    esac ;;
  PATCH)
    echo "MOCK_GH_PATCH: $ENDPOINT" >&2
    printf '{"ref":"%s","object":{"sha":"%s"}}\n' "$ENDPOINT" "$MOCK_TAG_SHA" ;;
  POST)
    echo "MOCK_GH_POST: $ENDPOINT" >&2
    printf '{"ref":"refs/tags/v1","object":{"sha":"%s"}}\n' "$MOCK_TAG_SHA" ;;
  *) echo "MOCK: unhandled method $METHOD $ENDPOINT" >&2; exit 1 ;;
esac
'@ | Set-Content -Path (Join-Path $mockDir 'gh') -Encoding utf8 -NoNewline

chmod +x (Join-Path $mockDir 'gh')
"$mockDir" | Out-File -FilePath $env:GITHUB_PATH -Append -Encoding utf8
