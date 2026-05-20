#!/usr/bin/env bash
# Fake version of the `gh` command used by the test workflow.
# It only answers the API calls that update-major-tag.sh actually
# makes. Any other call stops the script with an error, so that we
# notice right away if the real script starts doing something new
# that the fake does not cover.
set -euo pipefail

# Environment variables that the test workflow sets to control the
# answers of this fake. They let the tests run all the different
# cases in update-major-tag.sh: annotated or lightweight tag, major
# tag already exists or not, simulated API errors, and so on.
MOCK_TAG_TYPE="${MOCK_TAG_TYPE:-lightweight}"
MOCK_MAJOR_EXISTS="${MOCK_MAJOR_EXISTS:-false}"
MOCK_MAJOR_TAG_ERROR="${MOCK_MAJOR_TAG_ERROR:-}"
MOCK_TAG_SHA="${MOCK_TAG_SHA:-aaaa000000000000000000000000000000000000}"
MOCK_COMMIT_SHA="${MOCK_COMMIT_SHA:-bbbb000000000000000000000000000000000000}"

# This fake only knows the `gh api ...` calls. Make sure we got a
# subcommand at all before we look at $1, and then reject anything
# other than `api`. Unknown calls exit with code 99 (a value the real
# `gh` never returns) so the workflow log clearly shows that the
# failure came from this fake script and not from a real `gh` call.
# This matches the convention used by the auto-draft-pr mock.
if [[ $# -eq 0 ]]; then
  echo "MOCK: gh needs 'api' as first argument; nothing was provided" >&2
  exit 99
fi
if [[ "$1" != "api" ]]; then
  echo "MOCK: unexpected gh subcommand: $*" >&2
  exit 99
fi
shift

# Small parser for the few `gh api` options that update-major-tag.sh
# uses. The options -f and -F take a value, so they read the next
# argument as well. We do not look at the actual values, because the
# fake answer only depends on the URL and on the environment
# variables above.
METHOD="GET"
ENDPOINT=""
JQ_FILTER=""
while (( $# )); do
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
        # Request for the full version tag (vX.Y.Z). We look at the
        # --jq filter and return the data in the same form as the
        # real API would. The combined filter is what the real script
        # uses to fetch sha and type in a single call.
        tag_type="commit"
        if [[ "$MOCK_TAG_TYPE" == "annotated" ]]; then
          tag_type="tag"
        fi
        if [[ "$JQ_FILTER" == ".object.sha" ]]; then
          printf '%s\n' "$MOCK_TAG_SHA"
        elif [[ "$JQ_FILTER" == ".object.type" ]]; then
          printf '%s\n' "$tag_type"
        elif [[ "$JQ_FILTER" == '"\(.object.sha) \(.object.type)"' ]]; then
          printf '%s %s\n' "$MOCK_TAG_SHA" "$tag_type"
        else
          printf '{"object":{"sha":"%s","type":"%s"}}\n' "$MOCK_TAG_SHA" "$tag_type"
        fi
        ;;
      *git/tags/*)
        # Second request that follows an annotated tag object down
        # to the commit it points to.
        if [[ "$JQ_FILTER" == ".object.sha" ]]; then
          printf '%s\n' "$MOCK_COMMIT_SHA"
        else
          printf '{"object":{"sha":"%s","type":"commit"}}\n' "$MOCK_COMMIT_SHA"
        fi
        ;;
      *git/refs/tags/v*)
        # Request for the major tag (for example v1). Three cases:
        #   1. simulate a temporary API error,
        #   2. simulate that the tag already exists, which makes the
        #      real script update it,
        #   3. simulate that the tag is missing, which makes the
        #      real script create it.
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
      *) echo "MOCK: unhandled GET $ENDPOINT" >&2; exit 99 ;;
    esac
    ;;
  PATCH)
    # Write the call to stderr so the test workflow can check that
    # it really happened.
    echo "MOCK_GH_PATCH: $ENDPOINT" >&2
    printf '{"ref":"%s","object":{"sha":"%s"}}\n' "$ENDPOINT" "$MOCK_TAG_SHA"
    ;;
  POST)
    # Write the call to stderr so the test workflow can check that
    # it really happened.
    echo "MOCK_GH_POST: $ENDPOINT" >&2
    printf '{"ref":"refs/tags/v1","object":{"sha":"%s"}}\n' "$MOCK_TAG_SHA"
    ;;
  *)
    echo "MOCK: unhandled method $METHOD $ENDPOINT" >&2
    exit 99
    ;;
esac
