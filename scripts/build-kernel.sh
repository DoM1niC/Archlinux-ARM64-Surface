#!/bin/bash
# Baut die Pakete linux-surface und linux-surface-headers (aarch64) mit den
# Treibern für den Surface Laptop 7, siehe kernel/PKGBUILD. Läuft in einem
# x86_64-Docker-Container mit Cross-Compiler, ohne Emulation; auf 16 Kernen
# dauert ein Bau etwa 20 Minuten.
#
#   scripts/build-kernel.sh [Optionen] [upload]
#
#   --latest        vorher auf die neueste linux-surface-Version bringen
#   --tag T         vorher auf linux-surface-Tag T bringen (linux_surface-7.3.2-1)
#   --force         mit --latest/--tag: auch bauen, wenn die Version schon in
#                   der Registry liegt (nächste Revision, z. B. 7.3.1-1.2)
#   upload          Pakete in die Gitea-Paketregistry laden
#   clean           Docker-Volumes (Quellen, Bauordner) löschen
#
# Bei --latest/--tag landen das geänderte PKGBUILD und die Dateien von
# linux-surface in kernel/ (zum Einchecken). Pakete: out/kernel/.
# Upload: GITEA_TOKEN = Zugriffstoken mit Schreibrecht auf Pakete (oder die
# Datei ~/.config/archlinux-arm64-surface/gitea-token);
# GITEA_URL, GITEA_OWNER und KERNEL_REPO_NAME aus config.sh.
# Mit CI=true werden die Dateien in den Container kopiert statt eingebunden
# (Runner, deren Jobs selbst in einem Container laufen).
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

upload=0
tag=""
force=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        upload)   upload=1 ;;
        --latest) tag=latest ;;
        --tag)    tag="${2:?--tag braucht einen Wert}"; shift ;;
        --force)  force=1 ;;
        clean)    docker volume rm -f "$VOL_SRC" "$VOL_BUILD"; exit 0 ;;
        -h|--help|help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "Unbekannte Option: $1 (siehe scripts/build-kernel.sh --help)" ;;
    esac
    shift
done
(( force )) && [[ -z "$tag" ]] && die "--force nur zusammen mit --latest oder --tag."

command -v docker >/dev/null || die "Docker wird benötigt."
docker info >/dev/null 2>&1 || die "Docker läuft nicht oder ist für diesen Benutzer nicht zugänglich."

token_file="${GITEA_TOKEN_FILE:-$HOME/.config/archlinux-arm64-surface/gitea-token}"
if [[ -z "${GITEA_TOKEN:-}" && -r "$token_file" ]]; then
    GITEA_TOKEN="$(tr -d '[:space:]' < "$token_file")"
fi
if (( upload )) && [[ -z "${GITEA_TOKEN:-}" ]]; then
    die "GITEA_TOKEN fehlt (Gitea-Zugriffstoken mit Schreibrecht auf Pakete, oder Datei $token_file)."
fi

msg "Baue Build-Container..."
docker build -q -t "$IMAGE" kernel/ >/dev/null

mkdir -p "$OUT"
env_opts=(-e KERNEL_TAG="$tag" -e KERNEL_FORCE="$force"
          -e GITEA_URL="$GITEA_URL" -e GITEA_OWNER="$GITEA_OWNER")
# Der Token dient im Container nur zum Nachsehen, welche Revisionen es gibt.
[[ -n "${GITEA_TOKEN:-}" ]] && env_opts+=(-e GITEA_TOKEN)
export GITEA_TOKEN="${GITEA_TOKEN:-}"

msg "Baue den Kernel (Cross-Compile für aarch64)..."
if [[ -n "${CI:-}" ]]; then
    cid="$(docker create -v "$VOL_SRC":/srcdest -v "$VOL_BUILD":/build "${env_opts[@]}" \
           "$IMAGE" /project/scripts/kernel-in-container.sh)"
    trap 'docker rm -f "$cid" >/dev/null 2>&1' EXIT
    tar -c --exclude=./out --exclude=./.git . | docker cp - "$cid:/project"
    docker start -a "$cid"
    rm -rf "$OUT/.update"
    docker cp "$cid:/out/." "$OUT/"
else
    docker run --rm \
        -v "$PWD":/project:ro -v "$PWD/$OUT":/out \
        -v "$VOL_SRC":/srcdest -v "$VOL_BUILD":/build \
        -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" "${env_opts[@]}" \
        "$IMAGE" /project/scripts/kernel-in-container.sh
fi

status="$OUT/.update/status"
[[ -r "$status" ]] || die "Kein Ergebnis vom Build-Container."
version="$(sed -n 's/^VERSION=//p' "$status")"
if grep -qx 'STATUS=uptodate' "$status"; then
    msg "linux-surface $version ist bereits gebaut und hochgeladen; nichts zu tun."
    exit 0
fi

if [[ -d "$OUT/.update/kernel" ]]; then
    msg "Übernehme das aktualisierte PKGBUILD nach kernel/"
    cp "$OUT/.update/kernel/"{PKGBUILD,overrides.config,linux-surface.preset,linux-surface.install} kernel/
fi

pkgs=("$OUT/linux-surface-$version-aarch64.pkg.tar.zst"
      "$OUT/linux-surface-headers-$version-aarch64.pkg.tar.zst")
for p in "${pkgs[@]}"; do
    [[ -e "$p" ]] || die "Paket fehlt: $p"
done
msg "Fertig: linux-surface $version"
ls -lh "${pkgs[@]}"

if (( upload )); then
    for p in "${pkgs[@]}"; do
        msg "Lade hoch: $(basename "$p")"
        # Eine vorhandene gleiche Version wird nicht überschrieben (409);
        # dann mit --force eine neue Revision bauen.
        curl -fsS --user "${GITEA_OWNER}:${GITEA_TOKEN}" --upload-file "$p" \
            "${GITEA_URL}/api/packages/${GITEA_OWNER}/arch/${KERNEL_REPO_NAME}"
    done
    msg "Repository: ${KERNEL_REPO}"
fi
