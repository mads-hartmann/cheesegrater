---
type: reference
tags: [deployment, ops]
---

# Deployment

## How it works

Deployments are pull-based. The machine periodically pulls the latest commit on
`main` in its local checkout at `~/cheesegrater` and rebuilds — no inbound SSH
access or deploy keys required, only outbound HTTPS to github.com to fetch.

The repository is private, so the pull authenticates with a fine-grained GitHub
personal access token (PAT). See [Authentication](#authentication) for how the
token is stored and provisioned.

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
  2. Pins the `origin` remote to its HTTPS URL.
  3. Runs `git pull --ff-only` as the `mads` user, supplying the PAT through a
     git credential helper.
  4. Runs `nixos-rebuild switch --flake .#cheesegrater` as root.
- A systemd timer fires every 5 minutes (with up to 1 minute of random jitter).

Because the rebuild runs against the working tree, any uncommitted local changes
in `~/cheesegrater` are included in the build. Keep the checkout clean so the
machine tracks `main`.

## Authentication

The repository is private, so the pull needs credentials. On NixOS, anything in
the Nix store is world-readable, so the token must never be written into a
`.nix` file or a generated script. Instead it lives in an out-of-store file and
is handed to the service via systemd's `LoadCredential`.

**How the token reaches git:**

1. The token is stored at `/etc/nixos-auto-upgrade.token` (root-owned, `0600`),
   outside the Nix store and not tracked in git.
2. `LoadCredential` exposes it to the `nixos-auto-upgrade` unit only, mounted
   root-readable at `$CREDENTIALS_DIRECTORY/gh-token`.
3. The service stages it into a runtime tmpfs file readable by `mads`, then a
   git credential helper supplies it as the password (username
   `x-access-token`) over HTTPS.

The token value never enters the Nix store, the unit environment, or process
arguments.

### Creating the token

Create a [fine-grained personal access token](https://github.com/settings/tokens?type=beta):

- **Resource owner:** your account
- **Repository access:** Only select repositories → `mads-hartmann/cheesegrater`
- **Permissions:** Repository permissions → **Contents: Read-only**
- Set an expiry and note it for rotation.

### Provisioning it on the machine

Write the token to the expected path (run once, as root — never commit it):

```bash
sudo install -m 0600 -o root -g root /dev/stdin \
  /etc/nixos-auto-upgrade.token <<<'github_pat_REPLACE_ME'
```

No rebuild is required after rotating the token — rewrite the file and the next
run picks it up.

### Rotating the token

When the PAT nears expiry, create a new one and overwrite the file with the same
`install` command above.

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

Or run the steps by hand. Because the repo is private, the manual pull needs the
PAT too — supply it with a one-off credential helper that reads the token file:

```bash
cd ~/cheesegrater
git -c credential.helper='!f() { echo username=x-access-token; echo "password=$(sudo cat /etc/nixos-auto-upgrade.token)"; }; f' \
  pull --ff-only
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
