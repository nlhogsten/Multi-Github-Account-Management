# SSH Multi-Account Setup (macOS + GitHub)

Safe, script-first tooling to manage multiple GitHub accounts on one machine with separate SSH keys, host aliases, and dry-run defaults.

## Features

- Audits and backs up existing `~/.ssh` state before changes.
- Generates separate Ed25519 keys per account.
- Adds keys to `ssh-agent` and macOS keychain.
- Optionally uploads keys through `gh` after explicit confirmation.
- Writes a managed block in `~/.ssh/config` with account aliases.
- Validates aliases using `ssh -T git@<alias>`.
- Updates existing repo remotes with a safe dry-run workflow.

## Repository Layout

- `scripts/setup.sh`: Main idempotent setup flow.
- `scripts/update-remotes.sh`: Convert remotes to alias-based SSH URLs.
- `scripts/backup-keys.sh`: Back up SSH files.
- `scripts/generate-key.sh`: Standalone key creation helper.
- `scripts/generate-gh-actions-key.sh`: Optional CI key helper.
- `examples/owner-map.conf.example`: Owner-to-alias mapping example.
- `examples/gitconfig-includeIf.example`: Git identity routing example.
- `docs/audit-and-verify.md`: Manual audit and verification steps.
- `tests/lint.sh`: Shell lint script.

## Prerequisites

- macOS with OpenSSH
- Bash (macOS default Bash 3.2 is supported)
- `git`
- Optional: `gh` (GitHub CLI) for key upload
- Optional: `shellcheck` for lint checks

## What To Run (By Goal)

1. Preview everything and make no changes:
```bash
scripts/setup.sh --dry-run
```
2. Set up or refresh SSH aliases/keys for personal + work:
```bash
scripts/setup.sh --apply
```
3. Update existing repo remotes to alias-based SSH hosts:
```bash
scripts/update-remotes.sh --root "$HOME/code" --map ~/.ssh/owner-map.conf --dry-run
scripts/update-remotes.sh --root "$HOME/code" --map ~/.ssh/owner-map.conf --apply
```
4. Only create a backup snapshot of current SSH files:
```bash
scripts/backup-keys.sh --apply
```
5. Only create one key manually:
```bash
scripts/generate-key.sh --email "you@example.com" --name "id_ed25519_example" --apply
```

## What `setup.sh` Will Not Do

- It does not delete local SSH keys.
- It does not revoke/remove keys from GitHub automatically.
- It does not change git remotes (that is `scripts/update-remotes.sh`).
- It only generates a key when the target key filename does not already exist.
- It writes only a managed block in `~/.ssh/config`; it does not wipe the file.

## Quick Start

```bash
chmod +x scripts/*.sh tests/lint.sh
scripts/setup.sh --dry-run
scripts/setup.sh --apply
```

`--apply` behavior summary:

- Backs up existing `~/.ssh` files first (with confirmation).
- Reuses existing key files if present; otherwise generates new ones.
- Adds keys to `ssh-agent`/keychain.
- Optionally uploads public keys via `gh` after confirmation.
- Adds/updates a managed alias block in `~/.ssh/config`.

Interactive defaults:

- accounts: `personal,work`
- key names: `id_ed25519_personal`, `id_ed25519_work`
- aliases: `github-personal`, `github-work`

Explicit example:

```bash
scripts/setup.sh --apply \
  --accounts "personal,work" \
  --email-personal "you@personal.email" \
  --email-work "you@work.email"
```

Non-interactive example:

```bash
scripts/setup.sh --apply --yes \
  --accounts "personal,work" \
  --email-personal "you@personal.email" \
  --email-work "you@work.email" \
  --key-personal "id_ed25519_personal" \
  --key-work "id_ed25519_work" \
  --alias-personal "github-personal" \
  --alias-work "github-work"
```

## Update Remotes

Dry-run by default:

```bash
scripts/update-remotes.sh --root "$HOME/code" --map examples/owner-map.conf.example --dry-run
```

Apply changes (with confirmation):

```bash
scripts/update-remotes.sh --root "$HOME/code" --map ~/.ssh/owner-map.conf --apply
```

## Manual Commands (Reference)

Audit:

```bash
ls -la ~/.ssh
ls -1 ~/.ssh/*.pub 2>/dev/null || echo "no .pub files found"
ssh-add -l || echo "no keys loaded"
gh ssh-key list
```

Backup:

```bash
mkdir -p ~/ssh-backups
cp -v ~/.ssh/id_* ~/ssh-backups/ 2>/dev/null || echo "copied any id_* keys"
ls -la ~/ssh-backups
```

Generate keys:

```bash
ssh-keygen -t ed25519 -C "you@personal.email" -f ~/.ssh/id_ed25519_personal
ssh-keygen -t ed25519 -C "you@work.email" -f ~/.ssh/id_ed25519_work
```

Add to agent/keychain:

```bash
eval "$(ssh-agent -s)"
ssh-add --apple-use-keychain ~/.ssh/id_ed25519_personal
ssh-add --apple-use-keychain ~/.ssh/id_ed25519_work
ssh-add -l
```

Upload with `gh` (optional):

```bash
gh auth login
gh ssh-key add ~/.ssh/id_ed25519_personal.pub --title "MacBook Personal $(date +%F)"
gh auth login
gh ssh-key add ~/.ssh/id_ed25519_work.pub --title "MacBook Work $(date +%F)"
```

Use aliases in remotes:

```bash
git remote set-url origin git@github-personal:your-personal-username/repo.git
git remote set-url origin git@github-work:your-work-username/repo.git
```

Validate:

```bash
ssh -T git@github-personal
ssh -T git@github-work
ssh -vT git@github-personal 2>&1 | sed -n '1,200p'
```

## Safety Rules

- Never delete keys silently.
- Keep backups until all fetch/push checks are successful.
- `update-remotes.sh` is dry-run by default and confirms before apply.
- `setup.sh` prompts before risky operations unless `--yes` is used.

## Verification Checklist

- [ ] `ssh -T git@github-personal` authenticates to the personal username.
- [ ] `ssh -T git@github-work` authenticates to the work username.
- [ ] Critical repositories can fetch and push.
- [ ] `gh ssh-key list` reflects intended keys.
- [ ] Backups exist under `~/ssh-backups/<timestamp>`.

## Caution About Old Keys

Only remove old keys after successful verification across all repos. Prefer staged cleanup and revoke old keys in GitHub first.
