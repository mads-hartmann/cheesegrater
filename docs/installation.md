# Installation

Instructions for the initial installation and bootstrapping of NixOS on the [hardware](hardware.md), including networking and SSH setup so that any further maintenance can be done from another machine.

## Prerequisites

- A bootable USB with the [NixOS Graphical ISO image](https://nixos.org/download/#graphical-iso-image) — [Ventoy](https://www.ventoy.net/en/index.html) is recommended
- An ethernet cable — Wi-Fi (BCM943602CD) requires a driver not available during install
- Your SSH public key (e.g. `~/.ssh/id_ed25519.pub` from your other machine)

---

## 1. Boot from the USB

1. Plug in the ethernet cable.
2. Plug the USB into the Mac Pro.
3. Power on (or restart) and immediately hold **⌥ (Option/Alt)**.
4. The boot picker will appear. Select the drive labelled **EFI Boot** or **Ventoy**.
5. In the Ventoy menu, select the NixOS ISO.
6. In the NixOS boot menu, choose **NixOS Installer** (the default) and press Enter.

The graphical installer will load. This can take a minute or two.

---

## 2. Connect to the network

The installer will bring up the wired connection automatically via DHCP.

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

## 6. Configure

```bash
nixos-generate-config --root /mnt
nano /mnt/etc/nixos/configuration.nix
```

Replace the contents with the following, substituting your username and SSH public key:

```nix
{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Disable PCIe gen2 negotiation — the Mac Pro 4,1/5,1 EFI can cause GPU hangs with it enabled
  boot.kernelParams = [ "radeon.pcie_gen2=0" ];

  networking.hostName = "mac-pro";
  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Copenhagen"; # adjust to your timezone

  # ATI HD 4870 (RV770) — requires firmware blobs for hardware acceleration
  hardware.radeon.enable = true;
  hardware.graphics.enable = true;

  users.users.yourname = {         # replace with your username
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAA... you@yourhost" # replace with your public key
    ];
  };

  security.sudo.wheelNeedsPassword = true;

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };
}
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

## 8. Verify SSH access

Once the machine has booted, find its IP address from your router, then from your other machine:

```bash
ssh yourname@<ip-address>
```

If you can log in, the installation is complete and the machine is ready for remote maintenance.
