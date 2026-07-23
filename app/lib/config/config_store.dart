/// Persistente Verbindungs-Konfiguration (Host/Port/Token) über
/// [SharedPreferences] — überlebt Programmneustarts, auf allen Plattformen.
///
/// Der Token liegt damit im plattformüblichen Preferences-Speicher
/// (macOS: NSUserDefaults-Plist unter ~/Library/Preferences, nutzerlesbar
/// — vergleichbar mit der 0600-Konfig der Go-TUI). Eine härtere Ablage im
/// Schlüsselbund (flutter_secure_storage) ist später möglich.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../dictusb/keymap.dart';
import 'models.dart';

class SavedConfig {
  final String host;
  final int port;
  final String token;
  const SavedConfig({
    required this.host,
    required this.port,
    required this.token,
  });
}

class ConfigStore {
  static const _kHost = 'dictusb.host';
  static const _kPort = 'dictusb.port';
  static const _kToken = 'dictusb.token';

  /// Liefert die gespeicherte Konfiguration oder `null`, wenn noch nichts
  /// gespeichert wurde (dann greift die settings.toml-Vorbelegung).
  Future<SavedConfig?> load() async {
    final p = await SharedPreferences.getInstance();
    if (!p.containsKey(_kHost) && !p.containsKey(_kToken)) return null;
    return SavedConfig(
      host: p.getString(_kHost) ?? '',
      port: p.getInt(_kPort) ?? 8080,
      token: p.getString(_kToken) ?? '',
    );
  }

  Future<void> save({
    required String host,
    required int port,
    required String token,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kHost, host);
    await p.setInt(_kPort, port);
    await p.setString(_kToken, token);
  }

  static const _kModCtrl = 'dictusb.direct.modCtrl';
  static const _kModAlt = 'dictusb.direct.modAlt';
  static const _kModMeta = 'dictusb.direct.modMeta';
  static const _kAltChars = 'dictusb.direct.altChars';
  static const _kToggleKey = 'dictusb.direct.toggleKey';

  /// Direktmodus-Einstellungen; fehlende oder unbekannte Werte fallen auf
  /// die Plattform-Defaults zurück (rein additiv, keine Migration nötig).
  Future<DirectSettings> loadDirect({required bool isMacOS}) async {
    final p = await SharedPreferences.getInstance();
    final d = DirectSettings.defaultsFor(isMacOS: isMacOS);
    TargetMod mod(String? name, TargetMod fallback) => name == null
        ? fallback
        : (TargetMod.values.asNameMap()[name] ?? fallback);
    final toggle = p.getString(_kToggleKey);
    return DirectSettings(
      ctrlTo: mod(p.getString(_kModCtrl), d.ctrlTo),
      altTo: mod(p.getString(_kModAlt), d.altTo),
      metaTo: mod(p.getString(_kModMeta), d.metaTo),
      altChars: p.getString(_kAltChars) ?? d.altChars,
      toggleKey: fKeyByName.containsKey(toggle) ? toggle! : d.toggleKey,
    );
  }

  Future<void> saveDirect(DirectSettings s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kModCtrl, s.ctrlTo.name);
    await p.setString(_kModAlt, s.altTo.name);
    await p.setString(_kModMeta, s.metaTo.name);
    await p.setString(_kAltChars, s.altChars);
    await p.setString(_kToggleKey, s.toggleKey);
  }

  static const _kDevices = 'dictusb.devices';
  static const _kActiveDevice = 'dictusb.activeDevice';
  static const _kSnippets = 'dictusb.snippets';

  /// Geräteliste; migriert beim ersten Aufruf die alte Einzelverbindung
  /// (host/port/token-Keys aus Phase 2) zu „Gerät 1". Leer, wenn weder
  /// Liste noch Altbestand existieren (dann greift die Bootstrap-Vorlage).
  Future<List<Device>> loadDevices() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kDevices);
    if (raw != null) return Device.decodeList(raw);
    final legacy = await load();
    if (legacy == null) return const [];
    return [
      Device(
        name: 'Gerät 1',
        host: legacy.host,
        port: legacy.port,
        token: legacy.token,
      ),
    ];
  }

  Future<void> saveDevices(List<Device> devices) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDevices, Device.encodeList(devices));
  }

  Future<int> loadActiveDevice() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kActiveDevice) ?? 0;
  }

  Future<void> saveActiveDevice(int index) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kActiveDevice, index);
  }

  Future<List<Snippet>> loadSnippets() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kSnippets);
    return raw == null ? const [] : Snippet.decodeList(raw);
  }

  Future<void> saveSnippets(List<Snippet> snippets) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSnippets, Snippet.encodeList(snippets));
  }
}
