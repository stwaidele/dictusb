/// DICTUSB2-Protokoll (Client-Seite) in Dart.
///
/// Maßgeblich ist `PROTOCOL.md` im Repo-Wurzelverzeichnis; die Referenz
/// ist `firmware/dictusb_crypto.py`. Testvektoren (der verbindliche
/// Kompatibilitätsvertrag): `testdata/vectors.json`.
///
/// Reine HMAC-SHA256-Konstruktion, keine weiteren Krypto-Abhängigkeiten.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const String bannerPrefix = 'DICTUSB2 ';
const int saltLen = 16;
const int macLen = 8;
const int maxPlain = 255;
const int ackLen = 8;

/// Lebenszeichen des Clients: eine leere Kombinations-Spezifikation, die
/// die Firmware verwirft, ohne zu tippen. Hält die Sitzung offen und wird
/// vom Gerät quittiert.
final Uint8List heartbeat = Uint8List.fromList([0x00, 0x0a]);

final RegExp _bannerRe = RegExp(r'^DICTUSB2 ([0-9a-f]{32})\n$');

/// Meldet einen MAC- oder Formatfehler im Frame-Strom. Die Verbindung ist
/// danach unbrauchbar und muss geschlossen werden.
class ProtocolException implements Exception {
  final String message;
  ProtocolException(this.message);
  @override
  String toString() => 'DICTUSB2-Protokollfehler: $message';
}

// --- Hilfen -----------------------------------------------------------

Uint8List _hmacSum(List<int> key, List<List<int>> parts) {
  final b = BytesBuilder(copy: false);
  for (final p in parts) {
    b.add(p);
  }
  return Uint8List.fromList(Hmac(sha256, key).convert(b.toBytes()).bytes);
}

Uint8List _seqBE(int seq) {
  final d = ByteData(8);
  d.setUint64(0, seq, Endian.big);
  return d.buffer.asUint8List();
}

Uint8List _concat(Uint8List a, List<int> b) {
  final out = Uint8List(a.length + b.length);
  out.setRange(0, a.length, a);
  out.setRange(a.length, out.length, b);
  return out;
}

/// Konstantzeitiger Vergleich zweier gleich langer Byte-Folgen.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var r = 0;
  for (var i = 0; i < a.length; i++) {
    r |= a[i] ^ b[i];
  }
  return r == 0;
}

