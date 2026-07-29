# CLAUDE.md

Leitfaden für Claude Code in diesem Repo. Hier stehen die **dauerhaften**
Fakten; der aktuelle Stand steht in `Handoff.md`.

## Session-Übergabe

Zum Einstieg zuerst **`Handoff.md`** lesen — dort stehen Stand, offene
Punkte und der nächste Schritt.

Für Lesen, Fortschreiben und Prüfen gilt der globale Skill
`~/.claude/skills/handoff/` (`/handoff`, `/handoff start`,
`/handoff check`). Die Regeln dazu bitte nicht hier duplizieren.

## Projekt

Ein Mikrocontroller steckt per USB am Zielrechner und **ist dort eine ganz
normale Tastatur**. Gesendet wird per WLAN, verschlüsselt.

```
Sender (macOS/Linux/Windows) --(WLAN, TCP:8080, DICTUSB2)--> Pico 2 W / ESP32-S3 --(USB-HID)--> Zielrechner
```

**Auf dem Zielrechner läuft nie Software.** Daraus folgt die Stärke
(funktioniert überall, auch im BIOS und am Anmeldebildschirm, ohne Rechte)
und die einzige Einschränkung: Wir senden HID-Keycodes, also entscheidet
die **Tastaturbelegung des Zielrechners**, welche Zeichen ankommen.

Anleitungen: `README.md` · Protokoll: `PROTOCOL.md` ·
ESP32-Inbetriebnahme: `ESP32.md` · Client-Details: `app/README.md`.
Website-Inhalt: `docs/website-content.md` (inhaltliche Quelle der Seite
<https://werkzeugkasten.online/dictusb> — bei Textänderungen zuerst hier
pflegen, dann im Werkzeugkasten-Workspace nachziehen).

## Geräte

Beispiel-Setup mit zwei Geräten; die IPs im Repo sind **Beispielwerte**,
echte Betriebsdaten stehen in der gitignorten `PRIVAT.md`:

| Gerät | IP (Beispiel) | Besonderheit |
|---|---|---|
| Pico 2 W | `192.168.0.50` (fest reserviert) | LED einfarbig |
| ESP32-S3 | `192.168.0.51` (fest reserviert) | native USB-Buchse = **links**, RGB-LED |

Beide laufen mit **identischer Firmware** und **demselben Token** — Clients
sprechen ohne Umkonfiguration mit beiden, in der App per Geräte-Dropdown
umschaltbar. An welchem Zielrechner ein Gerät steckt, ist beliebig und wird
nach Bedarf umgesteckt; nur `DICTUSB_LAYOUT` muss zum jeweiligen Rechner
passen.

Fernwartung ohne Kabelwechsel (je Gerät, Login: Benutzername **leer**,
Passwort = `CIRCUITPY_WEB_API_PASSWORD`):

- Logs/REPL: `http://<ip>/cp/serial/`
- Dateien: `http://<ip>/fs/` (auch `settings.toml` bearbeiten)
- Updates: `./mac/deploy.sh` bzw. `DICTUSB_HOST=<ip> ./mac/deploy.sh`

## Firmware (`firmware/`, gilt für beide Geräte)

CircuitPython **10.2.1**. In `/lib`: `adafruit_hid` +
`keyboard_layout_win_de`/`keycode_win_de` (Neradoc-Bundle, 10.x-mpy).

- `code.py` — WLAN, TCP-Server, HID-Tippen, DICTUSB2, Lebenszeichen,
  Layout-Auswahl. Kombi-Tasten als Sequenz `0x00<spec>\n`; ein
  **Modifier-Name allein** ist erlaubt (`\x00shift\n` tippt Shift, z. B.
  gegen den Bildschirmschoner — `PROTOCOL.md` §7).
- `boot.py` — reduziert HID auf Tastatur, deaktiviert das
  `CIRCUITPY`-Laufwerk und remountet den Flash beschreibbar (nur so darf
  die Web-API schreiben). Wirkt **erst nach hartem Reset**.
- `dictusb_crypto.py` — geteilte Krypto-Schicht: läuft unverändert auf dem
  Gerät **und** im Python-Client. `deploy.sh` rollt sie mit aus.
- `status_led.py` — Onboard-LED als Zustandsanzeige, fähigkeitserkennend:
  RGB (NeoPixel via Core-Modul `neopixel_write`) → einfarbig (`board.LED`,
  Blinkmuster) → nichts. **Gelb** = bereit, **grün @50 %** = verbunden,
  Tastendruck → **Cyan-Tupfer**, **rot blinkend** = Abbruch (nur echte
  Abbrüche; sauberes Ende → direkt gelb). Farben und Fade-Zeit **ohne
  Neubau** per `settings.toml` änderbar: `DICTUSB_LED` (0=aus),
  `DICTUSB_LED_BRIGHTNESS`, `DICTUSB_LED_PIN`, `DICTUSB_LED_FADE`,
  `DICTUSB_LED_READY/_CONNECTED/_ACTIVITY/_ABORT` (Hex `rrggbb` oder
  `r,g,b`). Für die LED laufen die Socket-Timeouts auf 0.1 s — Tipp-Latenz
  und Heartbeat-Logik bleiben davon unberührt.
