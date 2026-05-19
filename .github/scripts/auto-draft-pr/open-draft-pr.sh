#!/usr/bin/env bash
# Open a draft PR for the pushed branch (GitLab auto-MR parity).
# Idempotent: re-runs on the same branch are a no-op if an open PR already exists.
set -euo pipefail

# Required inputs are passed via env from the calling workflow.
# The `:` builtin with `${VAR:?msg}` aborts with a clear error if any are unset or empty.
: "${GH_TOKEN:?GH_TOKEN is required}"
: "${COMMIT_MSG:?COMMIT_MSG is required}"
: "${BRANCH:?BRANCH is required}"
: "${DEFAULT_BRANCH:?DEFAULT_BRANCH is required}"
: "${ACTOR:?ACTOR is required}"
: "${REPO:?REPO is required}"

# Branch names may contain slashes and other characters that need percent-encoding
# before being used as a path segment in the GitHub REST API.
url_encode() {
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

# Skip protected branches (GitLab parity for the CI_COMMIT_REF_PROTECTED rule).
encoded_branch="$(url_encode "$BRANCH")"
is_protected="$(gh api "repos/${REPO}/branches/${encoded_branch}" --jq '.protected')"

if [[ "$is_protected" == "true" ]]; then
  echo "Branch '${BRANCH}' is protected, skipping auto-draft-PR."
  exit 0
fi

# Extract the first line of the commit message and strip a trailing CR (Windows line endings).
subject="${COMMIT_MSG%%$'\n'*}"
subject="${subject%$'\r'}"

# If the subject starts with `title:` or `titel:` (case-insensitive), use the remainder
# as the PR title; otherwise fall back to a generic "Draft: <branch>" title.
shopt -s nocasematch
if [[ "$subject" =~ ^(title|titel):[[:space:]]*(.+)$ ]]; then
  title="${BASH_REMATCH[2]}"
else
  title="Draft: ${BRANCH}"
fi
shopt -u nocasematch

# Idempotency check: bail out if an open PR for this head branch already exists.
# `--jq '.[0].number // empty'` returns the first PR's number or an empty string.
existing="$(gh pr list \
  --repo "$REPO" \
  --head "$BRANCH" \
  --base "$DEFAULT_BRANCH" \
  --state open \
  --json number \
  --jq '.[0].number // empty')"

if [[ -n "$existing" ]]; then
  echo "PR #${existing} already exists for '${BRANCH}', skipping."
  exit 0
fi

body="_Auto-drafted on push to \`${BRANCH}\`. Replace this body with details before requesting review._"

gh pr create \
  --repo "$REPO" \
  --draft \
  --base "$DEFAULT_BRANCH" \
  --head "$BRANCH" \
  --title "$title" \
  --body "$body" \
  --assignee "$ACTOR"
