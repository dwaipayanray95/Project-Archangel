import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'credential_crypto.dart';
import '../widgets/pin_prompt_dialog.dart';

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
  _cachedCreds = creds;
}

Future<void> clearSavedSshCredentials() async {
  final file = await _credentialsFile();
  if (await file.exists()) await file.delete();
  _cachedCreds = null;
}

/// In-memory-only cache of the decrypted key, held for the life of the
/// app process - never written to disk. Without this, every dialog that
/// independently restores the saved key (setup wizard, manage-key,
/// backend-update, uninstall) would prompt for the PIN again even
/// though the user already unlocked it once this session; that's just
/// as annoying as the OS-Keychain re-prompting this whole scheme was
/// built to avoid. Cleared on [clearSavedSshCredentials] and replaced
/// on [saveSshCredentials]; NOT cleared on wrong-PIN, so a mistyped PIN
/// doesn't evict a credential that was already unlocked earlier.
SavedSshCredentials? _cachedCreds;

/// The one entry point every screen/dialog that wants to restore a
/// saved key should use, instead of calling [hasSavedSshCredentials] /
/// [loadSavedSshCredentials] / promptForPin directly - it's what makes
/// "enter the PIN once per app session" actually true across dialogs.
///
/// Returns null if there's nothing saved, the user cancels the PIN
/// prompt, or they get the PIN wrong - callers just get "couldn't
/// restore, fall back to an empty form" without their own try/catch.
Future<SavedSshCredentials?> unlockSavedSshCredentials(BuildContext context) async {
  if (_cachedCreds != null) return _cachedCreds;
  if (!await hasSavedSshCredentials()) return null;
  if (!context.mounted) return null;

  final pin = await promptForPin(context, title: 'Enter PIN', message: 'Enter the PIN that protects your saved SSH key.');
  if (pin == null || !context.mounted) return null;

  try {
    final creds = await loadSavedSshCredentials(pin);
    _cachedCreds = creds;
    return creds;
  } on WrongPinException {
    return null;
  }
}
