# Arch Linux ARM64 for Snapdragon-based Surface devices

**English** | [Deutsch](README.de.md)

Builds a bootable live/installation ISO (aarch64, UEFI) with

- **userland** from [Arch Linux ARM](https://archlinuxarm.org),
- the **kernel** `linux-surface` from the aarch64 package repository of
  [linux-surface](https://github.com/linux-surface) (it ships the devicetrees
  and drivers for the Snapdragon Surfaces),
- **firmware** from `linux-firmware` (Qualcomm, Atheros, …), the Pro X firmware
  from linux-surface, and a tool that takes the device-specific firmware from
  the device's Windows installation,
- a **GRUB boot menu** that loads the matching devicetree for each device,
- an **installer** (`surface-install`) that puts the system, bootloader and
  devicetree onto the internal SSD.

The boot menu, the live system's messages and the helper tools are currently
in German.

## Supported devices

| ID          | Device                              | SoC       | Devicetree                           |
|-------------|-------------------------------------|-----------|--------------------------------------|
| `spx`       | Surface Pro X (SQ1/SQ2)             | SC8180X   | `sc8180x-surface-pro-x.dtb`          |
| `sp9-5g`    | Surface Pro 9 5G (SQ3)              | SC8280XP  | `sc8280xp-microsoft-arcata.dtb`      |
| `devkit`    | Windows Dev Kit 2023                | SC8280XP  | `sc8280xp-microsoft-blackrock.dtb`   |
| `sl7-13`    | Surface Laptop 7 13.8"              | X1E80100  | `x1e80100-microsoft-romulus13.dtb`   |
| `sl7-15`    | Surface Laptop 7 15"                | X1E80100  | `x1e80100-microsoft-romulus15.dtb`   |
| `sp11-lcd`  | Surface Pro 11 (LCD, X Plus)        | X1P64100  | `x1p64100-microsoft-denali.dtb`      |
| `sp11-oled` | Surface Pro 11 (OLED, X Elite)      | X1E80100  | `x1e80100-microsoft-denali-oled.dtb` |
| `sp12`      | Surface Pro 12" (2025, X Plus)      | X1P42100  | `x1p42100-microsoft-sp12in.dtb`      |

The list lives in [`devices.conf`](devices.conf) and matches the devicetrees
shipped with the linux-surface kernel.

### Hardware support

The table shows which hardware the linux-surface kernel (7.3.1) describes in
each device's devicetree. It was read from the kernel sources and **not tested
on hardware**: "✓" means "a driver is wired up", not "guaranteed to work". For
the actual state see the linux-surface wiki and issues.

| Feature | Pro X (SQ1/SQ2) | Pro 9 5G | Dev Kit 2023 | Laptop 7 (13.8"/15") | Pro 11 (LCD/OLED) | Pro 12" |
|---|---|---|---|---|---|---|
| Internal display | ✓ | ✓ | – (no display) | ✓ | ✓ | ✓ |
| GPU acceleration | ✓ (FW) | ✓ (FW) | ✓ (FW) | ✓ (FW) | ✓ (FW) | ✓ (FW) |
| Internal storage | ✓ NVMe | ✓ NVMe | ✓ NVMe | ✓ NVMe | ✓ NVMe | ✓ UFS |
| USB-C / USB | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| External monitor over USB-C | – | ✓ | ✓ | ✓ | ✓ | ✓ |
| Wi-Fi | ✓ (WCN3990) | ✓ (WCN6855) | ✓ (WCN6855) | ✓ (WCN7850) | ✓ (WCN7850) | ✓ (WCN7850) |
| Bluetooth | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Audio | – | ✓ (FW) | ✓ (FW) | ✓ (FW) | ✓ (FW) | ✓ (FW) |
| Keyboard/touchpad, battery (Surface Aggregator) | ✓ | ✓ | – (USB devices) | ✓ | ✓ | ✓ |
| Touchscreen | – | – | – | – | – | ✓ |
| Cameras | – | – | – | – | – | – |
| Cellular (LTE/5G) | – | – | – | – | – | – |

- **✓**: described in the devicetree, driver present in the kernel.
- **(FW)**: additionally needs the signed firmware from Windows
  (`surface-fw-extract`, see below). For the Pro X it is already in the ISO.
- **–**: not described in the devicetree, so currently without function.

Pen and fingerprint reader/Windows Hello were not checked individually. On the
Pro X, Wi-Fi only works with the helper services `tqftpserv` and `rmtfs`; they
are included in the ISO and set up by the installer.

## Building

The only requirement is **Docker**. On an x86_64 host the aarch64 system is
created under emulation (`binfmt_misc` + qemu-user); if the registration is
missing, `build.sh` sets it up through the `tonistiigi/binfmt` image (it lasts
until the host is rebooted).

```sh
./build.sh            # build the ISO -> out/archlinux-arm64-surface-<date>-aarch64.iso
./build.sh clean      # delete intermediate state (Docker volumes)
./build.sh shell      # shell inside the build container
```

Settings live in [`config.sh`](config.sh) and can be overridden from the
environment, e.g. `LIVE_KEYMAP=us LIVE_TIMEZONE=UTC ./build.sh` (the default
keymap is `de-latin1`). The live system's packages are listed in
[`packages.txt`](packages.txt).

Smoke test in QEMU (no Surface hardware, generic boot entry):

```sh
scripts/test-qemu.sh          # serial console, quit with Ctrl+A, X
```

## Getting it onto a USB drive

### Ventoy

Copy the ISO file onto the Ventoy drive and pick it in the Ventoy menu ("Boot
in normal mode"). At boot the live system looks for the ISO file on the drive
itself (initramfs hook `surface_isoscan`; exFAT/NTFS/FAT/ext4, up to three
directory levels deep) and loop-mounts it. Alternatively, Ventoy's "GRUB2
mode" works through the included `boot/grub/loopback.cfg`.

Ventoy itself has to be able to start on the device (ARM64 UEFI, Secure Boot
off). If it does not, write the ISO directly to a drive.

### Writing it directly (dd)

```sh
sudo dd if=out/archlinux-arm64-surface-<date>-aarch64.iso of=/dev/sdX bs=4M conv=fsync status=progress
```

(`/dev/sdX` is the drive, **not** a partition. All data on it is lost.)

## Booting

1. In Windows: turn off BitLocker/device encryption or keep the recovery key
   at hand, disable "Fast startup", and shrink the Windows partition to make
   room for Linux.
2. Open the Surface UEFI (device off, hold **Volume Up**, press Power):
   - *Security → Secure Boot*: **disable**,
   - *Boot configuration*: allow USB boot and move it to the top.
3. Boot from the drive (device off, hold **Volume Down**, press Power).
4. Pick your device in the boot menu. If the device is recognised from the
   firmware information, the matching entry is preselected; this detection is
   only a convenience – a wrong devicetree does not boot or gives no picture.

The live system logs in as `root` automatically. Change the keyboard layout
with `loadkeys us`.

## Installing

```sh
surface-device                      # show the detected device
iwctl station wlan0 connect <SSID>  # Wi-Fi (or USB Ethernet/tethering)

# Partition and format (example: free space behind Windows)
cfdisk /dev/nvme0n1
mkfs.ext4 /dev/nvme0n1pN

mount /dev/nvme0n1pN /mnt
mount --mkdir /dev/nvme0n1p1 /mnt/efi   # existing EFI system partition

surface-install /mnt
```

`surface-install`

- installs `base`, `linux-surface`, `linux-firmware`, GRUB etc. with `pacstrap`,
- adds the linux-surface repository to `/etc/pacman.conf` (kernel updates then
  arrive through a normal `pacman -Syu`),
- sets up an initramfs with all required platform drivers (hook
  `surface-qcom`, entered in `/etc/mkinitcpio.conf`),
- takes the device-specific firmware from Windows (`surface-fw-extract`),
- installs GRUB and generates, through `/etc/grub.d/09_surface`, an entry with
  the device's devicetree (`/etc/default/surface-boot`). `grub-mkconfig` keeps
  working as usual afterwards.

Partitioning, formatting and mounting are deliberately left to you.

### Firmware

The devices' DSP and GPU firmware is signed by Microsoft/Qualcomm and not
freely redistributable. `surface-fw-extract` reads from the devicetree which
files the kernel expects, looks for them in the driver store of the Windows
installation (BitLocker partitions are opened with the recovery key through
`cryptsetup`) and places them under `/usr/lib/firmware`:

```sh
surface-fw-extract --list           # what is needed, what is missing?
surface-fw-extract --root /mnt      # into the live and the installed system
```

Without these files the system still boots, but GPU acceleration, audio and
the battery indicator, among others, will be missing.

For the **Surface Pro X** the firmware from
[linux-surface/aarch64-firmware](https://github.com/linux-surface/aarch64-firmware)
is already included in the ISO (`WITH_SPX_FIRMWARE=1`). There is no explicit
redistribution licence for it – so do not distribute the ISO publicly, or
build with `WITH_SPX_FIRMWARE=0`.

## Layout

```
build.sh                      entry point on the host (Docker, binfmt)
config.sh                     settings
devices.conf                  devices, devicetrees, kernel parameters
packages.txt                  packages of the live system
scripts/build-in-container.sh the actual build (pacstrap, SquashFS, GRUB, xorriso)
scripts/chroot-customize.sh   tweaks inside the aarch64 root (initramfs, GRUB image)
scripts/test-qemu.sh          smoke test in QEMU
airootfs-pre/                 files placed in the root before package installation
                              (initramfs hooks surface-qcom and surface_isoscan)
airootfs/                     overlay of the live system (tools, systemd units)
```

The ISO is a hybrid image (ISO9660 + GPT with a FAT EFI system partition).
Kernel, initramfs, devicetrees and GRUB live in the EFI partition, the root
file system as SquashFS (`arch/aarch64/airootfs.sfs`, xz – the linux-surface
kernel cannot read zstd in SquashFS) in the ISO; the initramfs uses the hooks
from `mkinitcpio-archiso`.

## Known limitations

- The build was tested in QEMU (generic UEFI/ACPI boot, directly as a USB
  drive and through Ventoy), **not on real Surface hardware**. Devicetrees and
  kernel parameters follow the linux-surface sources; the device detection in
  the boot menu (SMBIOS names) is only an assumption.
- On the X Elite/X Plus devices, USB-C plug orientation partly depends on
  firmware that is only present after `surface-fw-extract`. If the drive is
  not found at boot: flip the plug or use another port (USB-A, if available).
- Surface Pro 11 (LCD/OLED) cannot be told apart reliably from the firmware
  information and has to be picked by hand in the boot menu.
- Surface Pro X: if the stock GRUB does not start, the patched GRUB from
  linux-surface is at `EFI/spx/bootaa64.efi` in the drive's EFI partition
  (menu entry, or copy it to `EFI/BOOT/BOOTAA64.EFI`).
- UEFI variables are not writable from Linux on every device. In that case
  `surface-install` can, on request, place GRUB as the default bootloader
  (`EFI/BOOT/BOOTAA64.EFI`, backing up the existing file).
