# dictUSB — Handoff

> Übergabedokument für die Fortsetzung in einer Claude-Code-Session.
> Stand: 2026-07-29 — läuft produktiv auf zwei Geräten, öffentlich unter
> <https://github.com/stwaidele/dictusb> (MIT), Website live auf
> <https://werkzeugkasten.online/dictusb>; **`v1.0.2` getaggt und
> gepusht**, Release-Prüfung steht aus.
> Dauerhafte Fakten stehen in `CLAUDE.md`; hier steht nur, was **nicht**
> aus Code und Git-Historie ersichtlich ist.

**🔜 NÄCHSTE SESSION:** v1.0.2 verifizieren (siehe erster offener Punkt),
danach **WP5 Gehäuse** — das aber erst in einer eigenen Planungsrunde mit
Stefan besprechen, nicht direkt mit OpenSCAD loslegen.

## Offene Punkte

- [ ] **v1.0.2 prüfen** — Tag ist am 29.07. gepusht, die Pipeline lief an.
      Nach Abschluss die übliche Kette: SHA256, `spctl -a -vv` und
      `stapler validate` fürs DMG. **Auf Linux zusätzlich** aus dem
      frischen tar.gz: Start über `./dictUSB/dictUSB` und das Dock-Icon —
      beides ist seit v1.0.1 neu und war noch nie in einem Release-Archiv.
- [ ] **WP5 Gehäuse** — erst separat mit Stefan besprechen (eigene
      Planungsrunde), dann OpenSCAD unter `hardware/`.
- [ ] **Zeichensatz-Test mit `DICTUSB_LAYOUT="us"`** — Versuch am
      2026-07-21 abgebrochen: Das Debian-Ziel ließ sich nicht auf US
      bringen (TTY kennt keinen Keymap `us`; GUI läuft Wayland, also ist
      `setxkbmap` wirkungslos — Layout dort nur über die
      Desktop-Einstellungen). Für den nächsten Anlauf ein Ziel wählen,
      dessen US-Layout sich zuverlässig setzen lässt. **Beide Seiten**
      müssen auf US stehen. Ergebnis in die Layout-Tabelle (`CLAUDE.md`)
      und ins README.
- [ ] **GitHub-Settings durch Stefan**: „Private vulnerability reporting"
      aktivieren, Repo-Beschreibung + Topics setzen.
- [ ] **macOS als Ziel** — es gibt kein passendes Layout; Lösungswege
      stehen im README, entschieden ist nichts.
- [ ] **Grundsatzentscheidungen Flutter** (bewusst offen gelassen):
      Zeichen- vs. Tastenmodell (ein Tastenmodell müsste nur
      `app/lib/dictusb/keymap.dart` ersetzen — deshalb ist das Mapping
      dort gekapselt); Go-TUI/Python ablösen (Stefan ist bereit, sobald
      Flutter sich bewährt); `app/` ggf. umbenennen.
- [ ] **Mobil** — Android braucht das SDK (fehlt auf dem Mac, `flutter
      doctor` meckert), iOS offen. Mobil bekommt einen **eigenen** Client;
      Fokus bleibt Desktop.
- [ ] **Go-TUI (archiviert) hat den Quittungs-Fehler noch** —
      `readAcks` in `tui/internal/dictusb/conn.go` im Gitea-Branch
      `intern/historie-2026-07` misst das Alter der letzten Quittung.
      Bewusst offen; bei einer Reaktivierung die Quittungs-Regel aus
      `CLAUDE.md` portieren.
- [ ] Latenz im Alltag beobachten; `DICTUSB_SCAN`-Hänger mit neuerer
      CircuitPython-Version erneut testen.

**Installierter Stand:** auf beiden Geräten CircuitPython 10.2.1 mit
`code.py` **0.18**; Toolchain auf dem Mac Flutter 3.44.7 / Dart 3.12.2
(`brew install --cask flutter`), CocoaPods 1.17, Xcode 26.6 — das
Android-SDK fehlt (nur für Android-Builds nötig).

