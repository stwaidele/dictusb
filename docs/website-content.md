# Website-Inhalt: werkzeugkasten.online/dictusb

> Vorbereiteter Inhalt für die dictUSB-Unterseite auf
> werkzeugkasten.online (WP6). Umsetzung als SvelteKit-Unterseite im
> Werkzeugkasten-Workspace (sveltekit-tool-Konventionen). Dieses
> Dokument ist die inhaltliche Quelle — Texte können beim Umsetzen
> redaktionell angepasst werden, Fakten (Preise, Befehle, Links)
> bitte unverändert übernehmen.
>
> Alle IPs im Text sind **Beispielwerte** (192.168.0.50/.51).

---

## Hero

**Titel:** dictUSB

**Claim:** Text live von einem Rechner auf einen anderen tippen — ohne
Software auf dem Zielrechner.

**Subclaim:** Ein Mikrocontroller für ca. 10 € steckt per USB am
Zielrechner und ist dort eine ganz normale Tastatur. Gesendet wird per
WLAN, Ende-zu-Ende verschlüsselt.

**Primärer Button:** App herunterladen →
<https://github.com/stwaidele/dictusb/releases/latest>

**Sekundärer Button:** Quellcode auf GitHub →
<https://github.com/stwaidele/dictusb> (MIT-Lizenz)

**Hero-Bild:** App-Icon (`docs/img/dictusb-icon-1024.png`) und/oder
Screenshot Blockmodus (`docs/img/app-blockmodus.png`).

---

## Der Anwendungsfall, aus dem dictUSB entstanden ist

Auf einem MacBook läuft eine lokale Diktiersoftware — schnell, präzise,
und die Sprache verlässt das Gerät nie. Im Bestand stehen aber auch
Windows- und Linux-Rechner, die dafür zu knapp ausgestattet sind: zu
wenig Leistung für lokale Spracherkennung, oder die Programme sind auf
den anderen Betriebssystemen so nicht verfügbar.

Mit dictUSB diktiert man einfach **am MacBook weiter** — und der Text
erscheint auf dem anderen Rechner, als würde ihn dort jemand auf einer
angeschlossenen Tastatur eintippen. Der Zielrechner braucht dafür
**nichts**: keine Installation, keine Treiber, keine Adminrechte, keine
Cloud. Er sieht nur eine USB-Tastatur.

Dasselbe Prinzip trägt weiter als nur Diktat: Lange
Konfigurationszeilen auf Server tippen (funktioniert sogar im BIOS und
am Anmeldebildschirm), Textbausteine auf einen Zweitrechner schicken,
oder einen Rechner fernbedienen, auf dem keine Fernwartung möglich ist.

---

## Wie es funktioniert

**Diagramm** (auf der Website als Grafik umsetzen):

```
Sender (macOS / Linux / Windows)
        │  WLAN, TCP — Ende-zu-Ende verschlüsselt (DICTUSB2)
        ▼
Raspberry Pi Pico 2 W  oder  ESP32-S3   (~10 €)
        │  USB — meldet sich als ganz normale HID-Tastatur
        ▼
Zielrechner (Windows / Linux — auch BIOS, Login-Screen, TTY)
```

Drei Schritte im Betrieb:

1. Der Mikrocontroller steckt per USB am Zielrechner — Strom und
   Tastatur-Anschluss in einem. Er verbindet sich mit dem WLAN.
2. Die dictUSB-App auf dem Sender (macOS, Windows oder Linux) verbindet
   sich per WLAN mit dem Mikrocontroller.
3. Was man in der App tippt, einfügt oder diktiert, tippt der
   Mikrocontroller auf dem Zielrechner — Zeichen für Zeichen, wie eine
   echte Tastatur.

**Weil auf dem Zielrechner keine Software läuft, funktioniert es
überall gleich**: in jedem Programm, im Terminal, auf der Textkonsole,
im BIOS-Setup und am Anmeldebildschirm — ganz ohne Rechte auf dem
Zielsystem. Die einzige Konsequenz daraus: Der Zielrechner interpretiert
die Tastendrücke nach **seiner** Tastaturbelegung; die wird deshalb
einmal am Gerät eingestellt (deutsch ist Standard, weitere Layouts
möglich).

