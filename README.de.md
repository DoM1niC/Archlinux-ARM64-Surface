# Arch Linux ARM64 für Snapdragon-Surface-Geräte

[English](README.md) | **Deutsch**

Baut ein bootfähiges Live-/Installations-ISO (aarch64, UEFI) mit

- **Userland** aus [Arch Linux ARM](https://archlinuxarm.org),
- **Kernel** `linux-surface` aus dem aarch64-Paket-Repository von
  [linux-surface](https://github.com/linux-surface) (enthält die Devicetrees
  und Treiber für die Snapdragon-Surfaces),
- **Firmware** aus `linux-firmware` (Qualcomm, Atheros, …), der Pro-X-Firmware
  von linux-surface sowie einem Werkzeug, das die gerätespezifische Firmware
  aus der Windows-Installation des Geräts übernimmt,
- einem **GRUB-Bootmenü**, das für jedes Gerät den passenden Devicetree lädt,
- einem **Installer** (`surface-install`), der das System samt Bootloader und
  Devicetree auf die interne SSD bringt.

## Unterstützte Geräte

| ID          | Gerät                               | SoC       | Devicetree                           |
|-------------|-------------------------------------|-----------|--------------------------------------|
| `spx`       | Surface Pro X (SQ1/SQ2)             | SC8180X   | `sc8180x-surface-pro-x.dtb`          |
| `sp9-5g`    | Surface Pro 9 5G (SQ3)              | SC8280XP  | `sc8280xp-microsoft-arcata.dtb`      |
| `devkit`    | Windows Dev Kit 2023                | SC8280XP  | `sc8280xp-microsoft-blackrock.dtb`   |
| `sl7-13`    | Surface Laptop 7 13,8"              | X1E80100  | `x1e80100-microsoft-romulus13.dtb`   |
| `sl7-15`    | Surface Laptop 7 15"                | X1E80100  | `x1e80100-microsoft-romulus15.dtb`   |
| `sp11-lcd`  | Surface Pro 11 (LCD, X Plus)        | X1P64100  | `x1p64100-microsoft-denali.dtb`      |
| `sp11-oled` | Surface Pro 11 (OLED, X Elite)      | X1E80100  | `x1e80100-microsoft-denali-oled.dtb` |
| `sp12`      | Surface Pro 12" (2025, X Plus)      | X1P42100  | `x1p42100-microsoft-sp12in.dtb`      |

Die Liste steht in [`devices.conf`](devices.conf) und entspricht den
Devicetrees, die der linux-surface-Kernel mitbringt.

### Hardware-Unterstützung

Die Tabelle zeigt, welche Hardware der linux-surface-Kernel (7.3.1) im
Devicetree des jeweiligen Geräts beschreibt. Sie ist aus den Kernel-Quellen
abgelesen, **nicht auf Hardware getestet**: „✓“ heißt „Treiber ist
vorgesehen“, nicht „funktioniert garantiert“. Den tatsächlichen Stand zeigen
das Wiki und die Issues von linux-surface.

| Funktion | Pro X (SQ1/SQ2) | Pro 9 5G | Dev Kit 2023 | Laptop 7 (13,8"/15") | Pro 11 (LCD/OLED) | Pro 12" |
|---|---|---|---|---|---|---|
| Internes Display | ✓ | ✓ | – (kein Display) | ✓ | ✓ | ✓ |
| GPU-Beschleunigung | ✓ (FW) | ✓ (FW) | ✓ (FW) | ✓ (FW) | ✓ (FW) | ✓ (FW) |
| Interner Speicher | ✓ NVMe | ✓ NVMe | ✓ NVMe | ✓ NVMe | ✓ NVMe | ✓ UFS |
| USB-C / USB | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Externer Monitor über USB-C | – | ✓ | ✓ | ✓ | ✓ | ✓ |
| WLAN | ✓ (WCN3990) | ✓ (WCN6855) | ✓ (WCN6855) | ✓ (WCN7850) | ✓ (WCN7850) | ✓ (WCN7850) |
| Bluetooth | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Ton | – | ✓ (FW) | ✓ (FW) | ✓ (FW) | ✓ (FW) | ✓ (FW) |
| Tastatur/Touchpad, Akku (Surface Aggregator) | ✓ | ✓ | – (USB-Geräte) | ✓ | ✓ | ✓ |
| Touchscreen | – | – | – | – | – | ✓ |
| Kameras | – | – | – | – | – | – |
| Mobilfunk (LTE/5G) | – | – | – | – | – | – |

- **✓**: im Devicetree beschrieben, Treiber im Kernel vorhanden.
- **(FW)**: braucht zusätzlich die signierte Firmware aus Windows
  (`surface-fw-extract`, siehe unten). Beim Pro X ist sie schon im ISO.
- **–**: im Devicetree nicht beschrieben, also nach aktuellem Stand ohne
  Funktion.

Stift und Fingerabdruckleser/Windows Hello sind nicht einzeln geprüft. Beim
Pro X läuft das WLAN nur mit den Zusatzdiensten `tqftpserv` und `rmtfs`; sie
sind im ISO enthalten und werden vom Installer mit eingerichtet.

## Bauen

Voraussetzung ist nur **Docker**. Auf einem x86_64-Host wird das aarch64-System
per Emulation (`binfmt_misc` + qemu-user) erzeugt; fehlt die Registrierung,
richtet `build.sh` sie über das Image `tonistiigi/binfmt` ein (gilt bis zum
nächsten Neustart des Hosts).

```sh
./build.sh            # ISO bauen -> out/archlinux-arm64-surface-<Datum>-aarch64.iso
./build.sh clean      # Zwischenstände (Docker-Volumes) löschen
./build.sh shell      # Shell im Build-Container
```

Einstellungen stehen in [`config.sh`](config.sh) und lassen sich per Umgebung
überschreiben, z. B. `LIVE_LANG=en LIVE_KEYMAP=us ./build.sh`. Die Pakete des Live-Systems
stehen in [`packages.txt`](packages.txt).

Rauchtest in QEMU (ohne Surface-Hardware, generischer Booteintrag):

```sh
scripts/test-qemu.sh          # serielle Konsole, beenden mit Strg+A, X
```

## Auf den USB-Stick bringen

### Ventoy

Die ISO-Datei einfach auf den Ventoy-Stick kopieren und im Ventoy-Menü
auswählen („Boot in normal mode“). Das Live-System sucht die ISO-Datei beim
Start selbst auf dem Stick (Initramfs-Hook `surface_isoscan`, Dateisysteme
exFAT/NTFS/FAT/ext4, bis drei Verzeichnisebenen tief) und bindet sie per
Loop-Mount ein. Alternativ funktioniert Ventoys „GRUB2 mode“ über die
mitgelieferte `boot/grub/loopback.cfg`.

Ventoy muss dafür selbst auf dem Gerät starten können (ARM64-UEFI, Secure Boot
aus). Falls nicht: das ISO direkt auf einen Stick schreiben.

### Direkt schreiben (dd)

```sh
sudo dd if=out/archlinux-arm64-surface-<Datum>-aarch64.iso of=/dev/sdX bs=4M conv=fsync status=progress
```

(`/dev/sdX` = der Stick, **nicht** eine Partition. Alle Daten darauf gehen
verloren.)

## Starten

1. Unter Windows: BitLocker/Geräteverschlüsselung ggf. abschalten oder den
   Wiederherstellungsschlüssel bereithalten, „Schnellstart“ deaktivieren und
   die Windows-Partition verkleinern, um Platz für Linux zu schaffen.
2. Surface-UEFI öffnen (Gerät aus, **Lauter** gedrückt halten, Power drücken):
   - *Security → Secure Boot*: **ausschalten**,
   - *Boot configuration*: USB-Start erlauben und nach oben schieben.
3. Vom Stick starten (Gerät aus, **Leiser** gedrückt halten, Power drücken).
4. Im Bootmenü das Gerät wählen. Wird das Gerät über die Firmware-Angaben
   erkannt, ist der passende Eintrag vorausgewählt; diese Erkennung ist nur
   eine Hilfe – ein falscher Devicetree startet nicht oder ohne Bild.

Die ersten beiden Einträge des Bootmenüs stellen **Sprache** (Deutsch/Englisch)
und **Tastaturbelegung** um. Beides gilt für das Live-System und wird von
`surface-install` ins installierte System übernommen. Später ändern:

```sh
surface-locale --lang en --keymap us   # oder: --lang de --keymap de-latin1
surface-locale --list-keymaps
```

Welche Belegungen das Bootmenü anbietet, steht in
[`keymaps.conf`](keymaps.conf); die Vorgaben sind `LIVE_LANG` und `LIVE_KEYMAP`
in `config.sh`.

Das Live-System meldet sich automatisch als `root` an.

## Installieren

```sh
surface-device                      # erkanntes Gerät anzeigen
iwctl station wlan0 connect <SSID>  # WLAN (oder USB-Ethernet/-Tethering)

# Partitionieren und formatieren (Beispiel: freier Platz hinter Windows)
cfdisk /dev/nvme0n1
mkfs.ext4 /dev/nvme0n1pN

mount /dev/nvme0n1pN /mnt
mount --mkdir /dev/nvme0n1p1 /mnt/efi   # vorhandene EFI-Systempartition

surface-install /mnt
```

`surface-install`

- installiert `base`, `linux-surface`, `linux-firmware`, GRUB u. a. per `pacstrap`,
- trägt das linux-surface-Repository in `/etc/pacman.conf` ein (Kernel-Updates
  kommen danach ganz normal über `pacman -Syu`),
- richtet ein Initramfs mit allen nötigen Plattformtreibern ein
  (Hook `surface-qcom`, eingetragen in `/etc/mkinitcpio.conf`),
- übernimmt die gerätespezifische Firmware aus Windows (`surface-fw-extract`),
- installiert GRUB und erzeugt über `/etc/grub.d/09_surface` einen Eintrag mit
  dem Devicetree des Geräts (`/etc/default/surface-boot`). `grub-mkconfig`
  funktioniert danach wie gewohnt.

Partitionieren, Formatieren und Einhängen macht das Skript bewusst nicht
selbst.

### Firmware

Die DSP- und GPU-Firmware der Geräte ist von Microsoft/Qualcomm signiert und
nicht frei verteilbar. `surface-fw-extract` liest aus dem Devicetree, welche
Dateien der Kernel erwartet, sucht sie im Treiberspeicher der
Windows-Installation (BitLocker-Partitionen werden mit dem
Wiederherstellungsschlüssel über `cryptsetup` geöffnet) und legt sie unter
`/usr/lib/firmware` ab:

```sh
surface-fw-extract --list           # was wird gebraucht, was fehlt?
surface-fw-extract --root /mnt      # ins Live- und ins installierte System
```

Ohne diese Dateien startet das System trotzdem, es fehlen dann aber z. B.
GPU-Beschleunigung, Ton und Akkuanzeige.

Für das **Surface Pro X** ist die Firmware aus
[linux-surface/aarch64-firmware](https://github.com/linux-surface/aarch64-firmware)
bereits im ISO enthalten (`WITH_SPX_FIRMWARE=1`). Dafür gibt es keine
ausdrückliche Weitergabe-Lizenz – das ISO deshalb nicht öffentlich verteilen
oder mit `WITH_SPX_FIRMWARE=0` bauen.

## Aufbau

```
build.sh                      Einstieg auf dem Host (Docker, binfmt)
config.sh                     Einstellungen
devices.conf                  Geräte, Devicetrees, Kernel-Parameter
keymaps.conf                  Tastaturbelegungen im Bootmenü
packages.txt                  Pakete des Live-Systems
scripts/build-in-container.sh eigentlicher Build (pacstrap, SquashFS, GRUB, xorriso)
scripts/chroot-customize.sh   Anpassungen im aarch64-Root (Initramfs, GRUB-Image)
scripts/test-qemu.sh          Rauchtest in QEMU
airootfs-pre/                 Dateien, die vor der Paketinstallation ins Root kommen
                              (Initramfs-Hooks surface-qcom und surface_isoscan)
airootfs/                     Overlay des Live-Systems (Werkzeuge, systemd-Units)
```

Das ISO ist ein Hybrid-Image (ISO9660 + GPT mit FAT-EFI-Systempartition).
Kernel, Initramfs, Devicetrees und GRUB liegen in der EFI-Partition, das
Root-Dateisystem als SquashFS (`arch/aarch64/airootfs.sfs`, xz – zstd kann der
linux-surface-Kernel in SquashFS nicht lesen) im ISO; das Initramfs nutzt die
Hooks aus `mkinitcpio-archiso`.

## Bekannte Grenzen

- Der Build wurde in QEMU getestet (generischer UEFI/ACPI-Start, direkt als
  USB-Datenträger und über Ventoy), **nicht auf echter Surface-Hardware**.
  Devicetrees und Kernel-Parameter folgen den Quellen von linux-surface; die
  Geräteerkennung im Bootmenü (SMBIOS-Namen) ist nur eine Annahme.
- Auf den X-Elite/X-Plus-Geräten hängt die USB-C-Steckerorientierung teils an
  Firmware, die erst nach `surface-fw-extract` vorhanden ist. Wird der Stick
  beim Start nicht gefunden: Stecker drehen oder einen anderen Anschluss
  (USB-A, falls vorhanden) verwenden.
- Surface Pro 11 (LCD/OLED) lässt sich über die Firmware-Angaben nicht sicher
  unterscheiden und muss im Bootmenü von Hand gewählt werden.
- Surface Pro X: Sollte das Standard-GRUB nicht starten, liegt das gepatchte
  GRUB von linux-surface unter `EFI/spx/bootaa64.efi` in der EFI-Partition des
  Sticks (Menüeintrag oder nach `EFI/BOOT/BOOTAA64.EFI` kopieren).
- UEFI-Variablen sind unter Linux nicht auf allen Geräten schreibbar. Dann
  kann `surface-install` GRUB auf Nachfrage als Standard-Bootloader
  (`EFI/BOOT/BOOTAA64.EFI`, mit Sicherung der vorhandenen Datei) ablegen.

## Referenzen

Kernel

- [linux-surface/kernel](https://github.com/linux-surface/kernel) –
  Kernelquellen mit den Surface-Patches und Devicetrees
- [linux-surface/aarch64-packages](https://github.com/linux-surface/aarch64-packages)
  – Arch-Paketierung von `linux-surface` für aarch64 (von dort stammen auch
  die hier verwendeten PKGBUILDs für `qrtr`, `tqftpserv`, `rmtfs-dummy`)
- [linux-surface/repo](https://github.com/linux-surface/repo) –
  Paket-Repository (`https://pkg.surfacelinux.com/arch-aarch64/`)

Firmware

- [linux-surface/aarch64-firmware](https://github.com/linux-surface/aarch64-firmware)
  – Firmware für das Surface Pro X
- [linux-firmware](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git)
  – Upstream-Firmware (Qualcomm, Atheros, …)
- [linux-msm](https://github.com/linux-msm) – Qualcomm-Userspace (`qrtr`,
  `tqftpserv`, `rmtfs`)

Weitere Bausteine

- [linux-surface](https://github.com/linux-surface) – das Projekt insgesamt,
  Wiki und Issues
- [linux-surface/aarch64-arch-mkimg](https://github.com/linux-surface/aarch64-arch-mkimg)
  – die Image-Skripte von linux-surface für das Pro X (Vorbild für dieses
  Projekt)
- [linux-surface/grub-image-aarch64](https://github.com/linux-surface/grub-image-aarch64)
  – gepatchtes GRUB für das Pro X
- [Arch Linux ARM](https://archlinuxarm.org) und dessen
  [PKGBUILDs](https://github.com/archlinuxarm/PKGBUILDs)
- [archiso](https://gitlab.archlinux.org/archlinux/archiso) /
  [mkinitcpio-archiso](https://gitlab.archlinux.org/archlinux/mkinitcpio/mkinitcpio-archiso)
- [Ventoy](https://github.com/ventoy/Ventoy)
