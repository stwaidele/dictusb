# DICTUSB2 — Wire-Protokoll

Sprachneutrale Spezifikation des verschlüsselten dictUSB-Kanals.
Referenz-Implementierung: `firmware/dictusb_crypto.py` (läuft auf CPython
und CircuitPython). Testvektoren: `testdata/vectors.json`.

Wer eine neue Implementierung schreibt (Go, C, JavaScript …), muss
ausschließlich dieses Dokument und die Testvektoren brauchen.

## 1. Rollen und Transport

- **Server** = das USB-Gerät (Pico 2 W, künftig ESP32-S3). Es lauscht
  auf einem TCP-Port (Default 8080) und tippt empfangenen Klartext als
  USB-HID-Tastatur.
- **Client** = Mac-/Terminal-/Browser-Programm. Es verbindet sich und
  sendet Daten.
- Transport ist ein einzelner TCP-Strom. **Nutzdaten fließen nur
  Client → Server.** Der Server sendet nach dem Banner ausschließlich
  Quittungen auf Herzschläge (Abschnitt 6.6).
- Der Server bedient jeweils eine Verbindung (`listen(1)`).

## 2. Betriebsarten

| Server-Konfiguration | Verhalten |
|---|---|
| `DICTUSB_TOKEN` gesetzt (nicht leer) | DICTUSB2, verschlüsselt — Pflicht |
| `DICTUSB_TOKEN` leer/fehlt | Klartext: Bytes werden direkt als Nutzlast gelesen, kein Banner |

Ein Client mit Token **muss** das Banner verlangen und darf **niemals**
auf Klartext zurückfallen. Sonst könnte ein schweigender oder
manipulierter Server das Token im Klartext entlocken (Downgrade).

## 3. Banner (Server → Client, einmalig, unverschlüsselt)

```
"DICTUSB2 " + 32 Hex-Zeichen (Kleinbuchstaben) + "\n"
```

Die 32 Hex-Zeichen sind ein **Salt** von 16 Bytes, das der Server pro
Verbindung neu aus einem kryptografischen Zufallsgenerator zieht
(`os.urandom`). Schlägt der Zufallsgenerator fehl, **muss** der Server
die Verbindung ablehnen — ein Zeit- oder Zähler-Ersatz wäre fatal
(gleiches Salt ⇒ gleicher Keystream).

Der Client prüft strikt: Präfix exakt, genau 32 Hex-Zeichen,
abschließendes `\n`. Jede Abweichung ⇒ Verbindung abbrechen.

## 4. Schlüsselableitung

Das Token wird als UTF-8 kodiert und dient als HMAC-Schlüssel:

```
K_enc = HMAC-SHA256(token_utf8, "enc" || salt)     32 Bytes
K_mac = HMAC-SHA256(token_utf8, "mac" || salt)     32 Bytes
```

`"enc"`/`"mac"` sind die ASCII-Bytes, gleich lang und verschieden — es
gibt keine Konkatenations-Ambiguität. **Das Token selbst wird nie
übertragen.** Beide Seiten leiten unabhängig ab; die Authentisierung
erfolgt implizit über den ersten Frame mit gültigem MAC.

HMAC-SHA256 nach RFC 2104: Schlüssel länger als 64 Bytes werden vorher
mit SHA-256 gehasht, kürzere mit Nullbytes auf 64 aufgefüllt.

## 5. Frames (Client → Server)

Jeder Frame trägt 1..255 Bytes Klartext und hat eine Sequenznummer
`seq`, beginnend bei **0**, pro Frame um 1 erhöht. `seq` wird **nicht**
übertragen — beide Seiten zählen implizit mit (TCP garantiert die
Reihenfolge).

### 5.1 Keystream

```
block(j) = HMAC-SHA256(K_enc, seq_be64 || j_u8)        32 Bytes
keystream = block(0) || block(1) || ...                (so viel wie nötig)
ct = plaintext XOR keystream[0 .. len-1]
```

