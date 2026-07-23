#!/usr/bin/env python3
"""dictUSB Mac-Client: schickt Tastatureingaben live an den Pico.

Interaktiv (Terminal):  jeder Tastendruck geht sofort raus (geringe Latenz).
Pipe-Modus:             echo "Hallo" | ./dictusb.py <host>   tippt den Text.

Mit Token laeuft die Verbindung verschluesselt (Protokoll DICTUSB2,
siehe pico/dictusb_crypto.py); das Token wird nie uebertragen. Ohne
--token wird es aus der Umgebungsvariable DICTUSB_TOKEN oder der
lokalen pico/settings.toml gelesen. Ohne Token: Klartext (nur fuer
tokenlosen Testbetrieb).

Beenden (interaktiv wie --tasten): 5x die LINKE Shift-Taste innerhalb
von 2 Sekunden, ohne andere Taste dazwischen. Shift alleine erzeugt
keine Eingabe — nichts muss gepuffert oder verzoegert werden, alle
anderen Tasten gehen sofort raus. Die Geste braucht pynput (im
interaktiven Modus als reiner Beobachter, ohne Tastensperre); fehlt
pynput, bleibt interaktiv nur Ctrl-] — das ist auf deutschem Layout
allerdings nicht tippbar (Ctrl+Option+6 liefert nur "6").
Strg+Buchstabe (z.B. Strg+P) wird als Strg-Kombination an Windows
weitergereicht; Ausnahmen: Strg+H/I/J/M wirken als Backspace/Tab/Enter.

Tasten-Modus (--tasten): greift echte Tastenereignisse samt Modifiern ab
(macOS-Event-Tap, braucht pynput + Freigabe "Bedienungshilfen" für das
Terminal) und tauscht Cmd<->Strg: Cmd+X kommt als Strg+X in Windows an,
Strg+X als Win+X. Solange der Modus läuft, gehen ALLE Tastendrücke an
Windows.
"""

import argparse
import os
import re
import socket
import sys
import time

# Geteilte Krypto-Schicht aus pico/ (dieselbe Datei laeuft auf dem Pico)
sys.path.insert(
    0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "pico")
)
try:
    import dictusb_crypto
except ImportError:
    dictusb_crypto = None  # nur noetig, wenn ein Token verwendet wird

QUIT_KEY = b"\x1d"  # Ctrl-] (Fallback; nur tippbar, wo ] direkt liegt)


def read_local_token():
    """Token aus DICTUSB_TOKEN (Env) oder der lokalen, gitignorten
    pico/settings.toml — haelt das Secret aus der Shell-History raus."""
    tok = os.environ.get("DICTUSB_TOKEN")
    if tok:
        return tok
    settings = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "pico", "settings.toml"
    )
    try:
        with open(settings) as f:
            for line in f:
                m = re.match(r'\s*DICTUSB_TOKEN\s*=\s*"([^"]*)"', line)
                if m:
                    return m.group(1)
    except OSError:
        pass
    return ""


# Lebenszeichen: bei Untaetigkeit alle HEARTBEAT_EVERY Sekunden ein
# Herzschlag-Paket. Das Geraet trennt sonst nach seinem Leerlauf-Limit
# (Default 90 s) — und ohne diesen Abbruch wuerde ein abgestuerzter
# Client das Geraet dauerhaft blockieren, weil es nur eine Verbindung
# bedient. Siehe PROTOCOL.md, Abschnitt 6.
HEARTBEAT_EVERY = 20.0


class CryptoSocket:
    """Huelle um den Socket: verschluesselt sendall(), wenn ein
    Encryptor gesetzt ist — die run_*-Funktionen merken davon nichts.
    Kuemmert sich ausserdem um Herzschlaege und deren Quittungen."""

    def __init__(self, sock, enc=None, ack=None):
        self.sock = sock
        self._enc = enc
        self._ack = ack
        self._last_sent = time.monotonic()
        self._last_ack = None  # Zeit der letzten Quittung (None = noch keine)

    def sendall(self, data):
        if self._enc:
            data = self._enc.encrypt(data)
        self.sock.sendall(data)
        self._last_sent = time.monotonic()

    def heartbeat_if_idle(self):
        """Schickt bei Bedarf ein Lebenszeichen und liest Quittungen.
        Gibt eine Fehlermeldung zurueck, wenn die Gegenstelle stumm
        bleibt — sonst None."""
        if not self._enc:
            return None
        now = time.monotonic()
        if now - self._last_sent >= HEARTBEAT_EVERY:
            self.sendall(dictusb_crypto.HEARTBEAT)
        self._read_acks()
        # Quittungen kamen bisher und bleiben jetzt aus -> Geraet weg.
        if self._last_ack is not None and now - self._last_ack > 3 * HEARTBEAT_EVERY:
            return "keine Antwort vom Gerät seit %d s" % int(now - self._last_ack)
        return None

    def _read_acks(self):
        if self._ack is None:
            return
        self.sock.setblocking(False)
        try:
            data = self.sock.recv(4096)
            if data:
                if self._ack.feed(data):
                    self._last_ack = time.monotonic()
            elif self._last_ack is not None:
                self._last_ack = 0  # Gegenstelle hat geschlossen
        except (BlockingIOError, InterruptedError):
            pass
        except OSError:
            pass
        finally:
            self.sock.setblocking(True)

    def close(self):
        self.sock.close()