## Abgenommen (live verifiziert)

Was Stefan tatsächlich am echten Gerät bestätigt hat — nicht neu „testen
lassen", sondern als Ausgangspunkt nehmen:

- Tippen in Block- und Direktmodus, Pipe-Modus, Textbausteine,
  Gerätewechsel; **Umlaute/Sonderzeichen** am Windows-PC (`äöüß ÄÖÜ @/\-_
  yz YZ 123`); Tastenkombinationen (Strg+A..Z direkt, beliebige Kombis per
  Sequenz); Tasten-Modus des Python-Clients; Ausstieg per 5× Shift.
- **Verschlüsselung** DICTUSB2 inkl. Token-Rotation; **Lebenszeichen**
  (Sitzung überlebt 100 s Untätigkeit, stille Sitzung gibt das Gerät nach
  97 s frei).
- **Beide Geräte** mit identischer Firmware, **Status-LED** auf RGB
  (ESP32) und einfarbig (Pico).
- **Linux-Ziel** (Debian 13, `win_de`): voller Zeichensatz auf TTY (nach
  `loadkeys de`), X11 (`de`, Variante `deadgraveacute`) und Wayland.
- **Alle drei Desktop-Sender** live: macOS, Windows (Release-Zip, nach
  SmartScreen-Warnung), Linux (inkl. Dock-Icon, 2026-07-24) — Windows und
  macOS auch **parallel** an zwei Geräten.
- **Signiertes DMG**: `spctl` „accepted, source=Notarized Developer ID"
  für DMG **und** App darin, Ticket angeheftet (v1.0.0, v1.0.1).
- **Diktat** end-to-end, auch für lange Texte (2026-07-29).

Die zwei macOS-Dialoge beim Erstöffnen sind **erwartet**: die normale
Erstöffnungs-Nachfrage und „unterscheidet sich von zuvor verwendeten
Versionen" (nur auf dem Entwickler-Mac, weil die Bundle-ID dort schon mit
Dev-Signatur lief).

## Stolperfallen

- **Kein USB-Host = kein Tipp-Server** — `Keyboard()` blockiert, bis ein PC
  das HID-Gerät konfiguriert hat. Das Gerät wirkt gesund (WLAN und
  Web-Workflow laufen), aber Port 8080 lauscht nie. Wird protokolliert;
  Auslöser war zu schnelles Umstecken → beim Wechsel ein paar Sekunden
  warten.
- **Deploy-Reihenfolge** — `code.py` immer **zuletzt** (macht `deploy.sh`
  selbst): Der erste Upload löst den Auto-Reload aus, und eine neue
  `code.py` ohne ihre Abhängigkeiten stirbt am ImportError.