- `seq_be64`: 8 Bytes, Big-Endian.
- `j_u8`: 1 Byte Blockzähler ab 0. Bei maximal 255 Klartext-Bytes ist
  `j ≤ 7`.
- Das Paar `(seq, j)` ist innerhalb einer Verbindung eindeutig, das
  Salt pro Verbindung frisch ⇒ kein Keystream wird je wiederverwendet.

### 5.2 MAC (Encrypt-then-MAC)

```
mac = HMAC-SHA256(K_mac, seq_be64 || len_u8 || ct)[0..7]     8 Bytes
```

Länge und Sequenznummer sind mitgeschützt. Der Vergleich auf
Server-Seite erfolgt konstantzeitig.

### 5.3 Rahmen auf der Leitung

```
+--------+------------------+-----------+
| len_u8 |   ct (len Bytes) | mac (8 B) |
+--------+------------------+-----------+
```

- `len_u8` = 1..255. **`len == 0` ist ein Protokollfehler.**
- Maximale Frame-Größe: 1 + 255 + 8 = **264 Bytes**. Empfangspuffer
  müssen mindestens so groß sein oder Teilframes zwischenpuffern.
- Frames dürfen über TCP-Segmentgrenzen zerrissen ankommen; der Server
  puffert, bis ein Frame vollständig ist.

## 6. Server-Verhalten

1. Banner senden, Schlüssel ableiten, `seq = 0`.
2. Eingehende Bytes puffern und Frames verarbeiten, solange vollständig.
3. Bei MAC-Fehler, `len == 0` oder anderem Protokollfehler: Vorgang
   protokollieren und **Verbindung schließen**. Keine Fehlermeldung an
   den Client (kein Orakel), kein Weiterlesen.
4. **Deadline:** Kommt innerhalb von 5 Sekunden nach dem Banner kein
   vollständiger, gültiger Frame, wird die Verbindung geschlossen. Das
   begrenzt Port-Scanner und Klartext-Clients, die den
   Einzelverbindungs-Server sonst blockieren würden.
5. Entschlüsselter Klartext geht unverändert in die Nutzlast-Pipeline.

6. **Lebenszeichen.** Der Klartext `0x00 0x0a` (leere
   Kombinations-Spezifikation) ist der **Herzschlag**: Die Firmware
   erkennt die leere Spezifikation, verwirft sie und tippt nichts.
   - Der Client sendet ihn **sofort nach dem Banner** (erfüllt zugleich
     die Deadline aus Punkt 4) und danach bei Untätigkeit mindestens
     alle 20 Sekunden.
   - Der Server **quittiert jeden Herzschlag-Frame** mit
     `HMAC-SHA256(K_ack, ack_seq_be64)[0..7]`, wobei
     `K_ack = HMAC-SHA256(token_utf8, "ack" || salt)` und `ack_seq` bei
     0 beginnt und je Quittung um 1 steigt. Das ist der einzige Fall,
     in dem der Server nach dem Banner sendet. Gezählt wird
     **frame-genau** — mehrere Frames können in einem Empfangsvorgang
     ankommen, ein Vergleich des gesamten Klartexts wäre dann blind.
   - Der Server schließt die Verbindung, wenn **90 Sekunden** lang kein
     gültiger Frame ankommt (`DICTUSB_IDLE_LIMIT`). Das ist kein reines
     Leerlauf-Limit: Solange der Client lebt, hält sein Herzschlag die
     Sitzung offen, auch über lange Pausen. Ohne diese Grenze blockiert
     ein verschwundener Client das Gerät dauerhaft, weil nur **eine**
     Verbindung bedient wird.
   - Der Client wertet ausbleibende Quittungen als verlorenes Gerät,
     sobald schon einmal welche kamen. Bleiben sie von Anfang an aus
     (ältere Firmware), verhält er sich wie bisher.

## 7. Nutzlast-Semantik (unabhängig von der Verschlüsselung)

