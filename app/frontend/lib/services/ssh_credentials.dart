import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Shared storage keys for the "Remember this key" SSH credentials the
/// setup wizard optionally saves - factored out of setup_wizard_screen.dart
/// so BackendUpdateService (and anything else that needs to SSH back
/// into an already-set-up server) can reuse the same saved key rather
/// than asking the user to paste it in again.
const kSshHostKey = 'vps_setup_ssh_host';
const kSshUsernameKey = 'vps_setup_ssh_username';
const kSshPrivateKeyKey = 'vps_setup_ssh_private_key';

const sshCredentialsStorage = FlutterSecureStorage();

class SavedSshCredentials {
  final String host;
  final String username;
  final String privateKeyPem;
  const SavedSshCredentials({required this.host, required this.username, required this.privateKeyPem});
}

/// Reads back a remembered SSH key/host/username, or null if nothing was
/// saved (the user never checked "Remember this key", or cleared it).
/// Does NOT gate this behind a biometric/PIN prompt itself - callers that
/// read this to act on it (not just to check whether it exists) should
/// do that first, same as setup_wizard_screen.dart's own
/// _restoreSavedKey does via LocalAuthService.
Future<SavedSshCredentials?> loadSavedSshCredentials() async {
  final key = await sshCredentialsStorage.read(key: kSshPrivateKeyKey);
  if (key == null) return null;
  final host = await sshCredentialsStorage.read(key: kSshHostKey);
  final username = await sshCredentialsStorage.read(key: kSshUsernameKey);
  return SavedSshCredentials(host: host ?? '', username: username ?? 'ubuntu', privateKeyPem: key);
}

Future<bool> hasSavedSshCredentials() => sshCredentialsStorage.containsKey(key: kSshPrivateKeyKey);

Future<void> saveSshCredentials(SavedSshCredentials creds) async {
  await sshCredentialsStorage.write(key: kSshHostKey, value: creds.host);
  await sshCredentialsStorage.write(key: kSshUsernameKey, value: creds.username);
  await sshCredentialsStorage.write(key: kSshPrivateKeyKey, value: creds.privateKeyPem);
}

Future<void> clearSavedSshCredentials() async {
  await sshCredentialsStorage.delete(key: kSshHostKey);
  await sshCredentialsStorage.delete(key: kSshUsernameKey);
  await sshCredentialsStorage.delete(key: kSshPrivateKeyKey);
}
