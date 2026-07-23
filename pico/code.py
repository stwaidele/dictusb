# dictUSB — Pico 2 W / ESP32-S3: WLAN-TCP-Server, der empfangenen Text
# als USB-HID-Tastatur an den angeschlossenen Rechner tippt. Auf dem
# Zielrechner laeuft KEINE Software — er sieht eine normale Tastatur.
#
# Konfiguration in settings.toml (siehe settings.toml.example):
#   CIRCUITPY_WIFI_SSID/_PASSWORD + CIRCUITPY_WEB_API_PASSWORD aktivieren
#   den CircuitPython-Web-Workflow (Logs + Datei-Update im Browser); der
#   Supervisor verbindet das WLAN dann selbst, vor code.py, und haelt es
#   ueber Soft-Reboots. Alternativ DICTUSB_WIFI_SSID/_PASSWORD, dann
#   verbindet nur code.py (kein Webinterface).
#   Weitere: DICTUSB_PORT, DICTUSB_TOKEN, DICTUSB_LAYOUT,
#   DICTUSB_SETTINGS_VERSION, DICTUSB_SCAN, DICTUSB_IDLE_LIMIT

# Bei jeder Änderung an dieser Datei hochzählen — dient zur Kontrolle,
# dass der Pico wirklich die neue Version geladen hat.
VERSION = "0.18"

import os
import time

import microcontroller
import supervisor

import socketpool
import usb_hid
import wifi
from adafruit_hid.keyboard import Keyboard
from adafruit_hid.keycode import Keycode

import dictusb_crypto  # geteilte Datei, per deploy.sh mit ausgerollt
import status_led  # Onboard-LED als Zustandsanzeige (faehigkeitserkennend)

# Tastaturlayout des ZIELRECHNERS (DICTUSB_LAYOUT in settings.toml).
# Wir senden HID-Keycodes; welches Zeichen daraus wird, entscheidet das
# Layout, das auf dem angeschlossenen Rechner eingestellt ist. Weil jedes
# Geraet dauerhaft an genau einem Rechner steckt, ist das eine
# Geraete-Eigenschaft. Siehe README, Abschnitt "Zielsysteme und Layouts".
#
# "win_de" passt auch fuer Linux mit deutschem Layout (gleiche
# Scancode-Belegung). "us" steckt in adafruit_hid, kann aber keine
# Umlaute — solche Zeichen werden dann protokolliert und verworfen.
# Weitere Layouts aus dem Neradoc-Bundle lassen sich hier ergaenzen,
# sobald die passende .mpy in /lib liegt.
LAYOUT = str(os.getenv("DICTUSB_LAYOUT") or "win_de")


def _load_us():
    from adafruit_hid.keyboard_layout_us import KeyboardLayoutUS

    return KeyboardLayoutUS


def _load_bundle(module_name):
    """Laedt ein Layout aus dem Neradoc-Bundle (Modul in /lib)."""

    def loader():
        mod = __import__(module_name)
        return mod.KeyboardLayout

    return loader


LAYOUT_LOADERS = {
    "win_de": _load_bundle("keyboard_layout_win_de"),
    "us": _load_us,
    # weitere Bundle-Layouts: .mpy nach /lib kopieren und hier eintragen
    "win_fr": _load_bundle("keyboard_layout_win_fr"),
    "win_uk": _load_bundle("keyboard_layout_win_uk"),
    "win_es": _load_bundle("keyboard_layout_win_es"),
    "win_it": _load_bundle("keyboard_layout_win_it"),
}


def load_layout(name):
    """Gibt (Layout-Klasse, Anzeigename) zurueck. Faellt bei unbekanntem
    oder fehlendem Modul hoerbar auf US zurueck, statt stumm etwas
    Falsches zu tippen."""
    loader = LAYOUT_LOADERS.get(name)
    if loader is None:
        return _load_us(), "us (FEHLER: DICTUSB_LAYOUT=%r unbekannt; bekannt: %s)" % (
            name,
            ", ".join(sorted(LAYOUT_LOADERS)),
        )
    try:
        return loader(), name
    except ImportError:
        return _load_us(), "us (FEHLER: Modul fuer %r fehlt in /lib)" % name


KeyboardLayout, LAYOUT_NAME = load_layout(LAYOUT)

