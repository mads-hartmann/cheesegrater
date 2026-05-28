# AGENTS.md

This repository contains the NixOS configuration for a Mac Pro (2009) running NixOS.

## Repository Structure

- `nixos/` — NixOS configuration files
  - `configuration.nix` — main system configuration
  - `hardware-configuration.nix` — hardware-specific settings
  - `modules/` — additional NixOS modules (e.g. `auto-upgrade.nix`)
- `flake.nix` — Nix flake defining the NixOS configuration, pre-commit checks, and dev shell
- `flake.lock` — locked flake inputs
- `docs/` — documentation covering hardware details, installation, and maintenance
- `.devcontainer/` — dev container configuration for working on this repo
- `.github/` — CI workflows

## Documentation

The `docs/` directory explains the hardware and setup in detail:

| File | Description |
|------|-------------|
| [docs/hardware.md](docs/hardware.md) | Hardware specifications and component notes |
| [docs/prerequisites.md](docs/prerequisites.md) | Creating a bootable USB |
| [docs/installation.md](docs/installation.md) | Installing NixOS |
| [docs/configuration-and-maintenance.md](docs/configuration-and-maintenance.md) | Storing configuration in git and iterating |

## Tooling

- **Formatter**: `nixfmt-rfc-style` — all `.nix` files must be formatted with it
- **Linter**: `statix` — enforces idiomatic Nix patterns (config in `statix.toml`)
- **Pre-commit hooks**: managed via `git-hooks.nix`; run `nix develop` to install them

## Diagnosing Issues

If diagnosing a problem requires running commands on the Mac Pro itself (e.g. checking hardware, inspecting logs, querying the running system), ask the user to run them and share the output.
