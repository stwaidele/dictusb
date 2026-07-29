/// Blockmodus + Direktmodus (Phase 2/3): Verbindungsleiste, Textfeld mit
/// Senden bzw. sofortige Tasten-Weiterleitung an den Zielrechner.
/// Snippets/Multi-Gerät folgen in Phase 4.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/config_store.dart';
import '../config/models.dart';
import '../config/settings_bootstrap.dart';
import '../dictusb/keymap.dart';
import '../dictusb/session.dart';
import 'settings_sheet.dart';

enum UiMode { block, direct }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Session _session = Session();
  final ConfigStore _store = ConfigStore();
  final TextEditingController _text = TextEditingController();
  bool _appendEnter = true;

  List<Device> _devices = [];
  int _activeDevice = 0;
  List<Snippet> _snippets = [];

  UiMode _mode = UiMode.block;
  bool _settingsOpen = false;
  DirectSettings _direct =
      DirectSettings.defaultsFor(isMacOS: Platform.isMacOS);

  // Tasten-Echo des Direktmodus: verblasst nach kurzer Zeit (Muster der
  // Go-TUI addEcho/tickEcho).
  static const _echoTtl = Duration(seconds: 4);
  final List<(String, DateTime)> _echoes = [];
  Timer? _echoTimer;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSession);
    _initConfig();
    _store.loadDirect(isMacOS: Platform.isMacOS).then((s) {
      if (mounted) setState(() => _direct = s);
    });
    // Diktat (Paraspeech) fügt sein Ergebnis über die Kombi Ctrl+Alt+V ein,
    // nicht als Tastendruck-Folge. Flutters Shortcuts/TextField erkennen
    // diese Nicht-Standard-Kombi nicht — wir werten sie direkt im globalen
    // Tasten-Strom aus (analog zum Bracketed-Paste-Abgriff der Go-TUI).
    HardwareKeyboard.instance.addHandler(_onGlobalKey);
  }

  // Paraspeech hält die Kombi nicht: beobachtete Event-Folge ist Ctrl-down,
  // Alt-down, Ctrl-up, Alt-up und DANN erst V-down (alle Events echt, nicht
  // synthetisiert). Beim V ist also kein Modifier mehr gedrückt — weder in
  // logicalKeysPressed noch in einem mitgeführten Halte-Status. Deshalb
  // Sequenz-Heuristik: V gilt als Diktat-Kombi, wenn Ctrl- und Alt-Down
  // zuvor gesehen wurden und seither keine andere Taste kam. Physisch
  // gehaltene Kombis erkennt zusätzlich der logicalKeysPressed-Weg.
  // Ankunftszeit im Handler statt e.timeStamp: synthetisch gepostete
  // CGEvents tragen unbrauchbare Zeitstempel.
  //
  // Die Wartezeit zwischen Ctrl/Alt-Antippen und dem V hängt an der
  // DIKTATLÄNGE (Paraspeech tippt die Modifier früh an und schickt das V
  // erst, wenn Aufnahme + Transkription fertig sind): bei einem kurzen
  // Einwurf ~2 s (gemessen 1,9 s / 2,2 s), bei 1–3 Sätzen schon deutlich
  // mehr. Ein knappes Zeitfenster ist deshalb strukturell falsch — es
  // ließ genau die langen Diktate durchfallen (Bug 2026-07-29: statt des
  // Textes kam ein „v" an). Das Fenster ist jetzt nur noch eine
  // Veraltungs-Grenze; die Schärfe liefert die Entwaffnung durch jede
  // andere Taste. Zusätzlich müssen Ctrl und Alt zusammengehören
  // (maschinell angetippt, wenige Millisekunden auseinander) — sonst
  // bewaffnet ein Strg-Shortcut plus ein viel späteres Alt die Erkennung.
  DateTime? _ctrlDownAt;
  DateTime? _altDownAt;
  static const Duration _comboWindow = Duration(minutes: 10);
  static const Duration _comboPairWindow = Duration(seconds: 1);

  /// Diagnose-Log der Tasten-Erkennung, eingeschaltet über
  /// `flutter run -d macos --dart-define=DICTUSB_DIAG=true`. Zeigt je
  /// Event Art, Taste, gehaltene Tasten und den Abstand zum bewaffnenden
  /// Ctrl/Alt — das Muster aus der Erst-Diagnose von 2026-07-22.
  static const bool _diag = bool.fromEnvironment('DICTUSB_DIAG');

  void _logKey(KeyEvent e, DateTime now) {
    if (!_diag) return;
    String age(DateTime? t) =>
        t == null ? '—' : '${now.difference(t).inMilliseconds}ms';
    final held = HardwareKeyboard.instance.logicalKeysPressed
        .map((k) => k.debugName ?? '?')
        .join(',');
    debugPrint(
      '[DIAG] ${e.runtimeType} ${e.logicalKey.debugName} '
      'held={$held} ctrl=${age(_ctrlDownAt)} alt=${age(_altDownAt)} '
      'synth=${e.synthesized}',
    );
  }

  bool _onGlobalKey(KeyEvent e) {
    // Im Einstellungsdialog gelten normale Eingaberegeln: keine
    // Umschaltung, kein Diktat-Abgriff, keine Direktmodus-Weiterleitung
    // (sonst wären dessen Textfelder nicht tippbar).
    if (_settingsOpen) return false;

    final k = e.logicalKey;

    // 1. Umschalt-Taste ist reserviert und geht nie ans Gerät —
    //    auch ihr Repeat/Up nicht.
    if (k == fKeyByName[_direct.toggleKey]) {
      if (e is KeyDownEvent) _toggleMode();
      return true;
    }

    final isCtrl = k == LogicalKeyboardKey.controlLeft ||
        k == LogicalKeyboardKey.controlRight;
    final isAlt =
        k == LogicalKeyboardKey.altLeft || k == LogicalKeyboardKey.altRight;
    final isV = k == LogicalKeyboardKey.keyV ||
        e.physicalKey == PhysicalKeyboardKey.keyV;

    if (e is KeyUpEvent) {
      _logKey(e, DateTime.now());
      if (_mode == UiMode.direct) {
        _completeModTap(k);
        return true; // im Direktmodus sickert nichts ins Framework
      }
      return false;
    }
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return false;

    // 2. Diktat-Heuristik (Paraspeech, Ctrl+Alt+V) — nur echte Downs.
    if (e is KeyDownEvent) {
      final now = DateTime.now();
      _logKey(e, now);
      if (isCtrl) _ctrlDownAt = now;
      if (isAlt) _altDownAt = now;
      if (!isCtrl && !isAlt && !isV) {
        // Andere Taste dazwischen → das war keine Diktat-Kombi.
        _ctrlDownAt = null;
        _altDownAt = null;
      }
      if (isV) {
        final pressed = HardwareKeyboard.instance.logicalKeysPressed;
        final held = (pressed.contains(LogicalKeyboardKey.controlLeft) ||
                pressed.contains(LogicalKeyboardKey.controlRight)) &&
            (pressed.contains(LogicalKeyboardKey.altLeft) ||
                pressed.contains(LogicalKeyboardKey.altRight));
        final ctrlAt = _ctrlDownAt;
        final altAt = _altDownAt;
        // Ctrl und Alt gehören zusammen (dicht beieinander angetippt) und
        // die Bewaffnung ist nicht veraltet; wie lange das Diktat gedauert
        // hat, spielt bewusst keine Rolle.
        final armed = ctrlAt != null &&
            altAt != null &&
            ctrlAt.difference(altAt).abs() < _comboPairWindow &&
            now.difference(ctrlAt) < _comboWindow &&
            now.difference(altAt) < _comboWindow;
        if (held || armed) {
          _ctrlDownAt = null;
          _altDownAt = null;
          _pasteDictation();
          return true; // Kombi verschlucken, damit kein 'v' ins Feld rutscht
        }
      }
    }

    // 3. Direktmodus: Down + Repeat mappen und senden; immer schlucken,
    //    damit lokal nichts auslöst (Menü, Textfelder, Shortcuts).
    if (_mode == UiMode.direct) {
      if (!_session.isConnected) return true;
      if (e is KeyDownEvent) _trackModTap(k);
      final a = mapKey(KeyInput.fromEvent(e), _direct);
      if (a != null) {
        switch (a) {
          case BytesAction b:
            unawaited(_session.sendBytes(b.bytes));
          case ComboAction c:
            unawaited(_session.sendCombo(c.spec));
        }
        _addEcho(a.echo);
      }
      return true;
    }

    // 4. Snippet-Hotkeys, nur im Blockmodus: Cmd+1..9 (macOS) bzw.
    //    Strg+1..9 (Windows/Linux). Bewusst ohne Alt — sonst finge das
    //    unter Windows/Linux AltGr-Zeichen wie AltGr+7={ ab.
    if (e is KeyDownEvent) {
      final hk = HardwareKeyboard.instance;
      final mod = Platform.isMacOS ? hk.isMetaPressed : hk.isControlPressed;
      if (mod && !hk.isAltPressed && !hk.isShiftPressed) {
        final idx = _digitKeys.indexOf(k);
        if (idx >= 0 && idx < _snippets.length) {
          unawaited(_triggerSnippet(idx));
          return true;
        }
      }
    }

    return false; // Blockmodus: normal weiterverarbeiten
  }

  static const List<LogicalKeyboardKey> _digitKeys = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  // Reiner Modifier-Tipp im Direktmodus: ein Modifier, der allein gedrückt
  // und wieder losgelassen wird (keine andere Taste dazwischen), geht beim
  // KeyUp als eigene Kombi ans Gerät (Firmware ≥ 0.18) — z. B. Shift, um
  // den Bildschirmschoner des Ziels zu beenden, ohne ein Zeichen zu senden.
  LogicalKeyboardKey? _modTapCandidate;

  void _trackModTap(LogicalKeyboardKey k) {
    if (!isModifierKey(k)) {
      _modTapCandidate = null; // normale Taste → das war ein Kombi-Griff
      return;
    }
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    // Nur bewaffnen, wenn dieser Modifier allein gedrückt ist; ein
    // zweiter Modifier entwaffnet (vermutlich Griff zu einer Kombi).
    _modTapCandidate =
        (_modTapCandidate == null && pressed.length == 1) ? k : null;
  }

  void _completeModTap(LogicalKeyboardKey k) {
    final cand = _modTapCandidate;
    if (cand == null || k != cand) return;
    _modTapCandidate = null;
    final spec = modifierTapSpec(cand, _direct);
    if (spec == null || !_session.isConnected) return;
    unawaited(_session.sendCombo(spec));
    _addEcho('[$spec]');
  }

  void _toggleMode() {
    setState(() {
      _mode = _mode == UiMode.block ? UiMode.direct : UiMode.block;
    });
    if (_mode == UiMode.direct) {
      // Kein fokussiertes Textfeld im Direktmodus — zweite
      // Verteidigungslinie, falls ein Event doch durchsickert.
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  void _addEcho(String text) {
    final now = DateTime.now();
    setState(() {
      _echoes.removeWhere((x) => now.difference(x.$2) > _echoTtl);
      _echoes.add((text, now));
    });
    _echoTimer ??= Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final cutoff = DateTime.now();
      setState(() {
        _echoes.removeWhere((x) => cutoff.difference(x.$2) > _echoTtl);
      });
      if (_echoes.isEmpty) {
        _echoTimer?.cancel();
        _echoTimer = null;
      }
    });
  }

  /// Lädt Geräte, aktives Gerät und Snippets; ohne gespeicherte Geräte
  /// (und ohne Phase-2-Altbestand, den loadDevices migriert) dient die
  /// settings.toml-Vorlage als erster Listeneintrag.
  Future<void> _initConfig() async {
    var devices = await _store.loadDevices();
    if (devices.isEmpty) {
      final b = loadBootstrap();
      if (b.host.isNotEmpty || b.token.isNotEmpty) {
        devices = [
          Device(name: 'Gerät 1', host: b.host, port: b.port, token: b.token),
        ];
      }
    }
    final active = await _store.loadActiveDevice();
    final snippets = await _store.loadSnippets();
    if (!mounted) return;
    setState(() {
      _devices = devices;
      _activeDevice = devices.isEmpty ? 0 : active.clamp(0, devices.length - 1);
      _snippets = snippets;
    });
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _echoTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onGlobalKey);
    _session.removeListener(_onSession);
    _session.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_devices.isEmpty) return;
    final d = _devices[_activeDevice];
    // Auswahl persistieren, unabhängig vom Verbindungsausgang.
    await _store.saveDevices(_devices);
    await _store.saveActiveDevice(_activeDevice);
    await _session.connect(host: d.host.trim(), port: d.port, token: d.token);
  }

  /// Gerätewechsel über das Dropdown; bei bestehender Verbindung wird
  /// sauber getrennt und mit dem neuen Gerät verbunden.
  Future<void> _selectDevice(int index) async {
    if (index == _activeDevice) return;
    final wasConnected = _session.isConnected;
    if (wasConnected) await _session.disconnect();
    setState(() => _activeDevice = index);
    await _store.saveActiveDevice(index);
    if (wasConnected) await _connect();
  }

  Future<void> _send() async {
    final text = _appendEnter ? '${_text.text}\n' : _text.text;
    await _session.sendText(text);
    if (_session.isConnected) _text.clear();
  }

  /// Verarbeitet Diktat (Paraspeech liefert per Zwischenablage): im
  /// Blockmodus an der Cursorposition ins Textfeld, im Direktmodus direkt
  /// ans Gerät (analog zum Bracketed-Paste der Go-TUI).
  Future<void> _pasteDictation() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isEmpty) return;
    if (_mode == UiMode.direct) {
      if (_session.isConnected) {
        await _session.sendText(text);
        _addEcho('[Diktat: ${text.characters.length} Zeichen]');
      } else {
        _addEcho('[Diktat verworfen: nicht verbunden]');
      }
      return;
    }
    _insertIntoText(text);
  }

  /// Fügt Text an der Cursorposition ins Blockmodus-Textfeld ein.
  void _insertIntoText(String text) {
    final sel = _text.selection;
    final start = sel.isValid ? sel.start : _text.text.length;
    final end = sel.isValid ? sel.end : _text.text.length;
    final newText = _text.text.replaceRange(start, end, text);
    _text.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  /// Löst einen Textbaustein aus: Blockmodus → einfügen (nachbearbeitbar),
  /// Direktmodus → sofort ans Gerät (wie Diktat).
  Future<void> _triggerSnippet(int index) async {
    if (index < 0 || index >= _snippets.length) return;
    final s = _snippets[index];
    if (s.text.isEmpty) return;
    if (_mode == UiMode.direct) {
      if (_session.isConnected) {
        await _session.sendText(s.text);
        _addEcho('[${s.label}]');
      } else {
        _addEcho('[Baustein verworfen: nicht verbunden]');
      }
      return;
    }
    _insertIntoText(s.text);
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    return Scaffold(
      appBar: AppBar(
        title: const Text('dictUSB'),
        actions: [
          Center(
            child: Tooltip(
              message: 'Umschalten: ${_direct.toggleKey.toUpperCase()}',
              child: SegmentedButton<UiMode>(
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
                segments: const [
                  ButtonSegment(
                    value: UiMode.block,
                    label: Text('Block'),
                    icon: Icon(Icons.notes),
                  ),
                  ButtonSegment(
                    value: UiMode.direct,
                    label: Text('Direkt'),
                    icon: Icon(Icons.keyboard),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (sel) {
                  if (sel.first != _mode) _toggleMode();
                },
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Einstellungen',
            onPressed: _openSettings,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _StatusChip(state: s.state),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _connectionBar(s),
            const SizedBox(height: 12),
            Expanded(
              child: _mode == UiMode.block
                  ? TextField(
                      controller: _text,
                      // Bewusst auch ohne Verbindung nutzbar: Text lässt sich
                      // vorab tippen/diktieren, gesendet wird erst nach dem
                      // Verbinden.
                      enabled: true,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Text hier eingeben und „Senden" — kommt als '
                            'Tastatureingabe am Zielrechner an.',
                      ),
                    )
                  : _directPanel(context, s),
            ),
            if (_snippets.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _snippets.length; i++)
                    OutlinedButton(
                      onPressed: () => _triggerSnippet(i),
                      child: Text(
                        _mode == UiMode.block
                            ? '${_snippetHotkeyLabel(i)} '
                                '${_snippets[i].label}'
                            : _snippets[i].label,
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (_mode == UiMode.block) ...[
                  Switch(
                    value: _appendEnter,
                    onChanged: (v) => setState(() => _appendEnter = v),
                  ),
                  const Text('Enter am Ende'),
                ],
                const Spacer(),
                Text(
                  s.isConnected
                      ? '${s.sentBytes} B gesendet · ${s.acks} Quittung(en)'
                      : '',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_mode == UiMode.block) ...[
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: s.isConnected ? _send : null,
                    icon: const Icon(Icons.send),
                    label: const Text('Senden'),
                  ),
                ],
              ],
            ),
            if (s.error != null) ...[
              const SizedBox(height: 8),
              _errorBar(context, s.error!),
            ],
          ],
        ),
      ),
    );
  }

  String _snippetHotkeyLabel(int i) =>
      Platform.isMacOS ? '⌘${i + 1}' : 'Strg+${i + 1}';

  Widget _directPanel(BuildContext context, Session s) {
    final scheme = Theme.of(context).colorScheme;
    final echo = _echoes.map((e) => e.$1).join(' ');
    final hint = s.isConnected
        ? '${_direct.toggleKey.toUpperCase()} zurück zum Blockmodus · '
            'Diktat (Ctrl+Alt+V) wird direkt gesendet'
        : 'Nicht verbunden — Tasten werden verworfen.';
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(24),
      // Scroll-Fallback: bei kleiner Fensterhöhe (Snippet-Leiste,
      // Fehlerbalken) darf die Spalte nicht überlaufen.
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.keyboard, size: 48, color: scheme.primary),
              const SizedBox(height: 12),
              const Text(
                'Direktmodus — Tastendrücke gehen sofort an den Zielrechner',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                echo.isEmpty ? ' ' : echo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 16),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    // Für die Dauer des Dialogs in den Blockmodus wechseln (sichtbar) und
    // die Sonderbehandlung im Tasten-Handler aussetzen — sonst verschluckt
    // der Direktmodus die Eingaben in den Dialog-Feldern.
    final prev = _mode;
    setState(() {
      _settingsOpen = true;
      _mode = UiMode.block;
    });
    try {
      final r = await showSettingsSheet(
        context,
        direct: _direct,
        devices: _devices,
        snippets: _snippets,
        isMacOS: Platform.isMacOS,
      );
      if (r != null) {
        await _store.saveDirect(r.direct);
        await _store.saveDevices(r.devices);
        await _store.saveSnippets(r.snippets);
        final active = r.devices.isEmpty
            ? 0
            : _activeDevice.clamp(0, r.devices.length - 1);
        await _store.saveActiveDevice(active);
        if (mounted) {
          setState(() {
            _direct = r.direct;
            _devices = List.of(r.devices);
            _snippets = List.of(r.snippets);
            _activeDevice = active;
          });
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _settingsOpen = false;
          _mode = prev;
        });
        if (prev == UiMode.direct) {
          FocusManager.instance.primaryFocus?.unfocus();
        }
      }
    }
  }

  Widget _connectionBar(Session s) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Gerät',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            child: _devices.isEmpty
                ? const Text('Kein Gerät angelegt — Einstellungen → Geräte')
                : DropdownButton<int>(
                    value: _activeDevice,
                    isDense: true,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (var i = 0; i < _devices.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(
                            '${_devices[i].name} — '
                            '${_devices[i].host}:${_devices[i].port}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: s.isBusy
                        ? null
                        : (i) => i == null ? null : _selectDevice(i),
                  ),
          ),
        ),
        const SizedBox(width: 8),
        if (s.isConnected)
          OutlinedButton.icon(
            onPressed: _session.disconnect,
            icon: const Icon(Icons.link_off),
            label: const Text('Trennen'),
          )
        else
          FilledButton.icon(
            onPressed: (s.isBusy || _devices.isEmpty) ? null : _connect,
            icon: s.isBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.link),
            label: const Text('Verbinden'),
          ),
      ],
    );
  }

  Widget _errorBar(BuildContext context, String msg) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.state});

  final ConnState state;

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = switch (state) {
      ConnState.disconnected => ('getrennt', Colors.grey),
      ConnState.connecting => ('verbinde …', Colors.orange),
      ConnState.connected => ('verbunden', Colors.green),
      ConnState.error => ('Fehler', Colors.red),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 12, color: color),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}
