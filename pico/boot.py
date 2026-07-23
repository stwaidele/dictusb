# boot.py — läuft nur bei hartem Reset (Einstecken, microcontroller.reset()),
# nicht beim Auto-Reload.
import os

import storage
import usb_hid

# USB-HID auf reine Tastatur reduzieren (kein Maus/Consumer-HID).
usb_hid.enable((usb_hid.Device.KEYBOARD,))

# CIRCUITPY-Laufwerk standardmäßig deaktivieren UND den Flash für
# CircuitPython beschreibbar machen: Beides ist nötig, damit die
# Web-Workflow-API Dateien schreiben darf (sonst 409 Conflict) — das
# Laufwerk wegzunehmen reicht nicht, der Flash bleibt sonst aus
# CircuitPython-Sicht read-only. Der Windows-PC sieht so nur noch eine
# "echte" Tastatur.
# Für Entwicklung am Kabel: DICTUSB_USB_DRIVE = "1" in settings.toml
# (Änderung wirkt nach dem nächsten harten Reset; die settings.toml ist
# über http://<ip>/fs/ oder REPL weiterhin erreichbar. Notausstieg: BOOTSEL.)
if os.getenv("DICTUSB_USB_DRIVE") != "1":
    storage.disable_usb_drive()
    storage.remount("/", readonly=False)
