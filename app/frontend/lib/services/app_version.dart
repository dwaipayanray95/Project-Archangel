import 'package:flutter/services.dart' show rootBundle;

/// Central version helper for Project Archangel frontend.
///
/// Draws the version dynamically at build/runtime from the project root's
/// `VERSION` asset, with a compile-time fallback constant.
class AppVersion {
  AppVersion._();

  static const String fallback = '1.1.0';
  static String? _cached;

  /// Returns the current app version. Asynchronously reads the root `VERSION`
  /// asset once, or returns [fallback] immediately.
  static Future<String> get() async {
    if (_cached != null) return _cached!;
    try {
      final text = await rootBundle.loadString('assets/VERSION');
      final clean = text.trim();
      if (clean.isNotEmpty) {
        _cached = clean;
        return clean;
      }
    } catch (_) {}
    return fallback;
  }

  /// Synchronous cached or fallback version string.
  static String get current => _cached ?? fallback;
}
