# shellcheck shell=bash
# Konfiguration für den ISO-Build. Alle Werte lassen sich per Umgebungsvariable
# überschreiben, z. B.:  LIVE_KEYMAP=us ./build.sh

# --- ISO ---------------------------------------------------------------------
ISO_NAME="${ISO_NAME:-archlinux-arm64-surface}"
ISO_LABEL="${ISO_LABEL:-ARCH_SURFACE}"

# --- Paketquellen ------------------------------------------------------------
# Userland: "port" = aarch64-Port von Arch Linux (https://ports.archlinux.page/aarch64/,
# noch nicht offiziell; Repositories forge/core/extra, gebaut für ARMv8.2+) oder
# "alarm" = Arch Linux ARM. Der Kernel kommt in beiden Fällen von linux-surface.
# Ein installiertes System wechselt nicht von selbst: Dort zählt die
# /etc/pacman.conf, siehe README (Abschnitt zum Wechsel von Arch Linux ARM).
USERLAND="${USERLAND:-port}"
PORT_MIRROR="${PORT_MIRROR:-https://arch-linux-repo.drzee.net/arch/\$repo/os/\$arch}"
# Signaturschlüssel des Ports ("np <key@drzee.net>") aus dem Paket
# archports-keyring; der Build bricht ab, wenn es einen anderen enthält.
PORT_KEY_FPR="9B2C213B21883BB65CE2FB900CF25682E6BA0751"
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

# --- Eigener Kernel ----------------------------------------------------------
# linux-surface mit den Treibern für den Surface Laptop 7 (kernel/PKGBUILD,
# gebaut mit scripts/build-kernel.sh) aus der Arch-Paketregistry von Gitea. ISO
# und installierte Systeme binden sie vor [linux-surface] ein, damit pacman
# den Kernel von dort nimmt.
WITH_SURFACE_KERNEL="${WITH_SURFACE_KERNEL:-1}"
GITEA_URL="${GITEA_URL:-https://git.3dns.eu}"
GITEA_OWNER="${GITEA_OWNER:-dom1nic}"
KERNEL_REPO_NAME="${KERNEL_REPO_NAME:-surface-kernel}"
KERNEL_REPO="${KERNEL_REPO:-${GITEA_URL}/api/packages/${GITEA_OWNER}/arch/${KERNEL_REPO_NAME}/\$arch}"
# Signaturschlüssel der Arch-Registry von Gitea ("Arch Registry", pro Besitzer);
# der Build bricht ab, wenn repository.key einen anderen liefert.
KERNEL_KEY_FPR="BD9DA325AF7BB09149F3AE5E9F391D3802FDE845"
# Ohne den eigenen Kernel (WITH_SURFACE_KERNEL=0) kommt linux-surface
# unverändert von linux-surface, und surface-kmods baut die Treiber als Module.

# --- Surface Laptop 7 --------------------------------------------------------
# Zusatzmodule für den Kernel des ISOs vorab bauen (siehe surface-kmods):
# gepatchtes WLAN-Modul (ohne es ist das WLAN hart gesperrt) sowie die Treiber
# für Touchpad und Touchscreen.
WITH_SL7_KMODS="${WITH_SL7_KMODS:-1}"

# iptsd (Touch-Verarbeitung im Userspace) – ohne es liefern Touchpad und
# Touchscreen des Laptop 7 keine Eingaben, und ohne die Patches von Omarchy
# kommt das Drücken des Touchpads nicht als Klick an. Bezogen aus dem
# Paket-Repository von Omarchy, das iptsd pflegt und neu baut, wenn fmt oder
# spdlog aktualisiert werden (ein selbst gebautes Paket bräche dann). ISO und
# installierte Systeme binden es als letztes Repository ein: Pakete, die es auch
# im Userland-Repository gibt, kommen weiter von dort.
WITH_IPTSD="${WITH_IPTSD:-1}"
OMARCHY_REPO="${OMARCHY_REPO:-https://pkgs.omarchy.org/edge/\$arch}"
# Signaturschlüssel "Omarchy <pkgs@omarchy.org>"; der Build bricht ab, wenn das
# Paket omarchy-keyring einen anderen enthält.
OMARCHY_KEY_FPR="40DFB630FF42BCFFB047046CF0134EE680CAC571"

# --- Kompression -------------------------------------------------------------
# Der linux-surface-Kernel kann SquashFS nur mit xz, lz4, lzo oder zlib lesen (kein zstd).
SQUASHFS_OPTS=(-comp xz -b 1M -Xdict-size 100%)