SSID = os.getenv("CIRCUITPY_WIFI_SSID") or os.getenv("DICTUSB_WIFI_SSID")
PASSWORD = os.getenv("CIRCUITPY_WIFI_PASSWORD") or os.getenv("DICTUSB_WIFI_PASSWORD")
PORT = int(os.getenv("DICTUSB_PORT", 8080))
# str(): unquotierte Werte in settings.toml kommen als int an
TOKEN = str(os.getenv("DICTUSB_TOKEN") or "")
# Netz-Scan beim Start (nur Diagnose). Standard aus: haengt auf manchen
# CircuitPython-Versionen fuer den Pico 2 W dauerhaft.
SCAN = os.getenv("DICTUSB_SCAN") == "1"
# Sekunden ohne gueltigen Frame, nach denen die Verbindung getrennt wird.
# Kein reines Leerlauf-Limit: Der Client sendet bei Untaetigkeit
# Herzschlaege, lange Denkpausen sind also unkritisch. Greift nur, wenn
# der Client wirklich verschwunden ist (abgestuerzt, Netz weg) — sonst
# blockierte er das Geraet dauerhaft, weil nur eine Verbindung bedient
# wird (siehe PROTOCOL.md, Abschnitt 6).
IDLE_LIMIT = int(os.getenv("DICTUSB_IDLE_LIMIT", 90))
# Onboard-LED als Zustandsanzeige. "0" schaltet sie ganz aus; sonst
# waehlt status_led automatisch RGB (NeoPixel), einfarbig (board.LED)
# oder nichts. Helligkeit als Obergrenze (WS2812 voll ist grell).
LED_ON = os.getenv("DICTUSB_LED", "1") != "0"
try:
    LED_BRIGHTNESS = float(os.getenv("DICTUSB_LED_BRIGHTNESS") or 0.5)
except ValueError:
    LED_BRIGHTNESS = 0.5
LED_PIN = os.getenv("DICTUSB_LED_PIN") or None  # leer = board.NEOPIXEL

print("dictUSB: code.py Version", VERSION)
print("dictUSB: CircuitPython", os.uname().version)
# Diagnose CYW43-Soft-Reboot-Problem: Nach AUTO_RELOAD/SUPERVISOR_RELOAD
# ist der Funkchip oft verklemmt; nur nach hartem Reset laeuft er sauber.
print("dictUSB: Startgrund:", supervisor.runtime.run_reason)
print("dictUSB: settings.toml Version", os.getenv("DICTUSB_SETTINGS_VERSION") or "(fehlt)")
print("dictUSB: MAC-Adresse", ":".join("%02X" % b for b in wifi.radio.mac_address))
print("dictUSB: Layout =", LAYOUT_NAME, "(Ziel-Tastaturbelegung)")
if TOKEN:
    try:
        os.urandom(1)
        print("dictUSB: Verschluesselung aktiv (Protokoll DICTUSB2)")
    except Exception:
        print("dictUSB: FEHLER: os.urandom fehlt — verschluesselte Verbindungen werden abgelehnt")
else:
    print("dictUSB: WARNUNG: kein DICTUSB_TOKEN — Klartextbetrieb, jeder im WLAN kann tippen")


def init_keyboard():
    """Wartet auf den USB-Host und baut die HID-Tastatur auf.

    Keyboard() blockiert, solange kein Host das HID-Geraet konfiguriert
    hat. Ohne Meldung sieht das Geraet dabei gesund aus (WLAN und
    Web-Workflow laufen), waehrend der Tipp-Server nie startet und
    Clients nur 'connection refused' bekommen. Deshalb hier: Zustand
    protokollieren und regelmaessig daran erinnern, was fehlt.
    """
    waited = 0
    while not supervisor.runtime.usb_connected:
        if waited == 0:
            print("dictUSB: WARTE auf USB-Host — keine Datenverbindung.")
            print("dictUSB:   Steckt das Kabel in der Buchse, die direkt am Chip haengt?")
            print("dictUSB:   Beim Umstecken einige Sekunden warten, sonst bricht")
            print("dictUSB:   der PC die USB-Erkennung ab ('Geraet hat nicht richtig funktioniert').")
        elif waited % 30 == 0:
            print("dictUSB: warte weiter auf USB-Host (%d s) — es wird nichts getippt" % waited)
        time.sleep(1)
        waited += 1
    if waited:
        print("dictUSB: USB-Host da nach %d s" % waited)
    k = Keyboard(usb_hid.devices)
    print("dictUSB: HID-Tastatur bereit")
    return k


