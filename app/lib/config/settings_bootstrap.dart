/// Best-effort-Vorbelegung der Verbindungsfelder aus `pico/settings.toml`
/// (nur Desktop, wenn die Datei im Repo neben der App liegt). Eine echte
/// persistente Konfiguration kommt in einer späteren Phase; auf Mobil gibt
/// es die Datei nicht → leere Vorgabe, Nutzer trägt selbst ein.
library;

import 'dart:io';

class Bootstrap {
  final String host;
  final int port;
  final String token;
  const Bootstrap({this.host = '', this.port = 8080, this.token = ''});
}

Bootstrap loadBootstrap() {
  if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    return const Bootstrap();
  }
  const candidates = [
    '../pico/settings.toml',
    'pico/settings.toml',
    '../../pico/settings.toml',
  ];
  for (final p in candidates) {
    final f = File(p);
    if (!f.existsSync()) continue;
    try {
      final m = _parseToml(f.readAsStringSync());
      return Bootstrap(
        host: m['DICTUSB_HOST'] ?? '',
        port: int.tryParse(m['DICTUSB_PORT'] ?? '') ?? 8080,
        token: m['DICTUSB_TOKEN'] ?? '',
      );
    } catch (_) {
      // Unlesbar → ignorieren, leere Vorgabe.
    }
  }
  return const Bootstrap();
}

final _tomlLine = RegExp(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+?)\s*$');

Map<String, String> _parseToml(String s) {
  final out = <String, String>{};
  for (final line in s.split('\n')) {
    if (line.trimLeft().startsWith('#')) continue;
    final m = _tomlLine.firstMatch(line);
    if (m == null) continue;
    var v = m.group(2)!;
    if (v.length >= 2 &&
        ((v.startsWith('"') && v.endsWith('"')) ||
            (v.startsWith("'") && v.endsWith("'")))) {
      v = v.substring(1, v.length - 1);
    }
    out[m.group(1)!] = v;
  }
  return out;
}
