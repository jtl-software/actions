#!/usr/bin/env bash
# Install a `gh` mock for the _test-auto-draft-pr integration workflow.
# The mock is dropped into a directory that we then prepend to $GITHUB_PATH
# so subsequent steps in the same job pick it up instead of the real CLI.
set -euo pipefail

mock_dir="$HOME/mock-bin"
mkdir -p "$mock_dir"

# `BASH_SOURCE[0]` is this script's path; resolving its directory lets us locate
# the sibling `ghmock-gh.sh` regardless of the caller's working directory.
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Stage the mock via a temp file and then atomically rename it into place so
# a concurrent reader never sees a half-written executable.
tmp_gh="$(mktemp "${mock_dir}/gh.XXXXXX")"
cp "${script_dir}/ghmock-gh.sh" "${tmp_gh}"
mv "${tmp_gh}" "${mock_dir}/gh"

chmod +x "$mock_dir/gh"

# Appending to $GITHUB_PATH makes the directory available on PATH for all
# subsequent steps in the same job (GitHub Actions reads this file after each step).
echo "$mock_dir" >> "$GITHUB_PATH"