# Ausstiegs-Geste: 5x die LINKE Shift-Taste innerhalb von 2 Sekunden,
# ohne andere Taste dazwischen.
SHIFT_QUIT_COUNT = 5
SHIFT_QUIT_WINDOW = 2.0


def make_shift_quit_callback(keyboard, on_quit):
    """on_press-Callback fuer einen pynput-Listener, der die
    Shift-Ausstiegs-Geste erkennt. Nur die Gesamtzeit der letzten
    SHIFT_QUIT_COUNT Druecke zaehlt; jede andere Taste setzt zurueck."""
    times = []

    def on_press(key):
        if key == keyboard.Key.shift:  # pynput: Key.shift = linke Shift-Taste
            times.append(time.monotonic())
            del times[:-SHIFT_QUIT_COUNT]
            if (
                len(times) == SHIFT_QUIT_COUNT
                and times[-1] - times[0] <= SHIFT_QUIT_WINDOW
            ):
                on_quit()
        else:
            del times[:]

    return on_press


def connect(host, port, token):
    sock = socket.create_connection((host, port), timeout=5)
    sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    if not token:
        # Kurz lauschen: Ein verschluesselnder Pico schickt sofort sein
        # Banner — dann ist tokenloser Klartext sinnlos und wir sagen
        # das klar an, statt ins Leere zu senden.
        sock.settimeout(0.5)
        try:
            peek = sock.recv(9)
        except socket.timeout:
            peek = b""
        if peek.startswith(dictusb_crypto.BANNER_PREFIX[: len(peek)]) and peek:
            raise OSError(
                "der Pico erwartet Verschlüsselung (DICTUSB2), aber es ist "
                "kein Token konfiguriert — --token angeben oder "
                "DICTUSB_TOKEN in Env/pico/settings.toml setzen"
            )
        sock.settimeout(None)
        return CryptoSocket(sock)
    if dictusb_crypto is None:
        raise OSError(
            "dictusb_crypto.py nicht gefunden (gehoert neben dieses Skript "
            "ins Repo unter pico/) — ohne sie kein Token-Betrieb"
        )
    # Mit Token ist das DICTUSB2-Banner Pflicht. Es gibt bewusst KEINEN
    # Klartext-Fallback: ein schweigender/alter Server koennte sonst das
    # Token im Klartext entlocken (Downgrade-Angriff).
    line = b""
    while not line.endswith(b"\n") and len(line) < 64:
        b_ = sock.recv(1)
        if not b_:
            break
        line += b_
    try:
        salt = dictusb_crypto.parse_banner(line)
    except ValueError as e:
        raise OSError(
            "kein DICTUSB2-Banner vom Pico (%s) — Firmware zu alt? "
            "Klartext-Fallback gibt es aus Sicherheitsgruenden nicht" % e
        )
    sock.settimeout(None)
    conn = CryptoSocket(sock, dictusb_crypto.Encryptor(token, salt),
                        dictusb_crypto.AckReceiver(token, salt))
    # Sofort authentisieren: Das Geraet verwirft eine Verbindung, in der
    # nicht binnen 5 s ein gueltiger Frame ankommt. Der Herzschlag ist
    # dafuer die harmloseste Nutzlast — die Firmware verwirft sie, ohne
    # etwas zu tippen, und quittiert sie.
    conn.sendall(dictusb_crypto.HEARTBEAT)
    return conn


def run_pipe(sock):
    """Nicht-interaktiv: stdin durchreichen (z.B. echo/cat | dictusb.py)."""
    total = 0
    while True:
        chunk = sys.stdin.buffer.read(1024)
        if not chunk:
            break
        sock.sendall(chunk)
        total += len(chunk)
    print(f"{total} Bytes gesendet.", file=sys.stderr)