- `settings.toml` — nur lokal und auf dem Gerät, **gitignored**. Vorlage:
  `settings.toml.example`. Bei jeder Änderung `DICTUSB_SETTINGS_VERSION`
  hochzählen (die Startzeile zeigt sie).

### Verschlüsselung (DICTUSB2)

Mit gesetztem `DICTUSB_TOKEN` läuft der Kanal verschlüsselt und
integritätsgeschützt; **das Token wird nie übertragen**. Frisches Salt pro
Verbindung, HMAC-SHA256 als Keystream (CTR) und 8-Byte-MAC je Frame,
Quittungen in der Rückrichtung. Der Client verweigert Klartext, wenn ein
Token gesetzt ist (Downgrade-Schutz). Vollständig in `PROTOCOL.md`,
Testvektoren in `testdata/vectors.json` (`make_vectors.py --check`).

**Token rotieren**: neues per
`python3 -c 'import os; print(os.urandom(16).hex())'` in die lokale
`firmware/settings.toml`, `DICTUSB_SETTINGS_VERSION` hochzählen, dann
`DICTUSB_HOST=<ip> ./mac/deploy.sh firmware/settings.toml` je Gerät.
**Beide Kopien müssen identisch sein**, sonst trennt das Gerät nach 5 s.

### Lebenszeichen statt Timeout

Der Client sendet bei Untätigkeit alle 20 s einen Herzschlag (leere
Kombi-Sequenz — tippt nichts), das Gerät quittiert jeden mit 8
authentifizierten Bytes. Bleibt 90 s (`DICTUSB_IDLE_LIMIT`) ein gültiger
Frame aus, trennt das Gerät. Lange Denkpausen sind damit unkritisch, ein
verschwundener Client blockiert das Gerät aber nicht dauerhaft (es wird
nur **eine** Verbindung bedient).

## Zielsysteme und Layouts

`DICTUSB_LAYOUT` in der `settings.toml` wählt die Belegung des
Zielrechners — beim Umstecken an einen Rechner mit anderem Layout muss der
Wert passend gesetzt werden. Unbekannter oder fehlender Wert ⇒ **hörbarer**
Rückfall auf `us`; die Startzeile `Layout = …` zeigt die aktive Belegung.

| Ziel | Wert | Stand |
|---|---|---|
| Windows, deutsch | `win_de` (Default) | abgenommen |
| Linux, deutsch | `win_de` | abgenommen (Debian 13: TTY, X11, Wayland) |
| Windows/Linux, US | `us` (aus `adafruit_hid`, keine Umlaute) | **unbestätigt**, siehe offene Punkte im Handoff |
| fr/uk/es/it | `win_fr`, … | nutzbar, sobald die `.mpy` in `/lib` liegt |
| **macOS** | — | **bewusst offen**, Lösungswege im README |

## Clients

- **`app/` — Flutter-App (macOS/Windows/Linux), der Hauptclient**: Block-
  und Direktmodus, Diktat, Snippets, Multi-Gerät, Modifier-Mapping. Wird
  als einziger Client als Download veröffentlicht. Krypto ist bewusst
  reines Dart (`app/lib/dictusb/`), UI in `app/lib/ui/` + `app/lib/config/`.
  Kein `web/` (kein Raw-TCP im Browser); Mobil bekommt einen **eigenen**
  Client (entschieden 2026-07-22), Fokus ist Desktop.
- **`mac/dictusb.py` — Python-Client, macOS/Linux** (kein Windows:
  `termios`). Kann als einziger den **Tasten-Modus** (`--tasten`,
  Cmd↔Strg-Tausch) — braucht `pynput` und die macOS-Freigabe
  **Bedienungshilfen**. Ausstieg beider Modi: 5× linke Shift in 2 s. Liest
  das Token ohne `--token` aus `DICTUSB_TOKEN` (Env) oder der lokalen
  `firmware/settings.toml`. In `mac/` liegt auch `deploy.sh`.
- **Go-TUI — archiviert** (2026-07-23): war der erste plattformüber-
  greifende Client (Bubble Tea v2), mit der Flutter-App aus dem
  öffentlichen Stand entfernt. Quellcode nur im privaten Gitea-Branch
  `intern/historie-2026-07`. Hat den unten beschriebenen Quittungs-Fehler
  noch; bei einer Reaktivierung zuerst dort hinsehen.

### Entscheidungen von Stefan (gelten weiter — nicht „verbessern")