# Erst in main() gesetzt — zuerst muss das WLAN stehen, damit das Log
# ueber den Web-Workflow lesbar ist, waehrend auf den USB-Host gewartet
# wird (genau dieser Fall trat am 2026-07-20 auf).
kbd = None
layout = None
# Modul-Global wie kbd/layout: type_char()/send_combo() melden hierueber
# echte Tastendruecke an die LED. Erst in main() gebaut (nach WLAN, weil
# der Pico den bereits initialisierten Funkchip fuer board.LED braucht).
led = status_led.StatusLED(status_led.NullBackend(), LED_BRIGHTNESS)
if os.getenv("CIRCUITPY_WEB_API_PASSWORD"):
    print("dictUSB: Web-Workflow aktiv: http://<ip>/fs/ (Dateien), http://<ip>/cp/serial/ (Logs)")
elif os.getenv("CIRCUITPY_WIFI_SSID"):
    print("dictUSB: Hinweis: CIRCUITPY_WIFI_SSID ohne CIRCUITPY_WEB_API_PASSWORD -> kein Webinterface")
if not SSID:
    print("dictUSB: FEHLER: keine WLAN-SSID in settings.toml (CIRCUITPY_/DICTUSB_WIFI_SSID)")


def mask(s):
    """Erstes/letztes Zeichen + Laenge — macht unsichtbare Leerzeichen
    oder Umbrueche aus Copy&Paste erkennbar, ohne das Passwort zu zeigen."""
    if not s:
        return "(leer)"
    if len(s) <= 2:
        return "*" * len(s) + " (%d Zeichen)" % len(s)
    return "%s%s%s (%d Zeichen)" % (s[0], "*" * (len(s) - 2), s[-1], len(s))


# repr() macht Leerzeichen/Sonderzeichen in der SSID sichtbar
print("dictUSB: SSID =", repr(SSID))
print("dictUSB: Passwort =", mask(PASSWORD))


def reset_radio():
    """Funkchip aus- und wieder einschalten. Nach einem fehlgeschlagenen
    connect() bleibt der CYW43 sonst gern in einem Zustand hängen, in dem
    Scans und weitere Versuche blockieren."""
    wifi.radio.enabled = False
    time.sleep(1)
    wifi.radio.enabled = True
    time.sleep(1)


def fmt_authmode(net):
    auth = getattr(net, "authmode", None)
    if not auth:
        return "?"
    return "/".join(str(m).split(".")[-1] for m in auth)


def scan_report():
    """Diagnose: listet sichtbare Netze mit Kanal, Signalstärke und
    Verschlüsselung (SSID-Tippfehler, 5-GHz-only, Kanal 12/13, WPA3)."""
    print("dictUSB: sichtbare Netze (Pico kann nur 2,4 GHz):")
    best = {}  # SSID -> (rssi, channel, authmode), stärkstes Signal je Netz
    try:
        for net in wifi.radio.start_scanning_networks():
            ssid = net.ssid
            if not ssid:
                continue
            if ssid not in best or net.rssi > best[ssid][0]:
                best[ssid] = (net.rssi, net.channel, fmt_authmode(net))
        wifi.radio.stop_scanning_networks()
    except Exception as e:
        print("dictUSB: Scan fehlgeschlagen:", e)
        return
    if not best:
        print("  (keine gefunden)")
    for ssid in sorted(best, key=lambda s: -best[s][0]):
        rssi, channel, auth = best[ssid]
        marker = "  <-- gesucht" if ssid == SSID else ""
        print("  %r  Kanal %d  RSSI %d  %s%s" % (ssid, channel, rssi, auth, marker))


