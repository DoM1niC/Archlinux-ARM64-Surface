#!/usr/bin/env bash
# Erzeugt aus overlays-src/*.dts.in die fertigen Overlays unter
# airootfs/usr/share/surface/overlays/*.dtso.
#
# Die .dts.in-Dateien nutzen Konstanten aus den dt-bindings-Headern des Kernels
# (Takt-IDs, Interconnects, ...). Damit die Overlays überall mit einem
# einfachen dtc übersetzt werden können (auch im installierten System), wird
# der Präprozessor hier einmal laufen gelassen und das Ergebnis eingecheckt.
#
#   scripts/gen-overlays.sh [KERNEL_COMMIT]
#
# KERNEL_COMMIT ist der linux-surface-Kernel-Stand, dessen Header benutzt
# werden (Standard: der des aktuellen aarch64-Pakets).
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."

ref="${1:-}"
if [[ -z "$ref" ]]; then
    ver="$(curl -fsSL https://pkg.surfacelinux.com/arch-aarch64/linux-surface.db \
            | bsdtar -xOf - '*/desc' 2>/dev/null \
            | awk '/%NAME%/{getline n} /%VERSION%/{getline v; if (n=="linux-surface") print v}')"
    ref="$(curl -fsSL "https://raw.githubusercontent.com/linux-surface/aarch64-packages/linux_surface-${ver}/linux-surface/PKGBUILD" \
            | sed -n 's/^_ref_ksource="\(.*\)"/\1/p')"
    [[ -n "$ref" ]] || { echo "Kernel-Stand nicht ermittelbar" >&2; exit 1; }
    echo "linux-surface $ver -> $ref"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git init -q "$tmp/k"
git -C "$tmp/k" remote add origin https://github.com/linux-surface/kernel.git
git -C "$tmp/k" sparse-checkout set include/dt-bindings
git -C "$tmp/k" fetch -q --depth 1 --filter=blob:none origin "$ref"
git -C "$tmp/k" checkout -q FETCH_HEAD

for src in overlays-src/*.dts.in; do
    name="$(basename "$src" .dts.in)"
    out="airootfs/usr/share/surface/overlays/$name.dtso"
    {
        echo "// GENERIERT aus overlays-src/$name.dts.in mit scripts/gen-overlays.sh"
        echo "// (dt-bindings von linux-surface/kernel ${ref:0:12}) – nicht von Hand ändern."
        echo "// Quellen und Erläuterungen stehen in der .dts.in-Datei."
        cpp -nostdinc -undef -x assembler-with-cpp -P -I "$tmp/k/include" "$src"
    } > "$out"
    dtc -q -@ -I dts -O dtb -o /dev/null "$out"
    echo "erzeugt: $out"
done
