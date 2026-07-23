/// Tabellengetriebene Tests des Direktmodus-Mappings (keymap.dart).
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dictusb_app/dictusb/keymap.dart';

KeyInput input(
  LogicalKeyboardKey logical, {
  PhysicalKeyboardKey physical = PhysicalKeyboardKey.keyA,
  String? char,
  bool ctrl = false,
  bool alt = false,
  bool shift = false,
  bool meta = false,
}) =>
    KeyInput(
      logical: logical,
      physical: physical,
      character: char,
      ctrl: ctrl,
      alt: alt,
      shift: shift,
      meta: meta,
    );

void main() {
  final identity = DirectSettings.defaultsFor(isMacOS: false);
  final macDefault = DirectSettings.defaultsFor(isMacOS: true);

  test('Defaults: Windows/Linux = Identität, macOS = Python-Tausch', () {
    expect(identity.ctrlTo, TargetMod.ctrl);
    expect(identity.altTo, TargetMod.alt);
    expect(identity.metaTo, TargetMod.win);
    expect(macDefault.ctrlTo, TargetMod.win);
    expect(macDefault.altTo, TargetMod.alt);
    expect(macDefault.metaTo, TargetMod.ctrl);
    expect(identity.altChars, r'@[]{}|~\€');
    expect(identity.toggleKey, 'f1');
  });

  List<int> bytesOf(KeyAction? a) => (a as BytesAction).bytes;
  String specOf(KeyAction? a) => (a as ComboAction).spec;

  test('Klartext: a → 0x61, Shift steckt im Zeichen, Umlaut mehrbytig', () {
    expect(bytesOf(mapKey(input(LogicalKeyboardKey.keyA, char: 'a'), identity)),
        [0x61]);
    expect(
        bytesOf(mapKey(
            input(LogicalKeyboardKey.keyA, char: 'A', shift: true), identity)),
        [0x41]);
    expect(
        bytesOf(
            mapKey(input(LogicalKeyboardKey.keyU, char: 'ü'), identity)),
        [0xc3, 0xbc]);
  });

  test('Ctrl+Buchstabe → Steuerbyte; Cmd wirkt auf dem Mac als Ctrl', () {
    expect(
        bytesOf(mapKey(input(LogicalKeyboardKey.keyC, ctrl: true), identity)),
        [0x03]);
    expect(
        bytesOf(mapKey(input(LogicalKeyboardKey.keyC, meta: true), macDefault)),
        [0x03]);
  });

  test('Ctrl+Shift+Buchstabe wird Kombi, kein Steuerbyte', () {
    expect(
        specOf(mapKey(
            input(LogicalKeyboardKey.keyC, ctrl: true, shift: true),
            identity)),
        'ctrl+shift+c');
  });

  test('Modifier-Mapping: Mac-control wirkt als Win', () {
    expect(
        specOf(mapKey(
            input(LogicalKeyboardKey.arrowLeft, ctrl: true), macDefault)),
        'win+left');
  });

  test('Mehrere Modifier: Cmd+Alt+x (macOS) → ctrl+alt+x', () {
    expect(
        specOf(mapKey(input(LogicalKeyboardKey.keyX, meta: true, alt: true),
            macDefault)),
        'ctrl+alt+x');
  });

  test('Alt-Zeichenliste: Treffer als Text, sonst Kombi', () {
    // Alt+L=@ (deutsches Mac-Layout) steht in der Default-Liste.
    expect(
        bytesOf(mapKey(
            input(LogicalKeyboardKey.keyL, char: '@', alt: true), macDefault)),
        [0x40]);
    // Alt+8={ ebenfalls.
    expect(
        bytesOf(mapKey(
            input(LogicalKeyboardKey.digit8, char: '{', alt: true),
            macDefault)),
        [0x7b]);
    // ƒ (Alt+F) steht nicht in der Liste → Kombi.
    expect(
        specOf(mapKey(
            input(LogicalKeyboardKey.keyF, char: 'ƒ', alt: true), identity)),
        'alt+f');
    // Leere Liste → auch @ wird zur Kombi.
    final noPass = identity.copyWith(altChars: '');
    expect(
        specOf(mapKey(
            input(LogicalKeyboardKey.keyL, char: '@', alt: true), noPass)),
        'alt+l');
  });

  test('Windows-AltGr (meldet Ctrl+Alt) reicht Listenzeichen durch', () {
    expect(
        bytesOf(mapKey(
            input(LogicalKeyboardKey.keyQ, char: '@', ctrl: true, alt: true),
            identity)),
        [0x40]);
  });

  test('Steuerbytes ohne Modifier: Enter/Tab/Backspace/Esc/Space', () {
    expect(bytesOf(mapKey(input(LogicalKeyboardKey.enter), identity)), [0x0d]);
    expect(bytesOf(mapKey(input(LogicalKeyboardKey.tab), identity)), [0x09]);
    expect(
        bytesOf(mapKey(input(LogicalKeyboardKey.backspace), identity)),
        [0x7f]);
    expect(bytesOf(mapKey(input(LogicalKeyboardKey.escape), identity)), [0x1b]);
    expect(
        bytesOf(mapKey(input(LogicalKeyboardKey.space, char: ' '), identity)),
        [0x20]);
  });

  test('Benannte Tasten: modifierlos und mit Kombination', () {
    expect(specOf(mapKey(input(LogicalKeyboardKey.arrowUp), identity)), 'up');
    expect(specOf(mapKey(input(LogicalKeyboardKey.f5), identity)), 'f5');
    expect(
        specOf(mapKey(input(LogicalKeyboardKey.delete), identity)), 'delete');
    expect(
        specOf(mapKey(input(LogicalKeyboardKey.home, ctrl: true, shift: true),
            identity)),
        'ctrl+shift+home');
    expect(
        specOf(
            mapKey(input(LogicalKeyboardKey.arrowUp, shift: true), identity)),
        'shift+up');
  });

  test('Reiner Modifier-Druck → null', () {
    expect(mapKey(input(LogicalKeyboardKey.controlLeft, ctrl: true), identity),
        isNull);
    expect(mapKey(input(LogicalKeyboardKey.metaLeft, meta: true), macDefault),
        isNull);
  });

  test('Dead-Key-Auftakt (character null) → null, Folge-Event tippt', () {
    // Auftakt: ^ auf DE-Mac liefert kein Zeichen.
    expect(mapKey(input(LogicalKeyboardKey.quoteSingle), identity), isNull);
    // Folge-Event trägt das komponierte Zeichen.
    expect(
        bytesOf(mapKey(input(LogicalKeyboardKey.keyO, char: 'ô'), identity)),
        [0xc3, 0xb4]);
  });

  test('Kombi mit nicht abbildbarer Taste → null (Firmware würde verwerfen)',
      () {
    // F13 kennt weder die Namens-Tabelle noch hat sie ein ASCII-Label.
    expect(mapKey(input(LogicalKeyboardKey.f13, ctrl: true), identity), isNull);
  });

  test('Echo-Texte sind gesetzt', () {
    expect(mapKey(input(LogicalKeyboardKey.keyA, char: 'a'), identity)!.echo,
        'a');
    expect(mapKey(input(LogicalKeyboardKey.enter), identity)!.echo, '⏎');
    expect(
        mapKey(input(LogicalKeyboardKey.keyC, ctrl: true), identity)!.echo,
        '[ctrl+c]');
    expect(mapKey(input(LogicalKeyboardKey.arrowUp), identity)!.echo, '[up]');
  });

  test('modifierTapSpec: Mapping greift, Sperrtasten bleiben stumm', () {
    expect(modifierTapSpec(LogicalKeyboardKey.shiftLeft, identity), 'shift');
    expect(modifierTapSpec(LogicalKeyboardKey.shiftRight, macDefault),
        'shift');
    expect(modifierTapSpec(LogicalKeyboardKey.controlLeft, identity), 'ctrl');
    // macOS-Default: control wirkt als Win, command als Ctrl.
    expect(modifierTapSpec(LogicalKeyboardKey.controlLeft, macDefault), 'win');
    expect(modifierTapSpec(LogicalKeyboardKey.metaLeft, macDefault), 'ctrl');
    expect(modifierTapSpec(LogicalKeyboardKey.altRight, identity), 'alt');
    expect(modifierTapSpec(LogicalKeyboardKey.capsLock, identity), isNull);
    expect(modifierTapSpec(LogicalKeyboardKey.keyA, identity), isNull);
  });

  test('isModifierKey unterscheidet Modifier von normalen Tasten', () {
    expect(isModifierKey(LogicalKeyboardKey.shiftLeft), isTrue);
    expect(isModifierKey(LogicalKeyboardKey.capsLock), isTrue);
    expect(isModifierKey(LogicalKeyboardKey.keyA), isFalse);
    expect(isModifierKey(LogicalKeyboardKey.f1), isFalse);
  });

  test('fKeyByName kennt f1..f12', () {
    expect(fKeyByName['f1'], LogicalKeyboardKey.f1);
    expect(fKeyByName['f12'], LogicalKeyboardKey.f12);
    expect(fKeyByName.length, 12);
  });
}
