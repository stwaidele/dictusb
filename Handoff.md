# Handoff: dictUSB — Text live auf einen anderen Rechner tippen

> Übergabedokument für die Fortsetzung in einer Claude-Code-Session.
> Stand: 2026-07-23 (abends) — **läuft produktiv auf zwei Geräten**,
> **öffentlich**: github.com/stwaidele/dictusb (MIT), und **v1.0.0 ist
> veröffentlicht und verifiziert** (signiert + notarisiert, App-Icon,
> Screenshots im README). Nächste Schritte: **WP6 Website, WP5
> Gehäuse** (Abschnitt „Veröffentlichung"). Davor: Modifier-Tipp
> (Firmware 0.18), Flutter-Phasen 2–4, Quittungs-Fix (Firmware
> quittiert NUR Lebenszeichen — siehe „Lebenszeichen-Quittungen").

## Was das ist

Ein Mikrocontroller steckt per USB am Zielrechner und **ist dort eine
ganz normale Tastatur**. Gesendet wird per WLAN, verschlüsselt.

```
Sender (macOS/Linux/Windows) --(WLAN, TCP:8080, DICTUSB2)--> Pico 2 W / ESP32-S3 --(USB-HID)--> Zielrechner
```

**Auf dem Zielrechner läuft nie Software.** Daraus folgt die Stärke
(funktioniert überall, auch im BIOS und am Anmeldebildschirm, ohne
Rechte) und die einzige Einschränkung: Wir senden HID-Keycodes, also
entscheidet die **Tastaturbelegung des Zielrechners**, welche Zeichen
ankommen (siehe „Zielsysteme und Layouts").

Anleitungen: `README.md` · Protokoll: `PROTOCOL.md` ·
ESP32-Inbetriebnahme: `ESP32.md`.

## Geräte

Beispiel-Setup mit zwei Geräten (die IPs hier sind **Beispielwerte** —
echte Betriebsdaten stehen in der gitignorten `PRIVAT.md`):

| Gerät | IP (Beispiel) | Besonderheit |
|---|---|---|
| Pico 2 W | `192.168.0.50` (fest reserviert) | |
| ESP32-S3 | `192.168.0.51` (fest reserviert) | native USB-Buchse = **links** |

Beide laufen mit **identischer Firmware** (`code.py` 0.18, `boot.py`,
`dictusb_crypto.py`, `status_led.py`) und **demselben Token** — Clients
sprechen ohne Umkonfiguration mit beiden, in der App per
Geräte-Dropdown umschaltbar. An welchem Zielrechner ein Gerät steckt,
ist beliebig und wird nach Bedarf umgesteckt; nur das Ziel-Layout
(`DICTUSB_LAYOUT`) muss zum jeweiligen Rechner passen.

Fernwartung ohne Kabelwechsel (je Gerät, Login: Benutzername **leer**,
Passwort = `CIRCUITPY_WEB_API_PASSWORD`):
- Logs/REPL: `http://<ip>/cp/serial/`
- Dateien: `http://<ip>/fs/` (auch `settings.toml` bearbeiten)
- Updates: `./mac/deploy.sh` bzw. `DICTUSB_HOST=<ip> ./mac/deploy.sh`

## Abgenommen (live verifiziert)

- Tippen in beiden Client-Modi, Pipe-Modus, Textbausteine, Gerätewechsel.
- **Umlaute/Sonderzeichen** am Windows-PC: `äöüß ÄÖÜ @/\-_ yz YZ 123`.
- **Tastenkombinationen**: Strg+A..Z direkt; beliebige Kombis über die
  Sequenz `0x00<spec>\n` (`ctrl/alt/shift/win` + Zeichen oder Name).
- **Tasten-Modus** des Python-Clients (Cmd↔Strg-Tausch, nur macOS).
- **Ausstieg**: 5× linke Shift-Taste in 2 s (beide Modi des
  Python-Clients).
- **Verschlüsselung** DICTUSB2 inkl. Token-Rotation.
- **Lebenszeichen**: Sitzung überlebt 100 s Untätigkeit; stille Sitzung
  gibt das Gerät nach 97 s frei.
- **ESP32-S3** mit unveränderter Firmware, inkl. Live-Tippen an einem
  Windows-PC.
- **Status-LED** (seit 0.17): gelb/grün, Cyan-Tupfer je Tastendruck,
  rot bei Abbruch — am ESP32 (RGB) und Pico (mono, Aus-Flackern) live
  abgenommen.
- **Linux-Ziel (Debian 13)** mit `DICTUSB_LAYOUT="win_de"`: voller
  Zeichensatz (`äöüß ÄÖÜ @/\-_ yz YZ 123 {[]}|~ €`) korrekt getippt —
  auf der Textkonsole (TTY, nach `loadkeys de`), unter X11
  (Layout `de`, Variante `deadgraveacute`, Terminal + GUI-App) **und
  Wayland** (2026-07-23, Sender: Windows-App).
- **Windows-Sender** (2026-07-23, Release-Zip aus rc4): App startet
  nach SmartScreen-Warnung („Trotzdem ausführen" — Zip unsigniert,
  bekannt/akzeptiert), verbindet und tippt an den Pico — **parallel**
  zum Mac-Sender am ESP32 (zwei Sender, zwei Geräte gleichzeitig).
- **Signiertes DMG** (v1.0.0-rc4): `spctl` „accepted,
  source=Notarized Developer ID" für DMG **und** App darin,
  Notarisierungs-Ticket angeheftet; Abnahme durch Stefan (die zwei
  macOS-Dialoge beim Erstöffnen sind erwartet, siehe
  „Veröffentlichung").

## Firmware (`firmware/`, gilt für beide Geräte)

CircuitPython **10.2.1**. In `/lib`: `adafruit_hid` +
`keyboard_layout_win_de`/`keycode_win_de` (Neradoc-Bundle, 10.x-mpy).

- `code.py` **0.18** — WLAN, TCP-Server, HID-Tippen, DICTUSB2,
  Lebenszeichen, Layout-Auswahl; seit 0.18 darf die Kombi-Taste auch
  ein **Modifier-Name allein** sein (`\x00shift\n` = Shift antippen,
  z. B. gegen den Bildschirmschoner — PROTOCOL.md §7).
- `boot.py` — reduziert HID auf Tastatur, deaktiviert das
  `CIRCUITPY`-Laufwerk und remountet den Flash beschreibbar (nur so darf
  die Web-API schreiben). Wirkt **erst nach hartem Reset**.
- `dictusb_crypto.py` — geteilte Krypto-Schicht: läuft unverändert auf
  dem Gerät **und** im Mac-Client. `deploy.sh` rollt sie mit aus.
- `status_led.py` — Onboard-LED als Zustandsanzeige (seit 0.17,
  **live abgenommen** auf beiden Geräten): fähigkeitserkennend — RGB
  (NeoPixel via Core-Modul `neopixel_write`, keine Zusatz-Library) →
  einfarbig (`board.LED`, Blinkmuster) → nichts. **Gelb** = bereit,
  **grün @50 %** = verbunden, Tastendruck → **Cyan-Tupfer** (100 %,
  blendet in 0,2 s zurück auf Grün), **rot blinkend ~3 s** = Abbruch
  (nur echte Abbrüche; sauberes Ende → direkt gelb). Der Pico (mono)
  kann keine Farbe → Ready-Blinken, Dauerlicht bei Verbindung, kurzes
  **Aus-Flackern je Tastendruck** (0,1 s), schnelles Blinken bei Abbruch.
  Farben + Fade-Zeit **ohne Neubau** per `settings.toml` änderbar (per
  `/fs/` editierbar): `DICTUSB_LED` (0=aus), `DICTUSB_LED_BRIGHTNESS`
  (0.5), `DICTUSB_LED_PIN` (Clone), `DICTUSB_LED_FADE` (0.2 s),
  `DICTUSB_LED_READY/_CONNECTED/_ACTIVITY/_ABORT` (Hex `rrggbb` oder
  `r,g,b`). Reine Logik auf dem Mac getestet (30/30). `deploy.sh` rollt
  die Datei mit aus. Für die LED senkt `code.py` die Socket-Timeouts auf
  0.1 s (Fade/Blink flüssig; Tipp-Latenz und Heartbeat-Logik unberührt).
- `settings.toml` — nur lokal und auf dem Gerät, **gitignored**. Vorlage:
  `settings.toml.example`. Bei jeder Änderung
  `DICTUSB_SETTINGS_VERSION` hochzählen (die Startzeile zeigt sie).

### Verschlüsselung (DICTUSB2)

Mit gesetztem `DICTUSB_TOKEN` läuft der Kanal verschlüsselt und
integritätsgeschützt; **das Token wird nie übertragen**. Frisches Salt
pro Verbindung, HMAC-SHA256 als Keystream (CTR) und 8-Byte-MAC je Frame,
Quittungen in der Rückrichtung. Der Client verweigert Klartext, wenn ein
Token gesetzt ist (Downgrade-Schutz). Vollständig in `PROTOCOL.md`,
Testvektoren in `testdata/vectors.json` (`make_vectors.py --check`).

**Token rotieren**: neues per
`python3 -c 'import os; print(os.urandom(16).hex())'` in die lokale
`firmware/settings.toml`, `DICTUSB_SETTINGS_VERSION` hochzählen, dann
`DICTUSB_HOST=<ip> ./mac/deploy.sh firmware/settings.toml` je Gerät.
**Beide Kopien müssen identisch sein**, sonst trennt das Gerät nach 5 s.

### Lebenszeichen statt Timeout (seit 0.15)

Der Client sendet bei Untätigkeit alle 20 s einen Herzschlag (leere
Kombi-Sequenz — tippt nichts), das Gerät quittiert jeden mit 8
authentifizierten Bytes. Bleibt 90 s (`DICTUSB_IDLE_LIMIT`) ein gültiger
Frame aus, trennt das Gerät. Lange Denkpausen sind damit unkritisch, ein
verschwundener Client blockiert das Gerät aber nicht mehr dauerhaft
(nur **eine** Verbindung wird bedient). Umgekehrt erkennt der Client an
ausbleibenden Quittungen ein verschwundenes Gerät.

## Zielsysteme und Layouts

`DICTUSB_LAYOUT` in der `settings.toml` wählt die Belegung des
Zielrechners — beim Umstecken an einen Rechner mit anderem Layout muss
der Wert passend gesetzt werden.

| Ziel | Wert | Stand |
|---|---|---|
| Windows, deutsch | `win_de` (Default) | abgenommen |
| Linux, deutsch | `win_de` | **abgenommen** (Debian 13, TTY + X11; Wayland 2026-07-23, Sender Windows-App) |
| Windows/Linux, US | `us` (aus `adafruit_hid`, keine Umlaute) | Umschaltung verifiziert, **Zeichentest offen** (2026-07-21 abgebrochen: Ziel ließ sich nicht auf US stellen — Debian-TTY kennt keinen Keymap `us`, GUI läuft Wayland → `setxkbmap` wirkungslos) |
| fr/uk/es/it | `win_fr`, … | nutzbar, sobald die `.mpy` in `/lib` liegt |
| **macOS** | — | **bewusst offen**, Lösungswege im README |

Unbekannter oder fehlender Wert ⇒ **hörbarer** Rückfall auf `us`; die
Startzeile `Layout = …` zeigt die aktive Belegung.

## Clients

- **`app/` — Flutter-App (macOS/Windows/Linux), der Hauptclient**
  (Details im nächsten Abschnitt): Block- und Direktmodus, Diktat,
  Snippets, Multi-Gerät, Modifier-Mapping. Wird als einziger Client
  als Download veröffentlicht.
- **`mac/dictusb.py` — Python-Client, macOS/Linux** (kein Windows:
  `termios`). Kann als einziger den **Tasten-Modus** (`--tasten`,
  Cmd↔Strg-Tausch) — braucht `pynput` und die macOS-Freigabe
  **Bedienungshilfen**. Ausstieg beider Modi: 5× linke Shift in 2 s.
  Liest das Token ohne `--token` aus `DICTUSB_TOKEN` (Env) oder der
  lokalen `firmware/settings.toml`. In `mac/` liegt auch `deploy.sh`
  (Firmware-Rollout über die Web-API).
- **Go-TUI (archiviert, 2026-07-23):** war der erste
  plattformübergreifende Client (Bubble Tea v2); mit der Flutter-App
  aus dem öffentlichen Stand entfernt. Quellcode liegt im privaten
  Gitea-Branch `intern/historie-2026-07` (`tui/`); lokale Builds
  funktionieren weiter. Bekannter offener Fehler dort: siehe
  „Lebenszeichen-Quittungen".

## Flutter-Client (in Arbeit, seit 2026-07-22)

Ein **plattformübergreifender Sender-Client** in Flutter/Dart unter `app/`
— Ziel „ein Client für Desktop UND Mobil", der langfristig Go-TUI/Python
ablösen kann (Ausnahme: der Tasten-Modus bleibt Python-only, nicht
portabel). **Empfänger-Architektur unangetastet** (Gerät = HID). Web ist
draußen (kein Raw-TCP im Browser).

**Toolchain (frisch eingerichtet):** Flutter 3.44.7 / Dart 3.12.2 via
`brew install --cask flutter`; CocoaPods 1.17 (`brew install cocoapods`);
Xcode 26.6. **Android-SDK fehlt noch** (`flutter doctor` meckert) — nur
für Android-Builds nötig, macOS ist startklar. `flutter`/`dart` liegen
unter `/opt/homebrew/bin`.

**Struktur:** Standard-Flutter-Projekt, Plattformen **macos/android/
windows** gescaffoldet (kein `web/`). Krypto ist bewusst reines Dart
(`app/lib/dictusb/`), UI in `app/lib/ui/` + `app/lib/config/`.

| Phase | Inhalt | Stand |
|---|---|---|
| 0 | `protocol.dart` (DICTUSB2-Krypto) | ✅ **committet** `f314ca2`, 17/17 Vektoren bitgleich |
| 1 | `conn.dart` + `bin/probe.dart` | ✅ **committet** `b857d51`, Probe live am Gerät ok |
| 2 | Blockmodus-UI (`main.dart`, `ui/home_page.dart`, `dictusb/session.dart`) | ✅ **committet**, `analyze`+18/18 Tests grün, Verbinden+Senden live ok |
| — | Config-Persistenz (`shared_preferences`, `config/config_store.dart`) | ✅ **committet** |
| — | **Diktat-Fix (Paraspeech)** | ✅ **committet, End-to-End abgenommen** (Diktat → Feld → Senden → Windows-Ziel) |
| 3 | **Direktmodus** (`keymap.dart`, `settings_sheet.dart`, Umbau `home_page.dart`) | ✅ **committet, live abgenommen** (Tippen, Cmd→Strg, Alt-Zeichen, Diktat direkt, Cmd+Q unterdrückt, Settings-Dialog) |
| 4 | **Snippets + Multi-Gerät** (`models.dart`, 3-Tab-Settings, Geräte-Dropdown) + Quittungs-Fix in `conn.dart` | ✅ **committet, live abgenommen** (Persistenz, ESP32-Wechsel, Snippets per Klick/Hotkey, Stabilität in allen drei Abbruch-Mustern) |

### Diktat / Paraspeech — Befund und Lösung (2026-07-22 verifiziert)

**Wiederverwendbare Erkenntnis:** Diktiersoftware liefert ihr Ergebnis
**nicht als Tastendruck-Folge**, sondern legt es in die **Zwischenablage**
und drückt eine Nicht-Standard-Paste-Kombi — bei **Paraspeech**
`Ctrl+Alt+V`. Die Go-TUI fängt dasselbe als `tea.PasteMsg` (Bracketed
Paste, Commit `4953520`) ab.

**Warum drei Fix-Anläufe nötig waren** (alles live per `[DIAG]`-Log
belegt, Erkenntnisse gelten für jede künftige Kombi-Erkennung):

1. Paraspeech **hält die Kombi nicht**: Es sendet Ctrl-down, Alt-down,
   dann **Ctrl-up, Alt-up** (echte Events, nicht synthetisiert) — und das
   `v` erst danach. Jede „sind die Modifier gerade gedrückt?"-Prüfung
   (`logicalKeysPressed` oder mitgeführter Halte-Status) ist chancenlos.
2. Die **Timestamps synthetisch gepostet CGEvents sind unbrauchbar**
   (`e.timeStamp` lieferte Fantasiewerte) — Zeitmessung muss über die
   Ankunftszeit im Handler (`DateTime.now()`) laufen.
3. Zwischen Modifier-Antippen und dem `v` vergehen **~2 s, schwankend**
   (gemessen 1,9 s und 2,2 s) — vermutlich schreibt Paraspeech in der
   Zeit die Zwischenablage.

**Lösung (in `ui/home_page.dart`, `_onGlobalKey`):** Zeitfenster-Heuristik
— ein `v`-KeyDown gilt als Diktat-Kombi, wenn Ctrl- und Alt-Down
innerhalb der letzten **5 s** ankamen **und** dazwischen keine andere
Taste gedrückt wurde (jeder andere KeyDown entwaffnet die Erkennung —
so löst z. B. `Alt+L` für `@` plus späteres `v` nichts aus). Physisch
*gehaltenes* Ctrl+Alt+V greift zusätzlich über `logicalKeysPressed`.
Bei Treffer wird die Kombi verschluckt und `_pasteDictation()` fügt die
Zwischenablage an der Cursorposition ein. Das Textfeld ist bewusst auch
ohne Verbindung aktiv (vorab diktieren, später senden).

**Falls die Erkennung je wieder ausfällt:** Debug-Muster aus dieser
Diagnose — im `HardwareKeyboard`-Handler jede Taste mit
`logicalKeysPressed`-Satz, `synthesized`-Flag und Handler-Ankunftszeit
loggen; die App dazu per Harness im Hintergrund starten und das Log
mitlesen (Diktat ins Feld braucht kein Local-Network — nur
Verbinden/Senden braucht das echte Terminal).

### Direktmodus (Phase 3, live abgenommen 2026-07-22)

Bewusst **neu diskutiert statt aus der Go-TUI portiert**:

- **Mapping** in `app/lib/dictusb/keymap.dart` (rein, 15 Unit-Tests):
  Zeichen als UTF-8, Strg+A..Z als `0x01`–`0x1a`, Sondertasten als
  Kombi-Specs — hinter einer Funktion gekapselt, damit ein späteres
  **Tastenmodell** (bewusst offen gelassen) nur dieses Modul ersetzt.
- **Modifier-Mapping statt Tausch-Schalter**: drei Dropdowns
  (Quell-Modifier → `Strg`/`Alt`/`Win`), plattformspezifisch beschriftet.
  macOS-Default = Python-Tausch (Cmd→Strg, control→Win). Shift fix.
- **Alt-Zeichenliste** (Default `@[]{}|~\€`): gelistete komponierte
  Zeichen gehen als Text, andere Alt-Kombis als Kombi; deckt auch
  Windows-AltGr ab (meldet Ctrl+Alt).
- **Umschaltung**: SegmentedButton + konfigurierbare F-Taste (Default
  **F1**, auf Stefans Wunsch statt F10). Settings-Dialog (Zahnrad)
  wechselt für seine Dauer in den Blockmodus und setzt den
  Tasten-Handler aus (sonst wären seine Felder nicht tippbar).
- **Diktat** wirkt in beiden Modi (Direktmodus → direkt ans Gerät).
- **Modifier-Tipp** (seit 2026-07-23, live abgenommen): ein allein
  gedrückter und wieder losgelassener Modifier geht beim KeyUp als
  reine Kombi ans Gerät (`modifierTapSpec`, Mapping gilt; jede andere
  Taste dazwischen entwaffnet; CapsLock & Co. stumm). Braucht
  Firmware ≥ 0.18.
- Persistenz: `dictusb.direct.*`-Keys (SharedPreferences).
- **Verifiziert**: Cmd+Q/Cmd+H werden unterdrückt (MainMenu.xib blieb
  unangetastet); Grenzen dokumentiert in `app/README.md` — OS-reservierte
  Kombis (macOS control+Pfeile = Spaces!, Win+L …) und Zeichenvorrat =
  Ziel-Layout (typographische „" kommen mit `win_de` nie an).

### Snippets + Multi-Gerät (Phase 4, live abgenommen 2026-07-22)

Entscheidungen von Stefan (statt TUI-1:1): **Snippet-Hotkeys Cmd/Strg+1…9
nur im Blockmodus** (Direktmodus bleibt transparent, dort per Klick);
Auslösen = Blockmodus **einfügen** an Cursorposition, Direktmodus
**sofort senden**; Geräteliste mit **Token je Gerät** (beim Anlegen vom
ersten Gerät vorbelegt); **kein Wechsel-Hotkey** (nur Dropdown; Wechsel
bei bestehender Verbindung trennt + verbindet neu). Umsetzung:
`config/models.dart` (JSON in SharedPreferences,
`dictusb.devices/activeDevice/snippets`), Migration der alten
Einzelverbindung zu „Gerät 1", 3-Tab-Einstellungsdialog, Knopfleiste.
Hotkey-Falle im Code dokumentiert: Erkennung ignoriert Alt, sonst finge
sie AltGr+7=`{` unter Windows/Linux ab.

### Lebenszeichen-Quittungen — Erkenntnis + Client-Regel (2026-07-22)

**Die Firmware quittiert AUSSCHLIESSLICH Lebenszeichen**
(`dec.take_heartbeats()` in `code.py`) — Nutzlast-Frames nie. Daraus
folgt für jeden Client: Eine „keine Antwort"-Erkennung darf **nur** an
einem gesendeten Herzschlag hängen (Frist ab Versand, Quittung löscht
sie), niemals am Alter der letzten Quittung. Sonst bricht die Verbindung
fälschlich ab bei (a) anhaltendem Tippen ohne 20-s-Pause (keine
Herzschläge → keine Quittungen; das waren die sporadischen 64-s-Abbrüche)
und (b) Timer-Stillstand durch macOS App Nap. Fix im Dart-Client:
`conn.dart` `_sendHeartbeat()` bewaffnet `ackGrace` (30 s, großzügig,
weil das Gerät Herzschläge erst nach fertig getippter Nutzlast liest;
Frist VOR dem Senden setzen — die Quittung kann schon während
`await flush()` verarbeitet werden). In allen drei Mustern live
verifiziert. ⚠️ **Die (archivierte) Go-TUI hat denselben latenten
Fehler** (`readAcks` in `tui/internal/dictusb/conn.go` im Branch
`intern/historie-2026-07`: `time.Since(lastAck) > 3*HeartbeatEvery`) —
bewusst offen, da die TUI durch die Flutter-App abgelöst wurde; falls
sie je reaktiviert wird, gleiche Regel portieren.

### Offene Punkte Flutter (Plan-Phase 5)

- **Verpackung** (Phase 5): Desktop-Bundles; Android braucht das SDK
  (nur „darf funktionieren", kein Testgerät); iOS offen. **Mobil bekommt
  einen eigenen Client** (entschieden 2026-07-22), Fokus ist Desktop.
- Offene Grundsatzentscheidungen: Zeichen- vs. Tastenmodell;
  Go-TUI/Python ablösen (Stefan ist dazu bereit, wenn Flutter sich
  bewährt — dann auch den latenten Quittungs-Fehler der TUI bedenken).
  `app/` ggf. später umbenennen (analog zur 2026-07-24 erledigten
  Umbenennung `pico/`→`firmware/`).

### Verifikation (Krypto ohne Netz, ich-selbst-fähig)

```sh
cd app && flutter analyze && flutter test   # 18/18 (17 Vektoren + Widget)
cd app && dart run bin/probe.dart           # nur aus echtem Terminal!
```

## Veröffentlichung (seit 2026-07-23, Phase 5)

- **Öffentlich**: `github.com/stwaidele/dictusb` (MIT-Lizenz).
  **Entwicklung bleibt primär auf Gitea** (`gitea.101010.cloud`).
- **Ein `origin`, zwei Push-URLs** (Gitea + GitHub): jedes
  `git push origin` (auch `--tags`) erreicht **beide** Remotes.
  Zusätzlich Remote `github` zum Fetchen/Kontrollieren
  (`git fetch github && git log main..github/main` muss leer sein).
  SSH: Host-Alias `github-dictusb` (Deploy Key = fable-5-Key).
- **Historie**: öffentlicher Frischstart (`6400fd9` „initial public
  release"); die alte 74-Commit-Historie liegt **nur auf Gitea** im
  privaten Branch `intern/historie-2026-07` (dort auch die Go-TUI).
- **`PRIVAT.md`** (gitignored, Repo-Root): echte IPs/MACs und
  Handgriffe mit echten Werten — niemals committen.
- ⚠️ **GitHub-PRs nie über den Merge-Button mergen** (der Commit
  entstünde nur auf GitHub): stattdessen `gh pr checkout`, lokal
  mergen/testen, `git push origin main` — erreicht beide Remotes.
- **Erledigt (2026-07-23)**: WP1 Bereinigung; WP2 Frischstart +
  Doppel-Push (validiert); WP3 Release-Pipeline committet
  (`.github/workflows/release.yml` — Signierung/Notarisierung
  überspringen sich selbst, solange die Apple-Secrets fehlen; `-rc` =
  Prerelease); WP4 README (Schnellstart, Downloads, Einkaufsliste mit
  Affiliate-Links `101010cloud-21`, Mitmachen) + SECURITY.md;
  App-Version **1.0.0+1**, macOS-Bundle heißt **dictUSB.app**.
  rc1 schlug fehl (Linux-Plattform fehlte — behoben), rc2 grün
  (unsignierte Artefakte).

- **WP0 Apple — erledigt (2026-07-23)**: Developer-ID-Zertifikat
  „Stefan Waidele" (Team `ZDZ57JDWK4`, gültig bis 2027-02-01), per
  Xcode erzeugt; P12 + Passwort + App-Store-Connect-API-Key liegen
  unter `~/.config/dictusb/` (Mode 600, Details in `PRIVAT.md`;
  P12 mit OpenSSL 3 nur via `-legacy` lesbar). **Fünf** GitHub-Secrets
  gesetzt (`MACOS_CERT_P12` base64, `MACOS_CERT_PASSWORD`,
  `APPSTORE_KEY_ID`, `APPSTORE_ISSUER_ID`, `APPSTORE_PRIVATE_KEY`) —
  das früher geplante `APPLE_TEAM_ID` braucht der Workflow nicht.
  Werkzeug: `gh` CLI (brew), angemeldet als `stwaidele`.
  **Lehre aus rc3**: `hdiutil` erzeugt unsignierte DMGs — die App im
  DMG war einwandfrei, aber `spctl` wies das DMG ab („no usable
  signature"); seit `a8fcac0` signiert die Pipeline das DMG mit.
  **rc4 voll verifiziert**: `spctl -a -vv` „accepted, source=Notarized
  Developer ID" für DMG und App, `stapler validate` ok. Die zwei
  macOS-Dialoge bei Stefans Abnahme sind **erwartet**: die normale
  Erstöffnungs-Nachfrage (bekommt jede geladene App) und
  „unterscheidet sich von zuvor verwendeten Versionen" (nur auf dem
  Entwickler-Mac — Bundle-ID war dort schon mit Dev-Signatur gelaufen).
  Windows: SmartScreen warnt erwartungsgemäß (Zip unsigniert,
  „Trotzdem ausführen"); Windows-Signierung bewusst nicht geplant
  (Zertifikat = laufende Kosten; Reputation wächst mit Downloads).

- **App-Icon — erledigt (2026-07-23, `8da5334`)**: Entwurf von Stefan
  (Claude Design): weißer USB-Dreizack, ein Zweig geht in Funkwellen
  über, auf grüner Kachel. Quellen in `docs/img/`:
  `dictusb-icon.svg` + `dictusb-icon-1024.png` (randlose Kachel,
  Windows/Web) und `dictusb-icon-macos.svg` (abgerundete Kachel mit
  Apple-Randabstand: 824er-Tile, rx 186, auf 1024er-Canvas).
  Regenerieren: macOS-Iconset je Größe `rsvg-convert -w <s> -h <s>
  docs/img/dictusb-icon-macos.svg -o app/macos/…/app_icon_<s>.png`
  (16–1024); Windows `magick docs/img/dictusb-icon-1024.png -define
  icon:auto-resize=256,128,64,48,32,16 app/windows/runner/resources/
  app_icon.ico`. Icon ist oben im README eingebunden. **Falle**: Nach
  Icon-Wechsel zeigt das Dock gecacht das alte — `touch` aufs Bundle +
  `killall Dock` reicht.

- **`v1.0.0` veröffentlicht und verifiziert** (2026-07-23, von Stefan
  nach Icon-Abnahme freigegeben): Release (kein Prerelease) mit
  DMG/Zip/tar.gz/SHA256SUMS; DMG-Prüfsumme ok, `stapler validate` ok,
  `spctl` „accepted, source=Notarized Developer ID".

- **Screenshots — erledigt (2026-07-23, `3af36c5`)**: `docs/img/
  app-blockmodus.png` + `app-direktmodus.png` (README „Downloads")
  und `app-einstellungen.png` (`app/README.md`). Aufgenommen mit
  **Beispiel-Konfiguration** (Prefs-Domain `info.waidele.dictusbApp`
  vorher per `defaults export` gesichert, Beispielgeräte
  192.168.0.50/.51 + Dummy-Token gesetzt, danach re-importiert —
  echte IPs/Tokens stehen sonst im Geräte-Dropdown!). Rezept:
  Fenster-Geometrie per System Events, `screencapture -x -R…`;
  **Klicken/Fokussieren nur mit `cliclick`** (brew) — AppleScript
  „click at" gibt Flutter-Feldern keinen Fokus (F1/Hotkeys via
  System Events gehen, Text landet aber nirgends); Text ins Feld =
  `pbcopy` + Cmd+V nach `cliclick`-Klick ins Feld.

- **Nächste Schritte (in dieser Reihenfolge)**:
  1. **WP6 Website**: Inhalt in `docs/website-content.md` vorbereiten
     (Hero, Diagramm, Downloads→releases/latest, Hardware, Sicherheit,
     FAQ); Umsetzung als Unterseite werkzeugkasten.online/dictusb im
     separaten Werkzeugkasten-Workspace (sveltekit-tool-Konventionen).
     Dort auch SmartScreen-/Gatekeeper-Hinweise für Nutzer erklären.
  2. **WP5 Gehäuse**: **erst separat mit Stefan besprechen** (eigene
     Planungsrunde), dann OpenSCAD/`hardware/`.
  - Außerdem Stefan (GitHub-Settings): „Private vulnerability
    reporting" aktivieren, Repo-Beschreibung + Topics setzen.
  - Plan-Details: Phase-5-Plandatei der Claude-Session (Pfad in
    `PRIVAT.md`).

## Stolpersteine (ausführlich im README)

1. **Kein USB-Host = kein Tipp-Server**: `Keyboard()` blockiert, bis ein
   PC das HID-Gerät konfiguriert hat. Das Gerät wirkt gesund (WLAN und
   Web-Workflow laufen), aber Port 8080 lauscht nie. Seit 0.14 wird das
   laut protokolliert, und die Tastatur wird erst **nach** dem WLAN
   aufgebaut, damit das Log lesbar ist. Auslöser war zu schnelles
   Umstecken — beim Wechsel ein paar Sekunden warten.
2. **Deploy-Reihenfolge**: `code.py` immer **zuletzt** (macht
   `deploy.sh` selbst) — der erste Upload löst den Auto-Reload aus, und
   eine neue `code.py` ohne ihre Abhängigkeiten stirbt am ImportError.
3. **CYW43 verklemmt nach Soft-Reboot**: Scan hängt, Connect scheitert
   („Unknown failure 1"). Nur harter Reset hilft — `code.py` löst ihn
   nach 2 Fehlversuchen selbst aus (nvm-Marker gegen Schleifen). Der
   Web-Workflow flackert direkt nach einem Auto-Reload oft kurz weg;
   einfach abwarten und erneut hochladen.
4. Scheitert beim Kaltstart der **Supervisor-WLAN-Connect**, startet der
   Web-Workflow nicht, obwohl `code.py` das WLAN nachzieht (Port 8080
   läuft) — Updates gehen erst nach erneutem Neustecken. Idee: einmaliger
   Selbst-Reset in `code.py`, noch nicht gebaut.
5. **Web-API darf nur schreiben**, wenn `disable_usb_drive()` **und**
   `remount("/", readonly=False)` gelaufen sind (sonst 409).
6. **macOS „Lokales Netzwerk"**: Die Berechtigung gehört dem startenden
   Prozess (Terminal-App), nicht dem Binary. Direkt in Terminal/iTerm2
   läuft es; durch einen **Wrapper/Harness** gestartet scheitert es mit
   `no route to host`, obwohl `ping` geht (2026-07-21 vom Nutzer
   bestätigt). macOS vergisst die Freigabe gern nach Neustart/Update —
   Abhilfe: Systemeinstellungen → Datenschutz & Sicherheit → Lokales
   Netzwerk → Terminal aus/ein, Cmd+Q + neu; sonst `tccutil reset
   LocalNetwork`. Details in `app/README.md`.
7. Pico kann **nur 2,4 GHz**. `.mpy`-Libraries müssen zur
   CircuitPython-**Hauptversion** passen.
8. **ESP32 speziell** (Details in `ESP32.md`): native USB-Buchse nutzen
   (`usbmodem`, nicht `usbserial`); Download-Modus scheitert über
   USB-Hubs; ein Software-Reset holt den Chip nicht aus dem Bootloader.

## Offene Punkte

- **Zeichensatz-Test mit `DICTUSB_LAYOUT="us"`** (Ergebnisse in die
  Tabelle oben und ins README). Linux-DE ist abgenommen (siehe oben).
  Erster Versuch am 2026-07-21 **abgebrochen**, weil sich das Debian-Ziel
  nicht auf US bringen ließ (TTY: kein Keymap `us`; GUI: Wayland, also
  `setxkbmap` wirkungslos — Layout dort über die Desktop-Einstellungen).
  `us` gilt weiter als „sollte funktionieren" (Standard-Layout direkt aus
  `adafruit_hid`), aber **unbestätigt**. Für den nächsten Anlauf ein Ziel
  wählen, dessen US-Layout sich zuverlässig setzen lässt.
- **Flutter-App auf Linux ausprobieren** (macOS und Windows sind live
  abgenommen — Windows am 2026-07-23 mit dem Release-Zip; das
  Linux-tar.gz aus der Pipeline hat noch niemand gestartet).
  Seit 2026-07-24 packt die Pipeline das tar.gz mit Top-Level-Verzeichnis
  `dictUSB/` (vorher Tarbomb); das v1.0.0-Asset hat noch die alte
  Struktur — Fix greift ab dem nächsten Release-Tag.
- **macOS als Ziel** (siehe Layout-Tabelle), Lösungswege im README.
- Latenz im Alltag beobachten; `DICTUSB_SCAN`-Hänger mit neuerer
  CircuitPython-Version erneut testen.

## Bewusst zurückgestellt: Browser-Client (2026-07-20)

War der letzte Roadmap-Punkt (Zweck: fremde Rechner ohne Installation),
ist aber **bewusst zurückgestellt** — nicht aus Aufwand, sondern wegen
einer prinzipiellen Wand. Damit der Denkweg nicht neu durchlaufen wird:

Das Gerät kann **kein TLS-Server** sein (CircuitPython-Limit). Ein
Browser erreicht ein TLS-loses Gerät nur aus einem **unsicheren
Kontext** (`http`-Seite → `ws://`); eine `https`- oder `file://`-Seite
ist ein *sicherer* Kontext und blockiert `ws://` als Mixed Content. Ein
unsicherer Kontext lässt sich aber **nicht integer ausliefern** — ein
aktiver Angreifer im WLAN kann die Seite fälschen und das Token stehlen.
„Sicher ausgeliefert" und „darf das Gerät erreichen" schließen sich also
aus; verworfen wurden dazu die Idee, den Seitencode verschlüsselt
abzulegen (der Entschlüssel-Bootstrap kommt selbst im Klartext), und die
Idee, die Seite per HTTPS auszuliefern (dann blockiert Mixed Content die
Verbindung zum Gerät). Ein reiner Browser-Client wäre daher zwangsläufig
nur LAN-Vertrauen.

**Einzige wirklich sichere Zukunftsoption — eigenes Feature
„Fernzugriff", nicht der Browser-Client:** ein Relay, bei dem das Gerät
per TLS *ausgehend* zu einem Rendezvous-Server wählt (CircuitPython kann
TLS-**Client**), der Browser per HTTPS/`wss` dorthin verbindet und
DICTUSB2 **Ende-zu-Ende** läuft (Relay sieht nur Chiffrat). Größter
Brocken bisher und das Gerät ginge erstmals aktiv ins Internet — nur bei
konkretem Bedarf angehen. Für sichere Nutzung heute: die **Flutter-App**
(roher TCP, volle Krypto, alle drei Desktop-Systeme).

## Typische Handgriffe

```sh
# Flutter-App starten (aus echtem Terminal — macOS-Local-Network!)
cd app && flutter run -d macos

# Python-Client, interaktiv (Ende: 5x linke Shift-Taste in 2 s)
./mac/dictusb.py 192.168.0.50

# Text senden
echo 'Hallo' | ./mac/dictusb.py 192.168.0.50

# Tasten-Modus mit Cmd<->Strg-Tausch (nur macOS)
./mac/dictusb.py 192.168.0.50 --tasten

# Verbindung prüfen, ohne zu tippen (nur aus echtem Terminal)
cd app && dart run bin/probe.dart

# Firmware ausrollen (Gerät lädt automatisch neu)
./mac/deploy.sh                          # Pico (Host aus settings.toml)
DICTUSB_HOST=192.168.0.51 ./mac/deploy.sh   # ESP32

# Logs ansehen
open http://192.168.0.50/cp/serial/

# Alles prüfen
python3 -m py_compile firmware/*.py && ./testdata/make_vectors.py --check
cd app && flutter analyze && flutter test
```
