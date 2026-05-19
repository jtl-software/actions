#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <tag>" >&2
  exit 1
fi

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

tag="$1"

if [[ ! "$tag" =~ ^v([0-9]+)\.[0-9]+\.[0-9]+$ ]]; then
  echo "Tag '${tag}' does not match strict SemVer (vX.Y.Z); skipping major-tag roll."
  exit 0
fi
major="v${BASH_REMATCH[1]}"
echo "Rolling ${major} to ${tag}."

tag_ref_endpoint="repos/${GITHUB_REPOSITORY}/git/refs/tags/${tag}"
sha="$(gh api "$tag_ref_endpoint" --jq '.object.sha')"
object_type="$(gh api "$tag_ref_endpoint" --jq '.object.type')"
if [[ "$object_type" == "tag" ]]; then
  sha="$(gh api "repos/${GITHUB_REPOSITORY}/git/tags/${sha}" --jq '.object.sha')"
fi

echo "Resolved commit: ${sha}."

set +e
check_output="$(gh api "repos/${GITHUB_REPOSITORY}/git/refs/tags/${major}" 2>&1)"
check_exit=$?
set -e

if [[ $check_exit -ne 0 && ! "$check_output" =~ Not\ Found ]]; then
  echo "Unexpected error checking for tag ${major}: ${check_output}" >&2
  exit 1
fi

if [[ $check_exit -eq 0 ]]; then
  gh api --method PATCH "repos/${GITHUB_REPOSITORY}/git/refs/tags/${major}" \
    -f sha="$sha" -f force=true > /dev/null
  echo "Updated ${major} -> ${sha}."
else
  gh api --method POST "repos/${GITHUB_REPOSITORY}/git/refs" \
    -f "ref=refs/tags/${major}" -f sha="$sha" > /dev/null
  echo "Created ${major} -> ${sha}."
fi
