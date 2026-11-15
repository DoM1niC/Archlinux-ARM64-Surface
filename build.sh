#!/usr/bin/env bash
# Baut das Arch-Linux-ARM64-ISO für Snapdragon-Surface-Geräte.
#
#   ./build.sh            ISO bauen (Zwischenstände werden wiederverwendet)
#   ./build.sh clean      Zwischenstände (Docker-Volumes) löschen
#   ./build.sh shell      Shell im Build-Container öffnen
#
# Voraussetzung: Docker. Auf x86_64-Hosts wird aarch64-Emulation über
# binfmt_misc benötigt; fehlt sie, wird sie über das Image tonistiigi/binfmt
# registriert (gilt bis zum nächsten Neustart des Hosts).
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

IMAGE="surface-archiso-builder"
VOL_WORK="surface-archiso-work"
VOL_CACHE="surface-archiso-pkgcache"

msg() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mFEHLER:\033[0m %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null || die "Docker wird benötigt."

case "${1:-}" in
    ""|clean|shell) ;;
    -h|--help|help)
        sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
        echo
        echo "Einstellungen (Tastatur, Zeitzone, Pro-X-Firmware, ...): siehe config.sh,"
        echo "z. B.  LIVE_KEYMAP=us LIVE_TIMEZONE=UTC ./build.sh"
        exit 0 ;;
    *) die "Unbekannter Befehl: $1 (siehe ./build.sh --help)" ;;
esac

if ! docker info >/dev/null 2>&1; then
    die "Docker läuft nicht oder ist für diesen Benutzer nicht zugänglich."
fi

if [[ "${1:-}" == clean ]]; then
    docker volume rm -f "$VOL_WORK" "$VOL_CACHE"
    exit 0
fi

ensure_binfmt() {
    [[ "$(uname -m)" == aarch64 ]] && return 0
    if docker run --rm --platform linux/arm64 alpine:latest true 2>/dev/null; then
        return 0
    fi
    msg "Registriere aarch64-Emulation (binfmt_misc, bis zum nächsten Neustart)..."
    docker run --privileged --rm tonistiigi/binfmt --install arm64 >/dev/null
    docker run --rm --platform linux/arm64 alpine:latest true \
        || die "aarch64-Emulation funktioniert nicht."
}

ensure_binfmt

msg "Baue Build-Container..."
docker build -q -t "$IMAGE" . >/dev/null

mkdir -p out

run=(docker run --rm --privileged
     -v "$PWD":/project:ro
     -v "$PWD/out":/out
     -v "$VOL_WORK":/build
     -v "$VOL_CACHE":/var/cache/pacman/pkg-aarch64
     -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)")

# Konfigurations-Overrides aus der Umgebung durchreichen
for v in ISO_NAME ISO_LABEL ALARM_MIRROR SURFACE_REPO LIVE_KEYMAP LIVE_FONT \
         LIVE_TIMEZONE LIVE_HOSTNAME WITH_SPX_FIRMWARE WITH_QCOM_USERSPACE \
         WITH_SPX_GRUB REBUILD; do
    [[ -v $v ]] && run+=(-e "$v=${!v}")
done

if [[ "${1:-}" == shell ]]; then
    exec "${run[@]}" -it "$IMAGE" bash
fi

"${run[@]}" "$IMAGE" /project/scripts/build-in-container.sh

iso="$(ls -t out/*.iso | head -n1)"
cat <<EOF

Nächste Schritte:
  * Ventoy:    $iso auf den Ventoy-Stick kopieren
  * oder dd:   sudo dd if=$iso of=/dev/sdX bs=4M conv=fsync status=progress
  * Testen:    scripts/test-qemu.sh
EOF
