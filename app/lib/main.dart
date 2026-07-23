import 'package:flutter/material.dart';

import 'ui/home_page.dart';

void main() => runApp(const DictusbApp());

class DictusbApp extends StatelessWidget {
  const DictusbApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF00A0A0); // Cyan-Tupfer der Status-LED
    return MaterialApp(
      title: 'dictUSB',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: seed,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
