#!/usr/bin/env bash
set -euo pipefail

mock_dir="$HOME/gh-mock"
mkdir -p "$mock_dir"

cat > "$mock_dir/gh" <<'MOCK'
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
JQ_FILTER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --method)        METHOD="$2"; shift 2 ;;
    -f|--field)      shift 2 ;;
    -F|--raw-field)  shift 2 ;;
    --jq)            JQ_FILTER="$2"; shift 2 ;;
    --)              shift; break ;;
    -*)              shift ;;
    *)               [[ -z "$ENDPOINT" ]] && ENDPOINT="$1"; shift ;;
  esac
done

case "$METHOD" in
  GET)
    case "$ENDPOINT" in
      *git/refs/tags/v*.*.*)
        tag_type="commit"
        if [[ "$MOCK_TAG_TYPE" == "annotated" ]]; then
          tag_type="tag"
        fi
        if [[ "$JQ_FILTER" == ".object.sha" ]]; then
          printf '%s\n' "$MOCK_TAG_SHA"
        elif [[ "$JQ_FILTER" == ".object.type" ]]; then
          printf '%s\n' "$tag_type"
        else
          printf '{"object":{"sha":"%s","type":"%s"}}\n' "$MOCK_TAG_SHA" "$tag_type"
        fi
        ;;
      *git/tags/*)
        if [[ "$JQ_FILTER" == ".object.sha" ]]; then
          printf '%s\n' "$MOCK_COMMIT_SHA"
        else
          printf '{"object":{"sha":"%s","type":"commit"}}\n' "$MOCK_COMMIT_SHA"
        fi
        ;;
      *git/refs/tags/v*)
        if [[ -n "$MOCK_MAJOR_TAG_ERROR" ]]; then
          printf '%s\n' "$MOCK_MAJOR_TAG_ERROR" >&2
          exit 1
        elif [[ "$MOCK_MAJOR_EXISTS" == "true" ]]; then
          printf '{"ref":"refs/tags/v1","object":{"sha":"%s"}}\n' "$MOCK_TAG_SHA"
        else
          printf '{"message":"Not Found","documentation_url":"https://docs.github.com/rest"}\n' >&2
          exit 1
        fi
        ;;
      *) echo "MOCK: unhandled GET $ENDPOINT" >&2; exit 1 ;;
    esac
    ;;
  PATCH)
    echo "MOCK_GH_PATCH: $ENDPOINT" >&2
    printf '{"ref":"%s","object":{"sha":"%s"}}\n' "$ENDPOINT" "$MOCK_TAG_SHA"
    ;;
  POST)
    echo "MOCK_GH_POST: $ENDPOINT" >&2
    printf '{"ref":"refs/tags/v1","object":{"sha":"%s"}}\n' "$MOCK_TAG_SHA"
    ;;
  *)
    echo "MOCK: unhandled method $METHOD $ENDPOINT" >&2
    exit 1
    ;;
esac
MOCK

chmod +x "$mock_dir/gh"
echo "$mock_dir" >> "$GITHUB_PATH"
