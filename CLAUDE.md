# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Einstieg

Zum Einstieg zuerst **`Handoff.md`** lesen — dort stehen Ziel, gewählte
Lösung, Stolpersteine und der nächste Schritt. Diese Datei hier fasst nur
das Nötigste zusammen.

## Projekt

**dictUSB**: Text soll live vom Mac an einen Windows-PC gesendet und dort
als echte Tastatureingabe (USB-HID) ankommen. Da Mac und Windows beide
USB-Hosts sind, sitzt ein **Raspberry Pi Pico 2 W** (RP2350, WLAN) als
Zwischengerät am Windows-PC.

### Architektur / Datenfluss

```
Mac --(WLAN, TCP-Socket)--> Pico 2 W --(USB-HID)--> Windows-PC
```

- Pico steckt per USB am Windows-PC (HID-Tastatur + Strom); der Mac
  erreicht ihn **nur** über WLAN — es gibt keinen zweiten Kabelweg.
- Firmware: **CircuitPython** mit `adafruit_hid`.
- Der Pico öffnet einen TCP-Server; empfangene Bytes werden Zeichen für
  Zeichen als Tastendrücke getippt.

### Komponenten

- `firmware/boot.py` — reduziert USB-HID auf reine Tastatur
- `firmware/code.py` — WLAN-Verbindung, TCP-Server (`socketpool`), HID-Tippen,
  Token-Check, WLAN-Reconnect, UTF-8-Stream-Dekodierung
- `firmware/settings.toml.example` — Vorlage; echte `settings.toml` mit
  WLAN-Zugangsdaten ist in `.gitignore` (niemals committen)
- `mac/dictusb.py` — Client: interaktiv (raw mode, Zeichen einzeln,
  TCP_NODELAY, Ende mit Ctrl-]) oder Pipe-Modus (`echo … | dictusb.py`)

Installations- und Flash-Anleitung: `README.md`.

## Entwicklung

Kein Build-System, keine Tests: CircuitPython-Dateien werden direkt auf
das `CIRCUITPY`-Laufwerk des Pico kopiert; der Pico startet `code.py`
nach jedem Speichern neu. Debug-Ausgaben über die serielle Konsole
(z.B. `screen /dev/tty.usbmodem* 115200`). Libraries (`adafruit_hid`)
kommen aus dem CircuitPython-Library-Bundle nach `/lib` auf dem Pico.

## Kritische Randbedingungen (Details in Handoff.md)

- **Tastaturlayout:** Windows interpretiert HID-Keycodes nach seinem
  eingestellten Layout. Bei deutschem QWERTZ sind `y/z`, Umlaute, `ß`
  und Sonderzeichen betroffen — Layout-Entscheidung früh treffen und
  Zeichensatz testen (z.B. `KeyboardLayoutDE` aus Community-Layouts).
- **Latenz** hat Priorität: WLAN-Hop dominiert; TCP_NODELAY / sofortiges
  Senden einzelner Zeichen, gleiches WLAN/AP.
- **Sicherheit:** Offener Socket im WLAN — später Token/Shared-Secret.
- **Robustheit:** WLAN-Reconnect, Verbindungsabbrüche, Steuerzeichen
  (Enter, Tab, Backspace) definieren.

## Handoff aktualisieren

Wenn Stefan die `Handoff.md` aktualisieren lässt, umfasst das immer auch:

1. **`Handoff.md` fortschreiben** — mit allem, was man braucht, um in
   einer neuen Session nahtlos weiterzuarbeiten (Stand, offene Punkte,
   nächste Schritte, relevante Pfade/Befehle/Fallen).
2. **Auto-Memory aktualisieren** — betroffene Memory-Dateien und
   `MEMORY.md` nachziehen.
3. **Committen** — die Änderungen im lokalen Repo dieses Workspace
   festhalten (sobald das Repo initialisiert ist).
