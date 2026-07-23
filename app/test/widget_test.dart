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