def echo_local(ch):
    """Zeigt das gesendete Zeichen im Terminal an. Im Raw-Modus ist das
    normale Terminal-Echo aus, daher machen wir es selbst."""
    if ch in (b"\r", b"\n"):
        sys.stdout.buffer.write(b"\r\n")
    elif ch in (b"\x7f", b"\x08"):  # Backspace: letztes Zeichen "wegradieren"
        sys.stdout.buffer.write(b"\b \b")
    elif ch == b"\t" or ch[0] >= 0x20:  # Tab, Druckbares, UTF-8-Folgebytes
        sys.stdout.buffer.write(ch)
    elif 0x01 <= ch[0] <= 0x1A:  # Strg-Kombination, z.B. ^P
        sys.stdout.buffer.write(b"^" + bytes([ch[0] + 64]))
    sys.stdout.buffer.flush()


def run_interactive(sock, echo=True):
    import select
    import termios
    import threading
    import tty

    try:
        from pynput import keyboard
    except ImportError:
        keyboard = None

    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    quit_flag = threading.Event()
    listener = None
    if keyboard:
        # Shift-Druecke erzeugen im Terminal keine Bytes — die Geste
        # braucht einen pynput-Beobachter (ohne suppress: alle Tasten
        # wirken normal weiter, es wird nur mitgelesen).
        listener = keyboard.Listener(
            on_press=make_shift_quit_callback(keyboard, quit_flag.set)
        )
        try:
            listener.start()
        except Exception:
            listener = None
    if listener:
        print(
            "Verbunden — tippe los. Beenden: 5x linke Shift-Taste in 2 s.",
            file=sys.stderr,
        )
    else:
        print(
            "Verbunden — tippe los. (Shift-Geste nicht verfügbar — pynput "
            "fehlt oder Freigabe verweigert: Beenden nur mit Ctrl-] oder "
            "Fenster schließen.)",
            file=sys.stderr,
        )
    try:
        tty.setraw(fd)
        while not quit_flag.is_set():
            # kurzes select statt blockierendem read, damit die
            # Shift-Geste die Schleife auch ohne Eingabe beenden kann
            if not select.select([fd], [], [], 0.1)[0]:
                problem = sock.heartbeat_if_idle()
                if problem:
                    print("\nVerbindung verloren: " + problem, file=sys.stderr)
                    break
                continue
            chunk = os.read(fd, 1024)
            if not chunk or chunk == QUIT_KEY:
                break
            sock.sendall(chunk)
            if echo:
                echo_local(chunk)
    finally:
        if listener:
            listener.stop()
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
        print("\nVerbindung beendet.", file=sys.stderr)


