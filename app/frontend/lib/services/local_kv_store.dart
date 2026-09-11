import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A plain local-file key/value store, replacing flutter_secure_storage
/// for app state that isn't sensitive enough to need PIN-derived
/// encryption (see ssh_credentials.dart / credential_crypto.dart for the
/// one thing that is: the SSH private key that grants root on the VPS).
///
/// This holds things like the paired host/token and the WireGuard
/// tunnel config - real secrets, but ones the app needs on every launch
/// to function at all, so gating them behind a PIN prompt every single
/// time would be worse than what this replaces. flutter_secure_storage
/// on macOS is a thin wrapper over Keychain Services, which requires a
/// stable code-signing entitlement (Keychain Sharing, set up via Xcode)
/// to avoid re-prompting on every read; without it, EVERY separate key
/// read at startup (host, token, wg config, update-check cache - four
/// separate reads, each its own Keychain transaction) was its own
/// native macOS password prompt. Moving this data to one plain JSON
/// file removes the Keychain dependency, and with it every one of those
/// prompts - the file is protected the same way any other file in the
/// user's home directory is (OS login + disk encryption like FileVault,
/// not a second app-level secret).
class LocalKvStore {
  LocalKvStore._(this._fileName);

  final String _fileName;
  Map<String, String>? _cache;

  static final LocalKvStore instance = LocalKvStore._('archangel_app_state.json');

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<Map<String, String>> _load() async {
    if (_cache != null) return _cache!;
    final file = await _file();
    if (!await file.exists()) {
      _cache = {};
      return _cache!;
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _cache = decoded.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      // Corrupted/unreadable - start fresh rather than crash the app on
      // launch over stale local state that can just be re-paired.
      _cache = {};
    }
    return _cache!;
  }

  Future<void> _persist() async {
    final file = await _file();
    await file.writeAsString(jsonEncode(_cache ?? {}), flush: true);
  }

  Future<String?> read(String key) async => (await _load())[key];

  Future<void> write(String key, String value) async {
    final map = await _load();
    map[key] = value;
    await _persist();
  }

  Future<void> delete(String key) async {
    final map = await _load();
    if (map.remove(key) != null) await _persist();
  }
}
