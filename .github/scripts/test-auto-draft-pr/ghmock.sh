#!/usr/bin/env bash
#
# Builds a mock `gh` CLI in $HOME/mock-bin and appends that directory to
# $GITHUB_PATH. The mock reads its per-test-case configuration from
# environment variables at call time:
#
#   MOCK_PROTECTED   - "true" | "false"   (default: "false")
#                      Response for `gh api repos/*/branches/*`.
#   MOCK_EXISTING_PR - PR number or ""    (default: "")
#                      Response for `gh pr list`.
#
# `gh pr create` always echoes "MOCK_PR_CREATE <args>" so assert scripts
# can inspect the invocation. Any other `gh` call exits 99 to surface
# unexpected paths through the implementation.

set -euo pipefail

MOCK_DIR="$HOME/mock-bin"
mkdir -p "$MOCK_DIR"

cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  api)
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
        echo "MOCK_PR_CREATE $*"
        exit 0
        ;;
    esac
    ;;
esac

echo "UNEXPECTED gh call: $*" >&2
exit 99
MOCK_EOF

chmod +x "$MOCK_DIR/gh"

echo "$MOCK_DIR" >> "$GITHUB_PATH"
