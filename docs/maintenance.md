---
type: guide
tags: [maintenance, ops]
---

# Maintenance

Tips & tricks for maintaining the system

## Upgrading nixpkgs

To update the pinned `nixpkgs` version:

```bash
cd ~/cheesegrater
nix flake update
sudo nixos-rebuild switch --flake .#cheesegrater
```

Commit the updated `flake.lock` once you're happy with the result.