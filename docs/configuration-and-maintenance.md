# Configuration and Maintenance

## Store configuration in git

The generated configuration lives in `/etc/nixos/`. Rather than editing it there directly, keep it in this repo and symlink it — that way you can iterate as a normal user, commit changes, and roll back if something breaks.

### First-time setup

Clone this repo on the machine:

```bash
git clone git@github.com:mads-hartmann/cheesegrater.git ~/cheesegrater
mkdir -p ~/cheesegrater/nixos
```

Copy the generated files into the repo:

```bash
cp /etc/nixos/configuration.nix ~/cheesegrater/nixos/
cp /etc/nixos/hardware-configuration.nix ~/cheesegrater/nixos/
```

Replace the originals with symlinks:

```bash
sudo ln -sf ~/cheesegrater/nixos/configuration.nix /etc/nixos/configuration.nix
sudo ln -sf ~/cheesegrater/nixos/hardware-configuration.nix /etc/nixos/hardware-configuration.nix
```

Verify the system still builds cleanly:

```bash
sudo nixos-rebuild switch
```

Commit and push:

```bash
cd ~/cheesegrater
git add nixos/
git commit -m "add initial nixos configuration"
git push
```

### Iterating

Edit files under `~/cheesegrater/nixos/` as your normal user, then apply:

```bash
sudo nixos-rebuild switch
```

If it works, commit. If it breaks, either revert the file and rebuild, or use NixOS's built-in generation rollback:

```bash
sudo nixos-rebuild switch --rollback
```
