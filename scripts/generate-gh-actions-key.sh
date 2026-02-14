#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--repo owner/name] [--name keyname] [--email email] [--apply]

Generate a deploy/CI SSH key pair for GitHub Actions usage.
Dry-run by default.
USAGE
}

REPO=""
NAME="id_ed25519_ci"
EMAIL="ci@local"
APPLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) shift; REPO="${1:-}" ;;
    --name) shift; NAME="${1:-}" ;;
    --email) shift; EMAIL="${1:-}" ;;
    --dry-run) APPLY=false ;;
    --apply) APPLY=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

KEY_PATH="$HOME/.ssh/$NAME"

if [[ -f "$KEY_PATH" || -f "$KEY_PATH.pub" ]]; then
  echo "Key already exists: $KEY_PATH" >&2
  exit 1
fi

if [[ "$APPLY" != true ]]; then
  echo "[DRY RUN] ssh-keygen -t ed25519 -C '$EMAIL' -f '$KEY_PATH' -N ''"
  exit 0
fi

ssh-keygen -t ed25519 -C "$EMAIL" -f "$KEY_PATH" -N ""

echo ""
echo "Created CI key pair:"
echo "  Private: $KEY_PATH"
echo "  Public:  $KEY_PATH.pub"
echo ""
echo "Next steps (manual, safe):"
echo "1) Add public key as a Deploy Key (read/write as needed) in the target repo."
echo "2) Add private key to GitHub Actions secret, for example SSH_PRIVATE_KEY."
if [[ -n "$REPO" ]]; then
  echo "   Repo: $REPO"
fi
echo "3) Do not upload this key to personal/work account SSH keys unless explicitly intended."
