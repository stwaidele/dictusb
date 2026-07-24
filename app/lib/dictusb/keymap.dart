/// Direktmodus-Mapping: übersetzt Tastenereignisse in Protokoll-Nutzlast
/// (PROTOCOL.md §7) — Text-/Steuerbytes oder Kombi-Specs (`0x00<spec>\n`).
///
/// Bewusst reines Dart ohne UI-Abhängigkeit: das Mapping ist ohne
/// Widget-Baum testbar, und ein späteres Tastenmodell (Key-up/down-
/// Weiterleitung) müsste nur dieses Modul ersetzen.
library;

import 'dart:convert';

import 'package:flutter/services.dart';

/// Ziel-Modifier laut Protokoll. Shift wird nie umgemappt.
enum TargetMod { ctrl, alt, win }

/// Einstellungen des Direktmodus (persistiert im [ConfigStore]).
class DirectSettings {
  /// Wohin physisches Ctrl (macOS: control ⌃) am Ziel wirkt.
  final TargetMod ctrlTo;

  /// Wohin physisches Alt (macOS: option ⌥) am Ziel wirkt.
  final TargetMod altTo;

  /// Wohin physisches Win (macOS: command ⌘) am Ziel wirkt.
  final TargetMod metaTo;

  /// Mit Alt komponierte Zeichen, die als Text gesendet werden statt als
  /// Kombi (z. B. Alt+L=@ auf deutschem Mac).
  final String altChars;

  /// Umschalt-Taste Block/Direkt: 'f1'..'f12'.
  final String toggleKey;

  const DirectSettings({
    required this.ctrlTo,
    required this.altTo,
    required this.metaTo,
    required this.altChars,
    required this.toggleKey,
  });

  static const defaultAltChars = r'@[]{}|~\€';
  static const defaultToggleKey = 'f1';

  /// macOS erbt den bewährten Tausch des Python-Tasten-Modus
  /// (Cmd→Strg, Mac-Strg→Win); Windows/Linux senden unverändert.
  factory DirectSettings.defaultsFor({required bool isMacOS}) => isMacOS
      ? const DirectSettings(
          ctrlTo: TargetMod.win,
          altTo: TargetMod.alt,
          metaTo: TargetMod.ctrl,
          altChars: defaultAltChars,
          toggleKey: defaultToggleKey,
        )
      : const DirectSettings(
          ctrlTo: TargetMod.ctrl,
          altTo: TargetMod.alt,
          metaTo: TargetMod.win,
          altChars: defaultAltChars,
          toggleKey: defaultToggleKey,
        );

  DirectSettings copyWith({
    TargetMod? ctrlTo,
    TargetMod? altTo,
    TargetMod? metaTo,
    String? altChars,
    String? toggleKey,
  }) =>
      DirectSettings(
        ctrlTo: ctrlTo ?? this.ctrlTo,
        altTo: altTo ?? this.altTo,
        metaTo: metaTo ?? this.metaTo,
        altChars: altChars ?? this.altChars,
        toggleKey: toggleKey ?? this.toggleKey,
      );
}

/// Ergebnis von [mapKey]: entweder rohe Bytes oder eine Kombi-Spec,
/// jeweils mit dem Text fürs lokale Echo.
sealed class KeyAction {
  final String echo;
  const KeyAction(this.echo);
}

final class BytesAction extends KeyAction {
  final List<int> bytes;
  const BytesAction(this.bytes, String echo) : super(echo);
}

final class ComboAction extends KeyAction {
  final String spec;
  ComboAction(this.spec) : super('[$spec]');
}

/// Tastenereignis, entkoppelt von [KeyEvent] — in Tests ohne Widget-Baum
/// konstruierbar. Die Modifier-Flags sind der physische Ist-Zustand.
class KeyInput {
  final LogicalKeyboardKey logical;
  final PhysicalKeyboardKey physical;
  final String? character;
  final bool ctrl, alt, shift, meta;

