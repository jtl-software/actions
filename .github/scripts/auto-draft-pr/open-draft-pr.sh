#!/usr/bin/env bash
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${COMMIT_MSG:?COMMIT_MSG is required}"
: "${BRANCH:?BRANCH is required}"
: "${DEFAULT_BRANCH:?DEFAULT_BRANCH is required}"
: "${ACTOR:?ACTOR is required}"
: "${REPO:?REPO is required}"

url_encode() {
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

encoded_branch="$(url_encode "$BRANCH")"
is_protected="$(gh api "repos/${REPO}/branches/${encoded_branch}" --jq '.protected')"

if [[ "$is_protected" == "true" ]]; then
  echo "Branch '${BRANCH}' is protected, skipping auto-draft-PR."
  exit 0
fi

subject="${COMMIT_MSG%%$'\n'*}"
subject="${subject%$'\r'}"

shopt -s nocasematch
if [[ "$subject" =~ ^(title|titel):[[:space:]]*(.+)$ ]]; then
  title="${BASH_REMATCH[2]}"
else
  title="Draft: ${BRANCH}"
fi
shopt -u nocasematch

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
