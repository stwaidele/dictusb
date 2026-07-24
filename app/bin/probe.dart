/// dictUSB-Verbindungstest — verbindet, authentisiert, hält die Verbindung
/// über die 5-s-Deadline des Geräts und prüft die Quittungen. **Tippt
/// nichts.**
///
/// Muss aus einem echten Terminal laufen (macOS-Local-Network-Freigabe),
/// nicht durch einen Wrapper/Harness.
///
///   cd app && dart run bin/probe.dart [host]
///
/// Host/Port/Token: Argument bzw. Umgebungsvariablen DICTUSB_HOST/_PORT/
/// _TOKEN, sonst aus `firmware/settings.toml`, Host-Default 192.168.0.50.
library;

import 'dart:io';

import 'package:dictusb_app/dictusb/conn.dart';

Future<void> main(List<String> args) async {
  final settings = _readSettings();
  final env = Platform.environment;
  final host = args.isNotEmpty
      ? args.first
      : (env['DICTUSB_HOST'] ?? settings['DICTUSB_HOST'] ?? '192.168.0.50');
  final port =
      int.tryParse(env['DICTUSB_PORT'] ?? settings['DICTUSB_PORT'] ?? '') ??
      8080;
  final token = env['DICTUSB_TOKEN'] ?? settings['DICTUSB_TOKEN'] ?? '';

  stdout.writeln(
    'dictUSB-Probe → $host:$port  (${token.isEmpty ? "Klartext" : "verschlüsselt"})',
  );
  if (token.isEmpty) {
    stderr.writeln('WARN: kein DICTUSB_TOKEN gefunden — teste unverschlüsselt.');
  }

  final Conn conn;
  try {
    conn = await Conn.dial(host, port, token, const Duration(seconds: 5));
  } catch (e) {
    stderr.writeln('FEHLER: Verbindung/Authentisierung fehlgeschlagen: $e');
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'verbunden mit ${conn.remoteAddr}, authentisiert '
    '(Banner ok, Lebenszeichen gesendet).',
  );

  // Über die 5-s-Deadline des Geräts hinaus offen halten, ohne zu tippen.
  const hold = Duration(seconds: 7);
  final deadline = DateTime.now().add(hold);
  try {
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await conn.heartbeatIfIdle();
    }
  } catch (e) {
    stderr.writeln('FEHLER: Verbindung brach ab: $e');
    await conn.close();
    exitCode = 1;
    return;
  }

  final acks = conn.acksSeen;
  await conn.close();
  if (token.isNotEmpty && acks == 0) {
    stderr.writeln(
      'FEHLER: keine Quittung erhalten — Token falsch oder Firmware '
      'antwortet nicht.',
    );
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'OK: Verbindung über ${hold.inSeconds} s gehalten, $acks Quittung(en) — '
    'es wurde NICHT getippt.',
  );
}

Map<String, String> _readSettings() {
  const candidates = [
    '../firmware/settings.toml',
    'firmware/settings.toml',
    '../../firmware/settings.toml',
  ];
  for (final p in candidates) {
    final f = File(p);
    if (f.existsSync()) return _parseToml(f.readAsStringSync());
  }
  return {};
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
