#!/bin/bash
# Läuft im Container von scripts/build-kernel.sh: bringt kernel/PKGBUILD auf
# Wunsch auf eine neue linux-surface-Version (KERNEL_TAG, siehe
# scripts/kernel-update.py) und baut es mit makepkg für aarch64
# (Cross-Compile). /project = Repository (nur lesend), /out = Ausgabe,
# /srcdest = Quellen-Cache, /build = Bauordner.
#
# Ergebnis für build-kernel.sh in /out/.update/: status (STATUS, VERSION, ...)
# und bei einer Aktualisierung die geänderten Dateien unter kernel/.
set -euo pipefail

uid="${HOST_UID:-1000}"
gid="${HOST_GID:-1000}"
getent group "$gid" >/dev/null || groupadd -g "$gid" builder
id -u builder >/dev/null 2>&1 || useradd -M -d /build -u "$uid" -g "$gid" builder

rm -rf /build/pkg /build/work /out/.update
install -d -o "$uid" -g "$gid" /build /build/pkg /build/work /out /out/.update
chown "$uid:$gid" /srcdest
cp -a /project/kernel/. /build/pkg/
chown -R "$uid:$gid" /build/pkg

as_builder() { runuser -u builder -- "$@"; }

if [[ -n "${KERNEL_TAG:-}" ]]; then
    upd=(python3 -I /project/scripts/kernel-update.py --dir /build/pkg --tag "$KERNEL_TAG"
         --srcdest /srcdest --status /out/.update/status)
    [[ "${KERNEL_FORCE:-0}" == 1 ]] && upd+=(--force)
    as_builder env GITEA_TOKEN="${GITEA_TOKEN:-}" GITEA_URL="${GITEA_URL:-}" \
        GITEA_OWNER="${GITEA_OWNER:-}" "${upd[@]}"
    if grep -qx 'STATUS=uptodate' /out/.update/status; then
        exit 0
    fi
    install -d /out/.update/kernel
    cp -a /build/pkg/. /out/.update/kernel/
else
    # shellcheck disable=SC1091
    ( cd /build/pkg && set +u && startdir=/build/pkg && source ./PKGBUILD && printf 'STATUS=build\nVERSION=%s-%s\n' "$pkgver" "$pkgrel" ) \
        > /out/.update/status
fi

# makepkg-Konfiguration für das Zielsystem
sed -e 's/^CARCH=.*/CARCH="aarch64"/' \
    -e 's/^CHOST=.*/CHOST="aarch64-unknown-linux-gnu"/' \
    /etc/makepkg.conf > /build/makepkg-aarch64.conf
cat >> /build/makepkg-aarch64.conf <<EOF
MAKEFLAGS="-j$(nproc)"
PKGEXT='.pkg.tar.zst'
COMPRESSZST=(zstd -c -T0 -19 -)
PACKAGER="Arch Linux ARM64 for Surface <https://git.3dns.eu/dom1nic/archlinux_arm64_surface>"
EOF

cd /build/pkg
as_builder env \
    SURFACE_SHARE=/project/airootfs/usr/share/surface \
    SRCDEST=/srcdest PKGDEST=/out BUILDDIR=/build/work \
    makepkg --config /build/makepkg-aarch64.conf -f --noconfirm
chown -R "$uid:$gid" /out
