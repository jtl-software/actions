#!/usr/bin/env bash
# Install a fake `gh` command for the test workflow. The fake script
# is placed in its own folder. The folder is then added to the PATH
# variable for all later steps of the same job, so that any call to
# `gh` runs the fake script instead of the real one.
set -euo pipefail

mock_dir="$HOME/mock-bin"
mkdir -p "$mock_dir"

# BASH_SOURCE[0] holds the path to this script. We take its folder so
# we can find the helper file ghmock-gh.sh that lives next to it.
# This works no matter from which folder the script is started.
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Copy the fake script to a temporary file first and then rename it
# to its final name in a single step. This avoids the case where
# another process reads the file while it is only half written.
tmp_gh="$(mktemp "${mock_dir}/gh.XXXXXX")"
cp "${script_dir}/ghmock-gh.sh" "${tmp_gh}"
mv "${tmp_gh}" "${mock_dir}/gh"

chmod +x "$mock_dir/gh"

# Writing the folder name into $GITHUB_PATH adds the folder to the
# PATH variable for all later steps of the same job. GitHub Actions
# reads this file after every step and updates PATH from it.
echo "$mock_dir" >> "$GITHUB_PATH"
