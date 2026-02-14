#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--dry-run] [--yes] [--dest DIR]

Back up SSH key material from ~/.ssh to ~/ssh-backups/<timestamp> by default.
USAGE
}

DRY_RUN=true
ASSUME_YES=false
DEST_BASE="$HOME/ssh-backups"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --apply) DRY_RUN=false ;;
    --yes|--non-interactive) ASSUME_YES=true ;;
    --dest)
      shift
      DEST_BASE="${1:-}"
      [[ -n "$DEST_BASE" ]] || { echo "Missing value for --dest" >&2; exit 1; }
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

TS=$(date +%Y%m%d-%H%M%S)
DEST_DIR="$DEST_BASE/$TS"
SOURCE_DIR="$HOME/.ssh"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "No ~/.ssh directory found at $SOURCE_DIR"
  exit 0
fi

FILES=()
while IFS= read -r line; do
  FILES+=("$line")
done < <(find "$SOURCE_DIR" -maxdepth 1 -type f \( -name 'id_*' -o -name '*.pub' -o -name 'config' -o -name 'known_hosts*' \) | sort)

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "No matching SSH files found to back up."
  exit 0
fi

echo "Backup destination: $DEST_DIR"
echo "Files to backup:"
printf '  %s\n' "${FILES[@]}"

if [[ "$DRY_RUN" == true ]]; then
  echo "[DRY RUN] No files copied."
  exit 0
fi

if [[ "$ASSUME_YES" != true ]]; then
  read -r -p "Proceed with backup? [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 1; }
fi

mkdir -p "$DEST_DIR"
for f in "${FILES[@]}"; do
  cp -p "$f" "$DEST_DIR/"
done

echo "Backup complete: $DEST_DIR"
