# dictUSB auf dem ESP32-S3

Zweites Zielgerät neben dem Pico 2 W. **Die Firmware ist identisch** —
`code.py`, `dictusb_crypto.py` und `boot.py` laufen unverändert auf
beiden Plattformen; nur der Weg zur Installation unterscheidet sich.

## Getestetes Board

Generisches DevKitC-1-Derivat, Aufdruck „ESP32-S3-N16R8 WiFi+BT MODEL":

| | |
|---|---|
| Chip | ESP32-S3 (QFN56) Rev. v0.2, Dual Core + LP, 240 MHz |
| Flash / PSRAM | 16 MB (quad) / 8 MB embedded |
| Basis-/WLAN-MAC | gerätespezifisch (steht in `boot_out.txt` auf dem `CIRCUITPY`-Laufwerk) |
| CircuitPython | 10.2.1, Board-ID `espressif_esp32s3_devkitc_1_n16` |

**Die beiden USB-Buchsen sind nicht gleichwertig.** Bei Blick auf die
Buchsen ist beim Testboard **links die native USB-Buchse** — sie hängt
direkt am Chip und ist die einzige, die HID (Tastatur) kann. Erkennbar
am Mac daran, dass dort ein Gerät namens `/dev/cu.usbmodem*` erscheint;
ein UART-Wandler hieße `usbserial`. Die rechte Buchse versorgte das
Board zwar mit Strom, meldete aber kein serielles Gerät (Treiber für den
Wandler fehlt) — für dictUSB wird sie nicht gebraucht.

## Image-Wahl

Für „N16R8" gibt es **kein** fertiges CircuitPython-Image (angeboten
werden N8, N16, N8R8, N8R2, N32R8). Verwendet wird **N16**: passt exakt
zu den 16 MB Flash und ergibt das größte `CIRCUITPY`-Laufwerk. Die
8 MB PSRAM bleiben ungenutzt — für dictUSB ohne Bedeutung.

## Installation

1. **Download-Modus**: BOOT gedrückt halten, USB-Kabel (native Buchse,
   möglichst **direkt am Mac**, nicht über einen Hub) einstecken, kurz
   weiterhalten, loslassen. Erfolgskontrolle: Es erscheint ein Gerät
   „USB JTAG_serial debug unit" (VID `0x303A`, PID `0x1001`).
   *Über einen USB-Hub/Dock schlägt das oft fehl — das Board
   verschwindet dann beim Moduswechsel komplett vom Bus.*
2. **Flashen** (`pip install --user --break-system-packages esptool`):
   ```sh
   python3 -m esptool --port /dev/cu.usbmodem101 erase-flash
   python3 -m esptool --port /dev/cu.usbmodem101 write-flash 0x0 \
       adafruit-circuitpython-espressif_esp32s3_devkitc_1_n16-en_US-10.2.1.bin
   ```
3. **Neu starten**: Kabel abziehen und wieder einstecken (oder RST
   drücken) — **ohne** BOOT. Ein Software-Reset aus dem Bootloader
   heraus genügt nicht. Danach erscheint das Laufwerk `CIRCUITPY`, und
   macOS zeigt den Tastatur-Assistenten (das Board meldet sich bereits
   als Tastatur — Assistent einfach schließen).
4. **Dateien kopieren**: `code.py`, `dictusb_crypto.py`, `boot.py` sowie
   `lib/adafruit_hid/` und `lib/keyboard_layout_win_de.mpy` +
   `lib/keycode_win_de.mpy`. Die Libraries lassen sich bequem vom
   laufenden Pico ziehen — dort passen die `.mpy`-Versionen garantiert:
   ```sh
   curl -u ":$WEBPASS" http://<pico-ip>/fs/lib/keyboard_layout_win_de.mpy -o …
   ```
5. **`settings.toml` anlegen** (WLAN, Web-API-Passwort, `DICTUSB_TOKEN`).
   Gleiches Token wie der Pico ⇒ der Mac-Client spricht ohne
   Umkonfiguration mit beiden Geräten.

## Unterschiede zum Pico im Betrieb

- Kein CYW43-Workaround nötig; der WLAN-Aufbau lief auf Anhieb.
- Serielle Konsole am Mac: `/dev/cu.usbmodem*` (native Buchse),
  z. B. `screen /dev/cu.usbmodem* 115200`.
- Web-Workflow wie beim Pico: `http://<ip>/fs/` und `http://<ip>/cp/serial/`.
- Alles Weitere (Protokoll, Layout, Kombinationen) ist identisch —
  siehe `README.md` und `PROTOCOL.md`.
