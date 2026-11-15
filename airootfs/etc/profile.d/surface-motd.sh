# Begrüßung des Live-Systems in der gewählten Sprache
if [ -n "${PS1-}" ] && [ -z "${SURFACE_MOTD_SHOWN-}" ] && [ -d /run/archiso ]; then
    export SURFACE_MOTD_SHOWN=1
    if [ "$(cat /etc/surface/lang 2>/dev/null)" = en ]; then
        cat <<'MOTD'

  Arch Linux ARM – live/installation system for Snapdragon-based Surface devices
  ------------------------------------------------------------------------------

  Show device:           surface-device
  Language / keyboard:   surface-locale --lang de --keymap de-latin1
  Connect to Wi-Fi:      iwctl station wlan0 scan
                         iwctl station wlan0 connect "<SSID>"
  Firmware from Windows: surface-fw-extract
  Install:               mount the partition(s) under /mnt, then  surface-install
                         (help: surface-install --help)

  Shrink the Windows partition from within Windows first; Secure Boot has to
  be disabled in the Surface UEFI settings.

MOTD
    else
        cat <<'MOTD'

  Arch Linux ARM – Live-/Installationssystem für Snapdragon-Surface-Geräte
  ------------------------------------------------------------------------

  Gerät anzeigen:        surface-device
  Sprache / Tastatur:    surface-locale --lang en --keymap us
  WLAN verbinden:        iwctl station wlan0 scan
                         iwctl station wlan0 connect "<SSID>"
  Firmware aus Windows:  surface-fw-extract
  Installieren:          Partition(en) unter /mnt einhängen, dann  surface-install
                         (Hilfe: surface-install --help)

  Die Windows-Partition vorher unter Windows verkleinern; Secure Boot muss in
  den Surface-UEFI-Einstellungen ausgeschaltet sein.

MOTD
    fi
fi