- **Modifier-Mapping statt Tausch-Schalter**: drei Dropdowns (Quell-
  Modifier → `Strg`/`Alt`/`Win`), plattformspezifisch beschriftet;
  macOS-Default = der Python-Tausch (Cmd→Strg, control→Win), Shift fix.
- **Alt-Zeichenliste** (Default `@[]{}|~\€`): gelistete komponierte Zeichen
  gehen als Text, andere Alt-Kombis als Kombi — deckt auch Windows-AltGr
  ab (das meldet Ctrl+Alt).
- **Umschalt-Taste F1** (ausdrücklich statt F10), konfigurierbar. Der
  Einstellungsdialog wechselt für seine Dauer in den Blockmodus und setzt
  den Tasten-Handler aus, sonst wären seine eigenen Felder nicht tippbar.
- **Snippet-Hotkeys Cmd/Strg+1…9 nur im Blockmodus** (dort einfügen an der
  Cursorposition; im Direktmodus nur per Klick, dafür sofort senden) —
  der Direktmodus soll transparent bleiben. Die Erkennung ignoriert Alt
  bewusst, sonst finge sie AltGr+7=`{` unter Windows/Linux ab.
- **Geräteliste mit Token je Gerät** (beim Anlegen vom ersten vorbelegt),
  **kein** Wechsel-Hotkey — nur das Dropdown; ein Wechsel bei bestehender
  Verbindung trennt und verbindet neu.
- **Modifier-Tipp**: ein allein gedrückter und losgelassener Modifier geht
  beim KeyUp als reine Kombi ans Gerät (z. B. gegen den Bildschirmschoner).
- OS-reservierte Kombis bleiben außen vor (macOS control+Pfeile = Spaces,
  Win+L …), und der Zeichenvorrat ist immer der des Ziel-Layouts —
  typografische „Anführungszeichen" kommen mit `win_de` nie an. Grenzen
  stehen in `app/README.md`.

## Kritische Randbedingungen

- **Quittungs-Regel (gilt für jeden Client)**: Die Firmware quittiert
  **ausschließlich Lebenszeichen** (`dec.take_heartbeats()` in `code.py`),
  Nutzlast-Frames nie. Eine „keine Antwort"-Erkennung darf deshalb **nur**
  an einem gesendeten Herzschlag hängen (Frist ab Versand, Quittung löscht
  sie), niemals am Alter der letzten Quittung — sonst bricht die
  Verbindung fälschlich ab bei anhaltendem Tippen (keine 20-s-Pause → keine
  Herzschläge) und nach Timer-Stillstand durch macOS App Nap. Im
  Dart-Client: `conn.dart`, `_sendHeartbeat()` + `ackGrace` (30 s, Frist
  **vor** dem Senden setzen).
- **Diktat-Regel (Paraspeech)**: Diktiersoftware liefert ihr Ergebnis
  **nicht als Tastendruck-Folge**, sondern legt es in die Zwischenablage
  und drückt eine Nicht-Standard-Paste-Kombi (Paraspeech: `Ctrl+Alt+V`).
  Paraspeech **hält die Kombi nicht** (Ctrl-down, Alt-down, Ctrl-up,
  Alt-up, erst danach das `v`), und die Wartezeit bis zum `v` **skaliert
  mit der Diktatlänge**. Deshalb in `app/lib/ui/home_page.dart` eine
  Sequenz-Heuristik statt eines Zeitfensters: Ctrl+Alt bewaffnen (beide
  ≤ 1 s auseinander), jede andere Taste entwaffnet, das Zeitfenster ist
  nur noch Veraltungs-Grenze. `e.timeStamp` synthetischer CGEvents ist
  unbrauchbar — Ankunftszeit im Handler nehmen. Diagnose:
  `flutter run -d macos --dart-define=DICTUSB_DIAG=true`.
- **Latenz** hat Priorität: TCP_NODELAY, Zeichen sofort senden.
- **Sicherheit**: DICTUSB2 ist Pflicht, sobald ein Token gesetzt ist;
  echte Tokens/IPs gehören ausschließlich in `PRIVAT.md` bzw. die lokale
  `settings.toml`.

## Entwicklung

Firmware hat kein Build-System: Dateien werden auf das `CIRCUITPY`-Laufwerk
bzw. per `deploy.sh` über die Web-API kopiert; das Gerät startet `code.py`
nach jedem Schreiben neu. Debug-Ausgaben über die serielle Konsole oder
`http://<ip>/cp/serial/`.

Für die App gilt: `flutter analyze` und `flutter test` müssen grün sein;
`dart run bin/probe.dart` und `flutter run` nur **aus einem echten
Terminal** (macOS-Berechtigung „Lokales Netzwerk", siehe Stolperfallen im
Handoff).

## Veröffentlichung

