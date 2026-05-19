#!/usr/bin/env bash
# `gh` CLI stand-in for the _test-release integration workflow.
# Only the `gh api` calls that update-major-tag.sh actually makes are implemented;
# anything else is a hard error so an untested code path can never go unnoticed.
set -euo pipefail

# Knobs the test workflow flips via env vars to exercise the different branches
# in update-major-tag.sh (annotated vs lightweight tag, major tag exists or not,
# transient API errors, ...).
MOCK_TAG_TYPE="${MOCK_TAG_TYPE:-lightweight}"
MOCK_MAJOR_EXISTS="${MOCK_MAJOR_EXISTS:-false}"
MOCK_MAJOR_TAG_ERROR="${MOCK_MAJOR_TAG_ERROR:-}"
MOCK_TAG_SHA="${MOCK_TAG_SHA:-aaaa000000000000000000000000000000000000}"
MOCK_COMMIT_SHA="${MOCK_COMMIT_SHA:-bbbb000000000000000000000000000000000000}"

# We only ever expect `gh api ...`; bail loudly on anything else.
[[ "${1:-}" == "api" ]] || { echo "MOCK: unexpected gh subcommand: $*" >&2; exit 1; }
shift

# Minimal argument parser mirroring the subset of `gh api` flags used in production.
# `-f` / `-F` carry a value; we discard request fields because the mock answer is
# driven entirely by the endpoint plus the env knobs above.
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
        # Lookup of the SemVer tag ref. Honor the requested --jq filter so the
        # caller sees the same shape the real API would return.
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
        # Second hop used to peel an annotated tag object down to its commit.
        if [[ "$JQ_FILTER" == ".object.sha" ]]; then
          printf '%s\n' "$MOCK_COMMIT_SHA"
        else
          printf '{"object":{"sha":"%s","type":"commit"}}\n' "$MOCK_COMMIT_SHA"
        fi
        ;;
      *git/refs/tags/v*)
        # Lookup of the rolling major tag (e.g. v1). Three branches:
        #   1. simulate a transient API error,
        #   2. simulate the tag already existing (triggers the PATCH path),
        #   3. simulate a 404 (triggers the POST/create path).
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
    # Log the call to stderr so the test workflow can assert on it.
    echo "MOCK_GH_PATCH: $ENDPOINT" >&2
    printf '{"ref":"%s","object":{"sha":"%s"}}\n' "$ENDPOINT" "$MOCK_TAG_SHA"
    ;;
  POST)
    # Log the call to stderr so the test workflow can assert on it.
    echo "MOCK_GH_POST: $ENDPOINT" >&2
    printf '{"ref":"refs/tags/v1","object":{"sha":"%s"}}\n' "$MOCK_TAG_SHA"
    ;;
  *)
    echo "MOCK: unhandled method $METHOD $ENDPOINT" >&2
    exit 1
    ;;
esac
