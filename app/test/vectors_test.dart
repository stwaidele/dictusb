/// Kompatibilitätstest gegen `testdata/vectors.json` — der verbindliche
/// DICTUSB2-Vertrag (PROTOCOL.md §10). Der Dart-Port gilt als korrekt,
/// wenn er pro Fall die abgeleiteten Schlüssel und Quittungen reproduziert,
/// **jeden `frame` bitgleich** erzeugt und die Frames wieder entschlüsselt.
///
/// Reiner Dart-Test: `cd app && dart pub get && dart test`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dictusb_app/dictusb/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

File _vectorsFile() {
  const candidates = [
    '../testdata/vectors.json', // Lauf aus app/
    'testdata/vectors.json', // Lauf aus Repo-Wurzel
    '../../testdata/vectors.json',
  ];
  for (final p in candidates) {
    final f = File(p);
    if (f.existsSync()) return f;
  }
  throw StateError(
    'testdata/vectors.json nicht gefunden (cwd: ${Directory.current.path})',
  );
}

void main() {
  final data =
      jsonDecode(_vectorsFile().readAsStringSync()) as Map<String, dynamic>;
  final cases = (data['cases'] as List).cast<Map<String, dynamic>>();

  test('vectors.json enthält Fälle', () {
    expect(cases, isNotEmpty);
  });

  for (final c in cases) {
    final name = c['name'] as String;
    group('Fall: $name', () {
      final token = c['token'] as String;
      final salt = hexDecode(c['salt'] as String);

      test('Banner-Parse liefert das Salt', () {
        expect(hexEncode(parseBanner(c['banner'] as String)), c['salt']);
      });

      test('Schlüsselableitung K_enc/K_mac/K_ack', () {
        expect(hexEncode(deriveKey(token, 'enc', salt)), c['k_enc']);
        expect(hexEncode(deriveKey(token, 'mac', salt)), c['k_mac']);
        expect(hexEncode(deriveKey(token, 'ack', salt)), c['k_ack']);
      });

      test('Quittungen bitgleich reproduziert', () {
        final acks = (c['acks'] as List).cast<String>();
        // AckChecker akzeptiert die konkatenierten Referenz-Quittungen.
        final checker = AckChecker(token, salt);
        final stream = <int>[];
        for (final a in acks) {
          stream.addAll(hexDecode(a));
        }
        expect(checker.feed(stream), acks.length);
      });

      test('Frames bitgleich erzeugt und wieder entschlüsselt', () {
        final frames = (c['frames'] as List).cast<Map<String, dynamic>>();
        final enc = Encryptor(token, salt);
        final dec = Decryptor(token, salt);
        var expectedSeq = 0;
        for (final f in frames) {
          expect(f['seq'], expectedSeq, reason: 'Frames müssen ab 0 lückenlos zählen');
          final plain = hexDecode(f['plaintext'] as String);

          // Erzeugung: encrypt(plaintext) == frame (bitgleich).
          final produced = enc.encrypt(plain);
          expect(hexEncode(produced), f['frame'],
              reason: 'Frame seq=${f['seq']} muss bitgleich sein');

          // Entschlüsselung: derselbe Frame ergibt wieder den Klartext.
          final back = dec.feed(hexDecode(f['frame'] as String));
          expect(hexEncode(back), f['plaintext'],
              reason: 'Frame seq=${f['seq']} muss zurück-entschlüsseln');

          expectedSeq++;
        }
      });
    });
  }
}