- **Öffentlich**: `github.com/stwaidele/dictusb` (MIT). **Entwicklung
  bleibt primär auf Gitea** (`gitea.101010.cloud`).
- **Ein `origin`, zwei Push-URLs** (Gitea + GitHub): jedes
  `git push origin` (auch Tags) erreicht **beide** Remotes. Zusätzlich
  Remote `github` zum Fetchen (`git fetch github &&
  git log main..github/main` muss leer sein). SSH-Alias `github-dictusb`.
- **Historie**: öffentlicher Frischstart (`6400fd9`); die alte
  74-Commit-Historie liegt **nur auf Gitea** im privaten Branch
  `intern/historie-2026-07` (dort auch die Go-TUI).
- **`PRIVAT.md`** (gitignored, Repo-Root): echte IPs/MACs und Handgriffe
  mit echten Werten — niemals committen.
- ⚠️ **GitHub-PRs nie über den Merge-Button mergen** (der Commit entstünde
  nur auf GitHub): stattdessen `gh pr checkout`, lokal mergen/testen,
  `git push origin main` — erreicht beide Remotes.
- **Release**: Tag `v*` pushen löst `.github/workflows/release.yml` aus
  (`-rc` = Prerelease). Vorher `version:` in `app/pubspec.yaml` hochzählen.
  Signierung/Notarisierung (macOS) schalten sich über die Apple-Secrets
  selbst scharf; das **DMG wird selbst mitsigniert** (`hdiutil` erzeugt
  unsignierte Images — sonst weist `spctl` es ab). Prüfkette nach jedem
  Release: SHA256, `spctl -a -vv` („accepted, source=Notarized Developer
  ID") und `stapler validate`. Windows-Zip bleibt unsigniert
  (SmartScreen-Warnung ist erwartet und akzeptiert).
- **Apple-Einrichtung**: Developer-ID-Zertifikat „Stefan Waidele"
  (Team `ZDZ57JDWK4`, gültig bis 2027-02-01); P12 + Passwort +
  App-Store-Connect-Key unter `~/.config/dictusb/` (Mode 600, Details in
  `PRIVAT.md`; P12 mit OpenSSL 3 nur via `-legacy` lesbar). Fünf
  GitHub-Secrets: `MACOS_CERT_P12` (base64), `MACOS_CERT_PASSWORD`,
  `APPSTORE_KEY_ID`, `APPSTORE_ISSUER_ID`, `APPSTORE_PRIVATE_KEY`.
- **App-Icon regenerieren** (Quellen in `docs/img/`): macOS-Iconset je
  Größe `rsvg-convert -w <s> -h <s> docs/img/dictusb-icon-macos.svg -o
  app/macos/…/app_icon_<s>.png` (16–1024); Windows `magick
  docs/img/dictusb-icon-1024.png -define
  icon:auto-resize=256,128,64,48,32,16
  app/windows/runner/resources/app_icon.ico`. Danach zeigt das Dock
  gecacht das alte Icon — `touch` aufs Bundle + `killall Dock`.
- **Screenshots** immer mit **Beispiel-Konfiguration** aufnehmen
  (Prefs-Domain `info.waidele.dictusbApp` vorher per `defaults export`
  sichern — sonst stehen echte IPs/Tokens im Geräte-Dropdown). Klicken und
  Fokussieren nur mit `cliclick`; AppleScript „click at" gibt
  Flutter-Feldern keinen Fokus.

## Bewusst verworfen (nicht neu vorschlagen)

**Browser-Client** (2026-07-20 zurückgestellt) — keine Aufwandsfrage,
sondern eine prinzipielle Wand: Das Gerät kann **kein TLS-Server** sein
(CircuitPython-Limit). Ein Browser erreicht ein TLS-loses Gerät nur aus
einem **unsicheren Kontext** (`http`-Seite → `ws://`); eine `https`- oder
`file://`-Seite blockiert `ws://` als Mixed Content. Ein unsicherer Kontext
lässt sich aber nicht integer ausliefern — ein aktiver Angreifer im WLAN
fälscht die Seite und stiehlt das Token. „Sicher ausgeliefert" und „darf
das Gerät erreichen" schließen sich also aus. Verworfen wurden dazu auch:
Seitencode verschlüsselt ablegen (der Entschlüssel-Bootstrap kommt selbst
im Klartext) und Auslieferung per HTTPS (dann blockiert Mixed Content).
Einzige wirklich sichere Zukunftsoption wäre ein **eigenes Feature
„Fernzugriff"**: Relay, zu dem das Gerät per TLS *ausgehend* wählt
(CircuitPython kann TLS-**Client**), Browser per HTTPS/`wss` dorthin,
DICTUSB2 Ende-zu-Ende (Relay sieht nur Chiffrat) — großer Brocken, und das
Gerät ginge erstmals aktiv ins Internet; nur bei konkretem Bedarf.
