#!/usr/bin/env bash
# Roll the rolling major-version tag (e.g. v1) to point at the same commit as a
# strict SemVer tag (e.g. v1.2.3). Pre-release tags are intentionally ignored.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <tag>" >&2
  exit 1
fi

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

tag="$1"

# Match strict SemVer only (vX.Y.Z, no pre-release suffix). Capture the major
# component so we can derive the rolling tag name from it.
if [[ ! "$tag" =~ ^v([0-9]+)\.[0-9]+\.[0-9]+$ ]]; then
  echo "Tag '${tag}' does not match strict SemVer (vX.Y.Z); skipping major-tag roll."
  exit 0
fi
major="v${BASH_REMATCH[1]}"
echo "Rolling ${major} to ${tag}."

# A git tag ref can point either directly at a commit (lightweight tag) or at
# a tag object (annotated tag). For annotated tags we need a second hop to peel
# the tag object down to its target commit SHA.
tag_ref_endpoint="repos/${GITHUB_REPOSITORY}/git/refs/tags/${tag}"
sha="$(gh api "$tag_ref_endpoint" --jq '.object.sha')"
object_type="$(gh api "$tag_ref_endpoint" --jq '.object.type')"
if [[ "$object_type" == "tag" ]]; then
  sha="$(gh api "repos/${GITHUB_REPOSITORY}/git/tags/${sha}" --jq '.object.sha')"
fi

echo "Resolved commit: ${sha}."

# Probe whether the major tag already exists. `gh api` exits non-zero on 404,
# so we temporarily disable `errexit` to capture both the output and the status
# without aborting the script on the expected "not found" case.
set +e
check_output="$(gh api "repos/${GITHUB_REPOSITORY}/git/refs/tags/${major}" 2>&1)"
check_exit=$?
set -e

# Any error other than 404 is a real failure (auth, network, ...) and must surface.
if [[ $check_exit -ne 0 && ! "$check_output" =~ Not\ Found ]]; then
  echo "Unexpected error checking for tag ${major}: ${check_output}" >&2
  exit 1
fi

if [[ $check_exit -eq 0 ]]; then
  # Tag exists: force-update it to the new commit.
  gh api --method PATCH "repos/${GITHUB_REPOSITORY}/git/refs/tags/${major}" \
    -f sha="$sha" -f force=true > /dev/null
  echo "Updated ${major} -> ${sha}."
else
  # Tag does not exist yet: create it (first release of this major version).
  gh api --method POST "repos/${GITHUB_REPOSITORY}/git/refs" \
    -f "ref=refs/tags/${major}" -f sha="$sha" > /dev/null
  echo "Created ${major} -> ${sha}."
fi
