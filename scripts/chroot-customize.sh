#!/bin/bash
# Läuft per arch-chroot im aarch64-Live-Root (unter Emulation).
set -euo pipefail

ldconfig

# --- Sprache, Tastatur, Zeit -------------------------------------------------
sed -i -E 's/^#(en_US\.UTF-8 UTF-8)/\1/; s/^#(de_DE\.UTF-8 UTF-8)/\1/' /etc/locale.gen
locale-gen >/dev/null
install -d /etc/surface
if [[ "$LIVE_LANG" == en ]]; then
    echo en > /etc/surface/lang
    echo 'LANG=en_US.UTF-8' > /etc/locale.conf
else
    echo de > /etc/surface/lang
    echo 'LANG=de_DE.UTF-8' > /etc/locale.conf
fi
printf 'KEYMAP=%s\nFONT=%s\n' "$LIVE_KEYMAP" "$LIVE_FONT" > /etc/vconsole.conf
ln -sf "/usr/share/zoneinfo/$LIVE_TIMEZONE" /etc/localtime
echo "$LIVE_HOSTNAME" > /etc/hostname

# --- pacman ------------------------------------------------------------------
cat >> /etc/pacman.conf <<PACEOF

# Kernel für Snapdragon-Surface-Geräte
[linux-surface]
Server = $SURFACE_REPO
PACEOF
if [[ "$WITH_QCOM_USERSPACE" == 1 ]]; then
    cat >> /etc/pacman.conf <<'PACEOF'

# Lokal gebaute Qualcomm-Userspace-Pakete (Surface Pro X)
[surface-local]
SigLevel = Optional TrustAll
Server = file:///opt/surface-repo
PACEOF
fi

# --- Dienste -----------------------------------------------------------------
systemctl enable systemd-networkd.service systemd-resolved.service \
    systemd-timesyncd.service iwd.service pacman-init.service \
    surface-locale.service >/dev/null
if [[ "$WITH_QCOM_USERSPACE" == 1 ]]; then
    systemctl enable tqftpserv.service rmtfs.service >/dev/null
fi
systemctl set-default multi-user.target >/dev/null
passwd -d root >/dev/null

# --- Kernel und Initramfs ----------------------------------------------------
kver="$(basename "$(dirname "$(ls /usr/lib/modules/*/vmlinuz)")")"
depmod "$kver"
install -Dm644 "/usr/lib/modules/$kver/vmlinuz" /boot/vmlinuz-linux-surface
# Preset ohne Fallback-Image
sed -i "s/^PRESETS=.*/PRESETS=('default')/" /etc/mkinitcpio.d/linux-surface.preset
mkinitcpio -k "$kver" -g /boot/initramfs-linux-surface.img

# --- Bootloader für das ISO --------------------------------------------------
grub-mkstandalone -O arm64-efi -o /root/BOOTAA64.EFI \
    --locales="" --fonts="" --themes="" \
    --modules="part_gpt part_msdos fat iso9660 search search_fs_file configfile normal linux fdt gzio chain echo test regexp smbios sleep reboot halt" \
    "boot/grub/grub.cfg=/root/embedded.cfg"
