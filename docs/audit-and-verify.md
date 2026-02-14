# Audit and Verify

## Local Audit

```bash
ls -la ~/.ssh
ls -1 ~/.ssh/*.pub 2>/dev/null || echo "no .pub files found"
ssh-add -l || echo "no keys loaded"
```

If GitHub CLI is installed and authenticated:

```bash
gh ssh-key list
```

## Backups

```bash
scripts/backup-keys.sh --dry-run
scripts/backup-keys.sh --apply
```

## Verify Aliases

```bash
ssh -T git@github-personal
ssh -T git@github-work
```

Expected pattern:

- `Hi <username>! You've successfully authenticated, but GitHub does not provide shell access.`

## Verify Repository Access

For representative repositories:

```bash
git fetch
git push --dry-run
```

## Only Then: Key Cleanup

- Revoke old keys on GitHub.
- Remove old local keys with explicit commands and prompts.
- Keep backup snapshots until all workflows remain stable.
