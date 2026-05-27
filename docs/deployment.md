# Deployment

## How it works

Deployments are pull-based. The machine polls GitHub for new releases and applies them automatically — no inbound SSH access or deploy keys required.

```
push to branch  →  CI: nix flake check
                        ↓ (fails: no release)
merge to main   →  CI: nix flake check → create GitHub Release (tag)
                                                    ↓
cheesegrater    ←  systemd timer polls every 5 min ←
                   detects new tag → nixos-rebuild switch --flake github:…/<tag>#cheesegrater
                   persists tag to /var/lib/nixos-auto-upgrade/current-tag
```

## Components

**`.github/workflows/ci.yml`**
- Runs `nix flake check` on every push and PR.
- On `main` only, after checks pass, creates a GitHub Release tagged `deploy-YYYYMMDD-HHMMSS-<sha>` pointing at the exact commit.

**`nixos/modules/auto-upgrade.nix`**
- Defines a `nixos-auto-upgrade` systemd service that:
  1. Calls the GitHub releases API to get the latest tag.
  2. Compares it to `/var/lib/nixos-auto-upgrade/current-tag`.
  3. If different, runs `nixos-rebuild switch --flake github:mads-hartmann/cheesegrater/<tag>#cheesegrater`.
  4. Writes the new tag to the state file on success.
- A systemd timer fires every 5 minutes (with up to 1 minute of random jitter).

## First-time bootstrap

The auto-upgrade module is part of the configuration, so it activates itself on the first manual apply:

```bash
cd ~/cheesegrater
sudo nixos-rebuild switch --flake .#cheesegrater
```

After that, all future deployments happen automatically on push to `main`.

## Monitoring

Check the last run:

```bash
systemctl status nixos-auto-upgrade.service
journalctl -u nixos-auto-upgrade.service -n 50
```

Check the timer:

```bash
systemctl list-timers nixos-auto-upgrade.timer
```

See what's currently deployed:

```bash
cat /var/lib/nixos-auto-upgrade/current-tag
```

## Manual deployment

To deploy a specific release without waiting for the timer:

```bash
sudo systemctl start nixos-auto-upgrade.service
```

To deploy a specific tag directly:

```bash
sudo nixos-rebuild switch --flake "github:mads-hartmann/cheesegrater/<tag>#cheesegrater"
```

## Rollback

NixOS keeps previous generations. To roll back to the last working generation:

```bash
sudo nixos-rebuild switch --rollback
```

To roll back to a specific generation:

```bash
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
sudo nix-env --switch-generation <N> --profile /nix/var/nix/profiles/system
sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
```

After rolling back, update the state file so the timer doesn't immediately re-apply the broken release:

```bash
echo "<working-tag>" | sudo tee /var/lib/nixos-auto-upgrade/current-tag
```
