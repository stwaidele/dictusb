#!/bin/bash
# Lädt Dateien über die CircuitPython-Web-Workflow-API auf den Pico
# (HTTP PUT /fs/<name>, Basic-Auth mit leerem Benutzer + Web-API-Passwort).
# Der Upload löst auf dem Pico den Auto-Reload aus.
#
# Aufruf:  ./mac/deploy.sh                     # code.py + dictusb_crypto.py
#          ./mac/deploy.sh pico/boot.py …      # beliebige Dateien
#
# Zugangsdaten kommen aus der lokalen Kopie pico/settings.toml
# (gitignored; gleicher Inhalt wie auf dem Pico):
#   CIRCUITPY_WEB_API_PASSWORD  Web-API-Passwort
#   DICTUSB_HOST                IP/Hostname des Pico (optional)
# Umgebungsvariablen DICTUSB_HOST / DICTUSB_WEB_PASSWORD haben Vorrang.
set -euo pipefail

cd "$(dirname "$0")/.."
SETTINGS="pico/settings.toml"

# Liest einen String-Wert ('KEY = "wert"') aus der settings.toml
get_toml() {
    [ -f "$SETTINGS" ] || return 0
    sed -n 's/^[[:space:]]*'"$1"'[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$SETTINGS" | tail -1
}

HOST="${DICTUSB_HOST:-$(get_toml DICTUSB_HOST)}"
PASS="${DICTUSB_WEB_PASSWORD:-$(get_toml CIRCUITPY_WEB_API_PASSWORD)}"

if [ -z "$HOST" ]; then
    echo "FEHLER: Kein Host konfiguriert." >&2
    echo "In $SETTINGS eintragen:  DICTUSB_HOST = \"<pico-ip>\"" >&2
    exit 1
fi
if [ -z "$PASS" ]; then
    if [ ! -f "$SETTINGS" ]; then
        echo "Hinweis: $SETTINGS fehlt lokal — dort CIRCUITPY_WEB_API_PASSWORD" >&2
        echo "und DICTUSB_HOST pflegen (Datei ist gitignored)." >&2
    fi
    read -rs -p "Web-API-Passwort für $HOST: " PASS
    echo
fi

# Web-Workflow leitet teils auf den mDNS-Hostnamen um; --location-trusted
# schickt die Basic-Auth auch nach dem Redirect mit.
CURL=(curl -sS -L --location-trusted -u ":$PASS")

# Anmeldung vorab testen, damit ein Passwortfehler klar gemeldet wird
status=$("${CURL[@]}" -o /dev/null -w "%{http_code}" "http://$HOST/fs/" 2>/dev/null || true)
if [ "$status" = "000" ] || [ -z "$status" ]; then
    echo "FEHLER: $HOST ist nicht erreichbar (läuft der Pico? stimmt DICTUSB_HOST?)." >&2
    exit 1
elif [ "$status" = "401" ]; then
    echo "FEHLER: Web-API-Passwort abgelehnt (401) von $HOST." >&2
    echo "Gegenprobe im Browser: http://$HOST/fs/ (Benutzername leer)." >&2
    echo "Manueller Test:  curl -i -L --location-trusted -u \":PASSWORT\" http://$HOST/fs/" >&2
    exit 1
elif [ "$status" != "200" ]; then
    echo "FEHLER: $HOST antwortet mit HTTP $status auf /fs/." >&2
    exit 1
fi

# code.py IMMER zuletzt: jeder Upload loest den Auto-Reload aus, und die
# neue code.py darf erst starten, wenn ihre Abhaengigkeiten schon da sind.
files=("$@")
[ ${#files[@]} -eq 0 ] && files=(pico/dictusb_crypto.py pico/status_led.py pico/code.py)

for f in "${files[@]}"; do
    name=$(basename "$f")
    if [ "$name" = "settings.toml.example" ]; then
        echo "übersprungen: $f (Vorlage gehört nicht als settings.toml auf den Pico)"
        continue
    fi
    "${CURL[@]}" -f -T "$f" "http://$HOST/fs/$name" -o /dev/null
    echo "hochgeladen: $f -> /$name"
done
echo "Fertig — der Pico lädt jetzt neu (Auto-Reload)."
