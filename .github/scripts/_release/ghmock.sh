#!/usr/bin/env bash
# Install a fake `gh` command for the test workflow. The fake script
# is placed in its own folder. The folder is then added to the PATH
# variable for all later steps of the same job, so that any call to
# `gh` runs the fake script instead of the real one.
set -euo pipefail

mock_dir="$HOME/gh-mock"
mkdir -p "$mock_dir"

# Find the folder of this script so we can locate ghmock-gh.sh that
# lives next to it. We resolve it to an absolute path so the value
# stays correct even if anything later changes the working directory.
this_script="${BASH_SOURCE[0]}"
script_relativedir="$(dirname -- "$this_script")"
script_absolutedir="$(cd -- "$script_relativedir" && pwd)"

# Copy the fake script to a temporary file first and then rename it
# to its final name in a single step. This avoids the case where
# another process reads the file while it is only half written.
tmp_gh="$(mktemp "${mock_dir}/gh.XXXXXX")"
cp "${script_absolutedir}/ghmock-gh.sh" "${tmp_gh}"
mv "${tmp_gh}" "${mock_dir}/gh"

chmod +x "$mock_dir/gh"

# Writing the folder name into $GITHUB_PATH adds the folder to the
# PATH variable for all later steps of the same job. GitHub Actions
# reads this file after every step and updates PATH from it.
echo "$mock_dir" >> "$GITHUB_PATH"
