import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'local_kv_store.dart';

const _kHostKey = 'archangeld_host';
const _kTokenKey = 'archangeld_token';
final _store = LocalKvStore.instance;

/// The archangeld connection details: host:port (reachable only over the
/// WireGuard tunnel - see WIREGUARD.md) and the single auth token from
/// `archangeld gen-token`. Stored in the local app-state file (see
/// local_kv_store.dart's doc comment for why this isn't Keychain-backed)
/// rather than plaintext prefs.
class ArchangeldConnection extends ChangeNotifier {
  String? _host;
  String? get host => _host;

  String? _token;
  String? get token => _token;

  bool get isPaired => _host != null && _token != null;

  /// The backend's reported version (from /api/v1/health), refreshed by
  /// [refreshBackendVersion]. Null until that succeeds at least once -
  /// this is a purely informational field for the Settings screen, so a
  /// fetch failure just leaves it null rather than surfacing an error.
  String? _backendVersion;
  String? get backendVersion => _backendVersion;

  bool _loaded = false;

  /// True once [load] has finished reading storage - see
  /// WireGuardController.isBootstrapped for why the root router needs
  /// this rather than just checking [isPaired] immediately.
  bool get isLoaded => _loaded;

  Future<void> load() async {
    _host = await _store.read(_kHostKey);
    _token = await _store.read(_kTokenKey);
    _loaded = true;
    notifyListeners();
    if (isPaired) {
      unawaited(refreshBackendVersion());
    }
  }

  Future<void> pair({required String host, required String token}) async {
    final cleanHost = host.trim();
    final cleanToken = token.trim();
    if (cleanHost.isEmpty) throw const FormatException('Host is required');
    if (cleanToken.isEmpty) throw const FormatException('Token is required');

    await _store.write(_kHostKey, cleanHost);
    await _store.write(_kTokenKey, cleanToken);
    _host = cleanHost;
    _token = cleanToken;
    notifyListeners();
    unawaited(refreshBackendVersion());
  }

  Future<void> unpair() async {
    await _store.delete(_kHostKey);
    await _store.delete(_kTokenKey);
    _host = null;
    _token = null;
    _backendVersion = null;
    notifyListeners();
  }

  /// `http://<host>/api/v1/health` - unauthenticated, so this is usable
  /// without a token; the health endpoint itself needs none.
  Uri healthHttpUri() {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/health');
  }

  /// Fetches the backend's version from /api/v1/health and caches it.
  /// Failures are silent - this only feeds an informational Settings row.
  Future<void> refreshBackendVersion() async {
    if (!isPaired) return;
    try {
      final res = await http.get(healthHttpUri());
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final v = data['version'] as String?;
        if (v != null && v.isNotEmpty) {
          _backendVersion = v;
          notifyListeners();
        }
      }
    } catch (_) {
      // informational only - leave _backendVersion as-is
    }
  }

  /// `ws://<host>/ws/terminal?token=...` - plain ws, not wss: archangeld
  /// doesn't terminate TLS itself (see backend README), it relies on the
  /// WireGuard tunnel for transport encryption instead.
  Uri terminalWsUri() {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('ws://$_host/ws/terminal').replace(queryParameters: {'token': _token});
  }

  /// `ws://<host>/ws/stats?token=...` - real-time metrics stream.
  Uri statsWsUri() {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('ws://$_host/ws/stats').replace(queryParameters: {'token': _token});
  }

  /// `http://<host>/api/v1/system/metrics`
  Uri metricsHttpUri() {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/system/metrics');
  }

  /// `http://<host>/api/v1/system/processes`
  Uri processesHttpUri() {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/system/processes');
  }

  /// `http://<host>/api/v1/system/processes/{pid}/kill`
  Uri processKillHttpUri(int pid) {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/system/processes/$pid/kill');
  }

  /// `http://<host>/api/v1/system/processes/{pid}/renice`
  Uri processReniceHttpUri(int pid) {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/system/processes/$pid/renice');
  }

  /// `http://<host>/api/v1/files/list?path=...`
  Uri filesListHttpUri(String path) {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/files/list').replace(queryParameters: {'path': path});
  }

  /// `http://<host>/api/v1/files/read?path=...&lines=...`
  Uri filesReadHttpUri(String path, {int lines = 300}) {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/files/read').replace(queryParameters: {
      'path': path,
      'lines': lines.toString(),
    });
  }

  /// `http://<host>/api/v1/files/download?path=...`
  Uri filesDownloadHttpUri(String path) {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/files/download').replace(queryParameters: {'path': path});
  }

  /// `http://<host>/api/v1/docker/containers`
  Uri dockerContainersHttpUri() {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/docker/containers');
  }

  /// `http://<host>/api/v1/docker/containers/{id}/{action}`
  Uri dockerContainerActionHttpUri(String id, String action) {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/docker/containers/$id/$action');
  }

  /// `ws://<host>/ws/docker/containers/{id}/logs?token=...`
  Uri dockerContainerLogsWsUri(String id) {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('ws://$_host/ws/docker/containers/$id/logs').replace(queryParameters: {'token': _token});
  }
}
