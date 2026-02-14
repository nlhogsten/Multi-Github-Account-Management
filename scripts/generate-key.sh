#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $(basename "$0") --email EMAIL --name NAME [options]

Options:
  --dir DIR         Key directory (default: ~/.ssh)
  --passphrase STR  Passphrase for key (default: prompt by ssh-keygen)
  --dry-run         Print actions only
  --apply           Actually create key
USAGE
}

EMAIL=""
NAME=""
DIR="$HOME/.ssh"
PASSPHRASE=""
DRY_RUN=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --email) shift; EMAIL="${1:-}" ;;
    --name) shift; NAME="${1:-}" ;;
    --dir) shift; DIR="${1:-}" ;;
    --passphrase) shift; PASSPHRASE="${1:-}" ;;
    --dry-run) DRY_RUN=true ;;
    --apply) DRY_RUN=false ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

[[ -n "$EMAIL" ]] || { echo "--email is required" >&2; exit 1; }
[[ -n "$NAME" ]] || { echo "--name is required" >&2; exit 1; }

mkdir -p "$DIR"
chmod 700 "$DIR"
KEY_PATH="$DIR/$NAME"

if [[ -f "$KEY_PATH" || -f "$KEY_PATH.pub" ]]; then
  echo "Key already exists: $KEY_PATH"
  exit 1
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "[DRY RUN] ssh-keygen -t ed25519 -C '$EMAIL' -f '$KEY_PATH'"
  exit 0
fi

if [[ -n "$PASSPHRASE" ]]; then
  ssh-keygen -t ed25519 -C "$EMAIL" -f "$KEY_PATH" -N "$PASSPHRASE"
else
  ssh-keygen -t ed25519 -C "$EMAIL" -f "$KEY_PATH"
fi

echo "Generated key: $KEY_PATH"
echo "Public key: $KEY_PATH.pub"
