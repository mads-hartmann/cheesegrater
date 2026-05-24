# Prerequisites

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


