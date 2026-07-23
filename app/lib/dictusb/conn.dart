/// Verbindung zum Gerät (DICTUSB2, Client-Seite) über `dart:io`-Sockets.
///
/// Der Socket-Stream ist ereignisgetrieben, deshalb werden Quittungen
/// fortlaufend im Listener geprüft.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'protocol.dart';

/// Abstand der Lebenszeichen bei Untätigkeit. Das Gerät trennt nach seinem
/// Leerlauf-Limit (Default 90 s); ohne diesen Abbruch würde ein
/// abgestürzter Client es dauerhaft blockieren (nur eine Verbindung).
const Duration heartbeatEvery = Duration(seconds: 20);

/// Frist, binnen derer ein LEBENSZEICHEN quittiert sein muss. Die Firmware
/// quittiert ausschließlich Herzschläge (`take_heartbeats()` in code.py) —
/// Nutzlast-Frames nie. Deshalb darf nur der Herzschlag-Versand eine Frist
/// bewaffnen, und sie läuft ab diesem Versand — nicht ab der letzten
/// Quittung, denn die kann bei anhaltendem Tippen (keine 20-s-Pause → kein
/// Herzschlag → keine Quittungen) oder nach einem Timer-Stillstand (macOS
/// App Nap) beliebig alt sein, obwohl das Gerät gesund ist. Großzügig
/// bemessen, weil das Gerät einen Herzschlag erst liest, wenn es davor
/// empfangene Nutzlast fertig getippt hat.
const Duration ackGrace = Duration(seconds: 30);

Uint8List _cat(Uint8List a, List<int> b) {
  final out = Uint8List(a.length + b.length);
  out.setRange(0, a.length, a);
  out.setRange(a.length, out.length, b);
  return out;
}

/// Eine Verbindung zum Gerät. Mit Token verschlüsselt (DICTUSB2), ohne
/// Token im Klartext. Nicht nebenläufig aus mehreren Isolates benutzbar.
class Conn {
  final Socket _socket;
  final String _token;

  Encryptor? _enc;
  AckChecker? _ack;
  bool encrypted = false;

  /// Gesendete Klartext-Nutzlast-Bytes (für die Statusanzeige); Lebens-
  /// zeichen zählen nicht mit.
  int sent = 0;

  bool _bannerPhase;
  Uint8List _rxBuf = Uint8List(0);
  final Completer<Uint8List> _banner = Completer<Uint8List>();

  DateTime _lastSent = DateTime.now();
  DateTime? _lastAck;
  DateTime? _ackDeadline; // gesetzt beim ältesten unquittierten Frame
  int _acksSeen = 0;

  Object? _fatal; // erster tödlicher Fehler (Quittung/Format/Socket)
  final Completer<void> _closed = Completer<void>();

  // Klartext-Downgrade-Erkennung (nur ohne Token).
  Uint8List _peek = Uint8List(0);
  bool _sawBannerPrefix = false;

  Conn._(this._socket, this._token) : _bannerPhase = _token.isNotEmpty;

  /// Verbindet sich mit dem Gerät. Mit Token wird das Banner zwingend
  /// erwartet — es gibt bewusst keinen Klartext-Rückfall, sonst könnte ein
  /// alter oder gefälschter Server das Token entlocken.
  static Future<Conn> dial(
    String host,
    int port,
    String token,
    Duration timeout,
  ) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    socket.setOption(SocketOption.tcpNoDelay, true); // Latenz vor Durchsatz

    final conn = Conn._(socket, token);
    socket.listen(
      conn._onData,
      onError: conn._onSocketError,
      onDone: conn._onDone,
      cancelOnError: false,
    );

