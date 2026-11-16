#!/bin/bash
# Baut die Pakete linux-surface und linux-surface-headers (aarch64) mit den
# Treibern für den Surface Laptop 7, siehe kernel/PKGBUILD. Läuft in einem
# x86_64-Docker-Container mit Cross-Compiler, ohne Emulation; auf 16 Kernen
# dauert ein Bau etwa eine halbe Stunde.
#
#   scripts/build-kernel.sh            bauen, Pakete landen in out/kernel/
#   scripts/build-kernel.sh upload     zusätzlich in die Gitea-Paketregistry
#                                      laden (GITEA_TOKEN, siehe unten)
#   scripts/build-kernel.sh clean      Docker-Volumes (Quellen, Bauordner) löschen
#
# Upload: GITEA_TOKEN = Zugriffstoken mit Schreibrecht auf Pakete (oder die
# Datei ~/.config/archlinux-arm64-surface/gitea-token);
# GITEA_URL, GITEA_OWNER und KERNEL_REPO_NAME aus config.sh.
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")/.."
# shellcheck source=../config.sh
source ./config.sh

IMAGE="surface-kernel-builder"
VOL_SRC="surface-kernel-src"
VOL_BUILD="surface-kernel-build"
OUT="out/kernel"

msg() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mFEHLER:\033[0m %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null || die "Docker wird benötigt."
docker info >/dev/null 2>&1 || die "Docker läuft nicht oder ist für diesen Benutzer nicht zugänglich."

upload=0
case "${1:-}" in
    "") ;;
    upload) upload=1 ;;
    clean) docker volume rm -f "$VOL_SRC" "$VOL_BUILD"; exit 0 ;;
    -h|--help|help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "Unbekannter Befehl: $1 (siehe scripts/build-kernel.sh --help)" ;;
esac

if (( upload )); then
    token_file="${GITEA_TOKEN_FILE:-$HOME/.config/archlinux-arm64-surface/gitea-token}"
    if [[ -z "${GITEA_TOKEN:-}" && -r "$token_file" ]]; then
        GITEA_TOKEN="$(tr -d '[:space:]' < "$token_file")"
    fi
    [[ -n "${GITEA_TOKEN:-}" ]] \
        || die "GITEA_TOKEN fehlt (Gitea-Zugriffstoken mit Schreibrecht auf Pakete, oder Datei $token_file)."
fi

msg "Baue Build-Container..."
docker build -q -t "$IMAGE" kernel/ >/dev/null

mkdir -p "$OUT"
msg "Baue den Kernel (Cross-Compile für aarch64)..."
docker run --rm \
    -v "$PWD":/project:ro -v "$PWD/$OUT":/out \
    -v "$VOL_SRC":/srcdest -v "$VOL_BUILD":/build \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    "$IMAGE" /project/scripts/kernel-in-container.sh

pkgs=()
mapfile -t pkgs < <(ls -t "$OUT"/linux-surface-*.pkg.tar.zst | head -n 2)
[[ ${#pkgs[@]} -eq 2 ]] || die "Pakete nicht gefunden in $OUT"
msg "Fertig:"
ls -lh "${pkgs[@]}"

if (( upload )); then
    for p in "${pkgs[@]}"; do
        msg "Lade hoch: $(basename "$p")"
        # Eine vorhandene gleiche Version wird nicht überschrieben (409);
        # dann vorher die Revision (pkgrel) erhöhen.
        curl -fsS --user "${GITEA_OWNER}:${GITEA_TOKEN}" --upload-file "$p" \
            "${GITEA_URL}/api/packages/${GITEA_OWNER}/arch/${KERNEL_REPO_NAME}"
    done
    msg "Repository: ${KERNEL_REPO}"
fi