/// Dekodiert eine Hex-Zeichenkette (gerade Länge) zu Bytes.
Uint8List hexDecode(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// Kodiert Bytes als Hex-Zeichenkette (Kleinbuchstaben).
String hexEncode(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

// --- Banner & Schlüssel ----------------------------------------------

/// Liest das 16-Byte-Salt aus der Bannerzeile. Jeder Formatfehler ist ein
/// Fehler — ein Client mit Token darf nie auf Klartext zurückfallen.
Uint8List parseBanner(String line) {
  final m = _bannerRe.firstMatch(line);
  if (m == null) {
    throw ProtocolException('kein gültiges DICTUSB2-Banner: $line');
  }
  return hexDecode(m.group(1)!);
}

/// Leitet einen benannten Session-Schlüssel ab:
/// `HMAC-SHA256(token_utf8, label_utf8 || salt)`.
Uint8List deriveKey(String token, String label, Uint8List salt) =>
    _hmacSum(utf8.encode(token), [utf8.encode(label), salt]);

/// Verknüpft `data` mit dem Keystream des Frames `seqB` (CTR-artig, HMAC
/// als PRF): `block(j) = HMAC(kEnc, seqB || j_u8)`.
Uint8List _keystreamXor(Uint8List kEnc, Uint8List seqB, Uint8List data) {
  final out = Uint8List.fromList(data);
  for (var j = 0; j * 32 < out.length; j++) {
    final block = _hmacSum(kEnc, [
      seqB,
      Uint8List.fromList([j]),
    ]);
    final base = j * 32;
    for (var i = 0; i < 32 && base + i < out.length; i++) {
      out[base + i] ^= block[i];
    }
  }
  return out;
}

// --- Verschlüsselung (Client -> Gerät) -------------------------------

/// Verschlüsselt einen Byte-Strom als Folge von Frames. An eine Verbindung
/// gebunden, nicht nebenläufig benutzbar.
class Encryptor {
  final Uint8List _kEnc;
  final Uint8List _kMac;
  int _seq = 0;

  Encryptor(String token, Uint8List salt)
    : _kEnc = deriveKey(token, 'enc', salt),
      _kMac = deriveKey(token, 'mac', salt);

  /// Zerlegt `data` in Frames zu höchstens [maxPlain] Bytes und liefert die
  /// fertigen Leitungs-Bytes.
  Uint8List encrypt(List<int> data) {
    final out = BytesBuilder(copy: false);
    for (var off = 0; off < data.length; off += maxPlain) {
      final end = (off + maxPlain < data.length) ? off + maxPlain : data.length;
      out.add(_frame(Uint8List.fromList(data.sublist(off, end))));
    }
    return out.toBytes();
  }

  Uint8List _frame(Uint8List plain) {
    final seqB = _seqBE(_seq);
    final ct = _keystreamXor(_kEnc, seqB, plain);
    final ln = Uint8List.fromList([ct.length]);
    final mac = _hmacSum(_kMac, [seqB, ln, ct]).sublist(0, macLen);
    _seq++;
    final b = BytesBuilder(copy: false);
    b.add(ln);
    b.add(ct);
    b.add(mac);
    return b.toBytes();
  }
}

// --- Entschlüsselung (Gerät -> Client, nur für Tests) ----------------

/// Gegenstück zum [Encryptor] (Server-Rolle). Der Client braucht ihn nur
/// für Tests — der Datenfluss ist einseitig Client -> Gerät.
class Decryptor {
  final Uint8List _kEnc;
  final Uint8List _kMac;
  int _seq = 0;
  Uint8List _buf = Uint8List(0);

  Decryptor(String token, Uint8List salt)
    : _kEnc = deriveKey(token, 'enc', salt),
      _kMac = deriveKey(token, 'mac', salt);

  /// Nimmt rohe Leitungs-Bytes und liefert den Klartext aller darin
  /// vollständig enthaltenen Frames; Teilframes werden gepuffert.
  Uint8List feed(List<int> data) {
    _buf = _concat(_buf, data);
    final out = BytesBuilder(copy: false);
    var pos = 0;
    while (pos < _buf.length) {
      final ln = _buf[pos];
      if (ln == 0) {
        throw ProtocolException('Frame mit Länge 0');
      }
      final end = pos + 1 + ln + macLen;
      if (_buf.length < end) {
        break; // Teilframe: auf mehr Daten warten
      }
      final ct = _buf.sublist(pos + 1, pos + 1 + ln);
      final mac = _buf.sublist(pos + 1 + ln, end);
      final seqB = _seqBE(_seq);
      final want = _hmacSum(_kMac, [
        seqB,
        Uint8List.fromList([ln]),
        ct,
      ]).sublist(0, macLen);
      if (!constantTimeEquals(want, mac)) {
        throw ProtocolException('MAC-Fehler bei Frame $_seq');
      }
      out.add(_keystreamXor(_kEnc, seqB, ct));
      _seq++;
      pos = end;
    }
    _buf = _buf.sublist(pos);
    return out.toBytes();
  }
}

// --- Quittungen (Gerät -> Client) ------------------------------------

/// Prüft die fortlaufenden Quittungen des Geräts:
/// `HMAC(kAck, ack_seq_be64)[0..7]`. Eigener Schlüssel, damit sich
/// Quittungen nicht als Client-Frames wiederverwenden lassen.
class AckChecker {
  final Uint8List _key;
  int _seq = 0;
  Uint8List _buf = Uint8List(0);

  AckChecker(String token, Uint8List salt)
    : _key = deriveKey(token, 'ack', salt);

  /// Nimmt rohe Bytes vom Socket und liefert die Zahl gültiger Quittungen.
  /// Passt eine nicht, spricht die Gegenstelle nicht mit unserem Token.
  int feed(List<int> data) {
    _buf = _concat(_buf, data);
    var n = 0;
    var pos = 0;
    while (_buf.length - pos >= ackLen) {
      final want = _hmacSum(_key, [_seqBE(_seq)]).sublist(0, ackLen);
      if (!constantTimeEquals(want, _buf.sublist(pos, pos + ackLen))) {
        throw ProtocolException('ungültige Quittung Nr. $_seq');
      }
      _seq++;
      n++;
      pos += ackLen;
    }
    _buf = _buf.sublist(pos);
    return n;
  }
}