- **CYW43 verklemmt nach Soft-Reboot** — Scan hängt, Connect scheitert
  („Unknown failure 1"). Nur ein harter Reset hilft; `code.py` löst ihn
  nach 2 Fehlversuchen selbst aus (nvm-Marker gegen Schleifen). Direkt
  nach einem Auto-Reload flackert der Web-Workflow oft kurz weg — abwarten
  und erneut hochladen. **Reloads deshalb nur per Datei-Upload auslösen,
  nie per Ctrl-D.**
- **Supervisor-WLAN-Connect scheitert beim Kaltstart** → der Web-Workflow
  startet nicht, obwohl `code.py` das WLAN nachzieht (Port 8080 läuft);
  Updates gehen erst nach erneutem Neustecken. Idee (ungebaut): einmaliger
  Selbst-Reset in `code.py`.
- **Web-API schreibt nur**, wenn `disable_usb_drive()` **und**
  `remount("/", readonly=False)` gelaufen sind — sonst HTTP 409. Das ist
  eine Besitzfrage des Dateisystems, kein Zugangsdaten-Problem.
- **macOS „Lokales Netzwerk"** — die Berechtigung gehört dem startenden
  Prozess (Terminal-App), nicht dem Binary. Direkt in Terminal/iTerm2
  läuft es; durch einen **Wrapper/Harness** gestartet scheitert es mit
  `no route to host`, obwohl `ping` geht. macOS vergisst die Freigabe gern
  nach Neustart/Update — Systemeinstellungen → Datenschutz & Sicherheit →
  Lokales Netzwerk → Terminal aus/ein, Cmd+Q + neu; sonst
  `tccutil reset LocalNetwork`. **Folge für mich:** Verbindungstests kann
  ich nicht selbst ausführen, nur Stefan im echten Terminal.
- Pico kann **nur 2,4 GHz**; `.mpy`-Libraries müssen zur
  CircuitPython-**Hauptversion** passen.
- **ESP32 speziell** (Details in `ESP32.md`): native USB-Buchse nutzen
  (`usbmodem`, nicht `usbserial`); Download-Modus scheitert über USB-Hubs;
  ein Software-Reset holt den Chip nicht aus dem Bootloader.

## Session 2026-07-29 — Diktat-Fix für lange Texte, v1.0.2 (Claude Opus 5)

**Fehlerbild von Stefan:** Kurze Diktate kommen an, lange nicht — im
Direktmodus erscheint stattdessen ein „v" am Zielrechner, im Blockmodus
bleibt das Feld leer. Schon 1–3 Sätze reichten.

**Ursache:** Die Diktat-Erkennung in `app/lib/ui/home_page.dart`
(`_onGlobalKey`) verlangte Ctrl+Alt **innerhalb der letzten 5 s** vor dem
`v`. Paraspeech tippt die Modifier aber an, *bevor* Aufnahme und
Transkription fertig sind — die Lücke bis zum `v` **wächst mit der
Diktatlänge**. Die 5 s waren an einem kurzen Beispiel gemessen (1,9 s /
2,2 s) und damit strukturell falsch: **jedes feste Zeitfenster ist hier
falsch**, weil die Trennschärfe aus der Sequenz kommt, nicht aus der Uhr.

**Fix** (live abgenommen von Stefan): Das Zeitfenster ist nur noch
Veraltungs-Grenze (10 min); Garant bleibt die Entwaffnung durch jede
andere Taste. Als Ersatz für die nebenbei verlorene Schärfe müssen Ctrl
und Alt **zusammengehören** (≤ 1 s auseinander — maschinell angetippt sind
es Millisekunden), sonst bewaffnet ein Strg-Shortcut plus ein viel
späteres Alt die Erkennung. Dauerhafte Fassung der Regel in `CLAUDE.md`.

**Bewusst so gebaut:**

- Verworfen wurde ein Abgleich der Zwischenablage (Inhalt vorher/nachher
  vergleichen): Er würde zwei identische Diktate hintereinander
  verschlucken — echter Regressionsschaden gegen einen sehr seltenen
  Fehlauslöser.
- Zwei Regressionstests in `app/test/widget_test.dart` warten **echte**
  Zeit ab (6,5 s bzw. 1,2 s), weil die Heuristik die Wanduhr liest und
  `pump()` sie nicht bewegt. Gegenprobe gemacht: Mit dem alten 5-s-Fenster
  fällt der erste Test durch — der Test misst also wirklich den Bug.
- Statt Wegwerf-Logging ein Dauer-Schalter: `_logKey()` hinter
  `--dart-define=DICTUSB_DIAG=true`. Falls die Erkennung je wieder
  ausfällt, ist das Diagnosemuster damit sofort verfügbar (Event-Art,
  Taste, gehaltene Tasten, Abstand zum bewaffnenden Ctrl/Alt,
  `synthesized`).

**Danach:** `v1.0.2` getaggt (App-Version 1.0.2+3) — enthält den
Diktat-Fix und das Linux-Starter-Script aus der Vorsession. Auf Wunsch von
Stefan außerdem der Umbau dieses Handoffs auf das Skill-Format; die
Dauerfakten (Geräte, Firmware, Layouts, Clients, Veröffentlichung,
verworfener Browser-Client) sind dabei nach `CLAUDE.md` gezogen.

## Session 2026-07-24 — v1.0.1, Linux-Starter-Script, WP6 Website (Claude Fable 5)

- **`v1.0.1` veröffentlicht und verifiziert**: Archive mit Top-Level-
  Verzeichnis `dictUSB/` (vorher Tarbomb bzw. flaches Zip — nur die alten
  v1.0.0-Assets sind noch flach), Linux-Fenster-Icon, Fenstertitel
  „dictUSB", `pico/` → `firmware/`.
- **Linux-Starter-Script** `app/linux/dictUSB` (per CMake
  `install(PROGRAMS …)` ins Bundle-Root): legt den `.desktop`-Eintrag an
  bzw. schreibt ihn neu, wenn der Ordner verschoben wurde (Vergleich
  Soll/Ist-Inhalt), dann `exec dictusb_app`. **Grund**: Unter GNOME/
  Wayland braucht das Dock-Icon zwingend eine `.desktop`-Datei; das
  Fenster-Icon allein reicht nicht. Einstieg für Nutzer ist seitdem
  `./dictUSB/dictUSB`. Auf dem Mac per Dummy-Bundle getestet
  (Leerzeichen-Pfade, Idempotenz, Verschieben, Argument-Durchreichung) —
  ein echter Linux-Lauf **aus einem Release-Archiv** steht noch aus.
- **WP6 Website**: Inhalt in `docs/website-content.md` (von Stefan
  redigiert) und Umsetzung als SvelteKit-Unterseite im **anderen**
  Workspace `~/Claude/Werkzeugkasten` — live auf
  <https://werkzeugkasten.online/dictusb>. Download-Links zeigen auf
  `releases/latest`, damit keine Version hart verbaut ist.
- **Entscheidung**: kein Release nur fürs Starter-Script — Änderungen
  werden gesammelt (das wurde jetzt v1.0.2).

## Typische Handgriffe

```bash
# Flutter-App starten (aus echtem Terminal — macOS-Local-Network!)
cd app && flutter run -d macos

# … mit Diagnose-Log der Tasten-/Diktat-Erkennung
cd app && flutter run -d macos --dart-define=DICTUSB_DIAG=true

# Alles prüfen (ohne Gerät, mache ich selbst)
python3 -m py_compile firmware/*.py && ./testdata/make_vectors.py --check
cd app && flutter analyze && flutter test

# Verbindung prüfen, ohne zu tippen (nur aus echtem Terminal)
cd app && dart run bin/probe.dart

# Python-Client: interaktiv (Ende: 5x linke Shift), Pipe, Tasten-Modus
./mac/dictusb.py 192.168.0.50
echo 'Hallo' | ./mac/dictusb.py 192.168.0.50
./mac/dictusb.py 192.168.0.50 --tasten

# Firmware ausrollen (Gerät lädt automatisch neu)
./mac/deploy.sh                             # Pico (Host aus settings.toml)
DICTUSB_HOST=192.168.0.51 ./mac/deploy.sh   # ESP32

# Logs ansehen
open http://192.168.0.50/cp/serial/

# Release: Version in app/pubspec.yaml hochzählen, dann
git tag -a v1.0.3 -m "…" && git push origin main && git push origin v1.0.3
gh run list --repo stwaidele/dictusb --workflow release.yml --limit 3
```

## Verwandte Handoffs

- `~/Claude/Werkzeugkasten/Handoff.md` — dort liegt die Umsetzung der
  Produktseite <https://werkzeugkasten.online/dictusb>. Inhaltliche Quelle
  bleibt `docs/website-content.md` **hier**: bei Textänderungen zuerst
  hier pflegen, dann drüben nachziehen.

<!-- Ältere Sessions: git log -p Handoff.md -->
