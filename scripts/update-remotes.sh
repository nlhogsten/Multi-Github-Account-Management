#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $(basename "$0") --root PATH --map FILE [--apply] [--yes]

Update git origin remotes to alias-based SSH hostnames using owner->alias mappings.
Runs in dry-run mode by default.
USAGE
}

ROOT=""
MAP_FILE=""
APPLY=false
ASSUME_YES=false

log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

confirm() {
  local prompt="$1"
  if [[ "$ASSUME_YES" == true ]]; then
    return 0
  fi
  read -r -p "$prompt [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

lookup_alias() {
  local owner="$1"
  awk -F'=' -v owner="$owner" '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      key=$1
      gsub(/[[:space:]]/, "", key)
      val=$2
      gsub(/[[:space:]]/, "", val)
      if (key == owner) {
        print val
        exit
      }
    }
  ' "$MAP_FILE"
}

extract_owner_repo() {
  local origin="$1"

  if [[ "$origin" =~ ^git@([^:]+):([^/]+)/(.+)\.git$ ]]; then
    echo "${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
    return 0
  fi
  if [[ "$origin" =~ ^git@([^:]+):([^/]+)/(.+)$ ]]; then
    echo "${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
    return 0
  fi
  if [[ "$origin" =~ ^https://github\.com/([^/]+)/(.+)\.git$ ]]; then
    echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
    return 0
  fi
  if [[ "$origin" =~ ^https://github\.com/([^/]+)/(.+)$ ]]; then
    echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
    return 0
  fi

  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) shift; ROOT="${1:-}" ;;
    --map) shift; MAP_FILE="${1:-}" ;;
    --dry-run) APPLY=false ;;
    --apply) APPLY=true ;;
    --yes|--non-interactive) ASSUME_YES=true ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
  shift
done

[[ -n "$ROOT" ]] || fail "--root is required"
[[ -d "$ROOT" ]] || fail "Root path does not exist: $ROOT"
[[ -n "$MAP_FILE" ]] || fail "--map is required"
[[ -f "$MAP_FILE" ]] || fail "Map file does not exist: $MAP_FILE"

if [[ -z "$(awk '/^[[:space:]]*[^#[:space:]]+[[:space:]]*=[[:space:]]*[^[:space:]]+/{print; exit}' "$MAP_FILE")" ]]; then
  fail "No owner->alias mappings found in $MAP_FILE"
fi

log "Scanning $ROOT for git repositories"
git_dirs=()
while IFS= read -r line; do
  git_dirs+=("$line")
done < <(find "$ROOT" -type d -name .git)
[[ ${#git_dirs[@]} -gt 0 ]] || { warn "No repositories found."; exit 0; }

if [[ "$APPLY" == true ]]; then
  warn "Apply mode will modify git remotes."
  confirm "Proceed with remote updates?" || fail "Cancelled."
fi

for git_dir in "${git_dirs[@]}"; do
  repo_dir=$(dirname "$git_dir")
  origin=$(git -C "$repo_dir" remote get-url origin 2>/dev/null || true)
  if [[ -z "$origin" ]]; then
    warn "Skipping (no origin): $repo_dir"
    continue
  fi

  if ! parsed=$(extract_owner_repo "$origin"); then
    warn "Skipping (unsupported origin format): $repo_dir -> $origin"
    continue
  fi

  owner=${parsed%% *}
  repo=${parsed#* }
  alias=$(lookup_alias "$owner")
  if [[ -z "$alias" ]]; then
    warn "Skipping (owner not in map): $repo_dir -> owner=$owner"
    continue
  fi

  new_url="git@${alias}:${owner}/${repo}.git"
  if [[ "$origin" == "$new_url" ]]; then
    log "No change needed: $repo_dir"
    continue
  fi

  echo
  echo "Repo: $repo_dir"
  echo "  origin: $origin"
  echo "  new:    $new_url"

  if [[ "$APPLY" == true ]]; then
    git -C "$repo_dir" remote set-url origin "$new_url"
    log "Updated origin for $repo_dir"
  else
    echo "  [DRY RUN] git -C '$repo_dir' remote set-url origin '$new_url'"
  fi
done