---

## Die App

Ein Sender-Client für **macOS, Windows und Linux** (Flutter), als
fertiger Download. Screenshots: `docs/img/app-blockmodus.png`,
`docs/img/app-direktmodus.png`, `docs/img/app-einstellungen.png`.

- **Blockmodus**: Text in Ruhe eingeben oder diktieren, prüfen, dann
  als Ganzes senden. Ideal für Diktat: erst wenn der Text stimmt, geht
  er raus.
- **Direktmodus**: jeder Tastendruck geht sofort an den Zielrechner —
  die App wird zur Fernbedienung inklusive Tastenkombinationen
  (Strg+…, Alt+…, Windows-Taste). Modifier-Mapping konfigurierbar,
  auf dem Mac ist Cmd→Strg vorbelegt.
- **Diktat-Integration**: Ergebnisse lokaler Diktiersoftware (getestet
  mit Paraspeech) landen direkt im Textfeld bzw. gehen im Direktmodus
  sofort ans Ziel.
- **Textbausteine (Snippets)**: häufige Texte per Klick oder
  Hotkey (Cmd/Strg+1…9) einfügen bzw. senden.
- **Mehrere Geräte**: Geräteliste mit eigenem Token je Gerät,
  Umschalten per Dropdown.

Für macOS/Linux gibt es zusätzlich einen Python-Kommandozeilen-Client
(auch für Pipes: `echo 'Hallo' | dictusb.py 192.168.0.50`) — Details im
GitHub-README.

---

## Downloads

Fertige Builds gibt es auf GitHub:
**<https://github.com/stwaidele/dictusb/releases/latest>**

| Datei | Für |
|---|---|
| `dictusb-app_macos.dmg` | macOS (signiert + notarisiert) |
| `dictusb-app_windows_amd64.zip` | Windows 10/11 (64-bit) |
| `dictusb-app_linux_amd64.tar.gz` | Linux (64-bit, braucht GTK 3) |

Jedes Release enthält eine `SHA256SUMS` zum Prüfen der Downloads
(`shasum -a 256 -c SHA256SUMS`).

### Hinweise zum ersten Start (wichtig, eigener Abschnitt auf der Seite)

- **macOS**: Das DMG ist mit einer Apple-Developer-ID **signiert und
  notarisiert** und startet ohne Warnung. Beim allerersten Öffnen fragt
  macOS wie bei jeder geladenen App einmal nach — das ist normal.
  Falls macOS doch blockt (z. B. bei einem Prerelease): Rechtsklick auf
  die App → „Öffnen".
- **Windows**: Die App ist **nicht signiert** (ein Zertifikat kostet
  laufend Geld; die Prüfsumme ersetzt es). Beim ersten Start warnt
  Microsoft SmartScreen, weil es die App noch nicht kennt: **„Weitere
  Informationen" → „Trotzdem ausführen"**. Wer sichergehen will,
  vergleicht vorher die Prüfsumme mit der `SHA256SUMS` aus dem Release.
- **Linux**: Archiv entpacken (legt ein Verzeichnis `dictUSB/` an),
  dann **`./dictUSB/dictUSB`** starten. Das Starter-Script legt beim
  ersten Start automatisch den Menü-/Dock-Eintrag an (`.desktop`-Datei)
  und aktualisiert ihn, wenn der Ordner später verschoben wird.
  Voraussetzung: GTK 3.

---

## Hardware: Was man braucht

Genau **ein** Board (beide laufen mit identischer Firmware) plus ein
USB-Datenkabel — Gesamtkosten unter 15 €:

| Teil | ca. | Link |
|---|---|---|
| **Raspberry Pi Pico 2 W** (RP2350, WLAN) | 8 € | [Amazon](https://www.amazon.de/dp/B0DNZKYGWP?tag=101010cloud-21)* |
| **ESP32-S3 DevKitC-1 „N16R8"** (16 MB Flash) | 10 € | [Amazon](https://www.amazon.de/dp/B0F3XMYYQY?tag=101010cloud-21)* |
| Dazu passend: **USB-C-Datenkabel** (für den ESP32 — kein reines Ladekabel) | 5 € | [Amazon](https://www.amazon.de/dp/B01GGKYKQM?tag=101010cloud-21)* |
| bzw. **Micro-USB-Datenkabel** (für den Pico — kein reines Ladekabel) | 5 € | [Amazon](https://www.amazon.de/dp/B08HSC3NXZ?tag=101010cloud-21)* |

\* *Affiliate-Links (Werbung): Ein Kauf darüber unterstützt das Projekt
und kostet dich nichts extra.* Die Boards gibt es genauso bei BerryBase,
Reichelt & Co. — jedes ESP32-S3-DevKitC-1-Derivat mit nativem
USB-Anschluss funktioniert. Die verlinkten Kabel sind Beispiele — jedes
**Datenkabel** mit passendem Stecker funktioniert.

**Einrichtung in Kürze** (ausführlich im
[README](https://github.com/stwaidele/dictusb#schnellstart)):
CircuitPython flashen (Datei aufs Laufwerk kopieren — kein
Löt- oder Programmierwissen nötig), dictUSB-Firmware und
Tastatur-Layout dazu, WLAN-Zugangsdaten und ein Token in die
`settings.toml` — einstecken, fertig. Hinweis auf dem Pico/ESP32:
Status-LED zeigt den Zustand (bereit / verbunden / Tastendruck /
Abbruch).

---

## Sicherheit

- **Ende-zu-Ende verschlüsselt**: Mit gesetztem Token läuft der Kanal
  verschlüsselt und manipulationsgeschützt (eigenes Protokoll
  DICTUSB2: frisches Salt pro Verbindung, HMAC-SHA256, MAC je Frame).
  **Das Token wird nie übertragen**; die App verweigert Klartext,
  sobald ein Token konfiguriert ist.
- **Keine Cloud, kein Konto**: Alles läuft im eigenen WLAN. Es gibt
  keinen Server außerhalb des Hauses, nichts telefoniert nach Hause.
- **Nichts auf dem Zielrechner**: Der Zielrechner sieht eine Tastatur —
  es gibt dort nichts zu installieren, zu aktualisieren oder
  abzusichern.
- **Grenzen ehrlich benannt**: Tipp-Rhythmus und Nachrichtenlängen
  bleiben im WLAN beobachtbar; das Wartungs-Web-Interface des Geräts
  ist reines HTTP (nur im eigenen WLAN nutzen). Wer eine Lücke findet:
  bitte vertraulich melden, siehe
  [SECURITY.md](https://github.com/stwaidele/dictusb/blob/main/SECURITY.md).
- **Offener Quellcode**: Protokoll und Implementierung sind öffentlich
  ([PROTOCOL.md](https://github.com/stwaidele/dictusb/blob/main/PROTOCOL.md)),
  mit Testvektoren.

---

## FAQ

**Muss auf dem Zielrechner wirklich nichts installiert werden?**
Nein. Der Mikrocontroller meldet sich als USB-Standardtastatur (HID) —
die versteht jedes Betriebssystem von sich aus, auch BIOS und
Anmeldebildschirm. Genau deshalb braucht es auch keine Adminrechte.

**Warum kommt bei mir `z` statt `y` an (oder Umlaute fehlen)?**
Der Zielrechner interpretiert Tastendrücke nach seiner eingestellten
Tastaturbelegung. Das Gerät muss darauf eingestellt sein:
`DICTUSB_LAYOUT = "win_de"` (Standard) für deutsche Windows- und
Linux-Ziele, `"us"` für US-Layout (dann ohne Umlaute). Weitere Layouts
(fr, uk, es, it) sind möglich.

**Funktioniert ein Mac als Zielrechner?**
Derzeit nicht zuverlässig — Sonderzeichen wie `@ { } [ ]` liegen auf
dem Mac anders (Wahltaste statt AltGr). Als **Sender** ist der Mac
dagegen die erste Wahl. Lösungswege für Mac-als-Ziel stehen im README;
Mithilfe willkommen.

**Wie schnell ist das? Taugt es für Live-Diktat?**
Ja — dafür ist es gebaut. Gesendet wird ohne Puffern (TCP_NODELAY),
der WLAN-Hop dominiert die Latenz. Im Direktmodus erscheint jeder
Tastendruck praktisch sofort; im Blockmodus diktiert man in Ruhe und
sendet den fertigen Text.

**Was passiert, wenn das WLAN kurz wegbricht?**
Das Gerät verbindet sich selbst neu und zeigt seinen Zustand über die
Status-LED. Die App erkennt eine tote Verbindung an ausbleibenden
Quittungen; eine bestehende Sitzung übersteht lange Denkpausen
(Lebenszeichen-Mechanismus).

**Kann jemand in meinem WLAN mitlesen oder mittippen?**
Mit gesetztem Token: nein — der Kanal ist verschlüsselt und
authentisiert, und nur eine Verbindung wird gleichzeitig bedient.
Sichtbar bleiben nur Metadaten (wann und wie viel getippt wird).
Ohne Token läuft der Kanal im Klartext — das ist nur zum Testen gedacht.

**Welches Board soll ich kaufen?**
Egal — beide laufen mit identischer Firmware. Der Pico 2 W ist etwas
günstiger; der ESP32-S3 hat eine RGB-Status-LED (der Pico blinkt
stattdessen). Wichtig beim ESP32: die **native USB-Buchse** verwenden
(beim DevKitC-1 die linke).

**Kann ich mehrere Zielrechner bedienen?**
Ja — ein Gerät pro Zielrechner, in der App per Dropdown umschaltbar
(jedes Gerät mit eigenem Token möglich). Ein Gerät kann auch nach
Bedarf umgesteckt werden; nur die Layout-Einstellung muss zum
jeweiligen Rechner passen.

**Gibt es eine App fürs Handy?**
Noch nicht — der Fokus liegt auf Desktop (macOS, Windows, Linux). Ein
eigener Mobil-Client ist angedacht.

**Warum kein Browser-Client?**
Bewusste Entscheidung: Der Mikrocontroller kann kein TLS-Server sein,
und ein Browser verbietet aus sicheren Seiten (`https`) Verbindungen zu
TLS-losen Geräten — die einzig möglichen Umgehungen wären unsicher
(Token im WLAN stehlbar). Statt einer unsicheren Lösung gibt es die
Desktop-App mit voller Verschlüsselung.

---

## Fußbereich / Links

- Downloads: <https://github.com/stwaidele/dictusb/releases/latest>
- Quellcode & Doku: <https://github.com/stwaidele/dictusb> (MIT)
- Fragen & Fehler: <https://github.com/stwaidele/dictusb/issues>
- Sicherheitslücken vertraulich melden:
  [SECURITY.md](https://github.com/stwaidele/dictusb/blob/main/SECURITY.md)

---

## Umsetzungsnotizen (nicht veröffentlichen)

- **Seitenstruktur-Vorschlag**: Hero → Use Case → Funktionsweise
  (Diagramm) → App-Features mit Screenshots → Downloads inkl.
  Erststart-Hinweise → Hardware/Einkaufsliste → Sicherheit → FAQ
  (aufklappbar) → Footer-Links.
- **Bilder** aus diesem Repo übernehmen: `docs/img/dictusb-icon-1024.png`
  (bzw. `dictusb-icon.svg`), `app-blockmodus.png`, `app-direktmodus.png`,
  `app-einstellungen.png`.
- Das ASCII-Diagramm als richtige Grafik umsetzen (SVG, gern aus dem
  Icon-Stil abgeleitet: USB-Dreizack + Funkwellen).
- Affiliate-Links **immer** mit sichtbarer Werbe-Kennzeichnung
  (wie oben formuliert), Tag `101010cloud-21`.
- Download-Links immer auf `releases/latest` zeigen lassen, keine
  Versionsnummern hart einbauen (die Seite soll bei neuen Releases
  nicht anfasst werden müssen).
- Impressum/Datenschutz kommen von werkzeugkasten.online (bestehender
  Rahmen); falls die Seite eigene Rechtstexte braucht → Skill
  `rechtstexte`.
- Keine echten IPs/Tokens auf die Website — nur Beispielwerte
  192.168.0.50/.51.
