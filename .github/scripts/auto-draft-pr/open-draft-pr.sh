#!/usr/bin/env bash
# Open a draft pull request for the branch that was just pushed.
# Safe to run more than once. If an open pull request already exists
# for the branch, the script does nothing.
set -euo pipefail

# All inputs come from environment variables set by the workflow that
# runs this script. If any of them is missing or empty, stop the
# script with a clear error message that names the missing variable.
if [[ ! -v GH_TOKEN ]] || [[ -z "$GH_TOKEN" ]]; then
  echo "GH_TOKEN is required" >&2
  exit 1
fi
if [[ ! -v COMMIT_MSG ]] || [[ -z "$COMMIT_MSG" ]]; then
  echo "COMMIT_MSG is required" >&2
  exit 1
fi
if [[ ! -v BRANCH ]] || [[ -z "$BRANCH" ]]; then
  echo "BRANCH is required" >&2
  exit 1
fi
if [[ ! -v DEFAULT_BRANCH ]] || [[ -z "$DEFAULT_BRANCH" ]]; then
  echo "DEFAULT_BRANCH is required" >&2
  exit 1
fi
if [[ ! -v ACTOR ]] || [[ -z "$ACTOR" ]]; then
  echo "ACTOR is required" >&2
  exit 1
fi
if [[ ! -v REPO ]] || [[ -z "$REPO" ]]; then
  echo "REPO is required" >&2
  exit 1
fi

# Branch names can contain slashes and other characters that are not
# safe inside a URL. The url_encode helper rewrites them into the
# percent-escape form (%XX) so the branch name can be used as part of
# an API path. We do this in pure bash to keep the script
# self-contained (no python3, no jq, no curl dependency).
#
# How the function works:
#
#   1. It walks the input string one byte at a time. Bash strings are
#      byte-based, not character-based, so `${string:i:1}` reads one
#      byte. UTF-8 multi-byte characters get encoded as several %XX
#      escapes (one per byte), which is exactly what RFC 3986 asks
#      for.
#
#   2. The "unreserved" character set from RFC 3986 (letters, digits,
#      and the four punctuation marks `.`, `~`, `_`, `-`) is kept as
#      is. The `case` statement uses the bracket expression
#      `[a-zA-Z0-9.~_-]` for this. Everything else falls into the
#      catch-all `*)` branch and gets percent-encoded.
#
#   3. The percent-encoding itself uses a small bash printf trick:
#      when an argument to bash's built-in `printf` starts with a
#      single quote, printf interprets the next character as a
#      numeric value (its ASCII or byte value). So `printf '%d' "'A"`
#      prints 65. We use `%02X` instead of `%d` to get two-digit
#      uppercase hex, and we prefix the result with a literal `%`
#      using the format directive `%%`. So the format string is
#      `'%%%02X'` which expands to `%XX` for one input byte.
#
# Example: for input "feature/foo bar" (15 bytes), the loop produces:
#   f e a t u r e %2F f o o %20 b a r
# joined into the string "feature%2Ffoo%20bar".
url_encode() {
  local string="$1"
  local encoded=""
  local i char
  for (( i=0; i<${#string}; i++ )); do
    char="${string:i:1}"
    case "$char" in
      [a-zA-Z0-9.~_-]) encoded+="$char" ;;
      *)               encoded+=$(printf '%%%02X' "'$char") ;;
    esac
  done
  printf '%s' "$encoded"
}

# Stop early if the branch is protected. Protected branches usually
# get their pull requests in a different way, so we do not want to
# open an automatic draft for them.
encoded_branch="$(url_encode "$BRANCH")"
is_protected="$(gh api "repos/${REPO}/branches/${encoded_branch}" --jq '.protected')"

if [[ "$is_protected" == "true" ]]; then
  echo "Branch '${BRANCH}' is protected, skipping auto-draft-PR."
  exit 0
fi

# Take the first line of the commit message as the subject and remove
# a trailing carriage return that can appear on Windows line endings.
subject="${COMMIT_MSG%%$'\n'*}"
subject="${subject%$'\r'}"

# If the subject starts with "title:" or "titel:" in any combination
# of upper and lower case, use the text after the colon as the title
# of the pull request. Otherwise use "Draft: <branch>" as a simple
# default title.
shopt -s nocasematch
if [[ "$subject" =~ ^(title|titel):[[:space:]]*(.+)$ ]]; then
  title="${BASH_REMATCH[2]}"
else
  title="Draft: ${BRANCH}"
fi
shopt -u nocasematch

# Check whether an open pull request already exists for this branch.
# The --jq filter returns the number of the first matching pull
# request, or an empty string if there is none. If we find one, the
# script ends here and does not create a new pull request.
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
