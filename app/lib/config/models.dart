/// Datenmodell für Phase 4: benannte Geräte (mit eigenem Token) und
/// Textbausteine. Persistiert als JSON in SharedPreferences.
library;

import 'dart:convert';

class Device {
  final String name;
  final String host;
  final int port;
  final String token;

  const Device({
    required this.name,
    required this.host,
    required this.port,
    required this.token,
  });

  Map<String, Object?> toJson() =>
      {'name': name, 'host': host, 'port': port, 'token': token};

  factory Device.fromJson(Map<String, Object?> j) => Device(
        name: (j['name'] as String?) ?? '',
        host: (j['host'] as String?) ?? '',
        port: (j['port'] as num?)?.toInt() ?? 8080,
        token: (j['token'] as String?) ?? '',
      );

  static String encodeList(List<Device> list) =>
      jsonEncode([for (final d in list) d.toJson()]);

  static List<Device> decodeList(String raw) {
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! List) return const [];
      return [
        for (final e in parsed)
          if (e is Map<String, Object?>) Device.fromJson(e),
      ];
    } on FormatException {
      return const [];
    }
  }
}

class Snippet {
  final String label;
  final String text;

  const Snippet({required this.label, required this.text});

  Map<String, Object?> toJson() => {'label': label, 'text': text};

  factory Snippet.fromJson(Map<String, Object?> j) => Snippet(
        label: (j['label'] as String?) ?? '',
        text: (j['text'] as String?) ?? '',
      );

  static String encodeList(List<Snippet> list) =>
      jsonEncode([for (final s in list) s.toJson()]);

  static List<Snippet> decodeList(String raw) {
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! List) return const [];
      return [
        for (final e in parsed)
          if (e is Map<String, Object?>) Snippet.fromJson(e),
      ];
    } on FormatException {
      return const [];
    }
  }
}
