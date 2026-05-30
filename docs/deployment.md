# Deployment

## How it works

Deployments are pull-based. The machine periodically pulls the latest commit on
`main` in its local checkout at `~/cheesegrater` and rebuilds — no inbound SSH
access or deploy keys required, only outbound HTTPS to github.com to fetch.

```
push / merge to main  →  CI: nix flake check + build affineur
                                      ↓
cheesegrater          ←  systemd timer fires every 5 min
                         git pull --ff-only in ~/cheesegrater
                         nixos-rebuild switch --flake .#cheesegrater
```

## Components

**`.github/workflows/ci.yml`**
- Runs `nix flake check` and builds `affineur` on every push and PR.

**`nixos/modules/auto-upgrade.nix`**
- Defines a `nixos-auto-upgrade` systemd service that:
  1. `cd`s into `/home/mads/cheesegrater`.
  2. Runs `git pull --ff-only` as the `mads` user.
  3. Runs `nixos-rebuild switch --flake .#cheesegrater` as root.
- A systemd timer fires every 5 minutes (with up to 1 minute of random jitter).

Because the rebuild runs against the working tree, any uncommitted local changes
in `~/cheesegrater` are included in the build. Keep the checkout clean so the
machine tracks `main`.

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
cd ~/cheesegrater && git rev-parse HEAD
```

## Manual deployment

To deploy immediately without waiting for the timer:

```bash
sudo systemctl start nixos-auto-upgrade.service
```

Or run the steps by hand:

```bash
cd ~/cheesegrater
git pull --ff-only
sudo nixos-rebuild switch --flake .#cheesegrater
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

To stop the timer from immediately re-applying a broken commit, either check out
a known-good commit in `~/cheesegrater` or stop the timer until `main` is fixed:

```bash
sudo systemctl stop nixos-auto-upgrade.timer
```
