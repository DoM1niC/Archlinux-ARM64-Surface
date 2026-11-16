#!/bin/bash
# Läuft im Container von scripts/build-kernel.sh: baut kernel/PKGBUILD mit
# makepkg für aarch64 (Cross-Compile). /project = Repository (nur lesend),
# /out = Ausgabe, /srcdest = Quellen-Cache, /build = Bauordner.
set -euo pipefail

uid="${HOST_UID:-1000}"
gid="${HOST_GID:-1000}"
getent group "$gid" >/dev/null || groupadd -g "$gid" builder
id -u builder >/dev/null 2>&1 || useradd -M -d /build -u "$uid" -g "$gid" builder

rm -rf /build/pkg /build/work
install -d -o "$uid" -g "$gid" /build /build/pkg /build/work
chown "$uid:$gid" /srcdest
cp -a /project/kernel/. /build/pkg/
chown -R "$uid:$gid" /build/pkg

# makepkg-Konfiguration für das Zielsystem
sed -e 's/^CARCH=.*/CARCH="aarch64"/' \
    -e 's/^CHOST=.*/CHOST="aarch64-unknown-linux-gnu"/' \
    /etc/makepkg.conf > /build/makepkg-aarch64.conf
cat >> /build/makepkg-aarch64.conf <<EOF
MAKEFLAGS="-j$(nproc)"
PKGEXT='.pkg.tar.zst'
COMPRESSZST=(zstd -c -T0 -19 -)
PACKAGER="Arch Linux ARM for Surface <https://git.3dns.eu/dom1nic/archlinux_arm64_surface>"
EOF

cd /build/pkg
runuser -u builder -- env \
    SURFACE_SHARE=/project/airootfs/usr/share/surface \
    SRCDEST=/srcdest PKGDEST=/out BUILDDIR=/build/work \
    makepkg --config /build/makepkg-aarch64.conf -f --noconfirm
