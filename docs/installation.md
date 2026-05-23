# Installation

Instructions for the initial install

## Prerequisites

- A USB drive ≥ 8 GB (16 GB+ recommended)
- A second machine (Mac or Linux) to prepare the USB
- An ethernet cable — Wi-Fi (BCM943602CD) requires a driver not available during install

---

## 1. Download the NixOS ISO

Go to [nixos.org/download](https://nixos.org/download/) and download the **Graphical ISO image** for `x86_64`.

The filename will look like: `nixos-graphical-25.11-x86_64-linux.iso`

---

## 2. Prepare the bootable USB with Ventoy

> **Note on Mac Pro EFI compatibility:** The Mac Pro 4,1/5,1 uses Apple's EFI firmware, which does not always cooperate with Ventoy's UEFI boot shim. If Ventoy fails to appear in the boot picker (step 4), fall back to writing the ISO directly — see the [Fallback](#fallback-write-iso-directly) section below.

### Install Ventoy on the USB drive

**On Linux:**

```bash
# Download and extract Ventoy (check https://github.com/ventoy/ventoy/releases for latest version)
wget https://github.com/ventoy/ventoy/releases/download/v1.0.99/ventoy-1.0.99-linux.tar.gz
tar -xzf ventoy-1.0.99-linux.tar.gz
cd ventoy-1.0.99

# Find your USB device (look for your drive size)
lsblk

# Install Ventoy with GPT partition table (required for EFI)
sudo sh Ventoy2Disk.sh -i -g /dev/sdX   # replace sdX with your USB device
```

**On macOS:**

```bash
# Download and extract Ventoy
curl -LO https://github.com/ventoy/ventoy/releases/download/v1.0.99/ventoy-1.0.99-linux.tar.gz
tar -xzf ventoy-1.0.99-linux.tar.gz
cd ventoy-1.0.99

# Find your USB device
diskutil list

# Unmount the disk (but don't eject)
diskutil unmountDisk /dev/diskN   # replace diskN with your USB disk

# Install Ventoy
sudo sh Ventoy2Disk.sh -i -g /dev/diskN
```

### Copy the NixOS ISO

After Ventoy installs, the USB will have a large partition labelled `Ventoy`. Copy the ISO there:

```bash
cp nixos-graphical-25.11-x86_64-linux.iso /path/to/Ventoy/
```

That's it — no further steps needed. Ventoy will find the ISO automatically at boot.

---

## 3. Boot from the USB

1. Plug the USB into the Mac Pro.
2. Power on (or restart) and immediately hold **⌥ (Option/Alt)**.
3. The boot picker will appear. Select the drive labelled **EFI Boot** or **Ventoy**.
4. In the Ventoy menu, select the NixOS ISO.
5. In the NixOS boot menu, choose **NixOS Installer** (the default) and press Enter.

The graphical installer will load. This can take a minute or two.

---

## 4. Connect to the network

Plug in ethernet before booting. The installer will bring up a wired connection automatically via DHCP.

Verify connectivity before proceeding:

```bash
ping -c 3 nixos.org
```

---

## 5. Partition the disk

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

## 6. Format the partitions

```bash
# EFI partition
mkfs.fat -F 32 -n boot /dev/nvme0n1p1

# Root partition
mkfs.ext4 -L nixos /dev/nvme0n1p2

# Swap
mkswap -L swap /dev/nvme0n1p3
```

---

## 7. Mount and activate swap

```bash
mount /dev/disk/by-label/nixos /mnt

mkdir -p /mnt/boot
mount -o umask=077 /dev/disk/by-label/boot /mnt/boot

swapon /dev/disk/by-label/swap
```

---

## 8. Generate the initial configuration

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

# Enable a desktop environment (optional — remove if you want headless)
services.xserver.enable = true;
services.xserver.displayManager.gdm.enable = true;
services.desktopManager.gnome.enable = true;
```

Save and exit (`Ctrl+O`, `Ctrl+X` in nano).

---

## 9. Install

```bash
nixos-install
```

You will be prompted to set a root password at the end. Set one, then reboot:

```bash
reboot
```

Remove the USB drive when the machine powers off.

---

## 10. First boot

The Mac Pro will boot directly into NixOS via systemd-boot. Log in with the user account you created.

Change your password immediately:

```bash
passwd
```

---

## Fallback: write ISO directly

If Ventoy does not appear in the Mac Pro's boot picker, write the ISO directly to the USB instead.

**On Linux:**

```bash
sudo dd if=nixos-graphical-25.11-x86_64-linux.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

**On macOS:**

```bash
# Unmount the disk first
diskutil unmountDisk /dev/diskN

sudo dd if=nixos-graphical-25.11-x86_64-linux.iso of=/dev/rdiskN bs=4m
```

Then proceed from [step 3](#3-boot-from-the-usb) — in the boot picker the drive will appear as **EFI Boot**.
