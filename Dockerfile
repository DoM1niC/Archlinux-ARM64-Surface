# Build-Umgebung (x86_64). Das aarch64-Zielsystem wird per pacstrap erzeugt;
# Paket-Hooks im Ziel laufen über binfmt_misc/qemu-user (siehe build.sh).
FROM archlinux:latest

RUN pacman -Syu --noconfirm --needed \
        arch-install-scripts squashfs-tools libisoburn mtools dosfstools \
        git curl zstd libarchive edk2-shell \
    && pacman -Scc --noconfirm

WORKDIR /project
