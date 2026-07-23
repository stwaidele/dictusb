"""dictUSB: Onboard-LED als Zustandsanzeige.

Ein Code fuer alle Boards: Beim Bau wird die Faehigkeit erkannt und das
passende Backend gewaehlt — RGB (NeoPixel), einfarbig (an/aus) oder gar
nichts. Boards ohne LED laufen damit unveraendert weiter.

Zustaende:
  ready      bereit, wartet auf Verbindung   -> gelb / langsames Blinken
  connected  Verbindung steht                -> gruen 50 %  / Dauerlicht
  activity   echter Tastendruck              -> kurz 100 %, 5 s Fade -> 50 %
  aborted    unerwarteter Abbruch            -> rot blinkend ~3 s -> ready

Die Farb-/Helligkeitsberechnung (compute()) ist eine reine Funktion des
Zustands und der Zeit — dadurch ohne Hardware testbar. update(now) muss
oft genug aufgerufen werden (die Firmware tut das ~10x/s), damit Fade und
Blinken fluessig laufen.
"""

# Zustaende
OFF = "off"
READY = "ready"
CONNECTED = "connected"
ABORTED = "aborted"

# Zeiten (Sekunden)
FADE_TIME = 0.2        # Tastendruck: Aktivfarbe -> Verbindungsfarbe (Default)
ABORT_TIME = 3.0       # Dauer des Rot-Blinkens, dann zurueck auf ready
READY_BLINK = 1.0      # Mono: An/Aus-Periode je Haelfte im Ready-Zustand
ABORT_BLINK = 0.2      # Blink-Halbperiode waehrend Abbruch (rot/schnell)
MONO_FLICKER = 0.1     # Mono: kurzes Aus-Flackern je Tastendruck

# Helligkeitsstufen (Anteil der Obergrenze)
CONNECTED_LEVEL = 0.5  # Grundhelligkeit im Verbindungszustand
ACTIVITY_LEVEL = 1.0   # Spitzenhelligkeit direkt nach einem Tastendruck

# Standardfarben (r, g, b) bei voller Helligkeit — ueber settings.toml
# ueberschreibbar (DICTUSB_LED_READY/_CONNECTED/_ACTIVITY/_ABORT).
YELLOW = (255, 255, 0)      # ready
GREEN = (0, 255, 0)         # connected
RED = (255, 0, 0)           # aborted
ACTIVITY_COLOR = (0, 255, 255)  # Tastendruck-Tupfer (Cyan), blendet zu GREEN


def default_config():
    """Farb-/Zeit-Konfiguration mit den Standardwerten."""
    return {
        "fade": FADE_TIME,
        "ready": YELLOW,
        "connected": GREEN,
        "activity": ACTIVITY_COLOR,
        "abort": RED,
    }


def parse_color(s, default):
    """"rrggbb"-Hex oder "r,g,b" -> (r,g,b). Ungueltig/leer -> default."""
    if not s:
        return default
    s = s.strip().lstrip("#")
    try:
        if "," in s:
            parts = [int(x) for x in s.split(",")]
        else:
            parts = [int(s[i : i + 2], 16) for i in (0, 2, 4)]
        if len(parts) == 3 and all(0 <= v <= 255 for v in parts):
            return (parts[0], parts[1], parts[2])
    except (ValueError, IndexError):
        pass
    return default


def config_from_env(getenv):
    """Baut die Konfiguration aus settings.toml-Werten (getenv = os.getenv).
    Fehlende/ungueltige Werte fallen auf die Standardwerte zurueck."""
    try:
        fade = float(getenv("DICTUSB_LED_FADE") or FADE_TIME)
    except ValueError:
        fade = FADE_TIME
    if fade <= 0:  # Division-durch-Null vermeiden
        fade = FADE_TIME
    return {
        "fade": fade,
        "ready": parse_color(getenv("DICTUSB_LED_READY"), YELLOW),
        "connected": parse_color(getenv("DICTUSB_LED_CONNECTED"), GREEN),
        "activity": parse_color(getenv("DICTUSB_LED_ACTIVITY"), ACTIVITY_COLOR),
        "abort": parse_color(getenv("DICTUSB_LED_ABORT"), RED),
    }


def compute(state, now, last_activity, abort_start, cfg):
    """Liefert (r, g, b) fuer den RGB-Fall, 0..255, Helligkeit schon
    eingerechnet — oder None, wenn die LED aus sein soll (Blink-Aus).

    Reine Funktion: haengt nur von den Argumenten ab, nicht von Hardware.
    Fuer das Mono-Backend zaehlt nur, ob das Ergebnis None (aus) oder
    nicht-None (an) ist, plus die Farbe fuer den RGB-Fall.
    """
    if state == CONNECTED:
        level = CONNECTED_LEVEL
        color = cfg["connected"]
        if last_activity is not None:
            elapsed = now - last_activity
            if elapsed < cfg["fade"]:
                # frac 1..0 ueber fade: Farbe von activity zurueck auf
                # connected UND Helligkeit von ACTIVITY_LEVEL auf CONNECTED_LEVEL.
                frac = 1.0 - elapsed / cfg["fade"]
                level = CONNECTED_LEVEL + (ACTIVITY_LEVEL - CONNECTED_LEVEL) * frac
                color = _lerp(cfg["connected"], cfg["activity"], frac)
        return _scale(color, level)
    if state == READY:
        return _scale(cfg["ready"], 1.0)
    if state == ABORTED:
        # rot blinken; Blink-Aus liefert None
        phase = int((now - abort_start) / ABORT_BLINK)
        return _scale(cfg["abort"], 1.0) if phase % 2 == 0 else None
    return None  # OFF


