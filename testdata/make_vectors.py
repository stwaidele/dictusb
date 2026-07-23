#!/usr/bin/env python3
"""Erzeugt testdata/vectors.json aus der Referenz-Implementierung und
prueft die Datei anschliessend gegen sie zurueck.

  ./testdata/make_vectors.py            # erzeugen (ueberschreibt)
  ./testdata/make_vectors.py --check    # nur pruefen, nichts schreiben

Die Datei ist der Vertrag fuer weitere Implementierungen (Go, C, JS):
wer alle 'frame'-Werte bitgleich reproduziert und sie entschluesseln
kann, ist kompatibel. Siehe PROTOCOL.md, Abschnitt 10.
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "pico"))

import dictusb_crypto as dc  # noqa: E402

OUT = os.path.join(HERE, "vectors.json")

# Feste Eingaben — bewusst mit Sonderfaellen:
# leeres/kurzes Token, Token > 64 Byte (RFC-2104-Hashing), Umlaute,
# Kombi-Sequenz, Nullbytes, 1 Byte, exakt 255 Byte (8 Keystream-Bloecke).
CASES = [
    {
        "name": "kurzes Token, ASCII",
        "token": "geheim123",
        "salt": "000102030405060708090a0b0c0d0e0f",
        "payloads": ["61", "48616c6c6f2057656c74"],
    },
    {
        "name": "32-Hex-Token (Empfehlung), Umlaute und Kombi",
        "token": "556501a4bb820675decb2c06e991c9cc",
        "salt": "f0e1d2c3b4a5968778695a4b3c2d1e0f",
        "payloads": [
            "c3a4c3b6c3bcc39f",  # äöüß
            "006374726c2b700a",  # \x00ctrl+p\n
            "00",  # einzelnes Nullbyte
        ],
    },
    {
        "name": "Token laenger als 64 Byte (wird vorher gehasht)",
        "token": "L" * 100,
        "salt": "aaaaaaaabbbbbbbbccccccccdddddddd",
        "payloads": ["".join("%02x" % (i % 256) for i in range(255))],
    },
    {
        "name": "Token mit Sonderzeichen und Umlaut",
        "token": "pa$$wört mit Leerzeichen",
        "salt": "0123456789abcdef0123456789abcdef",
        "payloads": ["ff00ff00", "7a"],
    },
]


def hexs(b):
    return "".join("%02x" % x for x in b)


def unhex(s):
    return bytes(int(s[i : i + 2], 16) for i in range(0, len(s), 2))


def build():
    cases = []
    for c in CASES:
        salt = unhex(c["salt"])
        k_enc, k_mac = dc.derive_keys(c["token"], salt)
        enc = dc.Encryptor(c["token"], salt)
        frames = []
        for seq, p_hex in enumerate(c["payloads"]):
            plain = unhex(p_hex)
            frame = enc.encrypt(plain)  # genau ein Frame (<= 255 Byte)
            ln = frame[0]
            frames.append(
                {
                    "seq": seq,
                    "plaintext": p_hex,
                    "ct": hexs(frame[1 : 1 + ln]),
                    "mac": hexs(frame[1 + ln :]),
                    "frame": hexs(frame),
                }
            )
        acker = dc.AckSender(c["token"], salt)
        cases.append(
            {
                "name": c["name"],
                "token": c["token"],
                "salt": c["salt"],
                "banner": dc.make_banner(salt).decode("ascii"),
                "k_enc": hexs(k_enc),
                "k_mac": hexs(k_mac),
                "k_ack": hexs(dc.derive_ack_key(c["token"], salt)),
                # Quittungen des Servers auf Herzschlaege (Rueckrichtung)
                "acks": [hexs(acker.next()) for _ in range(3)],
                "frames": frames,
            }
        )
    return {
        "protocol": "DICTUSB2",
        "comment": "Erzeugt von testdata/make_vectors.py — siehe PROTOCOL.md",
        "cases": cases,
    }


def check(data):
    """Prueft die Vektoren gegen die Referenz: Keys, Banner, Frames
    (erzeugen) und Entschluesselung (lesen)."""
    problems = []
    for c in data["cases"]:
        salt = unhex(c["salt"])
        k_enc, k_mac = dc.derive_keys(c["token"], salt)
        if hexs(k_enc) != c["k_enc"] or hexs(k_mac) != c["k_mac"]:
            problems.append("%s: Schluessel weichen ab" % c["name"])
        if dc.make_banner(salt).decode("ascii") != c["banner"]:
            problems.append("%s: Banner weicht ab" % c["name"])
        if hexs(dc.derive_ack_key(c["token"], salt)) != c.get("k_ack"):
            problems.append("%s: K_ack weicht ab" % c["name"])
        acker = dc.AckSender(c["token"], salt)
        rec = dc.AckReceiver(c["token"], salt)
        for i, want in enumerate(c.get("acks", [])):
            got = acker.next()
            if hexs(got) != want:
                problems.append("%s: Quittung %d weicht ab" % (c["name"], i))
            if rec.feed(got) != 1:
                problems.append("%s: Quittung %d nicht akzeptiert" % (c["name"], i))
        enc = dc.Encryptor(c["token"], salt)
        dec = dc.FrameDecryptor(c["token"], salt)
        for f in c["frames"]:
            got = enc.encrypt(unhex(f["plaintext"]))
            if hexs(got) != f["frame"]:
                problems.append("%s seq %d: Frame weicht ab" % (c["name"], f["seq"]))
            back = dec.feed(unhex(f["frame"]))
            if hexs(back) != f["plaintext"]:
                problems.append(
                    "%s seq %d: Entschluesselung weicht ab" % (c["name"], f["seq"])
                )
    return problems


def main():
    check_only = "--check" in sys.argv
    if check_only:
        with open(OUT) as f:
            data = json.load(f)
    else:
        data = build()
    problems = check(data)
    for p in problems:
        print("FEHLER:", p)
    if problems:
        return 1
    if not check_only:
        with open(OUT, "w") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
        print("geschrieben:", OUT)
    n = sum(len(c["frames"]) for c in data["cases"])
    print("ok: %d Faelle, %d Frames stimmen mit der Referenz ueberein"
          % (len(data["cases"]), n))
    return 0


if __name__ == "__main__":
    sys.exit(main())
