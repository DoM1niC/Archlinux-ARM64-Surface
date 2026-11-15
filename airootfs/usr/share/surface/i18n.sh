# shellcheck shell=bash
# Sprachumschaltung für die surface-*-Werkzeuge (Deutsch/Englisch).
#
# Die Sprache steht in /etc/surface/lang ("de" oder "en") und wird beim Start
# aus dem Bootmenü übernommen; ändern mit:  surface-locale --lang en
# Für einen einzelnen Aufruf:               SURFACE_LANG=en surface-install

if [[ -z "${SURFACE_LANG:-}" ]]; then
    SURFACE_LANG="$(cat /etc/surface/lang 2>/dev/null || true)"
fi
[[ "$SURFACE_LANG" == en ]] || SURFACE_LANG=de

# t "deutscher Text" "English text" -> gibt die passende Fassung aus
t() {
    if [[ "$SURFACE_LANG" == en ]]; then
        printf '%s' "$2"
    else
        printf '%s' "$1"
    fi
}
