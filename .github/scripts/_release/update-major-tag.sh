#!/usr/bin/env bash
# Move the major version tag (for example v1) so that it points to
# the same commit as a full version tag (for example v1.2.3). Tags
# with a suffix such as -rc.1 or -beta.2 are skipped on purpose,
# because the major tag should always point to a stable release.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <tag>" >&2
  exit 1
fi

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

tag="$1"

# Accept only tags in the form vX.Y.Z with no extra suffix. The first
# number in parentheses is the major version. We save it to build the
# name of the major tag, for example v1 or v2.
if [[ ! "$tag" =~ ^v([0-9]+)\.[0-9]+\.[0-9]+$ ]]; then
  echo "Tag '${tag}' does not match strict SemVer (vX.Y.Z); skipping major-tag roll."
  exit 0
fi
major="v${BASH_REMATCH[1]}"
echo "Rolling ${major} to ${tag}."

# A git tag can point to a commit in two ways. A lightweight tag
# points directly at the commit. An annotated tag points at a tag
# object first, which then points at the commit. For annotated tags
# we need a second API call to follow that chain down to the commit.
tag_ref_endpoint="repos/${GITHUB_REPOSITORY}/git/refs/tags/${tag}"
sha="$(gh api "$tag_ref_endpoint" --jq '.object.sha')"
object_type="$(gh api "$tag_ref_endpoint" --jq '.object.type')"
if [[ "$object_type" == "tag" ]]; then
  sha="$(gh api "repos/${GITHUB_REPOSITORY}/git/tags/${sha}" --jq '.object.sha')"
fi

echo "Resolved commit: ${sha}."

# Check whether the major tag already exists. The gh command returns
# an error when the tag is missing (HTTP 404). The script normally
# stops on any error, so we turn that behavior off for one command,
# read both the output and the exit code, and then turn it back on.
set +e
check_output="$(gh api "repos/${GITHUB_REPOSITORY}/git/refs/tags/${major}" 2>&1)"
check_exit=$?
set -e

# A 404 means "the tag does not exist yet" and is the expected case
# for a new major version. Any other error (for example a network
# problem or a missing token) is a real failure and must stop the
# script.
if [[ $check_exit -ne 0 && ! "$check_output" =~ Not\ Found ]]; then
  echo "Unexpected error checking for tag ${major}: ${check_output}" >&2
  exit 1
fi

if [[ $check_exit -eq 0 ]]; then
  # Tag exists. Update it so that it points to the new commit.
  gh api --method PATCH "repos/${GITHUB_REPOSITORY}/git/refs/tags/${major}" \
    -f sha="$sha" -f force=true > /dev/null
  echo "Updated ${major} -> ${sha}."
else
  # Tag does not exist yet. Create it. This happens on the first
  # release of a new major version.
  gh api --method POST "repos/${GITHUB_REPOSITORY}/git/refs" \
    -f "ref=refs/tags/${major}" -f sha="$sha" > /dev/null
  echo "Created ${major} -> ${sha}."
fi