def connect_wifi():
    attempts = 0
    while not wifi.radio.connected:
        print("dictUSB: verbinde mit WLAN", SSID, "...")
        try:
            wifi.radio.connect(SSID, PASSWORD, timeout=15)
        except (ConnectionError, RuntimeError) as e:
            attempts += 1
            print("dictUSB: WLAN-Fehler:", e, "(Versuch %d)" % attempts)
            if attempts == 2:
                hard_reset_once()
            reset_radio()
            print("dictUSB: neuer Versuch in 5 s")
            time.sleep(5)
    microcontroller.nvm[0] = 0  # Verbindung ok -> Reset-Marker loeschen
    print("dictUSB: WLAN ok, IP =", wifi.radio.ipv4_address)


def hard_reset_once():
    """CYW43-Workaround: Nach einem Soft-Reboot (Auto-Reload) verklemmt
    der Funkchip; nur ein harter Reset initialisiert ihn sauber. Marker
    in nvm verhindert eine Reset-Schleife, wenn das WLAN wirklich fehlt."""
    if microcontroller.nvm[0] == 1:
        print("dictUSB: Hardware-Reset schon versucht, WLAN scheint wirklich weg")
        return
    microcontroller.nvm[0] = 1
    print("dictUSB: erzwinge Hardware-Reset (CYW43-Soft-Reboot-Workaround) ...")
    time.sleep(1)
    microcontroller.reset()


# Tastenkombinationen kommen als Escape-Sequenz im Datenstrom an:
# 0x00 + Spezifikation + "\n", z.B. "\x00ctrl+p\n" oder "\x00win+shift+s\n".
# Modifier: ctrl, alt, shift, win (auch gui/cmd). Taste: einzelnes Zeichen
# (layoutkorrekt), benannte Taste aus NAMED_KEYS oder (seit 0.18) ein
# Modifier-Name allein — "\x00shift\n" tippt Shift, ohne ein Zeichen zu
# senden (z.B. Bildschirmschoner am Ziel beenden).
COMBO_MODS = {
    "ctrl": Keycode.CONTROL,
    "alt": Keycode.ALT,
    "shift": Keycode.SHIFT,
    "win": Keycode.GUI,
    "gui": Keycode.GUI,
    "cmd": Keycode.GUI,
}
NAMED_KEYS = {
    "enter": Keycode.ENTER,
    "tab": Keycode.TAB,
    "esc": Keycode.ESCAPE,
    "backspace": Keycode.BACKSPACE,
    "delete": Keycode.DELETE,
    "insert": Keycode.INSERT,
    "space": Keycode.SPACE,
    "up": Keycode.UP_ARROW,
    "down": Keycode.DOWN_ARROW,
    "left": Keycode.LEFT_ARROW,
    "right": Keycode.RIGHT_ARROW,
    "home": Keycode.HOME,
    "end": Keycode.END,
    "pageup": Keycode.PAGE_UP,
    "pagedown": Keycode.PAGE_DOWN,
}
for _n in range(1, 13):
    NAMED_KEYS["f%d" % _n] = getattr(Keycode, "F%d" % _n)


def send_combo(spec):
    """Tippt eine Kombinations-Spezifikation wie "ctrl+shift+p"."""
    parts = [p for p in spec.strip().lower().split("+") if p]
    if not parts:
        return
    mods, key = parts[:-1], parts[-1]
    codes = []
    for m in mods:
        if m not in COMBO_MODS:
            print("dictUSB: unbekannter Modifier:", repr(m))
            return
        codes.append(COMBO_MODS[m])
    if key in NAMED_KEYS:
        codes.append(NAMED_KEYS[key])
    elif key in COMBO_MODS:
        # Modifier als "Taste": reiner Modifier-Tipp (z.B. "shift").
        codes.append(COMBO_MODS[key])
    elif len(key) == 1:
        try:
            codes.extend(layout.keycodes(key))
        except (ValueError, KeyError):
            print("dictUSB: Taste nicht im Layout:", repr(key))
            return
    else:
        print("dictUSB: unbekannte Taste:", repr(key))
        return
    kbd.send(*codes)
    led.activity(time.monotonic())  # echter Tastendruck (leere Kombi kehrt oben zurueck)


