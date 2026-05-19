#!/usr/bin/env bash
set -euo pipefail

mock_dir="$HOME/mock-bin"
mkdir -p "$mock_dir"

cat > "$mock_dir/gh" <<'MOCK'
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
MOCK

chmod +x "$mock_dir/gh"
echo "$mock_dir" >> "$GITHUB_PATH"
