# Installation

Instructions for the initial installation and bootstrapping of NixOS on the [hardware](hardware.md), including networking and SSH setup so that any further maintenance can be done from another machine.

## Prerequisites

- A bootable USB with the [NixOS Graphical ISO image](https://nixos.org/download/#graphical-iso-image) — [Ventoy](https://www.ventoy.net/en/index.html) is recommended
- An ethernet cable — Wi-Fi (BCM943602CD) requires a driver not available during install

---

## 1. Boot from the USB

1. Plug the USB into the Mac Pro.
2. Power on (or restart) and immediately hold **⌥ (Option/Alt)**.
3. The boot picker will appear. Select the drive labelled **EFI Boot** or **Ventoy**.
4. In the Ventoy menu, select the NixOS ISO.
5. In the NixOS boot menu, choose **NixOS Installer** (the default) and press Enter.

The graphical installer will load. This can take a minute or two.

---

## 2. Connect to the network

Plug in ethernet before booting. The installer will bring up a wired connection automatically via DHCP.

Verify connectivity before proceeding:

```bash
ping -c 3 nixos.org
```

---

## 3. Partition the disk

The Samsung 970 EVO (via the Lycom PCIe adapter) will appear as an NVMe device. Identify it:

```bash
lsblk
```

It will likely be `/dev/nvme0n1`. All commands below assume this — adjust if yours differs.

> **Warning:** The following will erase everything on the drive.

```bash
sudo -i

# Create a GPT partition table
parted /dev/nvme0n1 -- mklabel gpt

# EFI boot partition (512 MB)
parted /dev/nvme0n1 -- mkpart ESP fat32 1MB 512MB
parted /dev/nvme0n1 -- set 1 esp on

# Root partition (everything except the last 8 GB)
parted /dev/nvme0n1 -- mkpart root ext4 512MB -8GB

# Swap partition (last 8 GB)
parted /dev/nvme0n1 -- mkpart swap linux-swap -8GB 100%
```

---

## 4. Format the partitions

```bash
# EFI partition
mkfs.fat -F 32 -n boot /dev/nvme0n1p1

# Root partition
mkfs.ext4 -L nixos /dev/nvme0n1p2

# Swap
mkswap -L swap /dev/nvme0n1p3
```

---

## 5. Mount and activate swap

```bash
mount /dev/disk/by-label/nixos /mnt

mkdir -p /mnt/boot
mount -o umask=077 /dev/disk/by-label/boot /mnt/boot

swapon /dev/disk/by-label/swap
```

---

## 6. Generate the initial configuration

```bash
nixos-generate-config --root /mnt
```

This creates two files:
- `/mnt/etc/nixos/configuration.nix` — the main config you edit
- `/mnt/etc/nixos/hardware-configuration.nix` — auto-detected hardware (don't edit this)

Open the configuration for editing:

```bash
nano /mnt/etc/nixos/configuration.nix
```

Make sure the following are set (they should be auto-detected, but verify):

```nix
# Use systemd-boot (EFI bootloader)
boot.loader.systemd-boot.enable = true;
boot.loader.efi.canTouchEfiVariables = true;

# Disable PCIe gen2 negotiation — the Mac Pro 4,1/5,1 EFI can cause GPU hangs with it enabled
boot.kernelParams = [ "radeon.pcie_gen2=0" ];

# Set your hostname
networking.hostName = "mac-pro";

# Enable networking
networking.networkmanager.enable = true;

# Set your timezone
time.timeZone = "Europe/Copenhagen";  # adjust to your timezone

# Create your user account
users.users.yourname = {
  isNormalUser = true;
  extraGroups = [ "wheel" "networkmanager" ];
  initialPassword = "changeme";  # change after first login
};

# Allow sudo for wheel group
security.sudo.wheelNeedsPassword = true;

# ATI HD 4870 (RV770) — uses the legacy radeon driver
# hardware.radeon.enable pulls in the required linux-firmware blobs (RV770_pfp.bin etc.)
# Without it the GPU boots but falls back to framebuffer-only mode (no hardware-accelerated 3D)
hardware.radeon.enable = true;
hardware.graphics.enable = true;

# Enable a desktop environment (optional — remove if you want headless)
services.xserver.enable = true;
services.xserver.displayManager.gdm.enable = true;
services.desktopManager.gnome.enable = true;
```

Save and exit (`Ctrl+O`, `Ctrl+X` in nano).

---

## 7. Install

```bash
nixos-install
```

You will be prompted to set a root password at the end. Set one, then reboot:

```bash
reboot
```

Remove the USB drive when the machine powers off.

---

## 8. First boot

The Mac Pro will boot directly into NixOS via systemd-boot. Log in with the user account you created.

Change your password immediately:

```bash
passwd
```


