# Configuration and Maintenance

## Store configuration in git

The configuration lives in this repo under `nixos/`. The root `flake.nix` defines the system and pins `nixpkgs` via `flake.lock`.

## First-time setup on the machine

Install git (not available by default on a fresh NixOS install):

```bash
nix-env -iA nixos.git
```

> **Note:** `nix-env` installs into the current user's profile (`~/.nix-profile`). It survives reboots but is user-scoped. Once the repo is cloned and the configuration is applied, git is provided by `environment.systemPackages` — at that point `nix-env` git can be removed (`nix-env -e git`).

Configure your identity (required to commit):

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

Clone this repo:

```bash
git clone git@github.com:mads-hartmann/cheesegrater.git ~/cheesegrater
```

Enable flakes (required to use this repo's configuration):

```bash
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

Apply the configuration for the first time:

```bash
cd ~/cheesegrater
sudo nixos-rebuild switch --flake .#cheesegrater
```

This also generates `flake.lock` if it doesn't exist yet. Commit it:

```bash
git add flake.lock
git commit -m "add flake.lock"
git push
```

## Iterating

Edit files under `~/cheesegrater/nixos/`, then apply:

```bash
cd ~/cheesegrater
sudo nixos-rebuild switch --flake .#cheesegrater
```

If it works, commit. If it breaks, revert the file and rebuild, or use NixOS's built-in generation rollback:

```bash
sudo nixos-rebuild switch --rollback
```

## Upgrading nixpkgs

To update the pinned `nixpkgs` version:

```bash
cd ~/cheesegrater
nix flake update
sudo nixos-rebuild switch --flake .#cheesegrater
```

Commit the updated `flake.lock` once you're happy with the result.

## Pull-based auto-deployment

The intended deployment flow is:

1. CI (`nix flake check`) runs on every push and PR.
2. When `main` passes, CI creates a versioned GitHub Release (tag).
3. A systemd timer on the machine polls for new releases and applies them automatically.

See `docs/deployment.md` for setup instructions.
