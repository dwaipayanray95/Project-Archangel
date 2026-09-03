import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kHostKey = 'archangeld_host';
const _kTokenKey = 'archangeld_token';
const _secureStorage = FlutterSecureStorage(
  mOptions: MacOsOptions(usesDataProtectionKeychain: false),
);

/// The archangeld connection details: host:port (reachable only over the
/// WireGuard tunnel - see WIREGUARD.md) and the single auth token from
/// `archangeld gen-token`. Stored via the OS keychain/keystore, same as
/// the WireGuard private key - this token is a bearer credential for the
/// whole backend, not something to leave in plaintext prefs.
class ArchangeldConnection extends ChangeNotifier {
  String? _host;
  String? get host => _host;

  String? _token;
  String? get token => _token;

  bool get isPaired => _host != null && _token != null;

  bool _loaded = false;

  /// True once [load] has finished reading storage - see
  /// WireGuardController.isBootstrapped for why the root router needs
  /// this rather than just checking [isPaired] immediately.
  bool get isLoaded => _loaded;

  Future<void> load() async {
    _host = await _secureStorage.read(key: _kHostKey);
    _token = await _secureStorage.read(key: _kTokenKey);
    _loaded = true;
    notifyListeners();
  }

  Future<void> pair({required String host, required String token}) async {
    final cleanHost = host.trim();
    final cleanToken = token.trim();
    if (cleanHost.isEmpty) throw const FormatException('Host is required');
    if (cleanToken.isEmpty) throw const FormatException('Token is required');

    await _secureStorage.write(key: _kHostKey, value: cleanHost);
    await _secureStorage.write(key: _kTokenKey, value: cleanToken);
    _host = cleanHost;
    _token = cleanToken;
    notifyListeners();
  }

  Future<void> unpair() async {
    await _secureStorage.delete(key: _kHostKey);
    await _secureStorage.delete(key: _kTokenKey);
    _host = null;
    _token = null;
    notifyListeners();
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
}
