import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'credential_crypto.dart';

export 'credential_crypto.dart' show WrongPinException;

/// The "Remember this key" SSH credentials the setup wizard optionally
/// saves - factored out so BackendUpdateService (and anything else that
/// needs to SSH back into an already-set-up server) can reuse the same
/// saved key rather than asking the user to paste it in again.
///
/// Stored as a single PIN-encrypted file (see credential_crypto.dart)
/// rather than three separate flutter_secure_storage keys: that used to
/// mean three independent OS Keychain/Credential Manager transactions
/// per read or write, which on macOS (without a stable code-signing
/// entitlement) meant a fresh Keychain prompt for each one, every
/// rebuild. One file, one encrypt/decrypt call, no OS secure-storage
/// dependency at all - same behavior on every platform.
class SavedSshCredentials {
  final String host;
  final String username;
  final String privateKeyPem;
  const SavedSshCredentials({required this.host, required this.username, required this.privateKeyPem});

  Map<String, dynamic> toJson() => {'host': host, 'username': username, 'privateKeyPem': privateKeyPem};

  static SavedSshCredentials fromJson(Map<String, dynamic> json) => SavedSshCredentials(
        host: json['host'] as String? ?? '',
        username: json['username'] as String? ?? 'ubuntu',
        privateKeyPem: json['privateKeyPem'] as String? ?? '',
      );
}

Future<File> _credentialsFile() async {
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}/ssh_credentials.enc');
}

/// Whether a key has been saved - doesn't require the PIN, just checks
/// the file exists, so callers can decide whether to prompt for a PIN
/// at all.
Future<bool> hasSavedSshCredentials() async => (await _credentialsFile()).exists();

/// Decrypts the saved key with [pin]. Throws [WrongPinException] if the
/// PIN is wrong or the file is corrupted.
Future<SavedSshCredentials?> loadSavedSshCredentials(String pin) async {
  final file = await _credentialsFile();
  if (!await file.exists()) return null;
  final bytes = await file.readAsBytes();
  final json = await decryptJson(pin, bytes);
  return SavedSshCredentials.fromJson(json);
}

/// Encrypts and saves [creds] under [pin] - one file write, replacing
/// whatever was saved before (including under a different PIN, if the
/// user is rotating it).
Future<void> saveSshCredentials(String pin, SavedSshCredentials creds) async {
  final bytes = await encryptJson(pin, creds.toJson());
  final file = await _credentialsFile();
  await file.writeAsBytes(bytes, flush: true);
}

Future<void> clearSavedSshCredentials() async {
  final file = await _credentialsFile();
  if (await file.exists()) await file.delete();
}