Der Klartext ist ein **Byte-Strom**, kein Nachrichtenformat. Ein
UTF-8-Zeichen oder eine Steuersequenz darf Frame-Grenzen überschreiten;
der Server dekodiert fortlaufend und hält unvollständige Reste.

- **Text**: UTF-8. Jedes Zeichen wird nach dem eingestellten
  Tastaturlayout getippt.
- **Steuerzeichen**: `\n`/`\r` → Enter (ein `\r\n`-Paar zählt einmal),
  `\t` → Tab, `\x08`/`\x7f` → Backspace, `\x1b` → Escape,
  `\x01`–`\x1a` → Strg + zugehöriger Buchstabe. Übrige Bytes < 0x20
  ohne eigene Bedeutung werden verworfen.
- **Tastenkombinationen**: `0x00` + Spezifikation (ASCII) + `\n`,
  z. B. `\x00ctrl+shift+p\n`, `\x00win+e\n`.
  Modifier: `ctrl`, `alt`, `shift`, `win` (auch `gui`/`cmd`).
  Taste: einzelnes Zeichen (layoutabhängig) oder Name — `enter`, `tab`,
  `esc`, `backspace`, `delete`, `insert`, `space`, `up`, `down`,
  `left`, `right`, `home`, `end`, `pageup`, `pagedown`, `f1`…`f12`.
  Seit Firmware 0.18 darf die Taste auch ein **Modifier-Name allein**
  sein: `\x00shift\n` tippt Shift an, ohne ein Zeichen zu senden
  (z. B. um den Bildschirmschoner des Ziels zu beenden); ebenso
  `ctrl`, `alt`, `win`.
  Unbekannte Spezifikationen werden protokolliert und verworfen;
  Sequenzen über 32 Zeichen ohne `\n` werden verworfen.

## 8. Sicherheitseigenschaften und Grenzen

**Geschützt:** Vertraulichkeit und Integrität der Nutzlast,
Authentisierung des Clients, Replay über Verbindungsgrenzen hinweg
(frisches Salt) und innerhalb einer Verbindung (implizite Sequenz).
Das Token verlässt nie das Gerät.

**Nicht geschützt:**
- **Token-Qualität**: Salt, ct und MAC sind mitlesbar, also lässt sich
  ein schwaches Token offline durchprobieren. Das Token **muss**
  hochentropisch sein, z. B. `os.urandom(16).hex()` (32 Hex-Zeichen).
  Es gibt bewusst kein Key-Stretching (Latenz auf dem Mikrocontroller).
- **Metadaten**: Frame-Längen und -Zeitpunkte bleiben sichtbar; bei
  Einzelanschlägen ist Keystroke-Timing-Analyse möglich.
- **Server-Authentisierung**: Der Client kann einen falschen Server
  nicht erkennen. Dieser kann nichts entschlüsseln, aber den Nutzer ins
  Leere tippen lassen.
- **Verfügbarkeit**: Kein Schutz gegen Verbindungs-Flooding.
- Das Web-Interface des Geräts (CircuitPython Web Workflow, Port 80)
  ist reines HTTP und **nicht** Teil dieses Protokolls.

## 9. Versionierung

Das Banner trägt den Namen `DICTUSB2`. Jede inkompatible Änderung
erhöht die Zahl (`DICTUSB3`, …); Clients weisen unbekannte Banner ab.

## 10. Testvektoren

`testdata/vectors.json` enthält zu festen Tokens und Salts die
erwarteten Werte (alles hex-kodiert):

- `k_enc`, `k_mac` — abgeleitete Schlüssel
- `frames[]` — je Eintrag `seq`, `plaintext`, `ct`, `mac`, `frame`
  (der komplette Rahmen inklusive Längenbyte)
- `banner` — die vollständige Bannerzeile zum Salt

Erzeugt und gegengeprüft wird die Datei von
`testdata/make_vectors.py`. Eine neue Implementierung gilt als korrekt,
wenn sie alle `frame`-Werte bitgleich reproduziert und die Frames aus
der Datei entschlüsselt.
