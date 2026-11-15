# shellcheck shell=bash
# Konfiguration für den ISO-Build. Alle Werte lassen sich per Umgebungsvariable
# überschreiben, z. B.:  LIVE_KEYMAP=us ./build.sh

# --- ISO ---------------------------------------------------------------------
ISO_NAME="${ISO_NAME:-archlinux-arm64-surface}"
ISO_LABEL="${ISO_LABEL:-ARCH_SURFACE}"

# --- Paketquellen ------------------------------------------------------------
# Arch Linux ARM (Userland) und linux-surface (Kernel für Snapdragon-Surfaces)
ALARM_MIRROR="${ALARM_MIRROR:-http://mirror.archlinuxarm.org/\$arch/\$repo}"
SURFACE_REPO="${SURFACE_REPO:-https://pkg.surfacelinux.com/arch-aarch64/}"
SURFACE_KEY_URL="${SURFACE_KEY_URL:-https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc}"
SURFACE_KEY_ID="56C464BAAC421453"

# Vertrauensanker für Arch Linux ARM: Keyring per HTTPS von GitHub, Master-Key
# wird zusätzlich gegen diesen Fingerprint geprüft.
ALARM_KEYRING_URL="https://raw.githubusercontent.com/archlinuxarm/PKGBUILDs/master/core/archlinuxarm-keyring"
ALARM_MASTER_KEY="68B3537F39A313B3E574D06777193F152BDBE6A6"

# --- Live-System -------------------------------------------------------------
# Vorgaben für Sprache (de|en) und Tastaturbelegung; beides lässt sich beim
# Start im Bootmenü und später mit surface-locale ändern.
LIVE_LANG="${LIVE_LANG:-de}"
LIVE_KEYMAP="${LIVE_KEYMAP:-de-latin1}"
LIVE_FONT="${LIVE_FONT:-ter-132b}"          # große Konsolenschrift für HiDPI-Displays
LIVE_TIMEZONE="${LIVE_TIMEZONE:-Europe/Berlin}"
LIVE_HOSTNAME="${LIVE_HOSTNAME:-archsurface}"

# --- Surface Pro X (SQ1/SQ2) -------------------------------------------------
# Firmware aus https://github.com/linux-surface/aarch64-firmware einbinden.
# Achtung: Für diese Dateien gibt es keine ausdrückliche Weitergabe-Lizenz
# (siehe README dort) – das fertige ISO also nicht öffentlich verteilen.
WITH_SPX_FIRMWARE="${WITH_SPX_FIRMWARE:-1}"
SPX_FIRMWARE_REPO="https://github.com/linux-surface/aarch64-firmware"
SPX_FIRMWARE_REF="9f07579ee64aba56419cfd0fbbca9f26741edc90"
SPX_FIRMWARE_PATHS=(qcom/msft ath10k/WCN3990)

# Qualcomm-Userspace (qrtr, tqftpserv, rmtfs-dummy) für das WLAN des Pro X bauen.
WITH_QCOM_USERSPACE="${WITH_QCOM_USERSPACE:-1}"
QCOM_PKGBUILD_REPO="https://github.com/linux-surface/aarch64-packages"
QCOM_PKGBUILD_REF="9c4a53a129e1905ca0ba782877fadee3d47e50d2"
QCOM_PACKAGES=(qmic qrtr tqftpserv rmtfs-dummy)

# Gepatchtes GRUB von linux-surface als Ausweich-Bootloader für das Pro X.
WITH_SPX_GRUB="${WITH_SPX_GRUB:-1}"
SPX_GRUB_URL="https://github.com/linux-surface/grub-image-aarch64/releases/download/fedora-39-1/bootaa64.efi"

# --- Kompression -------------------------------------------------------------
# Der linux-surface-Kernel kann SquashFS nur mit xz, lz4, lzo oder zlib lesen (kein zstd).
SQUASHFS_OPTS=(-comp xz -b 1M -Xdict-size 100%)
