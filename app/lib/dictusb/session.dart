/// Bindet die async [Conn] als [ChangeNotifier] an die UI: Verbindung
/// auf-/abbauen, Text senden, Herzschlag-Timer, Statuswechsel.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'conn.dart';
import 'protocol.dart';

enum ConnState { disconnected, connecting, connected, error }

class Session extends ChangeNotifier {
  Conn? _conn;
  Timer? _hbTimer;

  ConnState state = ConnState.disconnected;
  String? error;
  String? remoteAddr;
  int sentBytes = 0;
  int acks = 0;

  bool get isConnected => state == ConnState.connected;
  bool get isBusy => state == ConnState.connecting;

  Future<void> connect({
    required String host,
    required int port,
    required String token,
  }) async {
    if (state == ConnState.connecting || state == ConnState.connected) return;
    state = ConnState.connecting;
    error = null;
    notifyListeners();
    try {
      final conn = await Conn.dial(host, port, token, const Duration(seconds: 5));
      _conn = conn;
      remoteAddr = conn.remoteAddr;
      sentBytes = 0;
      acks = conn.acksSeen;
      state = ConnState.connected;
      notifyListeners();
      // Verbindungsende (Gegenstelle schließt) beobachten.
      unawaited(
        conn.closed.then((_) {
          if (identical(_conn, conn) && state == ConnState.connected) {
            _fail('Verbindung vom Gerät geschlossen');
          }
        }),
      );
      _hbTimer = Timer.periodic(const Duration(seconds: 5), (_) => _tick());
    } catch (e) {
      _conn = null;
      state = ConnState.error;
      error = _clean(e);
      notifyListeners();
    }
  }

  Future<void> _tick() async {
    final conn = _conn;
    if (conn == null) return;
    try {
      await conn.heartbeatIfIdle();
      acks = conn.acksSeen;
      notifyListeners();
    } catch (e) {
      _fail(_clean(e));
    }
  }

  Future<void> sendText(String text) async {
    final conn = _conn;
    if (conn == null || state != ConnState.connected || text.isEmpty) return;
    try {
      await conn.send(utf8.encode(text));
      sentBytes = conn.sent;
      notifyListeners();
    } catch (e) {
      _fail(_clean(e));
    }
  }

  /// Sendet rohe Nutzlast-Bytes (Steuerbytes/Einzelzeichen des Direktmodus).
  Future<void> sendBytes(List<int> bytes) async {
    final conn = _conn;
    if (conn == null || state != ConnState.connected || bytes.isEmpty) return;
    try {
      await conn.send(bytes);
      sentBytes = conn.sent;
      notifyListeners();
    } catch (e) {
      _fail(_clean(e));
    }
  }

  /// Sendet eine Tastenkombination als Kombi-Sequenz (PROTOCOL.md §7).
  Future<void> sendCombo(String spec) async {
    final conn = _conn;
    if (conn == null || state != ConnState.connected || spec.isEmpty) return;
    try {
      await conn.sendCombo(spec);
      sentBytes = conn.sent;
      notifyListeners();
    } catch (e) {
      _fail(_clean(e));
    }
  }

  Future<void> disconnect() async {
    _hbTimer?.cancel();
    _hbTimer = null;
    final conn = _conn;
    _conn = null;
    await conn?.close();
    state = ConnState.disconnected;
    error = null;
    notifyListeners();
  }

  void _fail(String msg) {
    _hbTimer?.cancel();
    _hbTimer = null;
    final conn = _conn;
    _conn = null;
    unawaited(conn?.close());
    state = ConnState.error;
    error = msg;
    notifyListeners();
  }

  String _clean(Object e) => e is ProtocolException ? e.message : '$e';

  @override
  void dispose() {
    _hbTimer?.cancel();
    _conn?.close();
    super.dispose();
  }
}
