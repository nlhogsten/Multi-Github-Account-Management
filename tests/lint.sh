#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck not found; skipping shell lint." >&2
  exit 0
fi

scripts=()
while IFS= read -r line; do
  scripts+=("$line")
done < <(find "$ROOT_DIR/scripts" "$ROOT_DIR/tests" -type f -name '*.sh' | sort)

if [[ ${#scripts[@]} -eq 0 ]]; then
  echo "No shell scripts found."
  exit 0
fi

shellcheck "${scripts[@]}"
echo "Lint passed."