def run_capture(sock, echo=True):
    """Tasten-Modus: Event-Tap statt stdin. Tauscht Cmd<->Strg (Cmd wird
    zu Strg, Strg zu Win) und schickt Kombinationen als Escape-Sequenz
    "\\x00<spec>\\n" an den Pico (siehe send_combo in pico/code.py)."""
    try:
        from pynput import keyboard
    except ImportError:
        print("FEHLER: --tasten braucht das Paket pynput:", file=sys.stderr)
        print("  python3 -m pip install --user pynput", file=sys.stderr)
        return 1

    import threading

    Key = keyboard.Key

    def keyset(*names):
        return {k for k in (getattr(Key, n, None) for n in names) if k}

    MODIFIER_KEYS = {
        "cmd": keyset("cmd", "cmd_l", "cmd_r"),
        "ctrl": keyset("ctrl", "ctrl_l", "ctrl_r"),
        "alt": keyset("alt", "alt_l", "alt_r", "alt_gr"),
        "shift": keyset("shift", "shift_l", "shift_r"),
    }
    # Sondertasten: (Byte fuer normales Tippen, Name fuer Kombinationen)
    SPECIAL = {
        Key.enter: (b"\r", "enter"),
        Key.tab: (b"\t", "tab"),
        Key.backspace: (b"\x7f", "backspace"),
        Key.esc: (b"\x1b", "esc"),
        Key.space: (b" ", "space"),
        Key.delete: (None, "delete"),
        Key.up: (None, "up"),
        Key.down: (None, "down"),
        Key.left: (None, "left"),
        Key.right: (None, "right"),
        Key.home: (None, "home"),
        Key.end: (None, "end"),
        Key.page_up: (None, "pageup"),
        Key.page_down: (None, "pagedown"),
    }
    for _n in range(1, 13):
        _k = getattr(Key, "f%d" % _n, None)
        if _k:
            SPECIAL[_k] = (None, "f%d" % _n)

    held = set()
    quit_event = threading.Event()
    shift_gesture = make_shift_quit_callback(keyboard, quit_event.set)

    def echo_out(s):
        if echo:
            sys.stdout.write(s)
            sys.stdout.flush()

    def send_bytes(data):
        try:
            sock.sendall(data)
        except OSError:
            quit_event.set()

    def spec_mods(include_shift):
        """Aktive Modifier fuer die Drahtseite — hier passiert der Tausch."""
        mods = []
        if "cmd" in held:
            mods.append("ctrl")  # Mac-Cmd -> Windows-Strg
        if "ctrl" in held:
            mods.append("win")  # Mac-Strg -> Windows-Taste
        if "alt" in held:
            mods.append("alt")
        if "shift" in held and include_shift:
            mods.append("shift")
        return mods

    def send_combo(mods, key_name):
        spec = "+".join(mods + [key_name])
        echo_out("[%s]" % spec)
        send_bytes(b"\x00" + spec.encode("ascii", "replace") + b"\n")

    def mod_name(key):
        for name, keys in MODIFIER_KEYS.items():
            if key in keys:
                return name
        return None

    def on_press(key):
        shift_gesture(key)
        if quit_event.is_set():
            return
        name = mod_name(key)
        if name:
            held.add(name)
            return
        ch = getattr(key, "char", None)
        if "ctrl" in held and ch in ("\x1d", "]"):  # Strg+] als Fallback
            quit_event.set()
            return
        combo = "cmd" in held or "ctrl" in held
        if key in SPECIAL:
            byte, key_name = SPECIAL[key]
            if combo or "alt" in held or ("shift" in held and byte is None):
                send_combo(spec_mods(include_shift=True), key_name)
            elif byte is not None:
                send_bytes(byte)
                echo_out("\r\n" if byte == b"\r" else " " if byte == b" " else "")
            else:
                send_combo([], key_name)
            return
        if ch is None:
            return  # Fn-/Medientasten ohne Zeichen
        if combo:
            if "\x01" <= ch <= "\x1a":  # Strg macht aus 'p' ein 0x10 — zurueckrechnen
                ch = chr(ord(ch) + 96)
            if ch.isalpha():
                send_combo(spec_mods(include_shift=True), ch.lower())
            else:
                # Shift steckt schon im komponierten Zeichen (z.B. '/')
                send_combo(spec_mods(include_shift=False), ch)
        else:
            send_bytes(ch.encode("utf-8"))
            echo_out(ch)

    def on_release(key):
        name = mod_name(key)
        if name:
            held.discard(name)

    print("Tasten-Modus aktiv — ALLE Tastendrücke gehen an Windows.", file=sys.stderr)
    print(
        "Cmd wird als Strg getippt, Strg als Win-Taste. "
        "Beenden: 5x linke Shift-Taste in 2 s.",
        file=sys.stderr,
    )
    listener = keyboard.Listener(on_press=on_press, on_release=on_release, suppress=True)
    listener.start()
    try:
        while not quit_event.wait(0.2):
            problem = sock.heartbeat_if_idle()
            if problem:
                print("\nVerbindung verloren: " + problem, file=sys.stderr)
                return 1
            if not listener.running:
                print("FEHLER: Tasten-Listener läuft nicht — fehlt die Freigabe?", file=sys.stderr)
                print("Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen:", file=sys.stderr)
                print("dort dein Terminal-Programm erlauben, dann neu starten.", file=sys.stderr)
                return 1
    finally:
        listener.stop()
        print("\nTasten-Modus beendet.", file=sys.stderr)
    return 0


def main():
    parser = argparse.ArgumentParser(description="Text live an den dictUSB-Pico senden")
    parser.add_argument("host", help="IP oder Hostname des Pico")
    parser.add_argument("port", nargs="?", type=int, default=8080)
    parser.add_argument(
        "--token",
        default="",
        help="Shared-Secret (DICTUSB_TOKEN); ohne Angabe aus der "
        "Umgebungsvariable DICTUSB_TOKEN oder pico/settings.toml gelesen",
    )
    parser.add_argument(
        "--no-echo",
        action="store_true",
        help="gesendete Zeichen nicht lokal im Terminal anzeigen",
    )
    parser.add_argument(
        "--tasten",
        action="store_true",
        help="Tasten-Modus: alle Tastendrücke abgreifen, Cmd<->Strg tauschen (braucht pynput)",
    )
    args = parser.parse_args()
    token = args.token or read_local_token()

    try:
        sock = connect(args.host, args.port, token)
    except OSError as e:
        print(f"Verbindung zu {args.host}:{args.port} fehlgeschlagen: {e}", file=sys.stderr)
        return 1
    print(f"Verbunden mit {args.host}:{args.port}.", file=sys.stderr)

    try:
        if args.tasten:
            rc = run_capture(sock, echo=not args.no_echo)
            if rc:
                return rc
        elif sys.stdin.isatty():
            run_interactive(sock, echo=not args.no_echo)
        else:
            run_pipe(sock)
    except (BrokenPipeError, ConnectionResetError):
        print("Verbindung vom Pico getrennt.", file=sys.stderr)
        return 1
    finally:
        sock.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