  const KeyInput({
    required this.logical,
    required this.physical,
    this.character,
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
    this.meta = false,
  });

  factory KeyInput.fromEvent(KeyEvent e) {
    final hk = HardwareKeyboard.instance;
    return KeyInput(
      logical: e.logicalKey,
      physical: e.physicalKey,
      character: e.character,
      ctrl: hk.isControlPressed,
      alt: hk.isAltPressed,
      shift: hk.isShiftPressed,
      meta: hk.isMetaPressed,
    );
  }
}

/// Die wählbaren Umschalt-Tasten (Einstellungswert → logische Taste).
final Map<String, LogicalKeyboardKey> fKeyByName = {
  for (var i = 0; i < 12; i++) 'f${i + 1}': _fKeys[i],
};

const List<LogicalKeyboardKey> _fKeys = [
  LogicalKeyboardKey.f1,
  LogicalKeyboardKey.f2,
  LogicalKeyboardKey.f3,
  LogicalKeyboardKey.f4,
  LogicalKeyboardKey.f5,
  LogicalKeyboardKey.f6,
  LogicalKeyboardKey.f7,
  LogicalKeyboardKey.f8,
  LogicalKeyboardKey.f9,
  LogicalKeyboardKey.f10,
  LogicalKeyboardKey.f11,
  LogicalKeyboardKey.f12,
];

final Set<LogicalKeyboardKey> _modifierKeys = {
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.altGraph,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.capsLock,
  LogicalKeyboardKey.numLock,
  LogicalKeyboardKey.scrollLock,
  LogicalKeyboardKey.fn,
  LogicalKeyboardKey.fnLock,
};

/// Benannte Tasten mit exakt den Namen, die die Firmware kennt
/// (NAMED_KEYS in firmware/code.py).
final Map<LogicalKeyboardKey, String> _namedKeys = {
  LogicalKeyboardKey.enter: 'enter',
  LogicalKeyboardKey.numpadEnter: 'enter',
  LogicalKeyboardKey.tab: 'tab',
  LogicalKeyboardKey.escape: 'esc',
  LogicalKeyboardKey.backspace: 'backspace',
  LogicalKeyboardKey.delete: 'delete',
  LogicalKeyboardKey.insert: 'insert',
  LogicalKeyboardKey.space: 'space',
  LogicalKeyboardKey.arrowUp: 'up',
  LogicalKeyboardKey.arrowDown: 'down',
  LogicalKeyboardKey.arrowLeft: 'left',
  LogicalKeyboardKey.arrowRight: 'right',
  LogicalKeyboardKey.home: 'home',
  LogicalKeyboardKey.end: 'end',
  LogicalKeyboardKey.pageUp: 'pageup',
  LogicalKeyboardKey.pageDown: 'pagedown',
  for (var i = 0; i < 12; i++) _fKeys[i]: 'f${i + 1}',
};

/// Steuerbytes für benannte Tasten ohne Modifier (wie die Go-TUI).
const Map<String, (List<int>, String)> _plainBytes = {
  'enter': ([0x0d], '⏎'),
  'tab': ([0x09], '→'),
  'backspace': ([0x7f], '⌫'),
  'esc': ([0x1b], '⎋'),
  'space': ([0x20], ' '),
};

/// True für reine Modifier-Tasten (erzeugen selbst keine Nutzlast).
bool isModifierKey(LogicalKeyboardKey k) => _modifierKeys.contains(k);

