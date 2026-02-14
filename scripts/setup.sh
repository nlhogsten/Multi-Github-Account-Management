#!/usr/bin/env bash
set -euo pipefail

# Interactive, idempotent SSH multi-account setup for macOS.

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --dry-run                 Show planned changes only (default)
  --apply                   Apply changes
  --yes                     Non-interactive confirmations
  --non-interactive         Alias for --yes
  --accounts "a,b"          Comma-separated account labels (default: personal,work)
  --email-<label> EMAIL     Email for account label
  --key-<label> NAME        Key filename for account label (default: id_ed25519_<label>)
  --alias-<label> HOST      SSH host alias (default: github-<label>)
  --backup-dir DIR          Backup root (default: ~/ssh-backups)
  -h, --help                Show help
USAGE
}

DRY_RUN=true
ASSUME_YES=false
ACCOUNTS_CSV="personal,work"
BACKUP_ROOT="$HOME/ssh-backups"

ACCOUNT_LIST=()

sanitize_label() {
  echo "$1" | tr -c '[:alnum:]_' '_'
}

set_kv() {
  local prefix="$1"
  local label="$2"
  local value="$3"
  local key
  key=$(sanitize_label "$label")
  printf -v "${prefix}_${key}" '%s' "$value"
}

get_kv() {
  local prefix="$1"
  local label="$2"
  local key var
  key=$(sanitize_label "$label")
  var="${prefix}_${key}"
  printf '%s' "${!var-}"
}

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

add_key_to_agent() {
  local key_path="$1"
  if [[ "$DRY_RUN" == true ]]; then
    log "[DRY RUN] ssh-add --apple-use-keychain $key_path"
    return 0
  fi

  if ssh-add --apple-use-keychain "$key_path" >/dev/null 2>&1; then
    return 0
  fi

  if ssh-add -K "$key_path" >/dev/null 2>&1; then
    warn "Used legacy ssh-add -K for $key_path"
    return 0
  fi

  fail "Failed adding key to agent/keychain: $key_path"
}

upload_key_via_gh() {
  local pub_key="$1"
  local title="$2"
  if ! command -v gh >/dev/null 2>&1; then
    warn "gh CLI not found; skip upload for $pub_key"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    log "[DRY RUN] gh ssh-key add $pub_key --title '$title'"
    return 0
  fi

  echo
  warn "About to upload key: $pub_key"
  warn "Confirm you are logged into the correct GitHub account."
  if ! confirm "Continue with gh upload?"; then
    warn "Skipping gh upload for $pub_key"
    return 0
  fi

  gh auth status || true
  gh ssh-key add "$pub_key" --title "$title"
}

ensure_ssh_dir() {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
}

