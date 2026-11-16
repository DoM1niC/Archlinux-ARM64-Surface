#!/usr/bin/env bash
# Läuft im Build-Container (siehe ../build.sh). Erzeugt das ISO unter /out.
set -euo pipefail

PROJECT=/project
BUILD=/build
OUT=/out

# shellcheck source=../config.sh
source "$PROJECT/config.sh"

ROOTFS="$BUILD/rootfs"          # Live-Root (aarch64)
PKGROOT="$BUILD/pkgroot"        # Wegwerf-Root zum Bauen der Qualcomm-Pakete
LOCALREPO="$BUILD/localrepo"    # daraus entstehendes lokales pacman-Repo
ISOFS="$BUILD/iso"              # Inhalt des ISO9660-Dateisystems
ESPDIR="$BUILD/esp"             # Inhalt der EFI-Systempartition
DL="$BUILD/downloads"
PACCONF="$BUILD/pacman-aarch64.conf"

msg()  { printf '\033[1;32m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
msg2() { printf '\033[1;34m  ->\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mFEHLER:\033[0m %s\n' "$*" >&2; exit 1; }

umount_below() {
    local m
    while read -r m; do
        [[ -n "$m" ]] && umount -R "$m" 2>/dev/null || true
    done < <(findmnt -rno TARGET | grep -E "^$1(/|$)" | sort -r)
}

cleanup() {
    umount_below "$ROOTFS"
    umount_below "$PKGROOT"
    if [[ -n "${HOST_UID:-}" ]]; then
        chown -R "$HOST_UID:${HOST_GID:-$HOST_UID}" "$OUT" 2>/dev/null || true
    fi
}
trap cleanup EXIT

fetch() { # url ziel
    [[ -s "$2" ]] && return 0
    mkdir -p "$(dirname "$2")"
    curl -fL --retry 3 --retry-delay 5 -sS -o "$2.part" "$1"
    mv "$2.part" "$2"
}

git_checkout() { # repo ref ziel
    if [[ "$(git -C "$3" rev-parse HEAD 2>/dev/null)" != "$2" ]]; then
        rm -rf "$3"
        git init -q "$3"
        git -C "$3" fetch -q --depth 1 "$1" "$2"
        git -C "$3" checkout -q FETCH_HEAD
    fi
}

# ---------------------------------------------------------------------------
# Schlüssel und pacman-Konfiguration für das Zielsystem
# ---------------------------------------------------------------------------
setup_pacman() {
    msg "Richte pacman-Schlüssel ein (Arch Linux ARM, linux-surface)..."

    local kr=/usr/share/pacman/keyrings f
    for f in archlinuxarm.gpg archlinuxarm-trusted archlinuxarm-revoked; do
        curl -fsSL --retry 3 -o "$kr/$f" "$ALARM_KEYRING_URL/$f"
    done
    grep -q "^${ALARM_MASTER_KEY}:" "$kr/archlinuxarm-trusted" \
        || die "Unerwarteter Arch-Linux-ARM-Master-Key im Keyring."

    fetch "$SURFACE_KEY_URL" "$DL/surface.asc"

    pacman-key --init >/dev/null 2>&1
    pacman-key --populate archlinuxarm >/dev/null 2>&1
    pacman-key --add "$DL/surface.asc" >/dev/null 2>&1
    pacman-key --lsign-key "$SURFACE_KEY_ID" >/dev/null 2>&1

    cat > "$PACCONF" <<EOF
[options]
Architecture = aarch64
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional
CacheDir = /var/cache/pacman/pkg-aarch64
ParallelDownloads = 8
DisableSandbox

[core]
Server = $ALARM_MIRROR
[extra]
Server = $ALARM_MIRROR
[alarm]
Server = $ALARM_MIRROR
[aur]
Server = $ALARM_MIRROR

[linux-surface]
Server = $SURFACE_REPO
EOF
}

add_localrepo_to_pacconf() {
    cat >> "$PACCONF" <<EOF

[surface-local]
SigLevel = Optional TrustAll
Server = file://$LOCALREPO
EOF
}

# ---------------------------------------------------------------------------
# Pakete, die Arch Linux ARM nicht hat, als lokales Repo bauen:
#   - Qualcomm-Userspace (WLAN des Surface Pro X)
#   - iptsd (Touchpad/Touchscreen des Surface Laptop 7)
# ---------------------------------------------------------------------------
HAVE_LOCALREPO=0

build_local_packages() {
    [[ "$WITH_QCOM_USERSPACE" == 1 || "$WITH_IPTSD" == 1 ]] || return 0
    HAVE_LOCALREPO=1

    local key="q${WITH_QCOM_USERSPACE}-${QCOM_PKGBUILD_REF:0:12}-i${WITH_IPTSD}-${IPTSD_PKGBUILD_REF:0:12}"
    local stamp="$LOCALREPO/.built-$key"
    if [[ -e "$stamp" ]]; then
        msg "Lokale Pakete sind bereits gebaut."
        add_localrepo_to_pacconf
        return 0
    fi

    msg "Baue lokale Pakete (unter Emulation, das dauert)..."
    umount_below "$PKGROOT"
    rm -rf "$PKGROOT" "$LOCALREPO"
    mkdir -p "$PKGROOT" "$LOCALREPO"
    # Als eigener Einhängepunkt, damit pacman im chroot den freien Platz prüfen kann
    mount --bind "$PKGROOT" "$PKGROOT"

    # Ohne -G: Der Schlüsselbund des Build-Containers wird mitkopiert, damit
    # makepkg im chroot Build-Abhängigkeiten per pacman nachladen kann
    # (pacman-key --init läuft unter Emulation nicht zuverlässig).
    pacstrap -c -M -C "$PACCONF" "$PKGROOT" base base-devel git meson
    mkdir -p "$PKGROOT/home/pkgbuilds" "$PKGROOT/home/pkgout"
    chmod 777 "$PKGROOT/home/pkgout"

    local dirs=()
    if [[ "$WITH_QCOM_USERSPACE" == 1 ]]; then
        git_checkout "$QCOM_PKGBUILD_REPO" "$QCOM_PKGBUILD_REF" "$PKGROOT/home/pkgbuilds/qcom"
        local p
        for p in "${QCOM_PACKAGES[@]}"; do dirs+=("qcom/$p"); done
    fi
    if [[ "$WITH_IPTSD" == 1 ]]; then
        git_checkout "$IPTSD_PKGBUILD_REPO" "$IPTSD_PKGBUILD_REF" "$DL/omarchy-pkgs"
        mkdir -p "$PKGROOT/home/pkgbuilds/omarchy"
        cp -r "$DL/omarchy-pkgs/pkgbuilds/iptsd" "$PKGROOT/home/pkgbuilds/omarchy/iptsd"
        dirs+=("omarchy/iptsd")
    fi

    # pacman lädt im chroot Build-Abhängigkeiten nach; unter qemu-user gibt es
    # kein Landlock, also dessen Sandbox abschalten.
    sed -i '/^\[options\]/a DisableSandbox' "$PKGROOT/etc/pacman.conf"

    cat > "$PKGROOT/root/build.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
ldconfig
useradd -m builder
echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder
chown -R builder /home/pkgbuilds
for p in "$@"; do
    cd "/home/pkgbuilds/$p"
    sudo -u builder env MAKEFLAGS="-j$(nproc)" PKGDEST=/home/pkgout \
        makepkg -si --noconfirm --needed --nocheck
done
EOF
    arch-chroot "$PKGROOT" bash /root/build.sh "${dirs[@]}"

    cp "$PKGROOT"/home/pkgout/*.pkg.tar.* "$LOCALREPO/"
    # qmic wird nur zum Bauen gebraucht
    rm -f "$LOCALREPO"/qmic-*.pkg.tar.* "$LOCALREPO"/*-debug-*.pkg.tar.*
    repo-add -q "$LOCALREPO/surface-local.db.tar.zst" "$LOCALREPO"/*.pkg.tar.*

    umount_below "$PKGROOT"
    rm -rf "$PKGROOT"
    touch "$stamp"
    add_localrepo_to_pacconf
}

# ---------------------------------------------------------------------------
# Zusatzmodule für den Surface Laptop 7 (siehe surface-kmods): gepatchtes
# ath12k sowie die Treiber für Touchpad und Touchscreen
# ---------------------------------------------------------------------------
kernel_release() {
    local ver
    mkdir -p "$BUILD/pacdb"
    pacman --config "$PACCONF" --dbpath "$BUILD/pacdb" -Sy >/dev/null
    ver="$(pacman --config "$PACCONF" --dbpath "$BUILD/pacdb" -Si linux-surface \
            | awk '/^Version/ {print $3; exit}')"
    [[ -n "$ver" ]] || die "Version von linux-surface nicht ermittelbar."
    KERNEL_RELEASE="${ver}-surface"
}

build_kmods() {
    [[ "$WITH_SL7_KMODS" == 1 ]] || return 0

    local srcsum
    srcsum="$( (cat "$PROJECT/airootfs/usr/local/bin/surface-kmods" \
                    "$PROJECT/airootfs/usr/share/surface/patches/ath12k-sl7-rfkill.patch"
                find "$PROJECT/airootfs/usr/share/surface/kmods" -type f | sort | xargs cat) \
               | sha256sum | cut -c1-12)"
    KMOD_CACHE="$BUILD/modcache/${KERNEL_RELEASE}-${srcsum}"

    if [[ -e "$KMOD_CACHE/.done" ]]; then
        msg "Zusatzmodule für $KERNEL_RELEASE sind bereits gebaut."
        return 0
    fi

    msg "Baue Zusatzmodule für $KERNEL_RELEASE..."
    umount_below "$PKGROOT"
    rm -rf "$PKGROOT" "$KMOD_CACHE"
    mkdir -p "$PKGROOT" "$KMOD_CACHE"
    mount --bind "$PKGROOT" "$PKGROOT"
    pacstrap -c -G -M -C "$PACCONF" "$PKGROOT" base base-devel git curl linux-surface-headers >/dev/null

    install -Dm755 "$PROJECT/airootfs/usr/local/bin/surface-kmods" "$PKGROOT/usr/local/bin/surface-kmods"
    install -Dm644 "$PROJECT/airootfs/usr/share/surface/i18n.sh" "$PKGROOT/usr/share/surface/i18n.sh"
    cp -r "$PROJECT/airootfs/usr/share/surface/patches" "$PROJECT/airootfs/usr/share/surface/kmods" \
        "$PKGROOT/usr/share/surface/"
    arch-chroot "$PKGROOT" bash -c "ldconfig; surface-kmods --kernel '$KERNEL_RELEASE'"
    cp "$PKGROOT/usr/lib/modules/$KERNEL_RELEASE/updates"/*.ko "$KMOD_CACHE/"
    touch "$KMOD_CACHE/.done"

    umount_below "$PKGROOT"
    rm -rf "$PKGROOT"
}

# Overlays eines Geräts aus overlays.conf (leer, wenn keine eingetragen sind)
device_overlays() { # id
    awk -F'|' -v id="$1" '$1 == id { print $2 }' "$PROJECT/overlays.conf"
}

# ---------------------------------------------------------------------------
# Live-Root
# ---------------------------------------------------------------------------
build_rootfs() {
    msg "Erzeuge Live-Root (pacstrap, aarch64)..."
    umount_below "$ROOTFS"
    rm -rf "$ROOTFS"
    mkdir -p "$ROOTFS"
    mount --bind "$ROOTFS" "$ROOTFS"

    # Dateien, die vor der Paketinstallation vorhanden sein müssen
    cp -a "$PROJECT/airootfs-pre/." "$ROOTFS/"
    chown -R root:root "$ROOTFS"
    # mkinitcpio nicht während der Installation laufen lassen – das Initramfs
    # wird später gezielt einmal gebaut.
    mkdir -p "$ROOTFS/etc/pacman.d/hooks"
    ln -s /dev/null "$ROOTFS/etc/pacman.d/hooks/90-mkinitcpio-install.hook"

    local pkgs=()
    mapfile -t pkgs < <(grep -vE '^\s*(#|$)' "$PROJECT/packages.txt")
    if [[ "$WITH_QCOM_USERSPACE" == 1 ]]; then
        pkgs+=(qrtr tqftpserv rmtfs-dummy-git)
    fi
    if [[ "$WITH_IPTSD" == 1 ]]; then
        pkgs+=(iptsd)
    fi

    # linux-surface hängt vom Metapaket linux-firmware ab, das auch Firmware
    # für Intel/AMD/Nvidia nachzieht. Im Live-System reichen die Teilpakete.
    pacstrap -c -G -M -C "$PACCONF" "$ROOTFS" "${pkgs[@]}" \
        --assume-installed linux-firmware=99999999 \
        --hookdir "$ROOTFS/etc/pacman.d/hooks"

    rm "$ROOTFS/etc/pacman.d/hooks/90-mkinitcpio-install.hook"

    msg2 "Kopiere Overlay..."
    cp -a "$PROJECT/airootfs/." "$ROOTFS/"
    chown -R root:root "$ROOTFS/etc" "$ROOTFS/usr/local" "$ROOTFS/usr/share/surface"
    install -Dm644 "$PROJECT/devices.conf" "$ROOTFS/usr/share/surface/devices.conf"
    install -Dm644 "$PROJECT/overlays.conf" "$ROOTFS/usr/share/surface/overlays.conf"
    # Overlays vorab übersetzen
    local dtso
    for dtso in "$ROOTFS"/usr/share/surface/overlays/*.dtso; do
        dtc -q -@ -I dts -O dtb -o "${dtso%.dtso}.dtbo" "$dtso"
    done
    install -Dm644 "$DL/surface.asc"       "$ROOTFS/usr/share/surface/surface.asc"
    # Hook auch für das später installierte System bereitstellen
    install -Dm644 "$PROJECT/airootfs-pre/usr/lib/initcpio/install/surface-qcom" \
        "$ROOTFS/usr/share/surface/target/usr/lib/initcpio/install/surface-qcom"

    if [[ "$HAVE_LOCALREPO" == 1 ]]; then
        mkdir -p "$ROOTFS/opt/surface-repo"
        cp "$LOCALREPO"/*.pkg.tar.* "$LOCALREPO"/surface-local.db* "$LOCALREPO"/surface-local.files* \
            "$ROOTFS/opt/surface-repo/"
    fi

    if [[ "$WITH_SPX_FIRMWARE" == 1 ]]; then
        msg2 "Binde Firmware für das Surface Pro X ein..."
        git_checkout "$SPX_FIRMWARE_REPO" "$SPX_FIRMWARE_REF" "$DL/aarch64-firmware"
        # Nur die Pro-X-spezifischen Teile übernehmen; alles andere liefert
        # linux-firmware in aktuellerer Fassung.
        local p
        for p in "${SPX_FIRMWARE_PATHS[@]}"; do
            mkdir -p "$ROOTFS/usr/share/surface/firmware/$(dirname "$p")"
            cp -a "$DL/aarch64-firmware/firmware/$p" "$ROOTFS/usr/share/surface/firmware/$p"
        done
        chown -R root:root "$ROOTFS/usr/share/surface/firmware"
        # Im Live-System direkt nutzbar machen (ohne Duplikat im Image)
        local f
        while IFS= read -r -d '' f; do
            f="${f#./}"
            mkdir -p "$ROOTFS/usr/lib/firmware/$(dirname "$f")"
            ln -sf "/usr/share/surface/firmware/$f" "$ROOTFS/usr/lib/firmware/$f"
        done < <(cd "$ROOTFS/usr/share/surface/firmware" && find . \( -type f -o -type l \) -print0)
    fi

    if [[ "$WITH_SL7_KMODS" == 1 ]]; then
        [[ -d "$ROOTFS/usr/lib/modules/$KERNEL_RELEASE" ]] \
            || die "Kernel im Live-Root passt nicht zu den gebauten Zusatzmodulen ($KERNEL_RELEASE)."
        install -Dm644 -t "$ROOTFS/usr/lib/modules/$KERNEL_RELEASE/updates" "$KMOD_CACHE"/*.ko
    fi

    msg2 "Passe System an (chroot)..."
    install -m755 "$PROJECT/scripts/chroot-customize.sh" "$ROOTFS/root/customize.sh"
    cat > "$ROOTFS/root/embedded.cfg" <<EOF
search --no-floppy --file --set=root /boot/grub/${ISO_UUID}.esp
if [ -z "\$root" -o "\$root" = "memdisk" ]; then
    search --no-floppy --file --set=root /boot/grub/${ISO_UUID}.iso
fi
configfile (\$root)/boot/grub/grub.cfg
EOF
    arch-chroot "$ROOTFS" env \
        LIVE_KEYMAP="$LIVE_KEYMAP" LIVE_FONT="$LIVE_FONT" LIVE_LANG="$LIVE_LANG" \
        LIVE_TIMEZONE="$LIVE_TIMEZONE" LIVE_HOSTNAME="$LIVE_HOSTNAME" \
        WITH_QCOM_USERSPACE="$WITH_QCOM_USERSPACE" HAVE_LOCALREPO="$HAVE_LOCALREPO" \
        SURFACE_REPO="$SURFACE_REPO" \
        /root/customize.sh
    umount_below "$ROOTFS"

    msg2 "Räume auf..."
    mkdir -p "$BUILD/boot"
    rm -rf "$BUILD/boot"/*
    mv "$ROOTFS/root/BOOTAA64.EFI" "$BUILD/boot/"
    cp "$ROOTFS/boot/vmlinuz-linux-surface" "$ROOTFS/boot/initramfs-linux-surface.img" "$BUILD/boot/"
    mkdir -p "$BUILD/boot/dtb/qcom"
    local id name dtb rest
    while IFS='|' read -r id name dtb rest; do
        [[ "$id" =~ ^\s*(#|$) ]] && continue
        cp "$ROOTFS/boot/dtb/linux-surface/qcom/$dtb" "$BUILD/boot/dtb/qcom/" \
            || die "Devicetree $dtb fehlt im Kernelpaket."
        # Zusätze dieses Geräts (Touchpad, Touchscreen, ...) gleich einarbeiten
        local ovl dtbos=()
        for ovl in $(device_overlays "$id"); do
            dtbos+=("$ROOTFS/usr/share/surface/overlays/$ovl.dtbo")
        done
        if [[ ${#dtbos[@]} -gt 0 ]]; then
            fdtoverlay -i "$ROOTFS/boot/dtb/linux-surface/qcom/$dtb" \
                -o "$BUILD/boot/dtb/qcom/$dtb" "${dtbos[@]}" \
                || die "Overlays für $id lassen sich nicht anwenden."
        fi
    done < "$PROJECT/devices.conf"

    rm -f "$ROOTFS/root/customize.sh" "$ROOTFS/root/embedded.cfg"
    rm -f "$ROOTFS"/boot/initramfs-*.img
    rm -rf "$ROOTFS/etc/pacman.d/gnupg" "$ROOTFS"/var/lib/pacman/sync/*
    rm -rf "$ROOTFS"/var/log/* "$ROOTFS"/var/tmp/* "$ROOTFS"/tmp/*
    rm -f "$ROOTFS/etc/machine-id" "$ROOTFS/var/lib/dbus/machine-id"
    : > "$ROOTFS/etc/machine-id"
    ln -sf /run/systemd/resolve/stub-resolv.conf "$ROOTFS/etc/resolv.conf"
}

# ---------------------------------------------------------------------------
# GRUB-Menü
# ---------------------------------------------------------------------------
write_grub_cfg() { # zieldatei
    local id name dtb args compat product sku
    local base="archisobasedir=arch cow_spacesize=50% clk_ignore_unused pd_ignore_unused systemd.tpm2_wait=0"

    {
        cat <<EOF
# Automatisch erzeugt von build-in-container.sh – Geräteliste: devices.conf

insmod gzio

# Sprache und Tastaturbelegung: Vorgabe aus config.sh, im Menü änderbar. Die
# Variablen sind exportiert und überstehen so das Neuladen des Menüs.
if [ -z "\$lang" ]; then set lang="$LIVE_LANG"; fi
if [ -z "\$keymap" ]; then set keymap="$LIVE_KEYMAP"; fi
export lang
export keymap

if [ -n "\$iso_path" ]; then
    # Start aus einer ISO-Datei (Ventoy im GRUB2-Modus, loopback.cfg): Das
    # Live-System bindet die Datei selbst per Loop-Mount ein.
    set loopback_boot=1
    search --no-floppy --set=img_dev --file "\$iso_path"
    probe --set img_dev_uuid --fs-uuid "\$img_dev"
    set iso_args="img_dev=UUID=\$img_dev_uuid img_loop=\$iso_path"
else
    set loopback_boot=""
    set iso_args="archisosearchuuid=${ISO_UUID}"
fi
set base_args="\$iso_args $base surface.lang=\$lang surface.keymap=\$keymap"
set detected=""
set sys_product=""
set sys_sku=""

if [ -n "\$spx_grub" ]; then
    # Über das gepatchte linux-surface-GRUB gestartet (kennt kein smbios/regexp)
    set detected="spx"
else
    insmod smbios
    insmod regexp
    smbios --type 1 --get-string 5 --set sys_product
    smbios --type 1 --get-string 25 --set sys_sku
EOF
        while IFS='|' read -r id name dtb args compat product sku; do
            [[ "$id" =~ ^\s*(#|$) || -z "$product" ]] && continue
            if [[ -n "$sku" ]]; then
                printf '    if regexp -- "%s" "$sys_product"; then if regexp -- "%s" "$sys_sku"; then set detected="%s"; fi; fi\n' \
                    "$product" "$sku" "$id"
            else
                printf '    if regexp -- "%s" "$sys_product"; then set detected="%s"; fi\n' "$product" "$id"
            fi
        done < "$PROJECT/devices.conf"
        cat <<'EOF'
    # Virtuelle Maschine (Rauchtest mit scripts/test-qemu.sh)
    if regexp -- "QEMU|KVM Virtual Machine" "$sys_product"; then set detected="generic"; fi
fi

if [ -n "$detected" ]; then
    set default="$detected"
    set timeout=15
else
    set default="hint"
    set timeout=-1
fi

# Texte des Menüs
if [ "$lang" = "en" ]; then
    set t_lang="Language: English   (Enter: auf Deutsch umschalten)"
    set t_kbd="Keyboard layout"
    set t_hint="Please select your device (firmware reports"
    set t_generic="generic, no devicetree (ACPI; e.g. QEMU/VM)"
    set t_spxgrub="Surface Pro X: load the patched linux-surface GRUB (if booting hangs)"
    set t_shell="UEFI shell"
    set t_fwsetup="UEFI firmware settings"
    set t_reboot="Reboot"
    set t_poweroff="Power off"
    set t_kernel="Loading kernel..."
    set t_dtb="Loading devicetree"
    set t_initrd="Loading initramfs..."
    set t_start="Starting..."
else
    set t_lang="Sprache: Deutsch   (Enter: switch to English)"
    set t_kbd="Tastaturbelegung"
    set t_hint="Bitte das passende Gerät wählen (Firmware meldet"
    set t_generic="generisch, ohne Devicetree (ACPI; z. B. QEMU/VM)"
    set t_spxgrub="Surface Pro X: gepatchtes linux-surface-GRUB laden (falls der Start hängt)"
    set t_shell="UEFI-Shell"
    set t_fwsetup="UEFI-Firmware-Einstellungen"
    set t_reboot="Neu starten"
    set t_poweroff="Ausschalten"
    set t_kernel="Lade Kernel..."
    set t_dtb="Lade Devicetree"
    set t_initrd="Lade Initramfs..."
    set t_start="Starte..."
fi

menuentry "$t_lang" --id lang {
    if [ "$lang" = "en" ]; then set lang="de"; else set lang="en"; fi
    export lang
    configfile /boot/grub/grub.cfg
}

submenu "$t_kbd: $keymap" --id kbd {
EOF
        local km label
        while IFS='|' read -r km label; do
            [[ "$km" =~ ^\s*(#|$) ]] && continue
            cat <<EOF
    menuentry "$km  ($label)" {
        set keymap="$km"
        export keymap
        configfile /boot/grub/grub.cfg
    }
EOF
        done < "$PROJECT/keymaps.conf"
        cat <<'EOF'
}

menuentry "$t_hint: '$sys_product' / '$sys_sku')" --id hint {
    true
}

EOF
        while IFS='|' read -r id name dtb args compat product sku; do
            [[ "$id" =~ ^\s*(#|$) ]] && continue
            name="${name//\"/\\\"}"   # Anführungszeichen (Zoll) für GRUB maskieren
            cat <<EOF
menuentry "Arch Linux ARM – $name" --id $id {
    echo "\$t_kernel"
    linux /boot/vmlinuz-linux-surface \$base_args $args
    echo "\$t_dtb $dtb..."
    devicetree /boot/dtb/qcom/$dtb
    echo "\$t_initrd"
    initrd /boot/initramfs-linux-surface.img
    echo "\$t_start"
}

EOF
        done < "$PROJECT/devices.conf"
        cat <<'EOF'
menuentry "Arch Linux ARM – $t_generic" --id generic {
    linux /boot/vmlinuz-linux-surface $base_args console=tty0 console=ttyAMA0
    initrd /boot/initramfs-linux-surface.img
}

EOF
        if [[ "$WITH_SPX_GRUB" == 1 ]]; then
            cat <<'EOF'
if [ -z "$spx_grub" -a -z "$loopback_boot" ]; then
    menuentry "$t_spxgrub" --id spxgrub {
        chainloader /EFI/spx/bootaa64.efi
    }
fi

EOF
        fi
        cat <<'EOF'
if [ -z "$loopback_boot" ]; then
    menuentry "$t_shell" --id shell {
        chainloader /EFI/tools/shellaa64.efi
    }
fi

menuentry "$t_fwsetup" --id fwsetup {
    fwsetup
}

menuentry "$t_reboot" --id reboot {
    reboot
}

menuentry "$t_poweroff" --id poweroff {
    halt
}
EOF
    } > "$1"
}

# ---------------------------------------------------------------------------
# ISO zusammenbauen
# ---------------------------------------------------------------------------
build_iso() {
    msg "Erzeuge SquashFS..."
    rm -rf "$ISOFS" "$ESPDIR"
    mkdir -p "$ISOFS/arch/aarch64" "$ESPDIR"

    pacman --config "$PACCONF" -r "$ROOTFS" -Q > "$ISOFS/arch/pkglist.aarch64.txt"

    mksquashfs "$ROOTFS" "$ISOFS/arch/aarch64/airootfs.sfs" -noappend -quiet -no-progress \
        "${SQUASHFS_OPTS[@]}" -wildcards -e 'boot/*' 'var/cache/pacman/pkg/*'
    (cd "$ISOFS/arch/aarch64" && sha512sum airootfs.sfs > airootfs.sha512)

    msg "Erzeuge Boot-Dateien und EFI-Systempartition..."
    # Baum der EFI-Systempartition (wird zusätzlich ins ISO9660 gespiegelt)
    mkdir -p "$ESPDIR/EFI/BOOT" "$ESPDIR/EFI/tools" "$ESPDIR/boot/grub"
    cp "$BUILD/boot/BOOTAA64.EFI" "$ESPDIR/EFI/BOOT/BOOTAA64.EFI"
    cp "$BUILD/boot/vmlinuz-linux-surface" "$BUILD/boot/initramfs-linux-surface.img" "$ESPDIR/boot/"
    cp -r "$BUILD/boot/dtb" "$ESPDIR/boot/"
    cp /usr/share/edk2-shell/aarch64/Shell.efi "$ESPDIR/EFI/tools/shellaa64.efi"
    write_grub_cfg "$ESPDIR/boot/grub/grub.cfg"
    # Einstieg für das Starten aus einer ISO-Datei (Ventoy-GRUB2-Modus u. a.);
    # der aufrufende Bootloader setzt \$iso_path und \$root.
    echo 'source /boot/grub/grub.cfg' > "$ESPDIR/boot/grub/loopback.cfg"
    # Syntax des Menüs mit dem GRUB des Zielsystems prüfen
    cp "$ESPDIR/boot/grub/grub.cfg" "$ROOTFS/tmp/grub-check.cfg"
    chroot "$ROOTFS" grub-script-check /tmp/grub-check.cfg \
        || die "Das erzeugte GRUB-Menü enthält Syntaxfehler."
    rm -f "$ROOTFS/tmp/grub-check.cfg"

    if [[ "$WITH_SPX_GRUB" == 1 ]]; then
        fetch "$SPX_GRUB_URL" "$DL/spx-bootaa64.efi"
        mkdir -p "$ESPDIR/EFI/spx"
        cp "$DL/spx-bootaa64.efi" "$ESPDIR/EFI/spx/bootaa64.efi"
        cat > "$ESPDIR/EFI/spx/grub.cfg" <<EOF
search --no-floppy --file --set=root /boot/grub/${ISO_UUID}.esp
set spx_grub=1
export spx_grub
configfile /boot/grub/grub.cfg
EOF
    fi

    cp -r "$ESPDIR/." "$ISOFS/"
    touch "$ESPDIR/boot/grub/${ISO_UUID}.esp" "$ISOFS/boot/grub/${ISO_UUID}.iso"

    local kib
    kib=$(du -sk --apparent-size "$ESPDIR" | cut -f1)
    kib=$(( (kib * 105 / 100 + 16384 + 1023) / 1024 * 1024 ))
    rm -f "$BUILD/efiboot.img"
    mkfs.fat -C -F 32 -n ARCHSURFEFI "$BUILD/efiboot.img" "$kib" >/dev/null
    mcopy -s -i "$BUILD/efiboot.img" "$ESPDIR"/* ::/

    msg "Erzeuge ISO..."
    local iso="$OUT/${ISO_NAME}-${ISO_VERSION}-aarch64.iso"
    rm -f "$iso"
    xorriso -no_rc -as mkisofs \
        -iso-level 3 -full-iso9660-filenames -joliet -joliet-long -rational-rock \
        -volid "$ISO_LABEL" \
        -appid "Arch Linux ARM Live/Install für Snapdragon-Surface" \
        -publisher "lokaler Build" \
        -preparer "xorriso" \
        --modification-date="${ISO_UUID//-/}" \
        -partition_offset 16 \
        -append_partition 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B "$BUILD/efiboot.img" \
        -appended_part_as_gpt \
        -eltorito-alt-boot \
        -e --interval:appended_partition_2:all:: \
        -no-emul-boot \
        -output "$iso" \
        "$ISOFS/"

    (cd "$OUT" && sha256sum "$(basename "$iso")" > "$(basename "$iso").sha256")
    msg "Fertig: out/$(basename "$iso") ($(du -h "$iso" | cut -f1))"
}

# ---------------------------------------------------------------------------
mkdir -p "$BUILD" "$DL" "$OUT"

: "${SOURCE_DATE_EPOCH:=$(date +%s)}"
ISO_VERSION="$(date -u -d "@$SOURCE_DATE_EPOCH" +%Y.%m.%d)"
ISO_UUID="$(date -u -d "@$SOURCE_DATE_EPOCH" +%F-%H-%M-%S-00)"

setup_pacman
build_local_packages
kernel_release
build_kmods
build_rootfs
build_iso
