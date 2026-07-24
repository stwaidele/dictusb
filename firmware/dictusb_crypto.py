"""dictUSB: gemeinsame Krypto-Schicht fuer Mac-Client und Pico (DICTUSB2).

Laeuft unveraendert auf CPython (Mac) und CircuitPython (Pico): nur
hashlib.new("sha256") mit update()/digest() — kein copy(), kein
hexdigest(), keine weiteren Abhaengigkeiten.

Protokoll (aktiv, sobald DICTUSB_TOKEN gesetzt ist):

  Server -> Client:  b"DICTUSB2 " + 32 Hex (16-Byte-Salt) + b"\\n"  (Klartext)
  Ableitung:         K_enc = HMAC(token, b"enc"+salt)
                     K_mac = HMAC(token, b"mac"+salt)
  Frames Client -> Server (seq ab 0, Klartext 1..255 Bytes):
      Keystream-Block j = HMAC(K_enc, seq_8B_BE + j_1B)   (HMAC als PRF,
      CTR-Konstruktion), ct = Klartext XOR Keystream
      mac = HMAC(K_mac, seq_8B_BE + len_1B + ct)[:8]
      frame = len_1B + ct + mac
  Authentisierung = erster Frame mit gueltigem MAC; das Token selbst
  wird nie uebertragen. Ein Rueckkanal (Server->Client-Daten) braeuchte
  eigene Keys und eigene seq — den gibt es derzeit nicht.

Grenzen: Frame-Laengen und -Timing bleiben sichtbar (Keystroke-Timing),
keine Server-Authentisierung, kein Schutz gegen Offline-Wörterbuch-
Angriffe auf schwache Tokens — Token daher hochentropisch waehlen
(z.B. python3 -c 'import os; print(os.urandom(16).hex())').
"""

import hashlib

BANNER_PREFIX = b"DICTUSB2 "
SALT_LEN = 16
MAC_LEN = 8
MAX_PLAIN = 255
_BLOCK = 64  # SHA-256-Blockgroesse (HMAC)

# Lebenszeichen (siehe PROTOCOL.md, Abschnitt 6):
# Der Client schickt bei Untaetigkeit HEARTBEAT — eine leere
# Kombinations-Spezifikation, die die Firmware verwirft, ohne zu tippen.
# Der Server quittiert jeden Herzschlag mit ACK_LEN authentifizierten
# Bytes, damit auch der Client merkt, wenn das Geraet verschwindet.
HEARTBEAT = b"\x00\n"
ACK_LEN = 8


class MacError(Exception):
    """MAC- oder Protokollfehler im Frame-Strom — Verbindung schliessen."""


def _sha256(*parts):
    h = hashlib.new("sha256")
    for p in parts:
        h.update(p)
    return h.digest()


class Hmac:
    """HMAC-SHA256 mit einmal vorberechneten Pads (RFC 2104).

    Pro digest() werden nur zwei frische Hash-Objekte gebraucht —
    wichtig, weil CircuitPython-hashlib kein copy() kann und Objekte
    nach digest() finalisiert sind.
    """

    def __init__(self, key):
        if len(key) > _BLOCK:
            key = _sha256(key)
        ipad = bytearray(_BLOCK)
        opad = bytearray(_BLOCK)
        for i in range(_BLOCK):
            k = key[i] if i < len(key) else 0
            ipad[i] = k ^ 0x36
            opad[i] = k ^ 0x5C
        self._ipad = bytes(ipad)
        self._opad = bytes(opad)

    def digest(self, *parts):
        return _sha256(self._opad, _sha256(self._ipad, *parts))


def derive_keys(token, salt):
    """(K_enc, K_mac) aus Token (str) und Session-Salt (SALT_LEN Bytes)."""
    t = Hmac(token.encode("utf-8"))
    return t.digest(b"enc", salt), t.digest(b"mac", salt)


def derive_ack_key(token, salt):
    """Eigener Schluessel fuer die Rueckrichtung. Getrennt von K_enc/K_mac,
    damit sich Quittungen nicht als Client-Frames wiederverwenden lassen."""
    return Hmac(token.encode("utf-8")).digest(b"ack", salt)


class AckSender:
    """Server-Seite: erzeugt fortlaufende Quittungen."""

    def __init__(self, token, salt):
        self._h = Hmac(derive_ack_key(token, salt))
        self._seq = 0

    def next(self):
        a = self._h.digest(self._seq.to_bytes(8, "big"))[:ACK_LEN]
        self._seq += 1
        return a


class AckReceiver:
    """Client-Seite: prueft die Quittungen des Servers."""

    def __init__(self, token, salt):
        self._h = Hmac(derive_ack_key(token, salt))
        self._seq = 0
        self._buf = bytearray()

    def feed(self, data):
        """Nimmt rohe Bytes vom Socket, gibt die Zahl gueltiger Quittungen
        zurueck. Wirft MacError, wenn eine Quittung nicht passt — dann
        spricht die Gegenstelle nicht mit unserem Token."""
        self._buf = self._buf + data
        n = 0
        while len(self._buf) >= ACK_LEN:
            want = self._h.digest(self._seq.to_bytes(8, "big"))[:ACK_LEN]
            got = bytes(self._buf[:ACK_LEN])
            diff = 0
            for i in range(ACK_LEN):  # konstantzeitiger Vergleich
                diff |= want[i] ^ got[i]
            if diff:
                raise MacError("ungueltige Quittung Nr. %d" % self._seq)
            self._seq += 1
            n += 1
            self._buf = self._buf[ACK_LEN:]
        return n