def type_char(ch):
    """Tippt ein einzelnes Zeichen; Steuerzeichen werden gesondert behandelt."""
    led.activity(time.monotonic())  # jeder getippte Anschlag -> LED-Puls
    if ch in ("\r", "\n"):
        kbd.send(Keycode.ENTER)
    elif ch == "\t":
        kbd.send(Keycode.TAB)
    elif ch in ("\x08", "\x7f"):  # Backspace bzw. DEL (Mac-Backspace sendet 0x7f)
        kbd.send(Keycode.BACKSPACE)
    elif ch == "\x1b":
        kbd.send(Keycode.ESCAPE)
    elif "\x01" <= ch <= "\x1a":
        # Terminal-Raw-Mode liefert Strg+A..Z als Bytes 0x01..0x1A — als
        # echte Strg-Kombination weitertippen. Den Keycode des Buchstabens
        # liefert das Layout (QWERTZ: Strg+Z liegt auf der HID-Y-Taste).
        letter = chr(ord(ch) - 1 + ord("a"))
        kbd.send(Keycode.CONTROL, *layout.keycodes(letter))
    elif ord(ch) < 0x20:
        pass  # übrige Steuerzeichen ignorieren
    else:
        try:
            layout.write(ch)
        except ValueError:
            print("dictUSB: Zeichen nicht im Layout:", repr(ch))


def type_text(text, state):
    """Tippt Text; verschluckt das \n eines \r\n-Paars (state merkt sich das \r)
    und sammelt Kombinations-Sequenzen (0x00 ... \n) ein, statt sie zu tippen."""
    for ch in text:
        if state["combo"] is not None:
            if ch == "\n":
                send_combo(state["combo"])
                state["combo"] = None
            elif len(state["combo"]) > 32:
                print("dictUSB: Kombi-Sequenz zu lang, verworfen")
                state["combo"] = None
            else:
                state["combo"] += ch
            continue
        if ch == "\x00":
            state["combo"] = ""
            state["last_cr"] = False
            continue
        if ch == "\n" and state["last_cr"]:
            state["last_cr"] = False
            continue
        state["last_cr"] = ch == "\r"
        type_char(ch)


def decode_utf8_stream(buf):
    """Dekodiert so viel wie möglich; ein am Ende abgeschnittenes
    Mehrbyte-Zeichen bleibt als Rest für das nächste Paket stehen."""
    for cut in range(len(buf), max(len(buf) - 3, 0) - 1, -1):
        try:
            return buf[:cut].decode("utf-8"), buf[cut:]
        except UnicodeError:
            pass
    # Ungültiges Byte am Anfang: verwerfen, Rest behalten.
    return "", buf[1:]


def serve_client(conn, addr, recv_buf):
    """Mit TOKEN: Protokoll DICTUSB2 — Banner mit frischem Salt senden,
    Frames entschluesseln + MAC pruefen (erster gueltiger Frame = Auth,
    das Token laeuft nie uebers Netz). Ohne TOKEN: Klartext wie immer.

    Gibt "clean" (Client hat sauber geschlossen) oder "abort"
    (Timeout/Fehler/Netzverlust) zurueck — steuert die LED-Anzeige."""
    print("dictUSB: Verbindung von", addr)
    # Kurzer Timeout, damit die LED (Fade/Blinken) fluessig aktualisiert
    # wird; auf die Tipp-Latenz hat das keinen Einfluss (Daten kommen
    # weiter sofort), Idle-/Heartbeat-Logik prueft nur oefter.
    conn.settimeout(0.1)
    try:
        dec = None
        acker = None
        if TOKEN:
            salt = os.urandom(dictusb_crypto.SALT_LEN)  # TRNG; ohne den
            # gibt es hier eine Exception und die Verbindung wird
            # abgelehnt — niemals ein Zeit-Fallback (Salt-Reuse!)
            conn.send(dictusb_crypto.make_banner(salt))
            dec = dictusb_crypto.FrameDecryptor(TOKEN, salt)
            acker = dictusb_crypto.AckSender(TOKEN, salt)
        authed = dec is None
        if authed:
            led.connected()  # Klartextbetrieb: verbunden ab TCP-Accept
        deadline = time.monotonic() + 5  # bis zum ersten gueltigen Frame
        last_ok = time.monotonic()       # letztes gueltiges Lebenszeichen
        state = {"last_cr": False, "combo": None}
        pending = b""
        while True:
            led.update(time.monotonic())
            try:
                n = conn.recv_into(recv_buf)
            except OSError:  # Timeout: WLAN pruefen, weiter warten
                if not wifi.radio.connected:
                    return "abort"
                if not authed and time.monotonic() > deadline:
                    print("dictUSB: kein gueltiger Frame in 5 s, trenne")
                    return "abort"
                if authed and time.monotonic() - last_ok > IDLE_LIMIT:
                    # Client verschwunden, ohne die Verbindung zu schliessen.
                    # Ohne diesen Abbruch bliebe das Geraet dauerhaft belegt.
                    print("dictUSB: kein Lebenszeichen seit %d s, trenne" % IDLE_LIMIT)
                    return "abort"
                continue
            if n == 0:  # Client hat sauber geschlossen
                return "clean"
            data = bytes(recv_buf[:n])
            if dec is not None:
                try:
                    data = dec.feed(data)
                except dictusb_crypto.MacError as e:
                    print("dictUSB: %s — Verbindung abgelehnt" % e)
                    return "abort"
                if data:
                    if not authed:
                        led.connected()  # erster gueltiger Frame = verbunden
                    authed = True
                    last_ok = time.monotonic()
                    # Herzschlaege quittieren, damit auch der Client
                    # merkt, ob das Geraet noch lebt. Frame-genau
                    # gezaehlt, weil mehrere Frames zusammen ankommen
                    # koennen (der Herzschlag steckt dann mitten drin).
                    try:
                        for _ in range(dec.take_heartbeats()):
                            conn.send(acker.next())
                    except OSError:
                        return
                elif not authed and time.monotonic() > deadline:
                    print("dictUSB: kein gueltiger Frame in 5 s, trenne")
                    return "abort"
            pending += data
            if pending:
                text, pending = decode_utf8_stream(pending)
                type_text(text, state)
    finally:
        conn.close()
        print("dictUSB: Verbindung beendet")


