#!/usr/bin/env bash
set -euo pipefail

mock_dir="$HOME/gh-mock"
mkdir -p "$mock_dir"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
tmp_gh="$(mktemp "${mock_dir}/gh.XXXXXX")"
cp "${script_dir}/ghmock-gh.sh" "${tmp_gh}"
mv "${tmp_gh}" "${mock_dir}/gh"

chmod +x "$mock_dir/gh"
echo "$mock_dir" >> "$GITHUB_PATH"
