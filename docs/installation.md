# Installation

Instructions for the initial installation and bootstrapping of NixOS on the [hardware](hardware.md), including networking and SSH setup so that any further maintenance can be done from another machine.

## Prerequisites

- A bootable USB with the NixOS Minimal ISO — see [prerequisites.md](prerequisites.md) for instructions.
- An ethernet cable — Wi-Fi (BCM943602CD) requires a driver not available during install
- Your SSH public key (e.g. `~/.ssh/id_ed25519.pub` from your other machine)

---

## 1. Boot from the USB

1. Plug in the ethernet cable.
2. Plug the USB into the Mac Pro.
3. Power on (or restart) and immediately hold **⌥ (Option/Alt)**.
4. The boot picker will appear. Select the drive labelled **EFI Boot**.
5. In the NixOS boot menu, run the installer with `nomodeset`.[^nomodeset]

The minimal installer will drop you into a terminal. This can take a minute or two.

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

Switch to a root shell to avoid prefixing every command with `sudo`:

```bash
sudo -i
```

A partition table[^partition-table] tells the OS how the disk is divided up. GPT (GUID Partition Table)[^gpt] is the modern standard and required for EFI[^efi] boot:

```bash
parted /dev/nvme0n1 -- mklabel gpt
```

The EFI System Partition (ESP) is a small FAT32 volume the firmware reads at boot to find the bootloader. The partition starts at 1MB rather than the beginning of the disk to ensure proper alignment on modern drives.[^alignment] 512 MB is more than enough for the bootloader:

```bash
parted /dev/nvme0n1 -- mkpart ESP fat32 1MB 512MB
```

Set the `esp` flag so the firmware recognises this partition as the ESP:

```bash
parted /dev/nvme0n1 -- set 1 esp on
```

The root partition holds the entire OS and all data, formatted as ext4[^ext4]. We stop 8 GB short of the end of the disk to leave room for swap:

```bash
parted /dev/nvme0n1 -- mkpart root ext4 512MB -8GB
```

Swap[^swap] is disk space the kernel uses as overflow when RAM is full:

```bash
parted /dev/nvme0n1 -- mkpart swap linux-swap -8GB 100%
```

[^partition-table]: A partition table is metadata at the start of a disk that describes how it is divided into partitions — discrete regions each formatted and used independently.
[^alignment]: Modern drives perform best when partitions start on 4KB boundaries. Starting at 1MB (rather than sector 1) guarantees alignment regardless of the drive's physical sector size.
[^gpt]: GPT replaced the older MBR (Master Boot Record) standard. MBR has a 2 TB disk size limit and supports at most 4 primary partitions; GPT has neither restriction.
[^efi]: EFI (Extensible Firmware Interface) is the firmware standard on modern machines that handles the initial boot process before handing off to the OS bootloader.
[^ext4]: ext4 (fourth extended filesystem) is the standard Linux filesystem. It's mature, well-supported, and a safe default for a root partition.
[^swap]: Swap is disk space reserved for the kernel to move memory pages to when physical RAM is exhausted. It prevents out-of-memory crashes at the cost of speed.

---

## 4. Format the partitions

Format the EFI partition as FAT32 and label it `boot`. FAT32 is required by the EFI specification — the firmware expects to read this partition directly:

```bash
mkfs.fat -F 32 -n boot /dev/nvme0n1p1
```

Format the root partition as ext4 and label it `nixos`. The label is used to mount it by name rather than by device path:

```bash
mkfs.ext4 -L nixos /dev/nvme0n1p2
```

Initialise the swap partition and label it `swap`:

```bash
mkswap -L swap /dev/nvme0n1p3
```

---

## 5. Mount and activate swap

Mount the root partition at `/mnt`. The NixOS installer expects the target system to be rooted here:

```bash
mount /dev/disk/by-label/nixos /mnt
```

Create the mount point for the EFI partition, then mount it. The `umask=077` restricts permissions so only root can read the bootloader files:

```bash
mkdir -p /mnt/boot
mount -o umask=077 /dev/disk/by-label/boot /mnt/boot
```

Activate the swap partition so the installer can use it if needed:

```bash
swapon /dev/disk/by-label/swap
```

---

## 6. Configure

Scan the mounted system and generate a base NixOS configuration, including a `hardware-configuration.nix` that reflects the detected disk layout and hardware:

```bash
nixos-generate-config --root /mnt
```

Open the main configuration file for editing:

```bash
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

---

## 9. Store configuration in git

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

---

## Troubleshooting

### Kernel panic when booting from USB

If the USB was not flashed directly (e.g. using Ventoy), the Mac Pro 4,1/5,1 may fail with a fatal kernel panic:

```
Kernel panic - not syncing: Attempted to kill init! exitcode=0x00000100
```

Ensure the ISO is flashed directly to the USB stick — see [prerequisites.md](prerequisites.md).

[^nomodeset]: `nomodeset` prevents the kernel from loading the `radeon` DRM driver and switching display modes during boot. Without it, the ATI HD 4870 blanks the screen at stage 2 and the installer never becomes visible. With it, the installer uses the basic EFI framebuffer instead of the kernel driver taking over. `nomodeset` is only needed for the install environment, not the final system configuration.
