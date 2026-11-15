#!/usr/bin/env bash
# Startet das ISO in QEMU (aarch64, UEFI) – als Rauchtest für Bootloader,
# Initramfs und Live-System. Surface-Hardware wird dabei NICHT emuliert; das
# Bootmenü wählt in QEMU automatisch den generischen Eintrag ohne Devicetree.
#
#   scripts/test-qemu.sh [ISO] [usb|virtio|cdrom]
#
# Bedienung über die serielle Konsole im Terminal; beenden mit Strg+A, X.
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")/.."

iso="${1:-$(ls -t out/*.iso 2>/dev/null | head -n1)}"
mode="${2:-usb}"
[[ -f "$iso" ]] || { echo "Kein ISO gefunden – erst ./build.sh ausführen." >&2; exit 1; }

fw=""
for f in /usr/share/edk2/aarch64/QEMU_EFI.fd /usr/share/AAVMF/AAVMF_CODE.fd \
         /usr/share/qemu-efi-aarch64/QEMU_EFI.fd; do
    [[ -f "$f" ]] && fw="$f" && break
done
[[ -n "$fw" ]] || { echo "UEFI-Firmware für aarch64 (edk2-aarch64) nicht gefunden." >&2; exit 1; }

case "$mode" in
    usb)    disk=(-device usb-storage,drive=iso,bootindex=0) ;;
    virtio) disk=(-device virtio-blk-pci,drive=iso,bootindex=0) ;;
    cdrom)  disk=(-device virtio-scsi-pci -device scsi-cd,drive=iso,bootindex=0) ;;
    *) echo "Unbekannter Modus: $mode" >&2; exit 2 ;;
esac

exec qemu-system-aarch64 \
    -M virt -cpu cortex-a76 -smp 4 -m "${QEMU_MEM:-4096}" \
    -bios "$fw" \
    -device qemu-xhci \
    -drive if=none,id=iso,format=raw,readonly=on,file="$iso" \
    "${disk[@]}" \
    -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
    -nographic ${QEMU_EXTRA:-}
