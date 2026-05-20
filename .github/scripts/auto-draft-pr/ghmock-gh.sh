#!/usr/bin/env bash
# Fake version of the `gh` command used by the test workflow.
# It only answers the calls that open-draft-pr.sh actually makes.
# Any other call exits with code 99, so that an unexpected call shows
# up clearly in the workflow log.
set -euo pipefail

# This fake does not parse the command line flags of `gh` (such as
# `--jq` or `--json`). It just returns one fixed value per command.
# That means each environment variable below must already hold the
# value that the real `gh` would print AFTER the script's jq filter
# is applied, not the raw API response. If the real script's jq
# filter changes, the test setup must be updated to match.
#
# Environment variables that the test workflow sets to control the
# answers of this fake:
#   MOCK_PROTECTED     value returned by
#                      `gh api repos/.../branches/<name> --jq '.protected'`
#                      (the string "true" or "false")
#   MOCK_EXISTING_PR   value returned by
#                      `gh pr list ... --json number --jq '.[0].number // empty'`
#                      (an empty value means no pull request is open
#                      for the branch)

# Make sure we got a subcommand at all before we look at $1. Without
# this guard the script would crash on `$1` because of `set -u`.
if [[ $# -eq 0 ]]; then
  echo "MOCK: gh needs either 'api' or 'pr' as first argument; nothing was provided" >&2
  exit 99
fi

case "$1" in
  api)
    # The real script only calls the branches API through `gh api`.
    if [[ "${2:-}" == repos/*/branches/* ]]; then
      echo "${MOCK_PROTECTED:-false}"
      exit 0
    fi
    ;;
  pr)
    case "${2:-}" in
      list)
        echo "${MOCK_EXISTING_PR:-}"
        exit 0
        ;;
      create)
        # Print the full command line so the test workflow can check
        # the title, body, assignee and the other options.
        echo "MOCK_PR_CREATE $*"
        exit 0
        ;;
    esac
    ;;
esac

# Use exit code 99 here. The real script runs with `set -euo pipefail`
# and expects every `gh` call to succeed, so any non-zero exit code
# would stop the script. We pick 99 (a value that real `gh` never
# returns on its own) so the workflow log clearly shows that the
# failure came from this fake script and not from a real `gh` call.
echo "UNEXPECTED gh call: $*" >&2
exit 99
