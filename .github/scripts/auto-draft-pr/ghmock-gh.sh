#!/usr/bin/env bash
# `gh` CLI stand-in for the _test-auto-draft-pr integration workflow.
# Only the calls open-draft-pr.sh actually makes are implemented; anything else
# exits 99 so an unexpected call surfaces immediately in CI logs.
set -euo pipefail

# Env knobs flipped by the test workflow:
#   MOCK_PROTECTED     -> what `gh api repos/.../branches/<name>` returns (true|false)
#   MOCK_EXISTING_PR   -> what `gh pr list` returns (empty = no existing PR)
case "${1:-}" in
  api)
    # The production script only queries the branches endpoint via `gh api`.
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
        # Echo the full argv so the test can assert on title/body/assignee/...
        echo "MOCK_PR_CREATE $*"
        exit 0
        ;;
    esac
    ;;
esac

# Exit 99 (not 1) makes accidental real calls easy to distinguish from the
# normal "expected gh failure" exit codes the script under test handles.
echo "UNEXPECTED gh call: $*" >&2
exit 99