def _scale(color, level):
    if level <= 0:
        return None
    return tuple(int(c * level) for c in color)


def _lerp(a, b, t):
    """Farb-Interpolation: t=0 -> a, t=1 -> b."""
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


class StatusLED:
    """Zustandsmaschine + Hardware-Ansteuerung. Das Backend
    (RGB/Mono/Null) wird beim Bau erkannt; alle oeffentlichen Methoden
    funktionieren unabhaengig davon."""

    def __init__(self, backend, max_brightness=0.5, cfg=None):
        self._be = backend
        self._max = max_brightness
        self._cfg = cfg or default_config()
        self._state = OFF
        self._last_activity = None
        self._abort_start = 0.0
        self._last_output = object()  # erzwingt erstes Schreiben

    @property
    def kind(self):
        return self._be.kind

    def ready(self):
        self._state = READY
        self._last_activity = None

    def connected(self):
        self._state = CONNECTED
        self._last_activity = None

    def activity(self, now):
        # Nur relevant, wenn verbunden; setzt den Helligkeits-Peak.
        if self._state == CONNECTED:
            self._last_activity = now

    def aborted(self, now):
        self._state = ABORTED
        self._abort_start = now

    def off(self):
        self._state = OFF

    def update(self, now):
        """Berechnet die aktuelle Ausgabe und schreibt sie ins Backend.
        Der Abbruch-Zustand geht nach ABORT_TIME selbsttaetig auf ready."""
        if self._state == ABORTED and now - self._abort_start >= ABORT_TIME:
            self.ready()
        rgb = compute(self._state, now, self._last_activity, self._abort_start, self._cfg)
        # Mono-spezifisch: eine einfarbige LED kann keine Farbe/Helligkeit,
        # daher hier aus compute()s Dauerlicht die sichtbaren Muster machen,
        # ohne die reine Funktion (RGB-Fall) zu verkomplizieren.
        if self._be.kind == "mono":
            if self._state == READY and int(now / READY_BLINK) % 2 == 1:
                rgb = None  # langsames Blinken = bereit
            elif (
                self._state == CONNECTED
                and self._last_activity is not None
                and now - self._last_activity < MONO_FLICKER
            ):
                rgb = None  # kurzes Aus-Flackern = Tastendruck
        out = None if rgb is None else _scale(rgb, self._max)
        if out != self._last_output:
            self._be.show(out)
            self._last_output = out


# --- Backends --------------------------------------------------------------


class NullBackend:
    kind = "keine"

    def show(self, rgb):
        pass


class RgbBackend:
    """Einzelne WS2812/NeoPixel ueber das Core-Modul neopixel_write —
    keine zusaetzliche Library noetig. WS2812 erwarten die Farbreihenfolge
    GRB; kommen Farben vertauscht, hier die Reihenfolge anpassen."""

    kind = "rgb"

    def __init__(self, neopixel_write, dio):
        self._write = neopixel_write
        self._dio = dio
        self._buf = bytearray(3)

    def show(self, rgb):
        r, g, b = (0, 0, 0) if rgb is None else rgb
        self._buf[0] = g
        self._buf[1] = r
        self._buf[2] = b
        self._write(self._dio, self._buf)


class MonoBackend:
    kind = "mono"

    def __init__(self, dio):
        self._dio = dio

    def show(self, rgb):
        self._dio.value = rgb is not None


def make(enabled=True, brightness=0.5, pin_name=None, cfg=None):
    """Baut eine StatusLED mit dem besten verfuegbaren Backend.

    Reihenfolge: RGB (NeoPixel) -> Mono (board.LED) -> Null. Jede Stufe
    ist in try/except gekapselt, damit ein fehlendes Modul, ein fehlender
    Pin oder gar keine LED nur zur naechsten Stufe fuehrt, nie zum Absturz.
    """
    if not enabled:
        return StatusLED(NullBackend(), brightness, cfg)

    try:
        import board
    except ImportError:
        return StatusLED(NullBackend(), brightness, cfg)  # kein CircuitPython

    # 1) RGB / NeoPixel ueber das Core-Modul neopixel_write (keine Library)
    try:
        import digitalio
        from neopixel_write import neopixel_write

        pin = getattr(board, pin_name) if pin_name else board.NEOPIXEL
        dio = digitalio.DigitalInOut(pin)
        dio.direction = digitalio.Direction.OUTPUT
        return StatusLED(RgbBackend(neopixel_write, dio), brightness, cfg)
    except (ImportError, AttributeError, ValueError, RuntimeError):
        pass

    # 2) Einfarbige An/Aus-LED
    try:
        import digitalio

        dio = digitalio.DigitalInOut(board.LED)
        dio.direction = digitalio.Direction.OUTPUT
        return StatusLED(MonoBackend(dio), brightness, cfg)
    except (ImportError, AttributeError, ValueError, RuntimeError):
        pass

    # 3) Keine LED
    return StatusLED(NullBackend(), brightness, cfg)