backup_existing_ssh_files() {
  local ts dest
  ts=$(date +%Y%m%d-%H%M%S)
  dest="$BACKUP_ROOT/$ts"

  files=()
  while IFS= read -r line; do
    files+=("$line")
  done < <(find "$HOME/.ssh" -maxdepth 1 -type f \( -name 'id_*' -o -name '*.pub' -o -name 'config' -o -name 'known_hosts*' \) 2>/dev/null | sort)

  if [[ ${#files[@]} -eq 0 ]]; then
    log "No existing ~/.ssh files to back up."
    return 0
  fi

  log "Backup destination: $dest"
  printf '  %s\n' "${files[@]}"

  if [[ "$DRY_RUN" == true ]]; then
    log "[DRY RUN] Backup skipped."
    return 0
  fi

  confirm "Create backup now?" || fail "Backup declined; stopping."

  mkdir -p "$dest"
  for f in "${files[@]}"; do
    cp -p "$f" "$dest/"
  done
  log "Backup completed: $dest"
}

generate_key_if_missing() {
  local label="$1"
  local email="$2"
  local key_name="$3"
  local key_path="$HOME/.ssh/$key_name"

  if [[ -f "$key_path" && -f "$key_path.pub" ]]; then
    log "Existing key found for $label: $key_path (reusing)"
    return 0
  fi

  if [[ -z "$email" ]]; then
    if [[ "$ASSUME_YES" == true ]]; then
      fail "Missing required email for account '$label' in non-interactive mode."
    fi
    read -r -p "Email for account '$label': " email
    [[ -n "$email" ]] || fail "Email is required for '$label'"
    set_kv EMAIL "$label" "$email"
  fi

  if [[ "$DRY_RUN" == true ]]; then
    log "[DRY RUN] ssh-keygen -t ed25519 -C '$email' -f '$key_path'"
    return 0
  fi

  log "Generating key for $label at $key_path"
  ssh-keygen -t ed25519 -C "$email" -f "$key_path"
}

write_config_fragment() {
  local config_file="$HOME/.ssh/config"
  local tmp_file
  tmp_file=$(mktemp)

  {
    echo "Host *"
    echo "  AddKeysToAgent yes"
    echo "  UseKeychain yes"
    echo "  IdentitiesOnly yes"
    echo
    local label alias key_name
    for label in "${ACCOUNT_LIST[@]}"; do
      alias=$(get_kv ALIAS "$label")
      key_name=$(get_kv KEY "$label")
      echo "Host $alias"
      echo "  HostName github.com"
      echo "  User git"
      echo "  IdentityFile ~/.ssh/$key_name"
      echo
    done
  } > "$tmp_file"

  if [[ "$DRY_RUN" == true ]]; then
    log "[DRY RUN] Would merge SSH config into $config_file with fragment:"
    sed -n '1,200p' "$tmp_file"
    rm -f "$tmp_file"
    return 0
  fi

  touch "$config_file"
  chmod 600 "$config_file"

  local begin="# BEGIN ssh-multi-account-setup managed block"
  local end="# END ssh-multi-account-setup managed block"
  local current
  current=$(mktemp)
  cp "$config_file" "$current"

  awk -v begin="$begin" -v end="$end" '
    $0 == begin { in_block=1; next }
    $0 == end   { in_block=0; next }
    !in_block { print }
  ' "$current" > "$config_file"

  {
    echo
    echo "$begin"
    cat "$tmp_file"
    echo "$end"
  } >> "$config_file"

  rm -f "$tmp_file" "$current"
  log "Updated $config_file with managed host aliases"
}

validate_aliases() {
  local label alias
  for label in "${ACCOUNT_LIST[@]}"; do
    alias=$(get_kv ALIAS "$label")
    if [[ "$DRY_RUN" == true ]]; then
      log "[DRY RUN] ssh -T git@$alias"
    else
      echo
      log "Testing alias: $alias"
      ssh -T "git@$alias" || true
    fi
  done
}

parse_account_specific_flags() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --email-*)
        local label="${1#--email-}"
        shift
        set_kv EMAIL "$label" "${1:-}"
        ;;
      --key-*)
        local label="${1#--key-}"
        shift
        set_kv KEY "$label" "${1:-}"
        ;;
      --alias-*)
        local label="${1#--alias-}"
        shift
        set_kv ALIAS "$label" "${1:-}"
        ;;
      *)
        fail "Unknown argument: $1"
        ;;
    esac
    [[ $# -gt 0 ]] || fail "Missing value for account-specific argument"
    shift
  done
}

REMAINDER=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --apply) DRY_RUN=false ;;
    --yes|--non-interactive) ASSUME_YES=true ;;
    --accounts)
      shift
      ACCOUNTS_CSV="${1:-}"
      [[ -n "$ACCOUNTS_CSV" ]] || fail "--accounts requires a value"
      ;;
    --backup-dir)
      shift
      BACKUP_ROOT="${1:-}"
      [[ -n "$BACKUP_ROOT" ]] || fail "--backup-dir requires a value"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --email-*|--key-*|--alias-*)
      REMAINDER+=("$1")
      shift
      [[ $# -gt 0 ]] || fail "Missing value for $1"
      REMAINDER+=("$1")
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
  shift
done

parse_account_specific_flags "${REMAINDER[@]}"

IFS=',' read -r -a ACCOUNT_LIST <<< "$ACCOUNTS_CSV"
[[ ${#ACCOUNT_LIST[@]} -gt 0 ]] || fail "No account labels provided"

for i in "${!ACCOUNT_LIST[@]}"; do
  ACCOUNT_LIST[i]="${ACCOUNT_LIST[i]// /}"
done

ensure_ssh_dir
backup_existing_ssh_files

for label in "${ACCOUNT_LIST[@]}"; do
  [[ -n "$label" ]] || continue
  key_name=$(get_kv KEY "$label")
  alias_name=$(get_kv ALIAS "$label")
  email=$(get_kv EMAIL "$label")

  [[ -n "$key_name" ]] || key_name="id_ed25519_$label"
  [[ -n "$alias_name" ]] || alias_name="github-$label"

  set_kv KEY "$label" "$key_name"
  set_kv ALIAS "$label" "$alias_name"

  generate_key_if_missing "$label" "$email" "$key_name"
  add_key_to_agent "$HOME/.ssh/$key_name"

  upload_key_via_gh "$HOME/.ssh/${key_name}.pub" "$(hostname -s) $label $(date +%F)"
done

write_config_fragment
validate_aliases

log "Done."
if [[ "$DRY_RUN" == true ]]; then
  log "Dry run only; no persistent changes were made."
fi
