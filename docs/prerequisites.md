# Prerequisites

## Generate an SSH key

You'll need an SSH key pair to log into the machine after installation. If you already have one (e.g. `~/.ssh/id_ed25519`), you can skip this step.

Generate a new key:

```bash
ssh-keygen -t ed25519 -C "your@email.com"
```

Accept the default path (`~/.ssh/id_ed25519`) and set a passphrase when prompted. The public key at `~/.ssh/id_ed25519.pub` is what you'll paste into the NixOS configuration during installation.

---

## Create a bootable USB

Download the [NixOS Minimal ISO](https://nixos.org/download/#minimal-iso-image).

Flash it directly to a USB stick. **Do not use Ventoy** — it causes a kernel panic on Apple hardware during the NixOS boot process (see [Troubleshooting](installation.md#troubleshooting) for details).

### macOS

macOS mounts USB drives automatically, so you must unmount before flashing. Identify the disk first:

```bash
diskutil list
```

Unmount it (replace `diskN` with your disk, e.g. `disk9`):

```bash
diskutil unmountDisk /dev/diskN
```

Then flash using the raw device (`rdiskN`) for faster writes:

```bash
sudo dd if=nixos-minimal-*.iso of=/dev/rdiskN bs=4M status=progress
```


