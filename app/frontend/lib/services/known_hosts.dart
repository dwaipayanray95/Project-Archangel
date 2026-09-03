import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kKeyPrefix = 'known_host_';
const _secureStorage = FlutterSecureStorage();

/// A minimal trust-on-first-use (TOFU) store for SSH host key
/// fingerprints, the same model OpenSSH's own `known_hosts` uses:
/// remember the fingerprint the first time we connect to a host, and
/// treat any later mismatch as suspicious rather than silently
/// reconnecting. See lib/services/ssh_transport.dart's `onUnknownHostKey`
/// callback, which is what actually decides whether to trust a new or
/// changed key - this class only stores the outcome.
class KnownHosts {
  Future<String?> get(String host) => _secureStorage.read(key: '$_kKeyPrefix$host');

  Future<void> trust(String host, String fingerprint) =>
      _secureStorage.write(key: '$_kKeyPrefix$host', value: fingerprint);
}