def _keystream_xor(h_enc, seq, data):
    """XORt data mit dem Keystream von Frame seq; gibt bytearray zurueck."""
    seq_b = seq.to_bytes(8, "big")
    out = bytearray(data)
    for j in range((len(out) + 31) // 32):
        block = h_enc.digest(seq_b, bytes([j]))
        base = j * 32
        for i in range(min(32, len(out) - base)):
            out[base + i] ^= block[i]
    return out


def make_banner(salt):
    return BANNER_PREFIX + "".join("%02x" % b for b in salt).encode() + b"\n"


def parse_banner(line):
    """Banner-Zeile -> Salt. Wirft ValueError bei jedem Formatfehler —
    der Client darf NIE auf Klartext zurueckfallen."""
    if not line.startswith(BANNER_PREFIX) or not line.endswith(b"\n"):
        raise ValueError("kein DICTUSB2-Banner")
    hexpart = line[len(BANNER_PREFIX):-1]
    if len(hexpart) != SALT_LEN * 2:
        raise ValueError("Salt-Laenge falsch")
    try:
        return bytes(
            int(hexpart[i : i + 2], 16) for i in range(0, len(hexpart), 2)
        )
    except ValueError:
        raise ValueError("Salt ist kein Hex")


class Encryptor:
    """Client-Seite: framet (<=255 B), verschluesselt und MACt."""

    def __init__(self, token, salt):
        k_enc, k_mac = derive_keys(token, salt)
        self._h_enc = Hmac(k_enc)
        self._h_mac = Hmac(k_mac)
        self._seq = 0

    def encrypt(self, data):
        """Beliebig lange Klartext-Bytes -> Frame-Bytes fuer den Socket."""
        frames = bytearray()
        for off in range(0, len(data), MAX_PLAIN):
            chunk = data[off : off + MAX_PLAIN]
            ct = bytes(_keystream_xor(self._h_enc, self._seq, chunk))
            seq_b = self._seq.to_bytes(8, "big")
            ln = bytes([len(ct)])
            mac = self._h_mac.digest(seq_b, ln, ct)[:MAC_LEN]
            frames += ln + ct + mac
            self._seq += 1
        return bytes(frames)


class FrameDecryptor:
    """Server-Seite: sammelt Frame-Bytes, liefert Klartext zurueck."""

    def __init__(self, token, salt):
        k_enc, k_mac = derive_keys(token, salt)
        self._h_enc = Hmac(k_enc)
        self._h_mac = Hmac(k_mac)
        self._seq = 0
        self._buf = bytearray()
        # Zahl der seit dem letzten take_heartbeats() empfangenen
        # Herzschlaege. Frame-genau gezaehlt: mehrere Frames koennen in
        # einem recv() ankommen, dann waere ein Vergleich des gesamten
        # Klartexts mit HEARTBEAT blind fuer den Herzschlag darin.
        self._beats = 0

    def take_heartbeats(self):
        """Liefert die Zahl neuer Herzschlaege und setzt den Zaehler zurueck."""
        n = self._beats
        self._beats = 0
        return n

    def feed(self, data):
        """Nimmt rohe Socket-Bytes, gibt entschluesselten Klartext zurueck
        (b"" solange nur Teilframes da sind). Wirft MacError bei MAC-/
        Protokollfehler; danach ist der Strom unbrauchbar."""
        self._buf += data
        plain = bytearray()
        while self._buf:
            ln = self._buf[0]
            if ln == 0:
                raise MacError("Frame mit Laenge 0")
            end = 1 + ln + MAC_LEN
            if len(self._buf) < end:
                break  # Teilframe: auf mehr Daten warten
            ct = bytes(self._buf[1 : 1 + ln])
            mac = bytes(self._buf[1 + ln : end])
            seq_b = self._seq.to_bytes(8, "big")
            want = self._h_mac.digest(seq_b, bytes([ln]), ct)[:MAC_LEN]
            diff = 0
            for i in range(MAC_LEN):  # konstantzeitiger Vergleich
                diff |= want[i] ^ mac[i]
            if diff:
                raise MacError("MAC-Fehler bei Frame %d" % self._seq)
            frame_plain = _keystream_xor(self._h_enc, self._seq, ct)
            if bytes(frame_plain) == HEARTBEAT:
                self._beats += 1
            plain += frame_plain
            self._seq += 1
            # kein "del buf[:end]": CircuitPython-bytearray kann keine
            # Slice-Loeschung — Neuzuweisung ist auf beiden Seiten ok
            self._buf = self._buf[end:]
        return bytes(plain)
