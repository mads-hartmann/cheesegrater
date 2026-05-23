# Hardware

This is a Mac Pro from 2009 that I bought used and then upgraded as much as I could - see [specifications](#specifications) and [notes](#notes) below for details.

## Specifications

| Component | Details |
|-----------|---------|
| **Model** | Mac Pro 4,1 → 5,1 (firmware flash) |
| **CPU** | Intel Xeon X5690 3.46 GHz (6-core) |
| **RAM** | 4 × 16 GB DDR3 ECC PC3-10600 1333 MHz SDRAM (64 GB total) |
| **SSD** | Samsung 970 EVO 500 GB via Lycom DT-120 M.2 PCIe adapter |
| **GPU** | ATI Radeon HD 4870 512 MB |
| **Wi-Fi / Bluetooth** | Apple Broadcom BCM943602CD — 802.11 a/b/g/n/ac, Bluetooth 4.1 |

## Notes

- I flashed the firmware from 4,1 to 5,1 as it allows the machine to accept Westmere-class CPUs (e.g. X5690) and newer EFI features.
- The Lycom DT-120 adapter fits an M.2 NVMe drive into a PCIe slot, since the Mac Pro 4,1/5,1 has no native M.2 support.
- The ATI HD 4870 outputs via Mini DisplayPort and Dual-link DVI.
- The BCM943602CD card provides native macOS-compatible Wi-Fi and Bluetooth; Linux support requires the `brcmfmac` driver.