    if (token.isEmpty) {
      // Ein verschlüsselnder Server schickt sofort sein Banner. Kommt es,
      // ist Klartext sinnlos und wir sagen das klar.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (conn._sawBannerPrefix) {
        await socket.close();
        throw ProtocolException(
          'das Gerät erwartet Verschlüsselung, aber es ist kein Token konfiguriert',
        );
      }
      return conn;
    }

    final Uint8List line;
    try {
      line = await conn._banner.future.timeout(timeout);
    } catch (e) {
      await socket.close();
      throw ProtocolException('kein Banner vom Gerät (Firmware zu alt?): $e');
    }
    // Schlüssel wurden beim Bannerempfang in _onData abgeleitet.
    assert(line.isNotEmpty);

    // Sofort authentisieren: Das Gerät verwirft eine Verbindung, in der
    // nicht binnen 5 s ein gültiger Frame ankommt. Das Lebenszeichen ist
    // die harmloseste Nutzlast — die Firmware verwirft es und quittiert es.
    try {
      await conn._sendHeartbeat();
    } catch (e) {
      await socket.close();
      throw ProtocolException('Authentisierung fehlgeschlagen: $e');
    }
    conn.sent = 0; // das Lebenszeichen zählt nicht als Nutzlast
    return conn;
  }

  void _onData(Uint8List data) {
    if (_bannerPhase) {
      _rxBuf = _cat(_rxBuf, data);
      final idx = _rxBuf.indexOf(0x0a);
      if (idx < 0) {
        if (_rxBuf.length > 64 && !_banner.isCompleted) {
          _banner.completeError(ProtocolException('Bannerzeile zu lang'));
        }
        return;
      }
      final line = Uint8List.sublistView(_rxBuf, 0, idx + 1);
      final rest = Uint8List.sublistView(_rxBuf, idx + 1);
      _bannerPhase = false;
      _rxBuf = Uint8List(0);
      try {
        final salt = parseBanner(utf8.decode(line));
        _enc = Encryptor(_token, salt);
        _ack = AckChecker(_token, salt);
        encrypted = true;
        if (!_banner.isCompleted) _banner.complete(Uint8List.fromList(line));
      } catch (e) {
        if (!_banner.isCompleted) _banner.completeError(e);
        return;
      }
      if (rest.isNotEmpty) _handleAcks(Uint8List.fromList(rest));
      return;
    }

    if (_enc == null) {
      // Klartextmodus: nur auf ein (unerwartetes) Banner achten.
      _peek = _cat(_peek, data);
      if (_peek.length >= bannerPrefix.length) {
        final head = utf8.decode(
          _peek.sublist(0, bannerPrefix.length),
          allowMalformed: true,
        );
        if (head == bannerPrefix) _sawBannerPrefix = true;
      }
      return;
    }

    _handleAcks(data);
  }

  void _handleAcks(Uint8List data) {
    final ack = _ack;
    if (ack == null) return;
    try {
      final n = ack.feed(data);
      if (n > 0) {
        _acksSeen += n;
        _lastAck = DateTime.now();
        _ackDeadline = null; // Gerät lebt — Frist erfüllt
      }
    } catch (e) {
      _fatal ??= e;
      _socket.destroy();
    }
  }

  void _onSocketError(Object e, StackTrace st) {
    _fatal ??= e;
    if (!_closed.isCompleted) _closed.complete();
  }

  void _onDone() {
    _fatal ??= ProtocolException('Verbindung vom Gerät geschlossen');
    if (!_closed.isCompleted) _closed.complete();
  }

  Future<void> _sendFrames(List<int> data) async {
    final wire = _enc != null
        ? _enc!.encrypt(data)
        : Uint8List.fromList(data);
    _lastSent = DateTime.now();
    _socket.add(wire);
    await _socket.flush(); // sofort raus (Tipp-Latenz)
  }

  /// Schickt ein Lebenszeichen und bewaffnet die Quittungs-Frist — als
  /// einziger Sendeweg, weil nur Herzschläge quittiert werden. Die Frist
  /// wird VOR dem Senden gesetzt: Die Quittung kann bereits während
  /// `await flush()` verarbeitet werden (Event-Loop) und muss die Frist
  /// dann schon löschen können.
  Future<void> _sendHeartbeat() async {
    _ackDeadline ??= DateTime.now().add(ackGrace);
    await _sendFrames(heartbeat);
  }

  /// Verschickt Klartext-Bytes (verschlüsselt sie bei Bedarf).
  Future<void> send(List<int> data) async {
    if (data.isEmpty) return;
    await _sendFrames(data);
    sent += data.length;
  }

  /// Schickt eine Tastenkombination, z. B. "ctrl+shift+p".
  Future<void> sendCombo(String spec) =>
      send(<int>[0x00, ...utf8.encode(spec), 0x0a]);

  /// Schickt bei Untätigkeit ein Lebenszeichen und meldet eine verstummte
  /// oder abgebrochene Gegenstelle (wirft dann eine [ProtocolException]).
  ///
  /// Die Prüfung läuft über die [ackGrace]-Frist ab dem letzten
  /// unquittierten LEBENSZEICHEN (siehe [ackGrace]) — bewusst weder über
  /// das Alter der letzten Quittung (bei anhaltendem Tippen oder nach
  /// einem App Nap beliebig alt, obwohl das Gerät gesund ist) noch über
  /// Nutzlast-Sendungen (werden von der Firmware nie quittiert).
  Future<void> heartbeatIfIdle() async {
    if (_enc == null) {
      _throwIfFatal();
      return;
    }
    if (DateTime.now().difference(_lastSent) >= heartbeatEvery) {
      await _sendHeartbeat(); // Lebenszeichen sind keine Nutzlast
    }
    _throwIfFatal();
    final deadline = _ackDeadline;
    if (deadline != null && DateTime.now().isAfter(deadline)) {
      final last = _lastAck;
      throw ProtocolException(
        last == null
            ? 'Gerät quittiert nicht (${ackGrace.inSeconds}s überschritten)'
            : 'keine Antwort vom Gerät seit '
                '${DateTime.now().difference(last).inSeconds}s',
      );
    }
  }

  void _throwIfFatal() {
    final f = _fatal;
    if (f != null) throw f is Exception ? f : ProtocolException('$f');
  }

  int get acksSeen => _acksSeen;
  DateTime? get lastAck => _lastAck;

  /// Wird erfüllt, wenn die Verbindung endet (Fehler oder Gegenstelle zu).
  Future<void> get closed => _closed.future;

  String get remoteAddr =>
      '${_socket.remoteAddress.address}:${_socket.remotePort}';

  Future<void> close() async {
    try {
      await _socket.close();
    } catch (_) {}
    if (!_closed.isCompleted) _closed.complete();
  }
}