/// Spec für einen reinen Modifier-Tipp (Down und Up ohne weitere Taste
/// dazwischen), nach Modifier-Mapping — z. B. Shift antippen, um den
/// Bildschirmschoner des Ziels zu beenden, ohne ein Zeichen zu senden.
/// Braucht Firmware ≥ 0.18 (Modifier-Name als Kombi-Taste). `null` für
/// Nicht-Modifier und Sperrtasten (CapsLock & Co. sollen nicht
/// durchschlagen).
String? modifierTapSpec(LogicalKeyboardKey k, DirectSettings s) {
  if (k == LogicalKeyboardKey.shiftLeft ||
      k == LogicalKeyboardKey.shiftRight) {
    return 'shift';
  }
  if (k == LogicalKeyboardKey.controlLeft ||
      k == LogicalKeyboardKey.controlRight) {
    return s.ctrlTo.name;
  }
  if (k == LogicalKeyboardKey.altLeft ||
      k == LogicalKeyboardKey.altRight ||
      k == LogicalKeyboardKey.altGraph) {
    return s.altTo.name;
  }
  if (k == LogicalKeyboardKey.metaLeft || k == LogicalKeyboardKey.metaRight) {
    return s.metaTo.name;
  }
  return null;
}

/// Übersetzt ein Tastenereignis in Nutzlast; `null` = nichts senden
/// (reiner Modifier, Dead-Key-Auftakt, nicht abbildbare Taste).
KeyAction? mapKey(KeyInput e, DirectSettings s) {
  if (_modifierKeys.contains(e.logical)) return null;

  // Alt-Zeichenliste vor allem anderen: komponierte Zeichen wie Alt+L=@
  // als Text durchreichen. Deckt auch Windows-AltGr ab, das als
  // Ctrl+Alt gemeldet wird (AltGr+Q=@ soll Text sein, keine Kombi).
  final ch = e.character;
  if (e.alt &&
      ch != null &&
      ch.runes.length == 1 &&
      s.altChars.runes.contains(ch.runes.first)) {
    return BytesAction(utf8.encode(ch), ch);
  }

  // Physische Modifier auf die Ziel-Modifier abbilden (Set: wenn zwei
  // Quellen auf denselben Ziel-Modifier zeigen, kollabieren sie).
  final eff = <TargetMod>{
    if (e.ctrl) s.ctrlTo,
    if (e.alt) s.altTo,
    if (e.meta) s.metaTo,
  };

  // Strg+A..Z als klassisches Steuerbyte 0x01..0x1a. Über die logische
  // Taste, nicht das Zeichen — das ist mit gehaltenem Ctrl unbrauchbar.
  final letter = e.logical.keyId - LogicalKeyboardKey.keyA.keyId;
  if (eff.length == 1 &&
      eff.first == TargetMod.ctrl &&
      !e.shift &&
      letter >= 0 &&
      letter <= 25) {
    return BytesAction(
      [letter + 1],
      '[ctrl+${String.fromCharCode(0x61 + letter)}]',
    );
  }

  final name = _namedKeys[e.logical];
  if (name != null) {
    if (eff.isEmpty && !e.shift) {
      final plain = _plainBytes[name];
      if (plain != null) return BytesAction(plain.$1, plain.$2);
    }
    return ComboAction(_spec(eff, e.shift, name));
  }

  if (eff.isNotEmpty) {
    // Kombi mit Zeichentaste: Basiszeichen aus dem Tastenlabel; die
    // Firmware tippt es übers Ziel-Layout. Kein ASCII-Label → verwerfen.
    final base = _baseChar(e.logical);
    if (base == null) return null;
    return ComboAction(_spec(eff, e.shift, base));
  }

  if (ch != null && ch.isNotEmpty) {
    // Klartext: Shift/Umlaute/AltGr-Zeichen stecken bereits im Zeichen.
    return BytesAction(utf8.encode(ch), ch);
  }

  return null; // z. B. Dead-Key-Auftakt (character == null)
}

String _spec(Set<TargetMod> eff, bool shift, String key) => [
      if (eff.contains(TargetMod.ctrl)) 'ctrl',
      if (eff.contains(TargetMod.alt)) 'alt',
      if (eff.contains(TargetMod.win)) 'win',
      if (shift) 'shift',
      key,
    ].join('+');

String? _baseChar(LogicalKeyboardKey k) {
  final label = k.keyLabel;
  if (label.length != 1) return null;
  final c = label.codeUnitAt(0);
  if (c < 0x21 || c > 0x7e) return null;
  return label.toLowerCase();
}