def main():
    global kbd, layout, led
    # Scan nur auf Wunsch (DICTUSB_SCAN = "1"), und dann VOR dem ersten
    # connect(): nach einem fehlgeschlagenen Verbindungsversuch haengt
    # start_scanning_networks() auf dem CYW43 zuverlaessig.
    if SCAN:
        scan_report()
    connect_wifi()
    if kbd is None:
        kbd = init_keyboard()
        layout = KeyboardLayout(kbd)
    # LED erst jetzt bauen: der Pico braucht den bereits initialisierten
    # Funkchip fuer board.LED. status_led.make() erkennt die Faehigkeit
    # selbst und faellt hoerbar (Bannerzeile) auf Null zurueck.
    led = status_led.make(
        LED_ON, LED_BRIGHTNESS, LED_PIN, status_led.config_from_env(os.getenv)
    )
    print("dictUSB: LED =", led.kind)
    pool = socketpool.SocketPool(wifi.radio)
    server = pool.socket(pool.AF_INET, pool.SOCK_STREAM)
    server.setsockopt(pool.SOL_SOCKET, pool.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", PORT))
    server.listen(1)
    server.settimeout(0.1)  # kurzer Timeout: treibt LED-Blinken im Leerlauf
    print("dictUSB: lausche auf %s:%d" % (wifi.radio.ipv4_address, PORT))
    led.ready()

    recv_buf = bytearray(512)  # Max-Frame ist 264 B (1+255+8)
    while True:
        led.update(time.monotonic())
        if not wifi.radio.connected:
            print("dictUSB: WLAN weg, verbinde neu ...")
            connect_wifi()
        try:
            conn, addr = server.accept()
        except OSError:  # Timeout, einfach weiter lauschen
            continue
        result = "abort"
        try:
            result = serve_client(conn, addr, recv_buf)
        except Exception as e:  # Client-Fehler dürfen den Server nicht beenden
            print("dictUSB: Client-Fehler:", e)
        # Sauberes Ende -> direkt bereit (gelb); Abbruch -> rot blinken,
        # danach geht die LED von selbst zurueck auf bereit.
        if result == "clean":
            led.ready()
        else:
            led.aborted(time.monotonic())


while True:
    try:
        main()
    except Exception as e:
        # Letzte Verteidigungslinie: alles loggen und neu starten,
        # damit der Pico ohne Strom-Ziehen weiterläuft.
        print("dictUSB: Neustart nach Fehler:", e)
        time.sleep(3)
