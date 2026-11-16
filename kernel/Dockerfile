# Build-Umgebung für den Kernel (x86_64, Cross-Compiler für aarch64).
# Siehe scripts/build-kernel.sh.
FROM archlinux:latest

RUN pacman -Syu --noconfirm --needed \
        base-devel aarch64-linux-gnu-gcc bc cpio kmod inetutils dtc python perl \
        flex bison openssl libelf git zstd \
    && pacman -Scc --noconfirm
