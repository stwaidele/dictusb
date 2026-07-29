/// Smoke-Tests der UI: Aufbau im getrennten Zustand, Block/Direkt-
/// Umschaltung per Taste, Snippets (Knopf + Hotkey).
library;

import 'dart:io' show Platform;

import 'package:dictusb_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App startet im getrennten Zustand', (tester) async {
    await tester.pumpWidget(const DictusbApp());
    await tester.pump(); // asynchrones _loadSaved abarbeiten

    // Titel und Grundzustand.
    expect(find.text('dictUSB'), findsWidgets);
    expect(find.text('getrennt'), findsOneWidget);
    expect(find.text('Verbinden'), findsOneWidget);

    // Senden ist ohne Verbindung deaktiviert.
    final sendBtn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Senden'),
    );
    expect(sendBtn.onPressed, isNull);
  });

  testWidgets('F1 schaltet Block/Direkt um; Repeat togglet nicht doppelt',
      (tester) async {
    await tester.pumpWidget(const DictusbApp());
    await tester.pump();

    expect(find.text('Senden'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.f1);
    // Auto-Repeat der gehaltenen Taste darf nicht zurückschalten.
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.f1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f1);
    await tester.pump();

    expect(find.textContaining('Direktmodus'), findsOneWidget);
    expect(find.text('Senden'), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.f1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f1);
    await tester.pump();

    expect(find.text('Senden'), findsOneWidget);
  });

  // Regression zu Bug 2026-07-29: Bei langen Diktaten vergehen zwischen dem
  // Ctrl/Alt-Antippen und dem V viel mehr als die früheren 5 s (Paraspeech
  // schickt das V erst nach Aufnahme + Transkription). Der Text wurde dann
  // nicht eingefügt, stattdessen kam ein „v" durch. Der Test wartet echte
  // Zeit ab — die Heuristik liest die Uhr, nicht die Test-Fake-Zeit.
  testWidgets('Diktat: Ctrl+Alt … lange Pause … V fügt die Zwischenablage ein',
      (tester) async {
    const dictated = 'Ein langer diktierter Satz.';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? <String, dynamic>{'text': dictated}
          : null,
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(const DictusbApp());
    await tester.pump();

    // Paraspeech tippt die Modifier nur an und hält sie nicht.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

    // Diktatdauer: deutlich länger als das alte 5-s-Fenster.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 6500)),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.pumpAndSettle();

    expect(find.text(dictated), findsOneWidget);
    expect(find.text('v'), findsNothing);
  });

  testWidgets('Diktat: einzeln angetippte Modifier bewaffnen nicht',
      (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? <String, dynamic>{'text': 'darf nicht eingefügt werden'}
          : null,
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(const DictusbApp());
    await tester.pump();

    // Strg-Shortcut jetzt, Alt viel später: gehört nicht zusammen.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1200)),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.pumpAndSettle();

    expect(find.text('darf nicht eingefügt werden'), findsNothing);
  });

  testWidgets('Snippet: Knopf und Hotkey fügen im Blockmodus ins Textfeld ein',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'dictusb.snippets': '[{"label":"Gruß","text":"Hallo Welt"}]',
    });
    await tester.pumpWidget(const DictusbApp());
    await tester.pump(); // asynchrone Konfiguration laden
    await tester.pump();

    // Knopf mit Hotkey-Beschriftung sichtbar; Klick fügt ein.
    final btn = find.textContaining('Gruß');
    expect(btn, findsOneWidget);
    await tester.tap(btn);
    await tester.pump();
    expect(find.text('Hallo Welt'), findsOneWidget);

    // Hotkey (Cmd+1 bzw. Strg+1) fügt erneut ein.
    final mod = Platform.isMacOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(mod);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyUpEvent(mod);
    await tester.pump();
    expect(find.text('Hallo WeltHallo Welt'), findsOneWidget);
  });
}
