/// Roundtrip- und Fallback-Tests für die Direktmodus-Persistenz.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dictusb_app/config/config_store.dart';
import 'package:dictusb_app/config/models.dart';
import 'package:dictusb_app/dictusb/keymap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loadDirect ohne gespeicherte Werte liefert Plattform-Defaults',
      () async {
    SharedPreferences.setMockInitialValues({});
    final s = await ConfigStore().loadDirect(isMacOS: true);
    expect(s.metaTo, TargetMod.ctrl);
    expect(s.ctrlTo, TargetMod.win);
    expect(s.altChars, DirectSettings.defaultAltChars);
    expect(s.toggleKey, 'f1');
  });

  test('saveDirect/loadDirect Roundtrip', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ConfigStore();
    const s = DirectSettings(
      ctrlTo: TargetMod.alt,
      altTo: TargetMod.win,
      metaTo: TargetMod.ctrl,
      altChars: '@€',
      toggleKey: 'f7',
    );
    await store.saveDirect(s);
    final r = await store.loadDirect(isMacOS: false);
    expect(r.ctrlTo, TargetMod.alt);
    expect(r.altTo, TargetMod.win);
    expect(r.metaTo, TargetMod.ctrl);
    expect(r.altChars, '@€');
    expect(r.toggleKey, 'f7');
  });

  test('unbekannte gespeicherte Werte fallen auf Defaults zurück', () async {
    SharedPreferences.setMockInitialValues({
      'dictusb.direct.modCtrl': 'quatsch',
      'dictusb.direct.toggleKey': 'f99',
    });
    final r = await ConfigStore().loadDirect(isMacOS: false);
    expect(r.ctrlTo, TargetMod.ctrl);
    expect(r.toggleKey, 'f1');
  });

  test('loadDevices migriert die alte Einzelverbindung zu „Gerät 1"',
      () async {
    SharedPreferences.setMockInitialValues({
      'dictusb.host': '192.168.0.50',
      'dictusb.port': 8080,
      'dictusb.token': 'geheim',
    });
    final devices = await ConfigStore().loadDevices();
    expect(devices, hasLength(1));
    expect(devices.first.name, 'Gerät 1');
    expect(devices.first.host, '192.168.0.50');
    expect(devices.first.port, 8080);
    expect(devices.first.token, 'geheim');
  });

  test('Geräte-/Snippet-/Auswahl-Roundtrip', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ConfigStore();
    await store.saveDevices(const [
      Device(name: 'Pico', host: '192.168.0.50', port: 8080, token: 't1'),
      Device(name: 'ESP32', host: '192.168.0.51', port: 8080, token: 't2'),
    ]);
    await store.saveSnippets(const [
      Snippet(label: 'Gruß', text: 'Hallo Welt\n'),
    ]);
    await store.saveActiveDevice(1);

    final devices = await store.loadDevices();
    expect(devices, hasLength(2));
    expect(devices[1].name, 'ESP32');
    expect(devices[1].token, 't2');
    final snippets = await store.loadSnippets();
    expect(snippets, hasLength(1));
    expect(snippets.first.text, 'Hallo Welt\n');
    expect(await store.loadActiveDevice(), 1);
  });

  test('defekte JSON-Ablage liefert leere Listen statt Absturz', () async {
    SharedPreferences.setMockInitialValues({
      'dictusb.devices': 'kein json',
      'dictusb.snippets': '{"kein":"array"}',
    });
    final store = ConfigStore();
    expect(await store.loadDevices(), isEmpty);
    expect(await store.loadSnippets(), isEmpty);
  });
}
